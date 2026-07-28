import Foundation
import HubCalibration
import HubCore
import HubProtocol
import XCTest

final class CalibratedHubStateTests: XCTestCase {
  private let yaw90 = Quaternion(x: 0, y: 0.7071068, z: 0, w: 0.7071068)

  /// 1 Bridge分のframeを適用したstoreを作る。
  private func makeStore(
    bridgeID: UUIDBytes,
    trackingSpaceID: UUIDBytes,
    spaceEpoch: UInt32 = 1,
    receivedMonotonicNS: UInt64 = 1_000,
    trackers: [TrackerPose]
  ) throws -> HubStateStore {
    let store = HubStateStore()
    store.apply(
      makeAssembledFrame(
        bridgeID: bridgeID,
        sessionID: try calibrationTestUUID(0xF0),
        trackingSpaceID: trackingSpaceID,
        spaceEpoch: spaceEpoch,
        receivedMonotonicNS: receivedMonotonicNS,
        trackers: trackers
      )
    )
    return store
  }

  func test較正済みspaceのTrackerをStageSpaceへ写す() throws {
    let bridgeID = try calibrationTestUUID(0x01)
    let spaceID = try calibrationTestUUID(0x02)
    let store = try makeStore(
      bridgeID: bridgeID,
      trackingSpaceID: spaceID,
      trackers: [
        makeTrackerPose(
          trackerID: "tracker-1",
          position: Vector3(x: 1, y: 0, z: 0),
          linearVelocity: Vector3(x: 0, y: 0, z: -1)
        )
      ]
    )

    let resolver = CalibrationResolver(
      profile: try makeProfile(
        spaces: [
          try makeSpaceCalibration(
            trackingSpaceID: spaceID,
            transform: try makeTransform(
              translation: Vector3(x: 1, y: 2, z: 3),
              rotation: yaw90
            )
          )
        ]
      )
    )

    let projected = resolver.project(store.evaluatedSnapshot(atMonotonicNS: 1_000))
    XCTAssertEqual(projected.mode, .production)
    XCTAssertEqual(projected.profileID, "studio-a")
    XCTAssertEqual(projected.profileRevision, 1)
    XCTAssertEqual(projected.trackers.count, 1)
    XCTAssertFalse(projected.hasUncalibratedSpace)

    let tracker = try XCTUnwrap(projected.trackers.first)
    XCTAssertEqual(tracker.delivery, .stage)
    XCTAssertTrue(tracker.status.isCalibrated)
    XCTAssertEqual(tracker.key, TrackerKey(bridgeID: bridgeID, trackerID: "tracker-1"))

    let stagePose = try XCTUnwrap(tracker.stagePose)
    assertVector(stagePose.position, Vector3(x: 1, y: 2, z: 2))
    assertSameRotation(stagePose.orientation, yaw90)
    assertVector(try XCTUnwrap(stagePose.linearVelocity), Vector3(x: -1, y: 0, z: 0))

    // 変換前のTracker Space poseも保持する。
    assertVector(tracker.trackerSpacePose.position, Vector3(x: 1, y: 0, z: 0))
    assertVector(
      try XCTUnwrap(tracker.trackerSpacePose.linearVelocity),
      Vector3(x: 0, y: 0, z: -1)
    )
  }

  func test未較正spaceはproductionでblockedになり列挙は残る() throws {
    let bridgeID = try calibrationTestUUID(0x10)
    let spaceID = try calibrationTestUUID(0x11)
    let store = try makeStore(
      bridgeID: bridgeID,
      trackingSpaceID: spaceID,
      trackers: [makeTrackerPose(position: Vector3(x: 4, y: 5, z: 6))]
    )
    let resolver = CalibrationResolver(profile: try makeProfile(), mode: .production)

    let projected = resolver.project(store.evaluatedSnapshot(atMonotonicNS: 1_000))
    XCTAssertEqual(projected.trackers.count, 1, "blockedでもsnapshotから消しません")
    XCTAssertEqual(projected.blockedTrackers.count, 1)
    XCTAssertTrue(projected.stageTrackers.isEmpty)
    XCTAssertTrue(projected.hasUncalibratedSpace)

    let tracker = try XCTUnwrap(projected.trackers.first)
    XCTAssertEqual(tracker.delivery, .blocked)
    XCTAssertNil(tracker.stagePose)
    XCTAssertEqual(tracker.status, .uncalibrated(trackingSpaceID: spaceID))
    assertVector(tracker.trackerSpacePose.position, Vector3(x: 4, y: 5, z: 6))
  }

  func test未較正spaceはpreviewで変換せず配信される() throws {
    let spaceID = try calibrationTestUUID(0x21)
    let store = try makeStore(
      bridgeID: try calibrationTestUUID(0x20),
      trackingSpaceID: spaceID,
      trackers: [makeTrackerPose(position: Vector3(x: 4, y: 5, z: 6))]
    )
    let resolver = CalibrationResolver(profile: try makeProfile(), mode: .preview)

    let projected = resolver.project(store.evaluatedSnapshot(atMonotonicNS: 1_000))
    let tracker = try XCTUnwrap(projected.trackers.first)

    XCTAssertEqual(projected.mode, .preview)
    XCTAssertEqual(tracker.delivery, .rawTrackerSpace)
    assertVector(
      try XCTUnwrap(tracker.stagePose).position,
      Vector3(x: 4, y: 5, z: 6),
      "preview配信で変換を加えてはいけません"
    )
  }

  func testEpoch不一致は較正済みspaceでもblockedになる() throws {
    let spaceID = try calibrationTestUUID(0x31)
    let store = try makeStore(
      bridgeID: try calibrationTestUUID(0x30),
      trackingSpaceID: spaceID,
      spaceEpoch: 4,
      trackers: [makeTrackerPose(position: Vector3(x: 1, y: 0, z: 0))]
    )
    let profile = try makeProfile(
      spaces: [
        try makeSpaceCalibration(
          trackingSpaceID: spaceID,
          spaceEpoch: 2,
          transform: try makeTransform(translation: Vector3(x: 9, y: 9, z: 9))
        )
      ]
    )

    let blocked = CalibrationResolver(profile: profile, mode: .production)
      .project(store.evaluatedSnapshot(atMonotonicNS: 1_000))
    let blockedTracker = try XCTUnwrap(blocked.trackers.first)
    XCTAssertEqual(blockedTracker.delivery, .blocked)
    XCTAssertEqual(
      blockedTracker.status,
      .epochMismatch(trackingSpaceID: spaceID, profileEpoch: 2, observedEpoch: 4)
    )

    let previewed = CalibrationResolver(profile: profile, mode: .preview)
      .project(store.evaluatedSnapshot(atMonotonicNS: 1_000))
    let previewedTracker = try XCTUnwrap(previewed.trackers.first)
    XCTAssertEqual(previewedTracker.delivery, .rawTrackerSpace)
    assertVector(
      try XCTUnwrap(previewedTracker.stagePose).position,
      Vector3(x: 1, y: 0, z: 0),
      "epoch不一致で古い較正を適用してはいけません"
    )
  }

  func test複数Bridgeで較正済みspaceだけを変換する() throws {
    let calibratedBridge = try calibrationTestUUID(0x40)
    let calibratedSpace = try calibrationTestUUID(0x41)
    let uncalibratedBridge = try calibrationTestUUID(0x50)
    let uncalibratedSpace = try calibrationTestUUID(0x51)

    let store = HubStateStore()
    store.apply(
      makeAssembledFrame(
        bridgeID: calibratedBridge,
        sessionID: try calibrationTestUUID(0xF0),
        trackingSpaceID: calibratedSpace,
        trackers: [
          makeTrackerPose(trackerID: "a-1", position: Vector3(x: 1, y: 0, z: 0)),
          makeTrackerPose(trackerID: "a-2", position: Vector3(x: 2, y: 0, z: 0)),
        ]
      )
    )
    store.apply(
      makeAssembledFrame(
        bridgeID: uncalibratedBridge,
        sessionID: try calibrationTestUUID(0xF1),
        trackingSpaceID: uncalibratedSpace,
        trackers: [makeTrackerPose(trackerID: "b-1", position: Vector3(x: 3, y: 0, z: 0))]
      )
    )

    let resolver = CalibrationResolver(
      profile: try makeProfile(
        spaces: [
          try makeSpaceCalibration(
            trackingSpaceID: calibratedSpace,
            transform: try makeTransform(translation: Vector3(x: 0, y: 10, z: 0))
          )
        ]
      )
    )

    let projected = resolver.project(store.evaluatedSnapshot(atMonotonicNS: 1_000))
    XCTAssertEqual(projected.trackers.count, 3)
    XCTAssertEqual(projected.stageTrackers.count, 2)
    XCTAssertEqual(projected.blockedTrackers.count, 1)
    XCTAssertTrue(projected.hasUncalibratedSpace)

    for tracker in projected.stageTrackers {
      XCTAssertEqual(tracker.key.bridgeID, calibratedBridge)
      XCTAssertEqual(try XCTUnwrap(tracker.stagePose).position.y, 10, accuracy: 1.0e-5)
    }
    XCTAssertEqual(
      try XCTUnwrap(projected.blockedTrackers.first).key.bridgeID,
      uncalibratedBridge
    )
  }

  func testSpace一覧はstatusとTracker数を持つ() throws {
    let calibratedSpace = try calibrationTestUUID(0x61)
    let uncalibratedSpace = try calibrationTestUUID(0x71)

    let store = HubStateStore()
    store.apply(
      makeAssembledFrame(
        bridgeID: try calibrationTestUUID(0x60),
        sessionID: try calibrationTestUUID(0xF0),
        trackingSpaceID: calibratedSpace,
        spaceEpoch: 3,
        trackers: [
          makeTrackerPose(trackerID: "a-1", position: Vector3(x: 0, y: 0, z: 0)),
          makeTrackerPose(trackerID: "a-2", position: Vector3(x: 0, y: 0, z: 0)),
        ]
      )
    )
    store.apply(
      makeAssembledFrame(
        bridgeID: try calibrationTestUUID(0x70),
        sessionID: try calibrationTestUUID(0xF1),
        trackingSpaceID: uncalibratedSpace,
        spaceEpoch: 5,
        trackers: [makeTrackerPose(trackerID: "b-1", position: Vector3(x: 0, y: 0, z: 0))]
      )
    )

    let projected = CalibrationResolver(
      profile: try makeProfile(
        spaces: [
          try makeSpaceCalibration(trackingSpaceID: calibratedSpace, spaceEpoch: 3)
        ]
      )
    ).project(store.evaluatedSnapshot(atMonotonicNS: 1_000))

    XCTAssertEqual(projected.spaces.count, 2)
    XCTAssertEqual(
      projected.spaces.map(\.trackingSpaceID),
      [calibratedSpace, uncalibratedSpace],
      "tracking space ID順に整列します"
    )

    let calibrated = try XCTUnwrap(projected.spaces.first)
    XCTAssertTrue(calibrated.status.isCalibrated)
    XCTAssertEqual(calibrated.spaceEpoch, 3)
    XCTAssertEqual(calibrated.trackerCount, 2)

    let uncalibrated = try XCTUnwrap(projected.spaces.last)
    XCTAssertEqual(uncalibrated.status, .uncalibrated(trackingSpaceID: uncalibratedSpace))
    XCTAssertEqual(uncalibrated.spaceEpoch, 5)
    XCTAssertEqual(uncalibrated.trackerCount, 1)
  }

  func testLivenessと実効trackingStateを保つ() throws {
    let spaceID = try calibrationTestUUID(0x81)
    let store = try makeStore(
      bridgeID: try calibrationTestUUID(0x80),
      trackingSpaceID: spaceID,
      receivedMonotonicNS: 1_000,
      trackers: [makeTrackerPose(position: Vector3(x: 1, y: 0, z: 0))]
    )
    let resolver = CalibrationResolver(
      profile: try makeProfile(
        spaces: [try makeSpaceCalibration(trackingSpaceID: spaceID)]
      )
    )

    // 受信直後はfresh / tracking。
    let fresh = resolver.project(store.evaluatedSnapshot(atMonotonicNS: 1_000))
    let freshTracker = try XCTUnwrap(fresh.trackers.first)
    XCTAssertEqual(freshTracker.liveness, .fresh)
    XCTAssertEqual(freshTracker.trackingState, .tracking)
    XCTAssertEqual(freshTracker.receiveAgeNS, 0)

    // lost閾値を超えるとstale / lost / network_stale。
    let staleNS = 1_000 + HubLivenessPolicy.defaultLostAfterNS
    let stale = resolver.project(store.evaluatedSnapshot(atMonotonicNS: staleNS))
    let staleTracker = try XCTUnwrap(stale.trackers.first)
    XCTAssertEqual(staleTracker.liveness, .stale)
    XCTAssertEqual(staleTracker.trackingState, .lost)
    XCTAssertEqual(staleTracker.trackingReason, .networkStale)
    XCTAssertEqual(staleTracker.receiveAgeNS, HubLivenessPolicy.defaultLostAfterNS)

    // 状態が変わってもStage変換は続く。
    XCTAssertEqual(staleTracker.delivery, .stage)
    XCTAssertNotNil(staleTracker.stagePose)

    let expected = store.evaluatedSnapshot(atMonotonicNS: staleNS)
    XCTAssertEqual(stale.generation, expected.generation)
    XCTAssertEqual(stale.evaluatedMonotonicNS, staleNS)
    XCTAssertEqual(staleTracker.latest, try XCTUnwrap(expected.trackers.first))
  }
}
