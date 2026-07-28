import Foundation
import HubProtocol

/// stage plane v1のgolden packetをhexで標準出力へ書く。
///
/// C++のdivive_protocol_golden_toolと同じ役割を、encoderのあるSwift側で担う。
/// 出力を置き換えるだけでなく、schema互換性とprotocol versionの変更要否を
/// レビューすること。
///
///     swift run --package-path hub divive-stage-golden \
///       > protocol/golden/stage_v1.packet.hex

private func uuid(_ first: UInt8) -> UUIDBytes {
  // 先頭byteだけを変えた連番で、fixtureのUUIDを目視で区別できるようにする。
  try! UUIDBytes(bytes: (0..<16).map { first &+ UInt8($0) })
}

private let frame = StageFrameMessage(
  hubMonotonicNS: 987_654_321_000,
  generation: 1_234,
  profileID: "stage/default",
  profileRevision: 3,
  deliveryMode: .production,
  publishRateHz: 90,
  trackers: [
    StageTrackerRecord(
      trackerID: "htc/vive-tracker-3/LHR-ABC12345",
      role: "left_foot",
      idKind: .permanent,
      bridgeID: uuid(0x00),
      trackingSpaceID: uuid(0x30),
      spaceEpoch: 7,
      delivery: .stage,
      // +Yまわり90度。座標変換の実装差がそのまま値の差になる姿勢を選ぶ。
      pose: StagePose(
        position: Vector3(x: 1.25, y: 0.5, z: -2),
        orientation: Quaternion(x: 0, y: 0.707_106_77, z: 0, w: 0.707_106_77),
        linearVelocity: Vector3(x: 0.1, y: -0.2, z: 0.3),
        angularVelocity: Vector3(x: 0.01, y: 0.02, z: -0.03)
      ),
      trackingState: .tracking,
      trackingReason: .none,
      liveness: .fresh,
      connected: true,
      battery: BatteryStatus(level: 0.75, charging: false),
      receiveAgeNS: 1_200_000,
      sourceFrameSequence: 55_555,
      captureMonotonicNS: 123_456_789_000
    ),
    // velocityとbatteryを持たず、age評価でlostへ落ちたTracker。
    StageTrackerRecord(
      trackerID: "sim://tracker/002",
      role: "",
      idKind: .session,
      bridgeID: uuid(0x00),
      trackingSpaceID: uuid(0x30),
      spaceEpoch: 7,
      delivery: .stage,
      pose: StagePose(
        position: Vector3(x: 0, y: 1, z: 0),
        orientation: Quaternion(x: 0, y: 0, z: 0, w: 1),
        linearVelocity: nil,
        angularVelocity: nil
      ),
      trackingState: .lost,
      trackingReason: .networkStale,
      liveness: .stale,
      connected: true,
      battery: nil,
      receiveAgeNS: 400_000_000,
      sourceFrameSequence: 55_500,
      captureMonotonicNS: 123_456_000_000
    ),
    // 未較正spaceのため配信しないTracker。poseを持たない。
    StageTrackerRecord(
      trackerID: "htc/vive-ultimate/XYZ987654321",
      role: "prop_1",
      idKind: .permanent,
      bridgeID: uuid(0x10),
      trackingSpaceID: uuid(0x50),
      spaceEpoch: 2,
      delivery: .blocked,
      pose: nil,
      trackingState: .tracking,
      trackingReason: .none,
      liveness: .fresh,
      connected: true,
      battery: nil,
      receiveAgeNS: 2_000_000,
      sourceFrameSequence: 900,
      captureMonotonicNS: 123_400_000_000
    ),
  ]
)

do {
  let datagram = try StageFrameEncoder().encode(
    frame: frame,
    sessionID: uuid(0x20),
    sourceID: uuid(0x40),
    frameSequence: 4_242
  )
  print(datagram.map { String(format: "%02x", $0) }.joined())
} catch {
  fputs("stage golden packetを生成できませんでした: \(error)\n", stderr)
  exit(1)
}
