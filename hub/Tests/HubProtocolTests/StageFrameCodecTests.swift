import HubProtocol
import XCTest

final class StageFrameCodecTests: XCTestCase {
  private let goldenPath = "protocol/golden/stage_v1.packet.hex"
  private let unityFixturePath =
    "unity/com.divive.tracking/Tests/Editor/Fixtures/stage_v1.packet.hex.txt"

  private func goldenPacket() throws -> [UInt8] {
    try GoldenFixture.packet(atRepositoryPath: goldenPath)
  }

  func testGoldenPacketをdecodeできる() throws {
    let packet = try StageFrameDecoder().decode(try goldenPacket())

    XCTAssertEqual(packet.envelope.messageType, .stageFrame)
    XCTAssertEqual(packet.envelope.protocolMinor, 0)
    XCTAssertEqual(
      packet.envelope.sessionID.description,
      "20212223-2425-2627-2829-2a2b2c2d2e2f"
    )
    XCTAssertEqual(
      packet.envelope.bridgeID.description,
      "40414243-4445-4647-4849-4a4b4c4d4e4f"
    )
    XCTAssertEqual(packet.envelope.frameSequence, 4_242)
    XCTAssertEqual(packet.envelope.batchIndex, 0)
    XCTAssertEqual(packet.envelope.batchCount, 1)

    let frame = packet.frame
    XCTAssertEqual(frame.hubMonotonicNS, 987_654_321_000)
    XCTAssertEqual(frame.generation, 1_234)
    XCTAssertEqual(frame.profileID, "stage/default")
    XCTAssertEqual(frame.profileRevision, 3)
    XCTAssertEqual(frame.deliveryMode, .production)
    XCTAssertEqual(frame.publishRateHz, 90)
    XCTAssertEqual(frame.trackers.count, 3)

    let tracking = frame.trackers[0]
    XCTAssertEqual(tracking.trackerID, "htc/vive-tracker-3/LHR-ABC12345")
    XCTAssertEqual(tracking.role, "left_foot")
    XCTAssertEqual(tracking.idKind, .permanent)
    XCTAssertEqual(
      tracking.bridgeID.description,
      "00010203-0405-0607-0809-0a0b0c0d0e0f"
    )
    XCTAssertEqual(
      tracking.trackingSpaceID.description,
      "30313233-3435-3637-3839-3a3b3c3d3e3f"
    )
    XCTAssertEqual(tracking.spaceEpoch, 7)
    XCTAssertEqual(tracking.delivery, .stage)
    XCTAssertEqual(
      tracking.pose?.position,
      Vector3(x: 1.25, y: 0.5, z: -2)
    )
    XCTAssertEqual(
      tracking.pose?.orientation,
      Quaternion(x: 0, y: 0.707_106_77, z: 0, w: 0.707_106_77)
    )
    XCTAssertEqual(
      tracking.pose?.linearVelocity,
      Vector3(x: 0.1, y: -0.2, z: 0.3)
    )
    XCTAssertEqual(tracking.trackingState, .tracking)
    XCTAssertEqual(tracking.trackingReason, .none)
    XCTAssertEqual(tracking.liveness, .fresh)
    XCTAssertTrue(tracking.connected)
    XCTAssertEqual(tracking.battery, BatteryStatus(level: 0.75, charging: false))
    XCTAssertEqual(tracking.receiveAgeNS, 1_200_000)
    XCTAssertEqual(tracking.sourceFrameSequence, 55_555)
    XCTAssertEqual(tracking.captureMonotonicNS, 123_456_789_000)

    let stale = frame.trackers[1]
    XCTAssertEqual(stale.trackerID, "sim://tracker/002")
    XCTAssertEqual(stale.role, "")
    XCTAssertEqual(stale.idKind, .session)
    XCTAssertNil(stale.pose?.linearVelocity)
    XCTAssertNil(stale.pose?.angularVelocity)
    XCTAssertNil(stale.battery)
    XCTAssertEqual(stale.trackingState, .lost)
    XCTAssertEqual(stale.trackingReason, .networkStale)
    XCTAssertEqual(stale.liveness, .stale)

    let blocked = frame.trackers[2]
    XCTAssertEqual(blocked.trackerID, "htc/vive-ultimate/XYZ987654321")
    XCTAssertEqual(blocked.delivery, .blocked)
    XCTAssertNil(blocked.pose)
    XCTAssertEqual(blocked.spaceEpoch, 2)
  }

  func testGoldenPacketをdecodeしてencodeするとbyte一致する() throws {
    let packet = try goldenPacket()
    let decoded = try StageFrameDecoder().decode(packet)
    let reencoded = try StageFrameEncoder().encode(
      frame: decoded.frame,
      sessionID: decoded.envelope.sessionID,
      sourceID: decoded.envelope.bridgeID,
      frameSequence: decoded.envelope.frameSequence
    )

    XCTAssertEqual(reencoded, packet)
  }

  /// Unity Packageは単体で配布できるようfixtureを同梱する。
  /// 二重管理になるため、protocol/goldenとの乖離をここで機械的に止める。
  func testUnityPackageのfixtureがgoldenと一致する() throws {
    let golden = try GoldenFixture.hexText(atRepositoryPath: goldenPath)
    let packaged = try GoldenFixture.hexText(atRepositoryPath: unityFixturePath)

    XCTAssertEqual(
      packaged.filter { !$0.isWhitespace },
      golden.filter { !$0.isWhitespace },
      "unity/com.divive.tracking のfixtureが protocol/golden と一致しません"
    )
  }

  func testPosePlaneのpacketをstagedecoderが拒否する() throws {
    XCTAssertThrowsError(try StageFrameDecoder().decode(GoldenFixture.packet())) {
      XCTAssertEqual(
        $0 as? PacketDecodeError,
        .unexpectedMessageType
      )
    }
  }

  func testBlockedなTrackerがposeを持つとencodeできない() throws {
    let frame = makeFrame(
      trackers: [
        makeTracker(
          delivery: .blocked,
          pose: StagePose(
            position: Vector3(x: 0, y: 0, z: 0),
            orientation: Quaternion(x: 0, y: 0, z: 0, w: 1),
            linearVelocity: nil,
            angularVelocity: nil
          )
        )
      ]
    )

    XCTAssertThrowsError(try encode(frame)) {
      XCTAssertEqual(
        $0 as? StageEncodeError,
        .blockedTrackerCarriesPose(trackerID: "sim://tracker/001")
      )
    }
  }

  func testStageなTrackerがposeを持たないとencodeできない() throws {
    let frame = makeFrame(
      trackers: [makeTracker(delivery: .stage, pose: nil)]
    )

    XCTAssertThrowsError(try encode(frame)) {
      XCTAssertEqual(
        $0 as? StageEncodeError,
        .missingPose(trackerID: "sim://tracker/001")
      )
    }
  }

  func test非正規化QuaternionとNaNをencodeできない() throws {
    let nonNormalized = makeFrame(
      trackers: [
        makeTracker(
          delivery: .stage,
          pose: StagePose(
            position: Vector3(x: 0, y: 0, z: 0),
            orientation: Quaternion(x: 0, y: 0, z: 0, w: 0.5),
            linearVelocity: nil,
            angularVelocity: nil
          )
        )
      ]
    )
    XCTAssertThrowsError(try encode(nonNormalized)) {
      XCTAssertEqual(
        $0 as? StageEncodeError,
        .nonNormalizedQuaternion(trackerID: "sim://tracker/001")
      )
    }

    let nonFinite = makeFrame(
      trackers: [
        makeTracker(
          delivery: .stage,
          pose: StagePose(
            position: Vector3(x: .nan, y: 0, z: 0),
            orientation: Quaternion(x: 0, y: 0, z: 0, w: 1),
            linearVelocity: nil,
            angularVelocity: nil
          )
        )
      ]
    )
    XCTAssertThrowsError(try encode(nonFinite)) {
      XCTAssertEqual(
        $0 as? StageEncodeError,
        .nonFiniteValue(trackerID: "sim://tracker/001")
      )
    }
  }

  func testDatagram上限を超えるframeをencodeできない() throws {
    let trackers = (0..<64).map { index in
      makeTracker(
        trackerID: "htc/vive-tracker-3/LHR-\(String(format: "%08d", index))",
        delivery: .stage,
        pose: StagePose(
          position: Vector3(x: 0, y: 0, z: 0),
          orientation: Quaternion(x: 0, y: 0, z: 0, w: 1),
          linearVelocity: Vector3(x: 0, y: 0, z: 0),
          angularVelocity: Vector3(x: 0, y: 0, z: 0)
        )
      )
    }

    XCTAssertThrowsError(try encode(makeFrame(trackers: trackers))) { error in
      guard case .payloadTooLarge = error as? PacketEncodeError else {
        return XCTFail("payload_too_largeを期待しましたが \(error) でした")
      }
    }
  }

  func test購読messageをroundtripできる() throws {
    let codec = StageSubscriptionCodec()
    let datagram = try codec.encode(
      subscription: StageSubscriptionMessage(
        clientName: "unity-sample",
        requestedRateHz: 90,
        ttlMS: 3_000
      ),
      sessionID: try uuid(0x60),
      clientID: try uuid(0x70),
      sequence: 12
    )
    let decoded = try codec.decode(datagram)

    XCTAssertEqual(decoded.envelope.messageType, .stageSubscription)
    XCTAssertEqual(decoded.envelope.frameSequence, 12)
    XCTAssertEqual(decoded.subscription.clientName, "unity-sample")
    XCTAssertEqual(decoded.subscription.requestedRateHz, 90)
    XCTAssertEqual(decoded.subscription.ttlMS, 3_000)
    XCTAssertFalse(decoded.subscription.unsubscribe)
  }

  func test長すぎるclient名を切り詰める() throws {
    let codec = StageSubscriptionCodec()
    let datagram = try codec.encode(
      subscription: StageSubscriptionMessage(clientName: String(repeating: "a", count: 512)),
      sessionID: try uuid(0x60),
      clientID: try uuid(0x70),
      sequence: 1
    )
    let decoded = try codec.decode(datagram)

    XCTAssertEqual(
      decoded.subscription.clientName.count,
      StageWireProtocol.maximumClientNameLength
    )
  }

  func testStageFrameを購読decoderが拒否する() throws {
    XCTAssertThrowsError(try StageSubscriptionCodec().decode(try goldenPacket())) {
      XCTAssertEqual($0 as? PacketDecodeError, .unexpectedMessageType)
    }
  }

  private func encode(_ frame: StageFrameMessage) throws -> [UInt8] {
    try StageFrameEncoder().encode(
      frame: frame,
      sessionID: try uuid(0x20),
      sourceID: try uuid(0x40),
      frameSequence: 1
    )
  }

  private func uuid(_ first: UInt8) throws -> UUIDBytes {
    try UUIDBytes(bytes: (0..<16).map { first &+ UInt8($0) })
  }

  private func makeFrame(trackers: [StageTrackerRecord]) -> StageFrameMessage {
    StageFrameMessage(
      hubMonotonicNS: 1,
      generation: 1,
      profileID: "stage/test",
      profileRevision: 1,
      deliveryMode: .production,
      publishRateHz: 90,
      trackers: trackers
    )
  }

  private func makeTracker(
    trackerID: String = "sim://tracker/001",
    delivery: StageDelivery,
    pose: StagePose?
  ) -> StageTrackerRecord {
    StageTrackerRecord(
      trackerID: trackerID,
      role: "waist",
      idKind: .session,
      bridgeID: (try? uuid(0x00)) ?? .zero,
      trackingSpaceID: (try? uuid(0x30)) ?? .zero,
      spaceEpoch: 1,
      delivery: delivery,
      pose: pose,
      trackingState: .simulated,
      trackingReason: .none,
      liveness: .fresh,
      connected: true,
      battery: nil,
      receiveAgeNS: 0,
      sourceFrameSequence: 1,
      captureMonotonicNS: 1
    )
  }
}
