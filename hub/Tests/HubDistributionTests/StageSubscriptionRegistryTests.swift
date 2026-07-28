import HubDistribution
import HubProtocol
import XCTest

final class StageSubscriptionRegistryTests: XCTestCase {
  private func packet(
    clientName: String = "unity",
    requestedRateHz: UInt16 = 90,
    ttlMS: UInt32 = 1_000,
    unsubscribe: Bool = false,
    clientSeed: UInt8 = 0x70
  ) throws -> DecodedStageSubscriptionPacket {
    DecodedStageSubscriptionPacket(
      envelope: PacketEnvelope(
        protocolMinor: 0,
        messageType: .stageSubscription,
        flags: 0,
        sessionID: try stageTestUUID(0x60),
        bridgeID: try stageTestUUID(clientSeed),
        frameSequence: 1,
        batchIndex: 0,
        batchCount: 1
      ),
      subscription: StageSubscriptionMessage(
        clientName: clientName,
        requestedRateHz: requestedRateHz,
        ttlMS: ttlMS,
        unsubscribe: unsubscribe
      )
    )
  }

  func test購読を登録して更新できる() throws {
    var registry = StageSubscriptionRegistry<String>()

    XCTAssertEqual(
      registry.register(
        try packet(),
        from: "client-a",
        address: "127.0.0.1:50001",
        isLoopback: true,
        atMonotonicNS: 0
      ),
      .registered
    )
    XCTAssertEqual(registry.count, 1)

    XCTAssertEqual(
      registry.register(
        try packet(),
        from: "client-a",
        address: "127.0.0.1:50001",
        isLoopback: true,
        atMonotonicNS: 500_000_000
      ),
      .renewed
    )
    XCTAssertEqual(registry.count, 1)

    let subscriber = try XCTUnwrap(registry.activeSubscribers().first)
    XCTAssertEqual(subscriber.clientName, "unity")
    XCTAssertEqual(subscriber.requestedRateHz, 90)
    XCTAssertEqual(subscriber.renewals, 1)
    // 登録時刻は更新で巻き戻らない。
    XCTAssertEqual(subscriber.registeredAtMonotonicNS, 0)
    XCTAssertEqual(subscriber.expiresAtMonotonicNS, 1_500_000_000)
    XCTAssertEqual(registry.statistics.registrations, 1)
    XCTAssertEqual(registry.statistics.renewals, 1)
  }

  func testTTLを過ぎた購読を配信先から外す() throws {
    var registry = StageSubscriptionRegistry<String>()
    registry.register(
      try packet(ttlMS: 1_000),
      from: "client-a",
      address: "127.0.0.1:50001",
      isLoopback: true,
      atMonotonicNS: 0
    )

    XCTAssertEqual(registry.prune(atMonotonicNS: 999_999_999).count, 1)
    XCTAssertEqual(registry.prune(atMonotonicNS: 1_000_000_000).count, 0)
    XCTAssertEqual(registry.count, 0)
    XCTAssertEqual(registry.statistics.expirations, 1)
  }

  func testLoopback以外からの購読を既定で拒否する() throws {
    var registry = StageSubscriptionRegistry<String>()

    XCTAssertEqual(
      registry.register(
        try packet(),
        from: "client-remote",
        address: "192.168.0.5:50001",
        isLoopback: false,
        atMonotonicNS: 0
      ),
      .rejectedNotLoopback
    )
    XCTAssertEqual(registry.count, 0)
    XCTAssertEqual(registry.statistics.rejectedNotLoopback, 1)

    var permissive = StageSubscriptionRegistry<String>(allowNonLoopbackClients: true)
    XCTAssertEqual(
      permissive.register(
        try packet(),
        from: "client-remote",
        address: "192.168.0.5:50001",
        isLoopback: false,
        atMonotonicNS: 0
      ),
      .registered
    )
  }

  func test上限を超える購読を拒否する() throws {
    var registry = StageSubscriptionRegistry<String>(maximumSubscribers: 2)
    for index in 0..<2 {
      XCTAssertEqual(
        registry.register(
          try packet(),
          from: "client-\(index)",
          address: "127.0.0.1:5000\(index)",
          isLoopback: true,
          atMonotonicNS: UInt64(index)
        ),
        .registered
      )
    }

    XCTAssertEqual(
      registry.register(
        try packet(),
        from: "client-overflow",
        address: "127.0.0.1:59999",
        isLoopback: true,
        atMonotonicNS: 3
      ),
      .rejectedCapacity
    )
    XCTAssertEqual(registry.count, 2)
    XCTAssertEqual(registry.statistics.rejectedCapacity, 1)

    // 上限に達していても、登録済みclientの更新は通す。
    XCTAssertEqual(
      registry.register(
        try packet(),
        from: "client-0",
        address: "127.0.0.1:50000",
        isLoopback: true,
        atMonotonicNS: 4
      ),
      .renewed
    )
  }

  func testUnsubscribeで配信先から外す() throws {
    var registry = StageSubscriptionRegistry<String>()
    registry.register(
      try packet(),
      from: "client-a",
      address: "127.0.0.1:50001",
      isLoopback: true,
      atMonotonicNS: 0
    )

    XCTAssertEqual(
      registry.register(
        try packet(unsubscribe: true),
        from: "client-a",
        address: "127.0.0.1:50001",
        isLoopback: true,
        atMonotonicNS: 1
      ),
      .unsubscribed
    )
    XCTAssertEqual(registry.count, 0)

    // 未登録clientのunsubscribeは統計を動かさない。
    XCTAssertEqual(
      registry.register(
        try packet(unsubscribe: true),
        from: "client-b",
        address: "127.0.0.1:50002",
        isLoopback: true,
        atMonotonicNS: 2
      ),
      .ignored
    )
    XCTAssertEqual(registry.statistics.unsubscribes, 1)
  }

  func testTTLを許容範囲へ丸める() throws {
    var registry = StageSubscriptionRegistry<String>()

    registry.register(
      try packet(ttlMS: 0),
      from: "default",
      address: "127.0.0.1:1",
      isLoopback: true,
      atMonotonicNS: 0
    )
    registry.register(
      try packet(ttlMS: 1),
      from: "tooShort",
      address: "127.0.0.1:2",
      isLoopback: true,
      atMonotonicNS: 0
    )
    registry.register(
      try packet(ttlMS: 10_000_000),
      from: "tooLong",
      address: "127.0.0.1:3",
      isLoopback: true,
      atMonotonicNS: 0
    )

    let expirations = Dictionary(
      uniqueKeysWithValues: registry.activeSubscribers().map {
        ($0.key, $0.expiresAtMonotonicNS)
      }
    )
    XCTAssertEqual(
      expirations["default"],
      UInt64(StageWireProtocol.defaultSubscriptionTTLMS) * 1_000_000
    )
    XCTAssertEqual(
      expirations["tooShort"],
      UInt64(StageWireProtocol.minimumSubscriptionTTLMS) * 1_000_000
    )
    XCTAssertEqual(
      expirations["tooLong"],
      UInt64(StageWireProtocol.maximumSubscriptionTTLMS) * 1_000_000
    )
  }
}
