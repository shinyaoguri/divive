import HubProtocol
import XCTest

final class PosePacketDecoderTests: XCTestCase {
  func testGoldenPacketをCPlusPlusと同じ値へdecodeできる() throws {
    let packet = try PosePacketDecoder().decode(GoldenFixture.packet())

    XCTAssertEqual(packet.envelope.protocolMinor, 0)
    XCTAssertEqual(
      packet.envelope.sessionID.description,
      "00010203-0405-0607-0809-0a0b0c0d0e0f"
    )
    XCTAssertEqual(
      packet.envelope.bridgeID.description,
      "10111213-1415-1617-1819-1a1b1c1d1e1f"
    )
    XCTAssertEqual(packet.envelope.frameSequence, 0x0102_0304_0506_0708)
    XCTAssertEqual(packet.envelope.batchIndex, 0)
    XCTAssertEqual(packet.envelope.batchCount, 1)

    XCTAssertEqual(
      packet.poseBatch.trackingSpaceID.description,
      "30313233-3435-3637-3839-3a3b3c3d3e3f"
    )
    XCTAssertEqual(packet.poseBatch.spaceEpoch, 7)
    XCTAssertEqual(packet.poseBatch.captureMonotonicNS, 123_456_789_000)
    XCTAssertEqual(packet.poseBatch.sendMonotonicNS, 123_456_789_500)
    XCTAssertEqual(packet.poseBatch.requestedRateHz, 120)
    XCTAssertEqual(packet.poseBatch.backend, .openvr)
    XCTAssertEqual(packet.poseBatch.trackers.count, 2)

    let tracking = packet.poseBatch.trackers[0]
    XCTAssertEqual(tracking.trackerID, "htc/vive-tracker-3/LHR-ABC12345")
    XCTAssertEqual(tracking.role, "left_foot")
    XCTAssertEqual(tracking.position, Vector3(x: 1.25, y: 2.5, z: -3.75))
    XCTAssertEqual(tracking.trackingState, .tracking)
    XCTAssertEqual(tracking.battery, BatteryStatus(level: 0.75, charging: true))

    let lost = packet.poseBatch.trackers[1]
    XCTAssertEqual(lost.trackerID, "session/openvr/5")
    XCTAssertEqual(lost.trackingState, .lost)
    XCTAssertEqual(lost.trackingReason, .runtimePoseInvalid)
    XCTAssertNil(lost.linearVelocity)
    XCTAssertNil(lost.battery)
  }

  func testEnvelope破損をpayloadへ進む前に拒否する() throws {
    let original = try GoldenFixture.packet()
    let cases: [(Int, UInt8, PacketDecodeError)] = [
      (0, 0, .badMagic),
      (4, 2, .unsupportedProtocolMajor),
      (7, 1, .unsupportedFlags),
      (15, 0, .invalidBatch),
      (16, 0, .nilSessionID),
      (32, 0, .nilBridgeID),
      (56, 1, .unexpectedAuthTag),
    ]

    for (offset, value, expectedError) in cases {
      var packet = original
      if expectedError == .nilSessionID || expectedError == .nilBridgeID {
        let end = offset + UUIDBytes.byteCount
        packet.replaceSubrange(offset..<end, with: repeatElement(0, count: 16))
      } else {
        packet[offset] = value
      }

      XCTAssertThrowsError(
        try PosePacketDecoder().decode(packet),
        "期待したerror: \(expectedError)"
      ) { error in
        XCTAssertEqual(error as? PacketDecodeError, expectedError)
      }
    }
  }

  func test短すぎるpacketと破損FlatBuffersを拒否する() throws {
    XCTAssertThrowsError(try PosePacketDecoder().decode([0])) { error in
      XCTAssertEqual(error as? PacketDecodeError, .datagramTooShort)
    }

    var packet = try GoldenFixture.packet()
    packet[76] ^= 0xff
    XCTAssertThrowsError(try PosePacketDecoder().decode(packet)) { error in
      XCTAssertEqual(error as? PacketDecodeError, .flatbufferInvalid)
    }
  }
}
