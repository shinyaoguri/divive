import Foundation
import HubCalibration
import HubCore
import HubProtocol

func stageTestUUID(_ seed: UInt8) throws -> UUIDBytes {
  try UUIDBytes(bytes: (0..<16).map { seed &+ UInt8($0) })
}

func makeStageTrackerPose(
  trackerID: String,
  role: String = "waist",
  position: Vector3 = Vector3(x: 1, y: 2, z: 3),
  orientation: Quaternion = Quaternion(x: 0, y: 0, z: 0, w: 1),
  trackingState: TrackingState = .tracking,
  connected: Bool = true
) -> TrackerPose {
  TrackerPose(
    trackerID: trackerID,
    idKind: .permanent,
    role: role,
    runtimeRole: "generic_tracker",
    position: position,
    orientation: orientation,
    linearVelocity: Vector3(x: 0.1, y: 0.2, z: 0.3),
    angularVelocity: Vector3(x: 0.01, y: 0.02, z: 0.03),
    trackingState: trackingState,
    trackingReason: .none,
    connected: connected,
    battery: BatteryStatus(level: 0.5, charging: false),
    deviceMetadataRevision: 1
  )
}

/// 実際のingest経路と同じAssembledPoseFrameを組み立てる。
func makeStageFrame(
  sessionID: UUIDBytes,
  bridgeID: UUIDBytes,
  trackingSpaceID: UUIDBytes,
  spaceEpoch: UInt32 = 1,
  frameSequence: UInt64 = 1,
  receivedMonotonicNS: UInt64,
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
    poseBatch: PoseBatch(
      trackingSpaceID: trackingSpaceID,
      spaceEpoch: spaceEpoch,
      captureMonotonicNS: 1_000,
      sendMonotonicNS: 1_100,
      requestedRateHz: 90,
      backend: .simulator,
      trackers: trackers
    )
  )
}

func makeStageResolver(
  calibratedSpaceID: UUIDBytes?,
  spaceEpoch: UInt32 = 1,
  mode: CalibrationDeliveryMode = .production,
  translation: Vector3 = Vector3(x: 0, y: 0, z: 0)
) throws -> CalibrationResolver {
  var spaces: [SpaceCalibration] = []
  if let calibratedSpaceID {
    spaces.append(
      try SpaceCalibration(
        trackingSpaceID: calibratedSpaceID,
        spaceEpoch: spaceEpoch,
        transform: try RigidTransform(
          translation: translation,
          rotation: Quaternion(x: 0, y: 0, z: 0, w: 1)
        ),
        method: .manual,
        sampleCount: 4,
        rmsErrorM: 0.001,
        maxResidualM: 0.002,
        operatorNote: "test",
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
      )
    )
  }

  return CalibrationResolver(
    profile: try CalibrationProfile(
      profileID: "stage-test",
      name: "Stage Test",
      revision: 5,
      createdAt: Date(timeIntervalSince1970: 1_800_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
      applicationVersion: "0.1.0-test",
      spaces: spaces
    ),
    mode: mode
  )
}
