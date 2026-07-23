import Foundation
import HubProtocol

public struct TrackerKey: Hashable, Sendable {
  public let bridgeID: UUIDBytes
  public let trackerID: String

  public init(bridgeID: UUIDBytes, trackerID: String) {
    self.bridgeID = bridgeID
    self.trackerID = trackerID
  }
}

public struct LatestTrackerState: Equatable, Sendable {
  public let key: TrackerKey
  public let sessionID: UUIDBytes
  public let trackingSpaceID: UUIDBytes
  public let spaceEpoch: UInt32
  public let frameSequence: UInt64
  public let captureMonotonicNS: UInt64
  public let sendMonotonicNS: UInt64
  public let receivedMonotonicNS: UInt64
  public let frameCompleteness: FrameCompleteness
  public let pose: TrackerPose

  public func receiveAgeNS(at monotonicNS: UInt64) -> UInt64 {
    monotonicNS >= receivedMonotonicNS ? monotonicNS - receivedMonotonicNS : 0
  }
}

public struct LatestBridgeState: Equatable, Sendable {
  public let bridgeID: UUIDBytes
  public let sessionID: UUIDBytes
  public let trackingSpaceID: UUIDBytes
  public let spaceEpoch: UInt32
  public let frameSequence: UInt64
  public let captureMonotonicNS: UInt64
  public let sendMonotonicNS: UInt64
  public let receivedMonotonicNS: UInt64
  public let requestedRateHz: UInt16
  public let backend: Backend
  public let frameCompleteness: FrameCompleteness
}

public struct HubStateStatistics: Equatable, Sendable {
  public var appliedFrames: UInt64 = 0
  public var completeFrames: UInt64 = 0
  public var partialFrames: UInt64 = 0
  public var staleFrames: UInt64 = 0
  public var trackerUpdates: UInt64 = 0
  public var sessionResets: UInt64 = 0
  public var trackingSpaceResets: UInt64 = 0
}

public struct HubStateSnapshot: Equatable, Sendable {
  public let generation: UInt64
  public let bridges: [LatestBridgeState]
  public let trackers: [LatestTrackerState]
  public let stateStatistics: HubStateStatistics
  public let assemblerStatistics: FrameAssemblerStatistics
}

public enum HubFrameApplyDisposition: Equatable, Sendable {
  case applied
  case stale
}

/// Network、Simulator、Playbackから同じassembled frameを受け取るlatest state store。
///
/// lock内ではframe集約とdictionary更新だけを行い、I/Oやcallbackは実行しない。
public final class HubStateStore: @unchecked Sendable {
  private let lock = NSLock()
  private var assembler = FrameAssembler()
  private var bridges: [UUIDBytes: LatestBridgeState] = [:]
  private var trackers: [TrackerKey: LatestTrackerState] = [:]
  private var generation: UInt64 = 0
  private var value = HubStateStatistics()

  public init() {}

  @discardableResult
  public func ingest(
    _ packet: DecodedPosePacket,
    receivedMonotonicNS: UInt64
  ) -> FrameAssemblyResult {
    lock.withLock {
      let result = assembler.ingest(
        packet,
        receivedMonotonicNS: receivedMonotonicNS
      )
      for frame in result.emittedFrames {
        _ = applyUnlocked(frame)
      }
      return result
    }
  }

  /// SimulatorとPlaybackはwire encodeを経ず、同じstate reducerへframeを渡せる。
  @discardableResult
  public func apply(_ frame: AssembledPoseFrame) -> HubFrameApplyDisposition {
    lock.withLock {
      applyUnlocked(frame)
    }
  }

  @discardableResult
  public func flushPendingFrames() -> [AssembledPoseFrame] {
    lock.withLock {
      let frames = assembler.flush()
      for frame in frames {
        _ = applyUnlocked(frame)
      }
      return frames
    }
  }

  public func snapshot() -> HubStateSnapshot {
    lock.withLock {
      HubStateSnapshot(
        generation: generation,
        bridges: bridges.values.sorted(by: bridgeLessThan),
        trackers: trackers.values.sorted(by: trackerLessThan),
        stateStatistics: value,
        assemblerStatistics: assembler.statistics()
      )
    }
  }

  public func bridgeState(for bridgeID: UUIDBytes) -> LatestBridgeState? {
    lock.withLock {
      bridges[bridgeID]
    }
  }

  public func trackerState(for key: TrackerKey) -> LatestTrackerState? {
    lock.withLock {
      trackers[key]
    }
  }

  private func applyUnlocked(_ frame: AssembledPoseFrame) -> HubFrameApplyDisposition {
    if let current = bridges[frame.bridgeID],
      current.sessionID == frame.sessionID,
      frame.frameSequence <= current.frameSequence
    {
      value.staleFrames += 1
      return .stale
    }

    if let current = bridges[frame.bridgeID] {
      let sessionChanged = current.sessionID != frame.sessionID
      let trackingSpaceChanged =
        current.trackingSpaceID != frame.poseBatch.trackingSpaceID
        || current.spaceEpoch != frame.poseBatch.spaceEpoch
      if sessionChanged || trackingSpaceChanged {
        trackers = trackers.filter { $0.key.bridgeID != frame.bridgeID }
      }
      if sessionChanged {
        value.sessionResets += 1
      }
      if trackingSpaceChanged {
        value.trackingSpaceResets += 1
      }
    }

    let bridge = LatestBridgeState(
      bridgeID: frame.bridgeID,
      sessionID: frame.sessionID,
      trackingSpaceID: frame.poseBatch.trackingSpaceID,
      spaceEpoch: frame.poseBatch.spaceEpoch,
      frameSequence: frame.frameSequence,
      captureMonotonicNS: frame.poseBatch.captureMonotonicNS,
      sendMonotonicNS: frame.poseBatch.sendMonotonicNS,
      receivedMonotonicNS: frame.lastReceivedMonotonicNS,
      requestedRateHz: frame.poseBatch.requestedRateHz,
      backend: frame.poseBatch.backend,
      frameCompleteness: frame.completeness
    )
    bridges[frame.bridgeID] = bridge

    for pose in frame.poseBatch.trackers {
      let key = TrackerKey(bridgeID: frame.bridgeID, trackerID: pose.trackerID)
      trackers[key] = LatestTrackerState(
        key: key,
        sessionID: frame.sessionID,
        trackingSpaceID: frame.poseBatch.trackingSpaceID,
        spaceEpoch: frame.poseBatch.spaceEpoch,
        frameSequence: frame.frameSequence,
        captureMonotonicNS: frame.poseBatch.captureMonotonicNS,
        sendMonotonicNS: frame.poseBatch.sendMonotonicNS,
        receivedMonotonicNS: frame.lastReceivedMonotonicNS,
        frameCompleteness: frame.completeness,
        pose: pose
      )
    }

    generation += 1
    value.appliedFrames += 1
    value.trackerUpdates += UInt64(frame.poseBatch.trackers.count)
    if frame.completeness.isComplete {
      value.completeFrames += 1
    } else {
      value.partialFrames += 1
    }
    return .applied
  }

  private func bridgeLessThan(_ left: LatestBridgeState, _ right: LatestBridgeState) -> Bool {
    left.bridgeID.bytes.lexicographicallyPrecedes(right.bridgeID.bytes)
  }

  private func trackerLessThan(
    _ left: LatestTrackerState,
    _ right: LatestTrackerState
  ) -> Bool {
    if left.key.bridgeID == right.key.bridgeID {
      return left.key.trackerID < right.key.trackerID
    }
    return left.key.bridgeID.bytes.lexicographicallyPrecedes(right.key.bridgeID.bytes)
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
