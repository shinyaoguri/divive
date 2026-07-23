import HubCore
import HubProtocol
import XCTest

final class HubLivenessTests: XCTestCase {
  func testPolicyの閾値を検証する() throws {
    let defaults = HubLivenessPolicy()
    XCTAssertEqual(defaults.lostAfterNS, 250_000_000)
    XCTAssertEqual(defaults.disconnectedAfterNS, 2_000_000_000)

    XCTAssertThrowsError(
      try HubLivenessPolicy(lostAfterNS: 0, disconnectedAfterNS: 10)
    ) { error in
      XCTAssertEqual(
        error as? HubLivenessPolicyError,
        .lostThresholdMustBePositive
      )
    }
    XCTAssertThrowsError(
      try HubLivenessPolicy(lostAfterNS: 10, disconnectedAfterNS: 10)
    ) { error in
      XCTAssertEqual(
        error as? HubLivenessPolicyError,
        .disconnectedThresholdMustExceedLostThreshold
      )
    }
    XCTAssertThrowsError(
      try HubLivenessPolicy(lostAfterNS: 11, disconnectedAfterNS: 10)
    )
  }

  func test受信ageの境界でfreshからstaleとdisconnectedへ遷移する() throws {
    let tracker = try latestTracker(
      testTracker("a", trackingState: .tracking),
      receivedMonotonicNS: 100
    )
    let policy = try HubLivenessPolicy(
      lostAfterNS: 50,
      disconnectedAfterNS: 200
    )

    let fresh = tracker.evaluated(atMonotonicNS: 149, policy: policy)
    XCTAssertEqual(fresh.receiveAgeNS, 49)
    XCTAssertEqual(fresh.liveness, .fresh)
    XCTAssertEqual(fresh.trackingState, .tracking)
    XCTAssertEqual(fresh.trackingReason, .none)
    XCTAssertFalse(fresh.wasAgeAdjusted)

    let stale = tracker.evaluated(atMonotonicNS: 150, policy: policy)
    XCTAssertEqual(stale.receiveAgeNS, 50)
    XCTAssertEqual(stale.liveness, .stale)
    XCTAssertEqual(stale.trackingState, .lost)
    XCTAssertEqual(stale.trackingReason, .networkStale)
    XCTAssertTrue(stale.wasAgeAdjusted)

    let disconnected = tracker.evaluated(
      atMonotonicNS: 300,
      policy: policy
    )
    XCTAssertEqual(disconnected.receiveAgeNS, 200)
    XCTAssertEqual(disconnected.liveness, .disconnected)
    XCTAssertEqual(disconnected.trackingState, .disconnected)
    XCTAssertEqual(disconnected.trackingReason, .bridgeTimeout)
    XCTAssertTrue(disconnected.wasAgeAdjusted)
  }

  func test新鮮なsource状態を保持してclock巻き戻りをageゼロとして扱う() throws {
    let policy = try HubLivenessPolicy(
      lostAfterNS: 50,
      disconnectedAfterNS: 200
    )
    let lost = try latestTracker(
      testTracker(
        "lost",
        trackingState: .lost,
        trackingReason: .runtimePoseInvalid
      ),
      receivedMonotonicNS: 100
    ).evaluated(atMonotonicNS: 99, policy: policy)

    XCTAssertEqual(lost.receiveAgeNS, 0)
    XCTAssertEqual(lost.liveness, .fresh)
    XCTAssertEqual(lost.trackingState, .lost)
    XCTAssertEqual(lost.trackingReason, .runtimePoseInvalid)
    XCTAssertFalse(lost.wasAgeAdjusted)

    let unplugged = try latestTracker(
      testTracker(
        "unplugged",
        trackingState: .tracking,
        trackingReason: .deviceUnplugged,
        connected: false
      ),
      receivedMonotonicNS: 100
    ).evaluated(atMonotonicNS: 100, policy: policy)

    XCTAssertEqual(unplugged.liveness, .disconnected)
    XCTAssertEqual(unplugged.trackingState, .disconnected)
    XCTAssertEqual(unplugged.trackingReason, .deviceUnplugged)
    XCTAssertTrue(unplugged.wasAgeAdjusted)

    let reportedDisconnected = try latestTracker(
      testTracker(
        "reported-disconnected",
        trackingState: .disconnected,
        trackingReason: .deviceUnplugged
      ),
      receivedMonotonicNS: 100
    ).evaluated(atMonotonicNS: 100, policy: policy)

    XCTAssertEqual(reportedDisconnected.liveness, .disconnected)
    XCTAssertEqual(reportedDisconnected.trackingState, .disconnected)
    XCTAssertEqual(reportedDisconnected.trackingReason, .deviceUnplugged)
    XCTAssertFalse(reportedDisconnected.wasAgeAdjusted)
  }

  func testPartialで未更新Trackerだけがstaleになり新規frameで復帰する() throws {
    let session = try testUUID(1)
    let bridge = try testUUID(20)
    let space = try testUUID(40)
    let policy = try HubLivenessPolicy(
      lostAfterNS: 200,
      disconnectedAfterNS: 500
    )
    let store = HubStateStore()

    store.apply(
      testFrame(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 1,
        trackers: [
          testTracker("a", trackingState: .tracking),
          testTracker("b", trackingState: .tracking),
        ],
        receivedMonotonicNS: 100
      )
    )
    store.apply(
      testFrame(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 2,
        trackers: [testTracker("a", trackingState: .tracking)],
        receivedMonotonicNS: 300,
        completeness: .partial(missingBatchIndices: [1])
      )
    )

    let evaluated = store.evaluatedSnapshot(
      atMonotonicNS: 350,
      policy: policy
    )
    XCTAssertEqual(evaluated.generation, 2)
    XCTAssertEqual(evaluated.evaluatedMonotonicNS, 350)
    XCTAssertEqual(evaluated.policy, policy)
    XCTAssertEqual(evaluated.bridges.map(\.liveness), [.fresh])

    let a = try XCTUnwrap(
      evaluated.trackers.first { $0.latest.key.trackerID == "a" }
    )
    let b = try XCTUnwrap(
      evaluated.trackers.first { $0.latest.key.trackerID == "b" }
    )
    XCTAssertEqual(a.liveness, .fresh)
    XCTAssertEqual(a.trackingState, .tracking)
    XCTAssertEqual(b.liveness, .stale)
    XCTAssertEqual(b.trackingState, .lost)
    XCTAssertEqual(b.trackingReason, .networkStale)

    let rawB = try XCTUnwrap(
      store.trackerState(
        for: TrackerKey(bridgeID: bridge, trackerID: "b")
      )
    )
    XCTAssertEqual(rawB.pose.trackingState, .tracking)
    XCTAssertEqual(store.snapshot().generation, 2)

    store.apply(
      testFrame(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 3,
        trackers: [testTracker("b", trackingState: .tracking)],
        receivedMonotonicNS: 400
      )
    )
    let recovered = try XCTUnwrap(
      store.evaluatedTrackerState(
        for: TrackerKey(bridgeID: bridge, trackerID: "b"),
        atMonotonicNS: 401,
        policy: policy
      )
    )
    XCTAssertEqual(recovered.liveness, .fresh)
    XCTAssertEqual(recovered.trackingState, .tracking)
    XCTAssertFalse(recovered.wasAgeAdjusted)
  }

  func testBridgeも同じpolicyで段階的に評価する() throws {
    let session = try testUUID(1)
    let bridgeID = try testUUID(20)
    let space = try testUUID(40)
    let store = HubStateStore()
    let policy = try HubLivenessPolicy(
      lostAfterNS: 50,
      disconnectedAfterNS: 200
    )

    store.apply(
      testFrame(
        session: session,
        bridge: bridgeID,
        trackingSpace: space,
        sequence: 1,
        trackers: [testTracker("a")],
        receivedMonotonicNS: 100
      )
    )

    XCTAssertEqual(
      store.evaluatedBridgeState(
        for: bridgeID,
        atMonotonicNS: 149,
        policy: policy
      )?.liveness,
      .fresh
    )
    XCTAssertEqual(
      store.evaluatedBridgeState(
        for: bridgeID,
        atMonotonicNS: 150,
        policy: policy
      )?.liveness,
      .stale
    )
    XCTAssertEqual(
      store.evaluatedBridgeState(
        for: bridgeID,
        atMonotonicNS: 300,
        policy: policy
      )?.liveness,
      .disconnected
    )
  }

  private func latestTracker(
    _ pose: TrackerPose,
    receivedMonotonicNS: UInt64
  ) throws -> LatestTrackerState {
    let store = HubStateStore()
    store.apply(
      testFrame(
        session: try testUUID(1),
        bridge: try testUUID(20),
        trackingSpace: try testUUID(40),
        sequence: 1,
        trackers: [pose],
        receivedMonotonicNS: receivedMonotonicNS
      )
    )
    return try XCTUnwrap(store.snapshot().trackers.first)
  }
}
