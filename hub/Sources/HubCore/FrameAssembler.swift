import HubProtocol

public enum FrameCompleteness: Equatable, Sendable {
  case complete
  case partial(missingBatchIndices: [UInt16])

  public var isComplete: Bool {
    if case .complete = self {
      return true
    }
    return false
  }
}

public struct AssembledPoseFrame: Equatable, Sendable {
  public let sessionID: UUIDBytes
  public let bridgeID: UUIDBytes
  public let frameSequence: UInt64
  public let expectedBatchCount: UInt16
  public let receivedBatchIndices: [UInt16]
  public let firstReceivedMonotonicNS: UInt64
  public let lastReceivedMonotonicNS: UInt64
  public let completeness: FrameCompleteness
  public let poseBatch: PoseBatch

  public init(
    sessionID: UUIDBytes,
    bridgeID: UUIDBytes,
    frameSequence: UInt64,
    expectedBatchCount: UInt16,
    receivedBatchIndices: [UInt16],
    firstReceivedMonotonicNS: UInt64,
    lastReceivedMonotonicNS: UInt64,
    completeness: FrameCompleteness,
    poseBatch: PoseBatch
  ) {
    self.sessionID = sessionID
    self.bridgeID = bridgeID
    self.frameSequence = frameSequence
    self.expectedBatchCount = expectedBatchCount
    self.receivedBatchIndices = receivedBatchIndices
    self.firstReceivedMonotonicNS = firstReceivedMonotonicNS
    self.lastReceivedMonotonicNS = lastReceivedMonotonicNS
    self.completeness = completeness
    self.poseBatch = poseBatch
  }
}

public enum FramePacketDisposition: Equatable, Sendable {
  case accepted
  case duplicateBatch
  case outOfOrder
  case inconsistentBatchCount
  case inconsistentMetadata
  case duplicateTrackerID

  public var wasAccepted: Bool {
    self == .accepted
  }
}

public struct FrameAssemblyResult: Equatable, Sendable {
  public let packetDisposition: FramePacketDisposition
  public let sessionChanged: Bool
  public let emittedFrames: [AssembledPoseFrame]

  public init(
    packetDisposition: FramePacketDisposition,
    sessionChanged: Bool,
    emittedFrames: [AssembledPoseFrame]
  ) {
    self.packetDisposition = packetDisposition
    self.sessionChanged = sessionChanged
    self.emittedFrames = emittedFrames
  }
}

public struct FrameAssemblerStatistics: Equatable, Sendable {
  public var acceptedBatches: UInt64 = 0
  public var completedFrames: UInt64 = 0
  public var partialFrames: UInt64 = 0
  public var duplicateBatches: UInt64 = 0
  public var outOfOrderBatches: UInt64 = 0
  public var inconsistentBatchCountBatches: UInt64 = 0
  public var inconsistentMetadataBatches: UInt64 = 0
  public var duplicateTrackerIDBatches: UInt64 = 0
  public var sessionChanges: UInt64 = 0
  public var pendingFrames: UInt64 = 0
}

/// Bridgeごとに未完成frameを最大1つ保持する複数batch再構成器。
///
/// 全batchが届けば直ちにcomplete frameを返す。欠落がある場合は次sequenceまたは
/// session切替時にpartial frameとして確定し、到着待ちqueueを成長させない。
public struct FrameAssembler: Sendable {
  private struct FrameMetadata: Equatable, Sendable {
    let trackingSpaceID: UUIDBytes
    let spaceEpoch: UInt32
    let captureMonotonicNS: UInt64
    let sendMonotonicNS: UInt64
    let requestedRateHz: UInt16
    let backend: Backend

    init(_ batch: PoseBatch) {
      trackingSpaceID = batch.trackingSpaceID
      spaceEpoch = batch.spaceEpoch
      captureMonotonicNS = batch.captureMonotonicNS
      sendMonotonicNS = batch.sendMonotonicNS
      requestedRateHz = batch.requestedRateHz
      backend = batch.backend
    }
  }

  private struct AcceptedBatch: Sendable {
    let trackers: [TrackerPose]
    let receivedMonotonicNS: UInt64
  }

  private struct PendingFrame: Sendable {
    let sessionID: UUIDBytes
    let bridgeID: UUIDBytes
    let frameSequence: UInt64
    let batchCount: UInt16
    let metadata: FrameMetadata
    var batches: [UInt16: AcceptedBatch]
    var trackerIDs: Set<String>
  }

  private struct Stream: Sendable {
    var sessionID: UUIDBytes
    var lastFinalizedSequence: UInt64?
    var pending: PendingFrame?
  }

  private var streams: [UUIDBytes: Stream] = [:]
  private var value = FrameAssemblerStatistics()

  public init() {}

  public mutating func ingest(
    _ packet: DecodedPosePacket,
    receivedMonotonicNS: UInt64
  ) -> FrameAssemblyResult {
    let envelope = packet.envelope
    let bridgeID = envelope.bridgeID
    var emittedFrames: [AssembledPoseFrame] = []
    var sessionChanged = false

    var stream: Stream
    if let existing = streams[bridgeID] {
      if existing.sessionID == envelope.sessionID {
        stream = existing
      } else {
        sessionChanged = true
        value.sessionChanges += 1
        if let pending = existing.pending {
          emittedFrames.append(finalize(pending))
        }
        stream = Stream(
          sessionID: envelope.sessionID,
          lastFinalizedSequence: nil,
          pending: nil
        )
      }
    } else {
      stream = Stream(
        sessionID: envelope.sessionID,
        lastFinalizedSequence: nil,
        pending: nil
      )
    }

    if let pending = stream.pending {
      if envelope.frameSequence < pending.frameSequence {
        value.outOfOrderBatches += 1
        streams[bridgeID] = stream
        return result(.outOfOrder, sessionChanged: sessionChanged, frames: emittedFrames)
      }

      if envelope.frameSequence > pending.frameSequence {
        emittedFrames.append(finalize(pending))
        stream.lastFinalizedSequence = pending.frameSequence
        stream.pending = nil
      }
    }

    if stream.pending == nil, let finalized = stream.lastFinalizedSequence {
      if envelope.frameSequence < finalized {
        value.outOfOrderBatches += 1
        streams[bridgeID] = stream
        return result(.outOfOrder, sessionChanged: sessionChanged, frames: emittedFrames)
      }
      if envelope.frameSequence == finalized {
        value.duplicateBatches += 1
        streams[bridgeID] = stream
        return result(
          .duplicateBatch,
          sessionChanged: sessionChanged,
          frames: emittedFrames
        )
      }
    }

    if hasDuplicateTrackerID(packet.poseBatch.trackers) {
      value.duplicateTrackerIDBatches += 1
      streams[bridgeID] = stream
      return result(
        .duplicateTrackerID,
        sessionChanged: sessionChanged,
        frames: emittedFrames
      )
    }

    if stream.pending == nil {
      stream.pending = PendingFrame(
        sessionID: envelope.sessionID,
        bridgeID: bridgeID,
        frameSequence: envelope.frameSequence,
        batchCount: envelope.batchCount,
        metadata: FrameMetadata(packet.poseBatch),
        batches: [:],
        trackerIDs: []
      )
    }

    guard var pending = stream.pending else {
      preconditionFailure("pending frameの初期化に失敗しました")
    }
    guard envelope.batchCount == pending.batchCount else {
      value.inconsistentBatchCountBatches += 1
      streams[bridgeID] = stream
      return result(
        .inconsistentBatchCount,
        sessionChanged: sessionChanged,
        frames: emittedFrames
      )
    }
    guard FrameMetadata(packet.poseBatch) == pending.metadata else {
      value.inconsistentMetadataBatches += 1
      streams[bridgeID] = stream
      return result(
        .inconsistentMetadata,
        sessionChanged: sessionChanged,
        frames: emittedFrames
      )
    }
    guard pending.batches[envelope.batchIndex] == nil else {
      value.duplicateBatches += 1
      streams[bridgeID] = stream
      return result(
        .duplicateBatch,
        sessionChanged: sessionChanged,
        frames: emittedFrames
      )
    }

    let incomingTrackerIDs = Set(packet.poseBatch.trackers.map(\.trackerID))
    guard pending.trackerIDs.isDisjoint(with: incomingTrackerIDs) else {
      value.duplicateTrackerIDBatches += 1
      streams[bridgeID] = stream
      return result(
        .duplicateTrackerID,
        sessionChanged: sessionChanged,
        frames: emittedFrames
      )
    }

    pending.batches[envelope.batchIndex] = AcceptedBatch(
      trackers: packet.poseBatch.trackers,
      receivedMonotonicNS: receivedMonotonicNS
    )
    pending.trackerIDs.formUnion(incomingTrackerIDs)
    stream.pending = pending
    value.acceptedBatches += 1

    if pending.batches.count == Int(pending.batchCount) {
      emittedFrames.append(finalize(pending))
      stream.lastFinalizedSequence = pending.frameSequence
      stream.pending = nil
    }

    streams[bridgeID] = stream
    value.pendingFrames = pendingFrameCount
    return result(.accepted, sessionChanged: sessionChanged, frames: emittedFrames)
  }

  /// shutdownやsource切替時に、各Bridgeの最後の未完成frameをpartialとして確定する。
  public mutating func flush() -> [AssembledPoseFrame] {
    var frames: [AssembledPoseFrame] = []
    for bridgeID in streams.keys.sorted(by: uuidLessThan) {
      guard var stream = streams[bridgeID], let pending = stream.pending else {
        continue
      }
      frames.append(finalize(pending))
      stream.lastFinalizedSequence = pending.frameSequence
      stream.pending = nil
      streams[bridgeID] = stream
    }
    value.pendingFrames = 0
    return frames
  }

  public func statistics() -> FrameAssemblerStatistics {
    var snapshot = value
    snapshot.pendingFrames = pendingFrameCount
    return snapshot
  }

  private var pendingFrameCount: UInt64 {
    UInt64(streams.values.lazy.compactMap(\.pending).count)
  }

  private mutating func finalize(_ pending: PendingFrame) -> AssembledPoseFrame {
    let receivedIndices = pending.batches.keys.sorted()
    let missingIndices =
      (0..<pending.batchCount).filter { pending.batches[$0] == nil }
    let receivedTimes = pending.batches.values.map(\.receivedMonotonicNS)
    let trackers = receivedIndices.flatMap { pending.batches[$0]?.trackers ?? [] }
    let completeness: FrameCompleteness =
      missingIndices.isEmpty
      ? .complete
      : .partial(missingBatchIndices: missingIndices)

    if completeness.isComplete {
      value.completedFrames += 1
    } else {
      value.partialFrames += 1
    }

    return AssembledPoseFrame(
      sessionID: pending.sessionID,
      bridgeID: pending.bridgeID,
      frameSequence: pending.frameSequence,
      expectedBatchCount: pending.batchCount,
      receivedBatchIndices: receivedIndices,
      firstReceivedMonotonicNS: receivedTimes.min() ?? 0,
      lastReceivedMonotonicNS: receivedTimes.max() ?? 0,
      completeness: completeness,
      poseBatch: PoseBatch(
        trackingSpaceID: pending.metadata.trackingSpaceID,
        spaceEpoch: pending.metadata.spaceEpoch,
        captureMonotonicNS: pending.metadata.captureMonotonicNS,
        sendMonotonicNS: pending.metadata.sendMonotonicNS,
        requestedRateHz: pending.metadata.requestedRateHz,
        backend: pending.metadata.backend,
        trackers: trackers
      )
    )
  }

  private func result(
    _ disposition: FramePacketDisposition,
    sessionChanged: Bool,
    frames: [AssembledPoseFrame]
  ) -> FrameAssemblyResult {
    FrameAssemblyResult(
      packetDisposition: disposition,
      sessionChanged: sessionChanged,
      emittedFrames: frames
    )
  }

  private func hasDuplicateTrackerID(_ trackers: [TrackerPose]) -> Bool {
    Set(trackers.map(\.trackerID)).count != trackers.count
  }

  private func uuidLessThan(_ left: UUIDBytes, _ right: UUIDBytes) -> Bool {
    left.bytes.lexicographicallyPrecedes(right.bytes)
  }
}
