import HubProtocol

public enum HubLivenessPolicyError: Error, Equatable, Sendable {
  case lostThresholdMustBePositive
  case disconnectedThresholdMustExceedLostThreshold
}

/// 受信停止時にlatest stateをlost、disconnectedへ段階的に遷移させる閾値。
///
/// 既定値は実機検証前の暫定値。30Hzでも数frameの欠落を許容しつつ、
/// UIとcontentが停止を早期に認識できる値としている。
public struct HubLivenessPolicy: Equatable, Sendable {
  public static let defaultLostAfterNS: UInt64 = 250_000_000
  public static let defaultDisconnectedAfterNS: UInt64 = 2_000_000_000

  public let lostAfterNS: UInt64
  public let disconnectedAfterNS: UInt64

  public init() {
    lostAfterNS = Self.defaultLostAfterNS
    disconnectedAfterNS = Self.defaultDisconnectedAfterNS
  }

  public init(
    lostAfterNS: UInt64,
    disconnectedAfterNS: UInt64
  ) throws {
    guard lostAfterNS > 0 else {
      throw HubLivenessPolicyError.lostThresholdMustBePositive
    }
    guard disconnectedAfterNS > lostAfterNS else {
      throw HubLivenessPolicyError.disconnectedThresholdMustExceedLostThreshold
    }
    self.lostAfterNS = lostAfterNS
    self.disconnectedAfterNS = disconnectedAfterNS
  }
}

/// 最新値の受信ageとsource報告を合わせた可用性。
public enum HubLivenessState: String, Equatable, Sendable {
  case fresh
  case stale
  case disconnected
}

public struct EvaluatedBridgeState: Equatable, Sendable {
  public let latest: LatestBridgeState
  public let receiveAgeNS: UInt64
  public let liveness: HubLivenessState
}

public struct EvaluatedTrackerState: Equatable, Sendable {
  public let latest: LatestTrackerState
  public let receiveAgeNS: UInt64
  public let liveness: HubLivenessState
  public let trackingState: TrackingState
  public let trackingReason: TrackingReason

  /// age評価によりsource報告を上書きしたかを示す。
  public var wasAgeAdjusted: Bool {
    trackingState != latest.pose.trackingState
      || trackingReason != latest.pose.trackingReason
  }
}

public struct EvaluatedHubStateSnapshot: Equatable, Sendable {
  public let generation: UInt64
  public let evaluatedMonotonicNS: UInt64
  public let policy: HubLivenessPolicy
  public let bridges: [EvaluatedBridgeState]
  public let trackers: [EvaluatedTrackerState]
  public let stateStatistics: HubStateStatistics
  public let assemblerStatistics: FrameAssemblerStatistics
}

extension LatestBridgeState {
  public func evaluated(
    atMonotonicNS monotonicNS: UInt64,
    policy: HubLivenessPolicy = HubLivenessPolicy()
  ) -> EvaluatedBridgeState {
    let age = receiveAgeNS(at: monotonicNS)
    let liveness: HubLivenessState
    if age >= policy.disconnectedAfterNS {
      liveness = .disconnected
    } else if age >= policy.lostAfterNS {
      liveness = .stale
    } else {
      liveness = .fresh
    }
    return EvaluatedBridgeState(
      latest: self,
      receiveAgeNS: age,
      liveness: liveness
    )
  }

  public func receiveAgeNS(at monotonicNS: UInt64) -> UInt64 {
    monotonicNS >= receivedMonotonicNS ? monotonicNS - receivedMonotonicNS : 0
  }
}

extension LatestTrackerState {
  public func evaluated(
    atMonotonicNS monotonicNS: UInt64,
    policy: HubLivenessPolicy = HubLivenessPolicy()
  ) -> EvaluatedTrackerState {
    let age = receiveAgeNS(at: monotonicNS)
    let liveness: HubLivenessState
    let trackingState: TrackingState
    let trackingReason: TrackingReason

    if !pose.connected || pose.trackingState == .disconnected {
      liveness = .disconnected
      trackingState = .disconnected
      trackingReason = pose.trackingReason
    } else if age >= policy.disconnectedAfterNS {
      liveness = .disconnected
      trackingState = .disconnected
      trackingReason = .bridgeTimeout
    } else if age >= policy.lostAfterNS {
      liveness = .stale
      trackingState = .lost
      trackingReason = .networkStale
    } else {
      liveness = .fresh
      trackingState = pose.trackingState
      trackingReason = pose.trackingReason
    }

    return EvaluatedTrackerState(
      latest: self,
      receiveAgeNS: age,
      liveness: liveness,
      trackingState: trackingState,
      trackingReason: trackingReason
    )
  }
}

extension HubStateSnapshot {
  public func evaluated(
    atMonotonicNS monotonicNS: UInt64,
    policy: HubLivenessPolicy = HubLivenessPolicy()
  ) -> EvaluatedHubStateSnapshot {
    EvaluatedHubStateSnapshot(
      generation: generation,
      evaluatedMonotonicNS: monotonicNS,
      policy: policy,
      bridges: bridges.map {
        $0.evaluated(atMonotonicNS: monotonicNS, policy: policy)
      },
      trackers: trackers.map {
        $0.evaluated(atMonotonicNS: monotonicNS, policy: policy)
      },
      stateStatistics: stateStatistics,
      assemblerStatistics: assemblerStatistics
    )
  }
}
