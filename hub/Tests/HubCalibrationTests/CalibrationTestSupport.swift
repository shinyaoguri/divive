import Foundation
import HubCalibration
import HubCore
import HubProtocol
import XCTest

let calibrationTestDate = Date(timeIntervalSince1970: 1_800_000_000)

func calibrationTestUUID(_ seed: UInt8) throws -> UUIDBytes {
  try UUIDBytes(bytes: (0..<16).map { seed &+ UInt8($0) })
}

func makeTransform(
  translation: Vector3 = Vector3(x: 0, y: 0, z: 0),
  rotation: Quaternion = Quaternion(x: 0, y: 0, z: 0, w: 1)
) throws -> RigidTransform {
  try RigidTransform(translation: translation, rotation: rotation)
}

func makeSpaceCalibration(
  trackingSpaceID: UUIDBytes,
  spaceEpoch: UInt32 = 1,
  transform: RigidTransform = .identity,
  method: CalibrationMethod = .manual,
  sampleCount: UInt32 = 4,
  rmsErrorM: Double? = 0.003,
  maxResidualM: Double? = 0.006,
  operatorNote: String? = "test",
  updatedAt: Date = calibrationTestDate
) throws -> SpaceCalibration {
  try SpaceCalibration(
    trackingSpaceID: trackingSpaceID,
    spaceEpoch: spaceEpoch,
    transform: transform,
    method: method,
    sampleCount: sampleCount,
    rmsErrorM: rmsErrorM,
    maxResidualM: maxResidualM,
    operatorNote: operatorNote,
    updatedAt: updatedAt
  )
}

func makeProfile(
  profileID: String = "studio-a",
  name: String = "Studio A",
  revision: UInt32 = 1,
  spaces: [SpaceCalibration] = []
) throws -> CalibrationProfile {
  try CalibrationProfile(
    profileID: profileID,
    name: name,
    revision: revision,
    createdAt: calibrationTestDate,
    updatedAt: calibrationTestDate,
    applicationVersion: "0.1.0-test",
    spaces: spaces
  )
}

func makeTrackerPose(
  trackerID: String = "tracker-1",
  position: Vector3,
  orientation: Quaternion = Quaternion(x: 0, y: 0, z: 0, w: 1),
  linearVelocity: Vector3? = nil,
  angularVelocity: Vector3? = nil
) -> TrackerPose {
  TrackerPose(
    trackerID: trackerID,
    idKind: .permanent,
    role: "left-foot",
    runtimeRole: "generic_tracker",
    position: position,
    orientation: orientation,
    linearVelocity: linearVelocity,
    angularVelocity: angularVelocity,
    trackingState: .tracking,
    trackingReason: .none,
    connected: true,
    battery: nil,
    deviceMetadataRevision: 3
  )
}

func makePoseBatch(
  trackingSpaceID: UUIDBytes,
  spaceEpoch: UInt32 = 1,
  trackers: [TrackerPose]
) -> PoseBatch {
  PoseBatch(
    trackingSpaceID: trackingSpaceID,
    spaceEpoch: spaceEpoch,
    captureMonotonicNS: 1_000,
    sendMonotonicNS: 1_100,
    requestedRateHz: 120,
    backend: .openvr,
    trackers: trackers
  )
}

func makeAssembledFrame(
  bridgeID: UUIDBytes,
  sessionID: UUIDBytes,
  trackingSpaceID: UUIDBytes,
  spaceEpoch: UInt32 = 1,
  frameSequence: UInt64 = 1,
  receivedMonotonicNS: UInt64 = 1_000,
  trackers: [TrackerPose]
) -> AssembledPoseFrame {
  AssembledPoseFrame(
    sessionID: sessionID,
    bridgeID: bridgeID,
    frameSequence: frameSequence,
    expectedBatchCount: 1,
    receivedBatchIndices: [0],
    firstReceivedMonotonicNS: receivedMonotonicNS,
    lastReceivedMonotonicNS: receivedMonotonicNS,
    completeness: .complete,
    poseBatch: makePoseBatch(
      trackingSpaceID: trackingSpaceID,
      spaceEpoch: spaceEpoch,
      trackers: trackers
    )
  )
}

func assertVector(
  _ actual: Vector3,
  _ expected: Vector3,
  accuracy: Float = 1.0e-5,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "\(message) x", file: file, line: line)
  XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "\(message) y", file: file, line: line)
  XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, "\(message) z", file: file, line: line)
}

/// quaternion `q`と`-q`は同じrotationのため、成分ではなく回転として比較する。
func assertSameRotation(
  _ actual: Quaternion,
  _ expected: Quaternion,
  accuracy: Double = 1.0e-5,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  let dot =
    Double(actual.x) * Double(expected.x)
    + Double(actual.y) * Double(expected.y)
    + Double(actual.z) * Double(expected.z)
    + Double(actual.w) * Double(expected.w)
  XCTAssertEqual(
    abs(dot),
    1.0,
    accuracy: accuracy,
    "\(message) rotationが一致しません actual=\(actual) expected=\(expected)",
    file: file,
    line: line
  )
}
