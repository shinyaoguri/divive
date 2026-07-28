import Dispatch
import Foundation
import HubProtocol
import NIOCore
import NIOPosix

public struct StageDistributorConfiguration: Equatable, Sendable {
  /// 既定はloopbackだけ。LANへ広げる場合は認証を先に用意すること。
  public var host: String
  public var port: Int
  public var publishRateHz: UInt16
  public var maximumSubscribers: Int
  public var allowNonLoopbackClients: Bool

  public init(
    host: String = "127.0.0.1",
    port: Int = StageWireProtocol.defaultPort,
    publishRateHz: UInt16 = 90,
    maximumSubscribers: Int = 16,
    allowNonLoopbackClients: Bool = false
  ) {
    self.host = host
    self.port = port
    self.publishRateHz = publishRateHz
    self.maximumSubscribers = maximumSubscribers
    self.allowNonLoopbackClients = allowNonLoopbackClients
  }
}

public struct StageDistributorStatistics: Equatable, Sendable {
  public var publishedFrames: UInt64 = 0
  public var sentDatagrams: UInt64 = 0
  /// 購読者がいないため送信しなかった回数。
  public var idlePublishTicks: UInt64 = 0
  /// snapshotをまだ取得できず送信しなかった回数。
  public var emptySnapshotTicks: UInt64 = 0
  public var encodeErrors: UInt64 = 0
  public var invalidSubscriptionPackets: UInt64 = 0
  public var channelErrors: UInt64 = 0
  public var activeSubscribers: Int = 0
  public var lastEncodeError: String?
  public var lastSubscriptionError: String?
  public var subscription = StageSubscriptionStatistics()
  public var subscribers: [StageSubscriberSummary] = []

  public init() {}
}

/// 診断表示用のsubscriber要約。SocketAddressをそのまま外へ出さない。
public struct StageSubscriberSummary: Equatable, Sendable {
  public let address: String
  public let clientName: String
  public let clientID: String
  public let requestedRateHz: UInt16
  public let renewals: UInt64
}

public enum StageDistributorError: Error, Equatable, Sendable {
  case invalidLifecycle
  case invalidPublishRate
  case localAddressUnavailable
}

/// contentへstage frameをUDPで配信し、購読を受け付ける。
///
/// 最新値優先のため、送信できなかったframeを貯めない。配信tickごとに
/// snapshotを取り直し、その時点の最新値だけを送る。
public final class StageDistributor: @unchecked Sendable {
  public typealias SnapshotProvider = @Sendable () -> StageFrameMessage?

  private let group: MultiThreadedEventLoopGroup
  private let sessionID: UUIDBytes
  private let sourceID: UUIDBytes
  private let statisticsStore = StageStatisticsStore()
  private let lifecycleLock = NSLock()
  private var channel: Channel?
  private var didShutdown = false

  /// - Parameters:
  ///   - sessionID: Hub processの起動ごとに変わるID。contentは変化で再同期できる。
  ///   - sourceID: Hub instanceを識別するID。
  public init(sessionID: UUIDBytes, sourceID: UUIDBytes) {
    self.sessionID = sessionID
    self.sourceID = sourceID
    group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  @discardableResult
  public func start(
    configuration: StageDistributorConfiguration = .init(),
    snapshotProvider: @escaping SnapshotProvider
  ) throws -> SocketAddress {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }

    guard channel == nil, !didShutdown else {
      throw StageDistributorError.invalidLifecycle
    }
    guard configuration.publishRateHz > 0 else {
      throw StageDistributorError.invalidPublishRate
    }

    let handler = StageDatagramHandler(
      configuration: configuration,
      sessionID: sessionID,
      sourceID: sourceID,
      statisticsStore: statisticsStore,
      snapshotProvider: snapshotProvider
    )
    let bootstrap = DatagramBootstrap(group: group)
      .channelOption(.socketOption(.so_reuseaddr), value: 1)
      .channelOption(
        .recvAllocator,
        // 購読messageは小さいが、上限超過datagramを切り詰めず拒否できる余裕を持つ。
        value: FixedSizeRecvByteBufferAllocator(capacity: 2_048)
      )
      .channelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.addHandler(handler)
        }
      }

    let channel =
      try bootstrap
      .bind(host: configuration.host, port: configuration.port)
      .wait()
    self.channel = channel

    guard let address = channel.localAddress else {
      try channel.close().wait()
      self.channel = nil
      throw StageDistributorError.localAddressUnavailable
    }
    return address
  }

  public func statistics() -> StageDistributorStatistics {
    statisticsStore.snapshot()
  }

  public func isActive() -> Bool {
    lifecycleLock.withLock { channel?.isActive ?? false }
  }

  public func close() throws {
    let activeChannel = lifecycleLock.withLock { () -> Channel? in
      defer { channel = nil }
      return channel
    }
    try activeChannel?.close().wait()
  }

  /// EventLoopGroupを終了する。終了後にdistributorを再利用できない。
  public func shutdown() throws {
    let shouldShutdown = lifecycleLock.withLock { () -> Bool in
      guard !didShutdown else { return false }
      didShutdown = true
      return true
    }
    guard shouldShutdown else { return }

    try close()
    try group.syncShutdownGracefully()
  }
}

/// 購読registryとsequenceを単一event loopへ閉じ込める。
private final class StageDatagramHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = AddressedEnvelope<ByteBuffer>
  typealias OutboundOut = AddressedEnvelope<ByteBuffer>

  private let configuration: StageDistributorConfiguration
  private let sessionID: UUIDBytes
  private let sourceID: UUIDBytes
  private let statisticsStore: StageStatisticsStore
  private let snapshotProvider: StageDistributor.SnapshotProvider
  private let subscriptionCodec = StageSubscriptionCodec()
  private let frameEncoder = StageFrameEncoder()
  private var registry: StageSubscriptionRegistry<SocketAddress>
  private var frameSequence: UInt64 = 0
  private var publishTask: RepeatedTask?

  init(
    configuration: StageDistributorConfiguration,
    sessionID: UUIDBytes,
    sourceID: UUIDBytes,
    statisticsStore: StageStatisticsStore,
    snapshotProvider: @escaping StageDistributor.SnapshotProvider
  ) {
    self.configuration = configuration
    self.sessionID = sessionID
    self.sourceID = sourceID
    self.statisticsStore = statisticsStore
    self.snapshotProvider = snapshotProvider
    registry = StageSubscriptionRegistry(
      maximumSubscribers: configuration.maximumSubscribers,
      allowNonLoopbackClients: configuration.allowNonLoopbackClients
    )
  }

  func channelActive(context: ChannelHandlerContext) {
    let interval = TimeAmount.nanoseconds(
      Int64(1_000_000_000 / UInt64(configuration.publishRateHz))
    )
    publishTask = context.eventLoop.scheduleRepeatedTask(
      initialDelay: interval,
      delay: interval
    ) { [weak self] _ in
      self?.publish(context: context)
    }
    context.fireChannelActive()
  }

  func channelInactive(context: ChannelHandlerContext) {
    publishTask?.cancel()
    publishTask = nil
    context.fireChannelInactive()
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let addressed = unwrapInboundIn(data)
    let buffer = addressed.data
    let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) ?? []

    do {
      let packet = try subscriptionCodec.decode(bytes)
      let outcome = registry.register(
        packet,
        from: addressed.remoteAddress,
        address: String(describing: addressed.remoteAddress),
        isLoopback: addressed.remoteAddress.isLoopback,
        atMonotonicNS: DispatchTime.now().uptimeNanoseconds
      )
      statisticsStore.record(outcome: outcome, registry: registry)
    } catch let error as PacketDecodeError {
      statisticsStore.recordInvalidSubscription(error.description)
    } catch {
      statisticsStore.recordInvalidSubscription(
        PacketDecodeError.flatbufferInvalid.description
      )
    }
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    // client消失によるICMPなどで配信全体を止めない。
    statisticsStore.recordChannelError()
  }

  private func publish(context: ChannelHandlerContext) {
    let now = DispatchTime.now().uptimeNanoseconds
    let subscribers = registry.prune(atMonotonicNS: now)
    guard !subscribers.isEmpty else {
      statisticsStore.recordIdleTick(registry: registry)
      return
    }
    guard let frame = snapshotProvider() else {
      statisticsStore.recordEmptySnapshotTick(registry: registry)
      return
    }

    do {
      let datagram = try frameEncoder.encode(
        frame: frame,
        sessionID: sessionID,
        sourceID: sourceID,
        frameSequence: frameSequence
      )
      frameSequence &+= 1

      var buffer = context.channel.allocator.buffer(capacity: datagram.count)
      buffer.writeBytes(datagram)
      for subscriber in subscribers {
        context.write(
          wrapOutboundOut(
            AddressedEnvelope(remoteAddress: subscriber.key, data: buffer)
          ),
          promise: nil
        )
      }
      context.flush()
      statisticsStore.recordPublished(
        datagrams: subscribers.count,
        registry: registry
      )
    } catch {
      statisticsStore.recordEncodeError(
        String(describing: error),
        registry: registry
      )
    }
  }
}

private final class StageStatisticsStore: @unchecked Sendable {
  private let lock = NSLock()
  private var value = StageDistributorStatistics()

  func snapshot() -> StageDistributorStatistics {
    lock.withLock { value }
  }

  func record(
    outcome: StageSubscriptionOutcome,
    registry: StageSubscriptionRegistry<SocketAddress>
  ) {
    lock.withLock {
      value.subscription = registry.statistics
      updateSubscribers(registry)
      switch outcome {
      case .rejectedNotLoopback:
        value.lastSubscriptionError = "rejected_not_loopback"
      case .rejectedCapacity:
        value.lastSubscriptionError = "rejected_capacity"
      case .registered, .renewed, .unsubscribed, .ignored:
        value.lastSubscriptionError = nil
      }
    }
  }

  func recordInvalidSubscription(_ description: String) {
    lock.withLock {
      value.invalidSubscriptionPackets += 1
      value.lastSubscriptionError = description
    }
  }

  func recordChannelError() {
    lock.withLock {
      value.channelErrors += 1
    }
  }

  func recordPublished(
    datagrams: Int,
    registry: StageSubscriptionRegistry<SocketAddress>
  ) {
    lock.withLock {
      value.publishedFrames += 1
      value.sentDatagrams += UInt64(datagrams)
      value.subscription = registry.statistics
      refreshSubscribersIfChanged(registry)
    }
  }

  func recordIdleTick(registry: StageSubscriptionRegistry<SocketAddress>) {
    lock.withLock {
      value.idlePublishTicks += 1
      value.subscription = registry.statistics
      refreshSubscribersIfChanged(registry)
    }
  }

  func recordEmptySnapshotTick(registry: StageSubscriptionRegistry<SocketAddress>) {
    lock.withLock {
      value.emptySnapshotTicks += 1
      value.subscription = registry.statistics
      refreshSubscribersIfChanged(registry)
    }
  }

  func recordEncodeError(
    _ description: String,
    registry: StageSubscriptionRegistry<SocketAddress>
  ) {
    lock.withLock {
      value.encodeErrors += 1
      value.lastEncodeError = description
      value.subscription = registry.statistics
      refreshSubscribersIfChanged(registry)
    }
  }

  /// 配信tickは90Hzで来る。人が見るためのsubscriber一覧を毎tick作り直さない。
  ///
  /// 購読の増減は`record(outcome:)`が拾うため、ここでは件数の変化だけを見る。
  /// 期限切れによる減少もこの経路で反映される。
  private func refreshSubscribersIfChanged(
    _ registry: StageSubscriptionRegistry<SocketAddress>
  ) {
    guard registry.count != value.activeSubscribers else { return }
    updateSubscribers(registry)
  }

  private func updateSubscribers(
    _ registry: StageSubscriptionRegistry<SocketAddress>
  ) {
    let subscribers = registry.activeSubscribers()
    value.activeSubscribers = subscribers.count
    value.subscribers = subscribers.map {
      StageSubscriberSummary(
        address: $0.address,
        clientName: $0.clientName,
        clientID: $0.clientID.description,
        requestedRateHz: $0.requestedRateHz,
        renewals: $0.renewals
      )
    }
  }
}

extension SocketAddress {
  /// loopback判定。IPv4-mapped IPv6も同じloopbackとして扱う。
  var isLoopback: Bool {
    switch self {
    case .v4(let address):
      return UInt32(bigEndian: address.address.sin_addr.s_addr) >> 24 == 127
    case .v6:
      guard let ipAddress else { return false }
      return ipAddress == "::1" || ipAddress.hasPrefix("::ffff:127.")
    case .unixDomainSocket:
      return true
    }
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
