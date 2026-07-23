public enum SequenceDisposition: Equatable, Sendable {
  case sessionStarted
  case newFrame(missingFrames: UInt64, missingBatches: UInt16)
  case additionalBatch
  case duplicate
  case outOfOrder
  case inconsistentBatchCount

  public var shouldApplyPose: Bool {
    switch self {
    case .sessionStarted, .newFrame, .additionalBatch:
      true
    case .duplicate, .outOfOrder, .inconsistentBatchCount:
      false
    }
  }
}

/// Bridgeごとのsession、frame sequence、batch受信状況を追跡する。
public struct SequenceLedger: Sendable {
  private struct Stream: Sendable {
    var sessionID: UUIDBytes
    var frameSequence: UInt64
    var batchCount: UInt16
    var receivedBatches: Set<UInt16>
  }

  private var streams: [UUIDBytes: Stream] = [:]

  public init() {}

  public mutating func observe(_ envelope: PacketEnvelope) -> SequenceDisposition {
    guard var stream = streams[envelope.bridgeID],
      stream.sessionID == envelope.sessionID
    else {
      streams[envelope.bridgeID] = Stream(
        sessionID: envelope.sessionID,
        frameSequence: envelope.frameSequence,
        batchCount: envelope.batchCount,
        receivedBatches: [envelope.batchIndex]
      )
      return .sessionStarted
    }

    if envelope.frameSequence < stream.frameSequence {
      return .outOfOrder
    }

    if envelope.frameSequence == stream.frameSequence {
      guard envelope.batchCount == stream.batchCount else {
        return .inconsistentBatchCount
      }
      guard stream.receivedBatches.insert(envelope.batchIndex).inserted else {
        return .duplicate
      }
      streams[envelope.bridgeID] = stream
      return .additionalBatch
    }

    let missingFrames = envelope.frameSequence - stream.frameSequence - 1
    let receivedBatchCount = UInt16(clamping: stream.receivedBatches.count)
    let missingBatches = stream.batchCount - min(stream.batchCount, receivedBatchCount)
    streams[envelope.bridgeID] = Stream(
      sessionID: envelope.sessionID,
      frameSequence: envelope.frameSequence,
      batchCount: envelope.batchCount,
      receivedBatches: [envelope.batchIndex]
    )
    return .newFrame(
      missingFrames: missingFrames,
      missingBatches: missingBatches
    )
  }
}
