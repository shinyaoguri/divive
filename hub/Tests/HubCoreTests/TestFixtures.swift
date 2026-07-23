import HubCore
import HubProtocol

func testUUID(_ seed: UInt8) throws -> UUIDBytes {
  try UUIDBytes(bytes: (0..<16).map { seed &+ UInt8($0) })
}

func testTracker(_ id: String, x: Float = 0) -> TrackerPose {
  TrackerPose(
    trackerID: id,
    idKind: .session,
    role: id,
    runtimeRole: "",
    position: Vector3(x: x, y: 1, z: -1),
    orientation: Quaternion(x: 0, y: 0, z: 0, w: 1),
    linearVelocity: nil,
    angularVelocity: nil,
    trackingState: .simulated,
    trackingReason: .none,
    connected: true,
    battery: nil,
    deviceMetadataRevision: 1
  )
}

func testPacket(
  session: UUIDBytes,
  bridge: UUIDBytes,
  trackingSpace: UUIDBytes,
  sequence: UInt64,
  batchIndex: UInt16 = 0,
  batchCount: UInt16 = 1,
  trackers: [TrackerPose],
  spaceEpoch: UInt32 = 1,
  captureMonotonicNS: UInt64? = nil,
  sendMonotonicNS: UInt64? = nil
) -> DecodedPosePacket {
  let capture = captureMonotonicNS ?? sequence * 1_000
  return DecodedPosePacket(
    envelope: PacketEnvelope(
      protocolMinor: 0,
      messageType: .poseBatch,
      flags: 0,
      sessionID: session,
      bridgeID: bridge,
      frameSequence: sequence,
      batchIndex: batchIndex,
      batchCount: batchCount
    ),
    poseBatch: PoseBatch(
      trackingSpaceID: trackingSpace,
      spaceEpoch: spaceEpoch,
      captureMonotonicNS: capture,
      sendMonotonicNS: sendMonotonicNS ?? capture + 10,
      requestedRateHz: 90,
      backend: .simulator,
      trackers: trackers
    )
  )
}

func testFrame(
  session: UUIDBytes,
  bridge: UUIDBytes,
  trackingSpace: UUIDBytes,
  sequence: UInt64,
  trackers: [TrackerPose],
  receivedMonotonicNS: UInt64,
  spaceEpoch: UInt32 = 1,
  completeness: FrameCompleteness = .complete
) -> AssembledPoseFrame {
  let expectedBatchCount: UInt16
  let receivedBatchIndices: [UInt16]
  switch completeness {
  case .complete:
    expectedBatchCount = 1
    receivedBatchIndices = [0]
  case .partial(let missing):
    expectedBatchCount = UInt16(missing.count + 1)
    receivedBatchIndices = [0]
  }

  return AssembledPoseFrame(
    sessionID: session,
    bridgeID: bridge,
    frameSequence: sequence,
    expectedBatchCount: expectedBatchCount,
    receivedBatchIndices: receivedBatchIndices,
    firstReceivedMonotonicNS: receivedMonotonicNS,
    lastReceivedMonotonicNS: receivedMonotonicNS,
    completeness: completeness,
    poseBatch: PoseBatch(
      trackingSpaceID: trackingSpace,
      spaceEpoch: spaceEpoch,
      captureMonotonicNS: sequence * 1_000,
      sendMonotonicNS: sequence * 1_000 + 10,
      requestedRateHz: 90,
      backend: .simulator,
      trackers: trackers
    )
  )
}
