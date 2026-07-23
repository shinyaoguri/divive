import Dispatch
import Foundation
import HubProtocol
import NIOCore
import NIOPosix

public struct UDPReceiverConfiguration: Equatable, Sendable {
  public var host: String
  public var port: Int

  public init(host: String = "0.0.0.0", port: Int = 41_320) {
    self.host = host
    self.port = port
  }
}

public struct ReceivedPosePacket: Sendable {
  public let packet: DecodedPosePacket
  public let remoteAddress: String
  public let receivedMonotonicNS: UInt64
  public let processingTimeNS: UInt64
  public let disposition: SequenceDisposition
}

public struct ReceiverStatistics: Equatable, Sendable {
  public var datagrams: UInt64 = 0
  public var validPackets: UInt64 = 0
  public var invalidPackets: UInt64 = 0
  public var appliedPackets: UInt64 = 0
  public var duplicatePackets: UInt64 = 0
  public var outOfOrderPackets: UInt64 = 0
  public var inconsistentBatchPackets: UInt64 = 0
  public var missingFrames: UInt64 = 0
  public var missingBatches: UInt64 = 0
  public var trackerRecords: UInt64 = 0
  public var lastReceiveMonotonicNS: UInt64 = 0
  public var lastProcessingTimeNS: UInt64 = 0
  public var lastDecodeError: String?
}

/// 受信callbackはSwiftNIO event loop上で呼ばれる。重い処理やdisk I/Oを行わないこと。
public final class UDPReceiver: @unchecked Sendable {
  public typealias PacketHandler = @Sendable (ReceivedPosePacket) -> Void
  public typealias ErrorHandler = @Sendable (PacketDecodeError) -> Void

  private let group: MultiThreadedEventLoopGroup
  private let statisticsStore = StatisticsStore()
  private let lifecycleLock = NSLock()
  private var channel: Channel?
  private var didShutdown = false

  public init() {
    group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  @discardableResult
  public func start(
    configuration: UDPReceiverConfiguration = .init(),
    onPacket: @escaping PacketHandler,
    onDecodeError: @escaping ErrorHandler = { _ in }
  ) throws -> SocketAddress {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }

    guard channel == nil, !didShutdown else {
      throw UDPReceiverError.invalidLifecycle
    }

    let handler = PoseDatagramHandler(
      statisticsStore: statisticsStore,
      onPacket: onPacket,
      onDecodeError: onDecodeError
    )
    let bootstrap = DatagramBootstrap(group: group)
      .channelOption(.socketOption(.so_reuseaddr), value: 1)
      .channelOption(
        .recvAllocator,
        value: FixedSizeRecvByteBufferAllocator(
          // 上限超過datagramを切り詰めず、decoderで明示拒否できる余裕を持つ。
          capacity: 2_048
        )
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
      throw UDPReceiverError.localAddressUnavailable
    }
    return address
  }

  public func statistics() -> ReceiverStatistics {
    statisticsStore.snapshot()
  }

  public func close() throws {
    let activeChannel = lifecycleLock.withLock { () -> Channel? in
      defer { channel = nil }
      return channel
    }
    try activeChannel?.close().wait()
  }

  public func waitUntilClosed() throws {
    let activeChannel = lifecycleLock.withLock { channel }
    try activeChannel?.closeFuture.wait()
  }

  /// EventLoopGroupを終了する。終了後にreceiverを再利用できない。
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

public enum UDPReceiverError: Error, Equatable, Sendable {
  case invalidLifecycle
  case localAddressUnavailable
}

/// SwiftNIOの単一event loopへ閉じ込め、別threadからmutable stateへ触れない。
private final class PoseDatagramHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = AddressedEnvelope<ByteBuffer>

  private let decoder = PosePacketDecoder()
  private let statisticsStore: StatisticsStore
  private let onPacket: UDPReceiver.PacketHandler
  private let onDecodeError: UDPReceiver.ErrorHandler
  private var sequenceLedger = SequenceLedger()

  init(
    statisticsStore: StatisticsStore,
    onPacket: @escaping UDPReceiver.PacketHandler,
    onDecodeError: @escaping UDPReceiver.ErrorHandler
  ) {
    self.statisticsStore = statisticsStore
    self.onPacket = onPacket
    self.onDecodeError = onDecodeError
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let receivedAt = DispatchTime.now().uptimeNanoseconds
    let addressed = unwrapInboundIn(data)
    let buffer = addressed.data
    let bytes =
      buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) ?? []

    do {
      let packet = try decoder.decode(bytes)
      let disposition = sequenceLedger.observe(packet.envelope)
      let processingTime = DispatchTime.now().uptimeNanoseconds - receivedAt
      statisticsStore.record(
        packet: packet,
        disposition: disposition,
        receivedAt: receivedAt,
        processingTime: processingTime
      )
      guard disposition.shouldApplyPose else { return }
      onPacket(
        ReceivedPosePacket(
          packet: packet,
          remoteAddress: String(describing: addressed.remoteAddress),
          receivedMonotonicNS: receivedAt,
          processingTimeNS: processingTime,
          disposition: disposition
        )
      )
    } catch let error as PacketDecodeError {
      statisticsStore.record(error: error, receivedAt: receivedAt)
      onDecodeError(error)
    } catch {
      let decodeError = PacketDecodeError.flatbufferInvalid
      statisticsStore.record(error: decodeError, receivedAt: receivedAt)
      onDecodeError(decodeError)
    }
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    context.close(promise: nil)
  }
}

private final class StatisticsStore: @unchecked Sendable {
  private let lock = NSLock()
  private var value = ReceiverStatistics()

  func snapshot() -> ReceiverStatistics {
    lock.withLock { value }
  }

  func record(
    packet: DecodedPosePacket,
    disposition: SequenceDisposition,
    receivedAt: UInt64,
    processingTime: UInt64
  ) {
    lock.withLock {
      value.datagrams += 1
      value.validPackets += 1
      value.trackerRecords += UInt64(packet.poseBatch.trackers.count)
      value.lastReceiveMonotonicNS = receivedAt
      value.lastProcessingTimeNS = processingTime
      value.lastDecodeError = nil

      switch disposition {
      case .sessionStarted, .additionalBatch:
        value.appliedPackets += 1
      case .newFrame(let missingFrames, let missingBatches):
        value.appliedPackets += 1
        value.missingFrames += missingFrames
        value.missingBatches += UInt64(missingBatches)
      case .duplicate:
        value.duplicatePackets += 1
      case .outOfOrder:
        value.outOfOrderPackets += 1
      case .inconsistentBatchCount:
        value.inconsistentBatchPackets += 1
      }
    }
  }

  func record(error: PacketDecodeError, receivedAt: UInt64) {
    lock.withLock {
      value.datagrams += 1
      value.invalidPackets += 1
      value.lastReceiveMonotonicNS = receivedAt
      value.lastDecodeError = error.description
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
