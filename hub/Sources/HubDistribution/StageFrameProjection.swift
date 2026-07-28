import HubCalibration
import HubCore
import HubProtocol

/// 較正済みHub snapshotを、contentへ配信するstage frameへ写す。
///
/// Hub内部のdomain型をそのままwireへ出さず、ここで1か所に写像を閉じる。
/// `blocked`のTrackerはposeを落とすが、区分・role・状態は残す。contentが
/// 「未較正だから出せない」ことを表示できるようにするためである。
public enum StageFrameProjection {
  public static func makeFrame(
    from snapshot: CalibratedHubStateSnapshot,
    publishRateHz: UInt16
  ) -> StageFrameMessage {
    StageFrameMessage(
      hubMonotonicNS: snapshot.evaluatedMonotonicNS,
      generation: snapshot.generation,
      profileID: snapshot.profileID,
      profileRevision: snapshot.profileRevision,
      deliveryMode: map(snapshot.mode),
      publishRateHz: publishRateHz,
      trackers: snapshot.trackers.map(makeTracker)
    )
  }

  static func makeTracker(
    from tracker: CalibratedTrackerState
  ) -> StageTrackerRecord {
    let latest = tracker.latest.latest
    let source = latest.pose

    return StageTrackerRecord(
      trackerID: latest.key.trackerID,
      role: source.role,
      idKind: source.idKind,
      bridgeID: latest.key.bridgeID,
      trackingSpaceID: latest.trackingSpaceID,
      spaceEpoch: latest.spaceEpoch,
      delivery: map(tracker.delivery),
      // `blocked`のTrackerは`stagePose`を持たないため、ここで落ちる。
      // 二重に判定せず、較正側が決めた配信区分をそのまま信じる。
      pose: tracker.stagePose.map {
        StagePose(
          position: $0.position,
          orientation: $0.orientation,
          linearVelocity: $0.linearVelocity,
          angularVelocity: $0.angularVelocity
        )
      },
      trackingState: tracker.trackingState,
      trackingReason: tracker.trackingReason,
      liveness: map(tracker.liveness),
      connected: source.connected,
      battery: source.battery,
      receiveAgeNS: tracker.receiveAgeNS,
      sourceFrameSequence: latest.frameSequence,
      captureMonotonicNS: latest.captureMonotonicNS
    )
  }

  static func map(_ value: CalibratedDelivery) -> StageDelivery {
    switch value {
    case .stage: .stage
    case .rawTrackerSpace: .rawTrackerSpace
    case .blocked: .blocked
    }
  }

  static func map(_ value: CalibrationDeliveryMode) -> StageDeliveryMode {
    switch value {
    case .production: .production
    case .preview: .preview
    }
  }

  static func map(_ value: HubLivenessState) -> StageLiveness {
    switch value {
    case .fresh: .fresh
    case .stale: .stale
    case .disconnected: .disconnected
    }
  }
}
