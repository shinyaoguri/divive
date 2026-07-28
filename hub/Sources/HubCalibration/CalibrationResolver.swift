import Foundation
import HubProtocol

/// tracking spaceに対する較正の引き当て結果。
public enum CalibrationStatus: Equatable, Sendable {
  case calibrated(SpaceCalibration)
  case uncalibrated(trackingSpaceID: UUIDBytes)
  case epochMismatch(
    trackingSpaceID: UUIDBytes,
    profileEpoch: UInt32,
    observedEpoch: UInt32
  )

  public var isCalibrated: Bool {
    if case .calibrated = self {
      return true
    }
    return false
  }
}

/// 未較正spaceの扱いを決める配信mode。
public enum CalibrationDeliveryMode: String, Sendable, CaseIterable {
  /// 未較正とepoch不一致のbatchをcontentへ配信しない。
  case production
  /// 生のTracker Spaceであることを明示したうえで配信する。
  case preview
}

/// 配信されたposeがどの空間の値かを示す。
public enum SpaceState: String, Sendable {
  case stage
  case rawTrackerSpace = "raw_tracker_space"
}

/// Stage Spaceへ変換した、あるいは変換していないことを明示したbatch。
public struct CalibratedPoseBatch: Equatable, Sendable {
  public let trackingSpaceID: UUIDBytes
  public let spaceEpoch: UInt32
  public let spaceState: SpaceState
  public let profileID: String
  public let profileRevision: UInt32
  public let captureMonotonicNS: UInt64
  public let sendMonotonicNS: UInt64
  public let requestedRateHz: UInt16
  public let backend: Backend
  public let trackers: [TrackerPose]
}

/// 較正gateの判定結果。
public enum CalibrationOutcome: Equatable, Sendable {
  case delivered(CalibratedPoseBatch, status: CalibrationStatus)
  case blocked(CalibrationStatus)

  public var status: CalibrationStatus {
    switch self {
    case let .delivered(_, status):
      return status
    case let .blocked(status):
      return status
    }
  }

  public var batch: CalibratedPoseBatch? {
    if case let .delivered(batch, _) = self {
      return batch
    }
    return nil
  }
}

public struct CalibrationStatistics: Equatable, Sendable {
  public var stageBatches: UInt64 = 0
  public var rawTrackerSpaceBatches: UInt64 = 0
  public var blockedUncalibratedBatches: UInt64 = 0
  public var blockedEpochMismatchBatches: UInt64 = 0

  public init() {}

  public mutating func record(_ outcome: CalibrationOutcome) {
    switch outcome {
    case let .delivered(batch, _):
      switch batch.spaceState {
      case .stage:
        stageBatches += 1
      case .rawTrackerSpace:
        rawTrackerSpaceBatches += 1
      }
    case let .blocked(status):
      switch status {
      case .uncalibrated:
        blockedUncalibratedBatches += 1
      case .epochMismatch:
        blockedEpochMismatchBatches += 1
      case .calibrated:
        break
      }
    }
  }
}

/// profileを引き当ててTracker SpaceのposeをStage Spaceへ変換する。
///
/// profileが見つからない場合にidentity transformへ黙ってfallbackしない。
/// 未較正はuncalibrated、`space_epoch`の不一致はepochMismatchとして呼び出し側へ返す。
public struct CalibrationResolver: Sendable {
  public let profile: CalibrationProfile
  public let mode: CalibrationDeliveryMode

  public init(
    profile: CalibrationProfile,
    mode: CalibrationDeliveryMode = .production
  ) {
    self.profile = profile
    self.mode = mode
  }

  public func status(
    forTrackingSpaceID trackingSpaceID: UUIDBytes,
    spaceEpoch: UInt32
  ) -> CalibrationStatus {
    guard let calibration = profile.calibration(forTrackingSpaceID: trackingSpaceID) else {
      return .uncalibrated(trackingSpaceID: trackingSpaceID)
    }
    guard calibration.spaceEpoch == spaceEpoch else {
      return .epochMismatch(
        trackingSpaceID: trackingSpaceID,
        profileEpoch: calibration.spaceEpoch,
        observedEpoch: spaceEpoch
      )
    }
    return .calibrated(calibration)
  }

  public func resolve(_ batch: PoseBatch) -> CalibrationOutcome {
    let status = status(
      forTrackingSpaceID: batch.trackingSpaceID,
      spaceEpoch: batch.spaceEpoch
    )

    switch status {
    case let .calibrated(calibration):
      return .delivered(
        makeBatch(
          from: batch,
          spaceState: .stage,
          trackers: batch.trackers.map {
            stagePose($0, using: calibration.transform)
          }
        ),
        status: status
      )
    case .uncalibrated, .epochMismatch:
      guard mode == .preview else {
        return .blocked(status)
      }
      return .delivered(
        makeBatch(
          from: batch,
          spaceState: .rawTrackerSpace,
          trackers: batch.trackers
        ),
        status: status
      )
    }
  }

  /// 単一poseをStage Spaceへ変換する。
  ///
  /// positionにはrotationとtranslationを、orientationにはrotationを、
  /// linear / angular velocityにはrotationだけを適用する。
  public func stagePose(
    _ pose: TrackerPose,
    using transform: RigidTransform
  ) -> TrackerPose {
    TrackerPose(
      trackerID: pose.trackerID,
      idKind: pose.idKind,
      role: pose.role,
      runtimeRole: pose.runtimeRole,
      position: transform.apply(toPosition: pose.position),
      orientation: transform.apply(toOrientation: pose.orientation),
      linearVelocity: pose.linearVelocity.map { transform.apply(toDirection: $0) },
      angularVelocity: pose.angularVelocity.map { transform.apply(toDirection: $0) },
      trackingState: pose.trackingState,
      trackingReason: pose.trackingReason,
      connected: pose.connected,
      battery: pose.battery,
      deviceMetadataRevision: pose.deviceMetadataRevision
    )
  }

  private func makeBatch(
    from batch: PoseBatch,
    spaceState: SpaceState,
    trackers: [TrackerPose]
  ) -> CalibratedPoseBatch {
    CalibratedPoseBatch(
      trackingSpaceID: batch.trackingSpaceID,
      spaceEpoch: batch.spaceEpoch,
      spaceState: spaceState,
      profileID: profile.profileID,
      profileRevision: profile.revision,
      captureMonotonicNS: batch.captureMonotonicNS,
      sendMonotonicNS: batch.sendMonotonicNS,
      requestedRateHz: batch.requestedRateHz,
      backend: batch.backend,
      trackers: trackers
    )
  }
}
