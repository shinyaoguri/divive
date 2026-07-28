import Foundation
import HubCalibration
import HubCore
import HubDistribution
import HubProtocol
import NIOCore
import NIOPosix
import XCTest

final class StageDistributorTests: XCTestCase {
  /// contentの代わりにstage frameを受け取り、購読を送るtest client。
  private final class TestClient {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let handler = CollectingHandler()
    private var channel: Channel!

    func start() throws {
      channel = try DatagramBootstrap(group: group)
        .channelInitializer { channel in
          channel.eventLoop.makeCompletedFuture {
            try channel.pipeline.syncOperations.addHandler(self.handler)
          }
        }
        .bind(host: "127.0.0.1", port: 0)
        .wait()
    }

    func subscribe(
      to address: SocketAddress,
      ttlMS: UInt32 = 1_000,
      unsubscribe: Bool = false
    ) throws {
      let datagram = try StageSubscriptionCodec().encode(
        subscription: StageSubscriptionMessage(
          clientName: "unity-test",
          requestedRateHz: 90,
          ttlMS: ttlMS,
          unsubscribe: unsubscribe
        ),
        sessionID: try stageTestUUID(0x60),
        clientID: try stageTestUUID(0x70),
        sequence: 1
      )
      try send(datagram, to: address)
    }

    func send(_ datagram: [UInt8], to address: SocketAddress) throws {
      var buffer = channel.allocator.buffer(capacity: datagram.count)
      buffer.writeBytes(datagram)
      try channel.writeAndFlush(
        AddressedEnvelope(remoteAddress: address, data: buffer)
      ).wait()
    }

    var receivedFrames: [DecodedStageFramePacket] { handler.frames() }
    var decodeErrors: Int { handler.errorCount() }

    func waitForFrames(
      _ count: Int,
      timeout: TimeInterval = 5
    ) throws {
      let deadline = Date().addingTimeInterval(timeout)
      while Date() < deadline {
        if handler.frames().count >= count { return }
        Thread.sleep(forTimeInterval: 0.01)
      }
      XCTFail("stage frameを \(count) 件受信できませんでした")
    }

    func shutdown() throws {
      try channel.close().wait()
      try group.syncShutdownGracefully()
    }
  }

  private final class CollectingHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    private let lock = NSLock()
    private var received: [DecodedStageFramePacket] = []
    private var errors = 0
    private let decoder = StageFrameDecoder()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      let addressed = unwrapInboundIn(data)
      let buffer = addressed.data
      let bytes =
        buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) ?? []
      lock.lock()
      defer { lock.unlock() }
      if let packet = try? decoder.decode(bytes) {
        received.append(packet)
      } else {
        errors += 1
      }
    }

    func frames() -> [DecodedStageFramePacket] {
      lock.lock()
      defer { lock.unlock() }
      return received
    }

    func errorCount() -> Int {
      lock.lock()
      defer { lock.unlock() }
      return errors
    }
  }

  private func makeDistributor() throws -> (StageDistributor, HubStateStore) {
    let store = HubStateStore()
    let spaceID = try stageTestUUID(0x30)
    let resolver = try makeStageResolver(calibratedSpaceID: spaceID)
    store.apply(
      makeStageFrame(
        sessionID: try stageTestUUID(0x10),
        bridgeID: try stageTestUUID(0x20),
        trackingSpaceID: spaceID,
        receivedMonotonicNS: DispatchTime.now().uptimeNanoseconds,
        trackers: [
          makeStageTrackerPose(trackerID: "sim://tracker/001"),
          makeStageTrackerPose(trackerID: "sim://tracker/002", role: "left_foot"),
        ]
      )
    )

    let distributor = StageDistributor(
      sessionID: try stageTestUUID(0x80),
      sourceID: try stageTestUUID(0x90)
    )
    return (distributor, store)
  }

  private func snapshotProvider(
    store: HubStateStore,
    resolver: CalibrationResolver,
    publishRateHz: UInt16
  ) -> StageDistributor.SnapshotProvider {
    {
      StageFrameProjection.makeFrame(
        from: resolver.project(
          store.evaluatedSnapshot(
            atMonotonicNS: DispatchTime.now().uptimeNanoseconds
          )
        ),
        publishRateHz: publishRateHz
      )
    }
  }

  func test購読したclientへstageFrameを配信する() throws {
    let (distributor, store) = try makeDistributor()
    let resolver = try makeStageResolver(calibratedSpaceID: try stageTestUUID(0x30))
    let address = try distributor.start(
      configuration: .init(host: "127.0.0.1", port: 0, publishRateHz: 120),
      snapshotProvider: snapshotProvider(
        store: store,
        resolver: resolver,
        publishRateHz: 120
      )
    )
    defer { try? distributor.shutdown() }

    let client = TestClient()
    try client.start()
    defer { try? client.shutdown() }

    try client.subscribe(to: address)
    try client.waitForFrames(3)

    let frames = client.receivedFrames
    XCTAssertEqual(client.decodeErrors, 0)
    let first = try XCTUnwrap(frames.first)
    XCTAssertEqual(first.envelope.messageType, .stageFrame)
    XCTAssertEqual(
      first.envelope.sessionID.description,
      try stageTestUUID(0x80).description
    )
    XCTAssertEqual(first.frame.trackers.count, 2)
    XCTAssertEqual(first.frame.publishRateHz, 120)
    XCTAssertEqual(first.frame.trackers.map(\.trackerID).sorted(), [
      "sim://tracker/001",
      "sim://tracker/002",
    ])
    XCTAssertTrue(first.frame.trackers.allSatisfy { $0.delivery == .stage })

    // frame sequenceは配信ごとに単調増加する。
    let sequences = frames.map(\.envelope.frameSequence)
    XCTAssertEqual(sequences, sequences.sorted())
    XCTAssertEqual(Set(sequences).count, sequences.count)

    let statistics = distributor.statistics()
    XCTAssertGreaterThanOrEqual(statistics.publishedFrames, 3)
    XCTAssertEqual(statistics.activeSubscribers, 1)
    XCTAssertEqual(statistics.encodeErrors, 0)
    XCTAssertEqual(statistics.subscription.registrations, 1)
    XCTAssertEqual(statistics.subscribers.first?.clientName, "unity-test")
  }

  func test購読を更新しないと配信が止まる() throws {
    let (distributor, store) = try makeDistributor()
    let resolver = try makeStageResolver(calibratedSpaceID: try stageTestUUID(0x30))
    let address = try distributor.start(
      configuration: .init(host: "127.0.0.1", port: 0, publishRateHz: 120),
      snapshotProvider: snapshotProvider(
        store: store,
        resolver: resolver,
        publishRateHz: 120
      )
    )
    defer { try? distributor.shutdown() }

    let client = TestClient()
    try client.start()
    defer { try? client.shutdown() }

    // 最小TTLで購読し、更新しないまま期限を過ぎるのを待つ。
    try client.subscribe(to: address, ttlMS: StageWireProtocol.minimumSubscriptionTTLMS)
    try client.waitForFrames(2)

    // 「一定時間が経っても増えない」ことを確かめる否定的な検証のため、明示的に待つ。
    Thread.sleep(forTimeInterval: 0.5)
    let settled = client.receivedFrames.count
    Thread.sleep(forTimeInterval: 0.3)

    XCTAssertEqual(client.receivedFrames.count, settled)
    XCTAssertEqual(distributor.statistics().activeSubscribers, 0)
    XCTAssertGreaterThanOrEqual(distributor.statistics().subscription.expirations, 1)
  }

  func testUnsubscribeで配信を止める() throws {
    let (distributor, store) = try makeDistributor()
    let resolver = try makeStageResolver(calibratedSpaceID: try stageTestUUID(0x30))
    let address = try distributor.start(
      configuration: .init(host: "127.0.0.1", port: 0, publishRateHz: 120),
      snapshotProvider: snapshotProvider(
        store: store,
        resolver: resolver,
        publishRateHz: 120
      )
    )
    defer { try? distributor.shutdown() }

    let client = TestClient()
    try client.start()
    defer { try? client.shutdown() }

    try client.subscribe(to: address, ttlMS: 5_000)
    try client.waitForFrames(2)
    try client.subscribe(to: address, ttlMS: 5_000, unsubscribe: true)

    Thread.sleep(forTimeInterval: 0.3)
    let settled = client.receivedFrames.count
    Thread.sleep(forTimeInterval: 0.3)

    XCTAssertEqual(client.receivedFrames.count, settled)
    XCTAssertEqual(distributor.statistics().activeSubscribers, 0)
    XCTAssertEqual(distributor.statistics().subscription.unsubscribes, 1)
  }

  func test不正なdatagramで購読を登録しない() throws {
    let (distributor, store) = try makeDistributor()
    let resolver = try makeStageResolver(calibratedSpaceID: try stageTestUUID(0x30))
    let address = try distributor.start(
      configuration: .init(host: "127.0.0.1", port: 0, publishRateHz: 120),
      snapshotProvider: snapshotProvider(
        store: store,
        resolver: resolver,
        publishRateHz: 120
      )
    )
    defer { try? distributor.shutdown() }

    let client = TestClient()
    try client.start()
    defer { try? client.shutdown() }

    try client.send([UInt8](repeating: 0xab, count: 96), to: address)

    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline,
      distributor.statistics().invalidSubscriptionPackets == 0
    {
      Thread.sleep(forTimeInterval: 0.01)
    }

    let statistics = distributor.statistics()
    XCTAssertEqual(statistics.invalidSubscriptionPackets, 1)
    XCTAssertEqual(statistics.activeSubscribers, 0)
    XCTAssertEqual(statistics.subscription.registrations, 0)
    XCTAssertEqual(client.receivedFrames.count, 0)
  }

  func test購読者がいない間は送信しない() throws {
    let (distributor, store) = try makeDistributor()
    let resolver = try makeStageResolver(calibratedSpaceID: try stageTestUUID(0x30))
    _ = try distributor.start(
      configuration: .init(host: "127.0.0.1", port: 0, publishRateHz: 120),
      snapshotProvider: snapshotProvider(
        store: store,
        resolver: resolver,
        publishRateHz: 120
      )
    )
    defer { try? distributor.shutdown() }

    Thread.sleep(forTimeInterval: 0.3)

    let statistics = distributor.statistics()
    XCTAssertEqual(statistics.publishedFrames, 0)
    XCTAssertEqual(statistics.sentDatagrams, 0)
    XCTAssertGreaterThan(statistics.idlePublishTicks, 0)
  }
}
