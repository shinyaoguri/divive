import Foundation
import HubCore
import HubProtocol

/// Trackerがcontentへどの空間で渡るか。
public enum CalibratedDelivery: String, Sendable, CaseIterable {
  /// 較正済みで、Stage Spaceへ変換した。
  case stage
  /// preview modeで、Tracker Spaceのまま渡す。
  case rawTrackerSpace = "raw_tracker_space"
  /// 未較正またはepoch不一致で、content配信の対象にしない。
  case blocked
}

/// 較正を適用したあとのTracker状態。
///
/// 変換前のTracker Space poseを保持するのは、未較正の理由や較正のずれをGUIが
/// 説明できるようにするため。較正済みかどうかで表示できる情報を減らさない。
public struct CalibratedTrackerState: Equatable, Sendable {
  public let key: TrackerKey
  public let delivery: CalibratedDelivery
  public let status: CalibrationStatus

  /// Stage Space変換後のpose。`blocked`の場合はnil。
  ///
  /// `rawTrackerSpace`の場合は変換していないposeがそのまま入る。
  public let stagePose: TrackerPose?

  /// liveness評価まで済ませた、変換前のTracker Space状態。
  public let latest: EvaluatedTrackerState

  public var trackerSpacePose: TrackerPose {
    latest.latest.pose
  }

  public var liveness: HubLivenessState {
    latest.liveness
  }

  public var trackingState: TrackingState {
    latest.trackingState
  }

  public var trackingReason: TrackingReason {
    latest.trackingReason
  }

  public var receiveAgeNS: UInt64 {
    latest.receiveAgeNS
  }
}

/// tracking space単位の較正状態。
public struct CalibratedSpaceState: Equatable, Sendable {
  public let trackingSpaceID: UUIDBytes
  public let spaceEpoch: UInt32
  public let status: CalibrationStatus
  public let trackerCount: Int
}

/// 較正を適用したHub snapshot。
public struct CalibratedHubStateSnapshot: Equatable, Sendable {
  public let generation: UInt64
  public let evaluatedMonotonicNS: UInt64
  public let mode: CalibrationDeliveryMode
  public let profileID: String
  public let profileRevision: UInt32
  public let trackers: [CalibratedTrackerState]
  public let spaces: [CalibratedSpaceState]

  public var stageTrackers: [CalibratedTrackerState] {
    trackers.filter { $0.delivery == .stage }
  }

  public var blockedTrackers: [CalibratedTrackerState] {
    trackers.filter { $0.delivery == .blocked }
  }

  public var hasUncalibratedSpace: Bool {
    spaces.contains { !$0.status.isCalibrated }
  }
}

extension CalibrationResolver {
  /// 評価済みsnapshotへ較正を適用する。
  ///
  /// `blocked`のTrackerもsnapshotから取り除かない。未較正spaceを「表示しない」と
  /// 「較正済みとして表示する」のどちらもoperatorが状況を把握できなくなるため、
  /// 区分を付けたまま残す。
  public func project(
    _ snapshot: EvaluatedHubStateSnapshot
  ) -> CalibratedHubStateSnapshot {
    var spaceStatuses: [UUIDBytes: CalibrationStatus] = [:]
    var spaceEpochs: [UUIDBytes: UInt32] = [:]
    var spaceTrackerCounts: [UUIDBytes: Int] = [:]

    let trackers = snapshot.trackers.map { evaluated -> CalibratedTrackerState in
      let trackingSpaceID = evaluated.latest.trackingSpaceID
      let spaceEpoch = evaluated.latest.spaceEpoch
      let status =
        spaceStatuses[trackingSpaceID]
        ?? status(forTrackingSpaceID: trackingSpaceID, spaceEpoch: spaceEpoch)
      spaceStatuses[trackingSpaceID] = status
      spaceEpochs[trackingSpaceID] = spaceEpoch
      spaceTrackerCounts[trackingSpaceID, default: 0] += 1

      switch status {
      case let .calibrated(calibration):
        return CalibratedTrackerState(
          key: evaluated.latest.key,
          delivery: .stage,
          status: status,
          stagePose: stagePose(
            evaluated.latest.pose,
            using: calibration.transform
          ),
          latest: evaluated
        )
      case .uncalibrated, .epochMismatch:
        guard mode == .preview else {
          return CalibratedTrackerState(
            key: evaluated.latest.key,
            delivery: .blocked,
            status: status,
            stagePose: nil,
            latest: evaluated
          )
        }
        return CalibratedTrackerState(
          key: evaluated.latest.key,
          delivery: .rawTrackerSpace,
          status: status,
          stagePose: evaluated.latest.pose,
          latest: evaluated
        )
      }
    }

    let spaces =
      spaceStatuses
      .map { trackingSpaceID, status in
        CalibratedSpaceState(
          trackingSpaceID: trackingSpaceID,
          spaceEpoch: spaceEpochs[trackingSpaceID] ?? 0,
          status: status,
          trackerCount: spaceTrackerCounts[trackingSpaceID] ?? 0
        )
      }
      .sorted { $0.trackingSpaceID.bytes.lexicographicallyPrecedes($1.trackingSpaceID.bytes) }

    return CalibratedHubStateSnapshot(
      generation: snapshot.generation,
      evaluatedMonotonicNS: snapshot.evaluatedMonotonicNS,
      mode: mode,
      profileID: profile.profileID,
      profileRevision: profile.revision,
      trackers: trackers,
      spaces: spaces
    )
  }
}
