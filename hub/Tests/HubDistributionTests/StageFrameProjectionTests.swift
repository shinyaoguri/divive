import HubCalibration
import HubCore
import HubDistribution
import HubProtocol
import XCTest

final class StageFrameProjectionTests: XCTestCase {
  private let receivedNS: UInt64 = 10_000_000_000

  private func makeSnapshot(
    resolver: CalibrationResolver,
    trackingSpaceID: UUIDBytes,
    spaceEpoch: UInt32 = 1,
    evaluatedNS: UInt64? = nil,
    trackers: [TrackerPose]
  ) throws -> CalibratedHubStateSnapshot {
    let store = HubStateStore()
    store.apply(
      makeStageFrame(
        sessionID: try stageTestUUID(0x10),
        bridgeID: try stageTestUUID(0x20),
        trackingSpaceID: trackingSpaceID,
        spaceEpoch: spaceEpoch,
        receivedMonotonicNS: receivedNS,
        trackers: trackers
      )
    )
    return resolver.project(
      store.evaluatedSnapshot(atMonotonicNS: evaluatedNS ?? receivedNS)
    )
  }

  func test較正済みTrackerをStageSpaceで配信する() throws {
    let spaceID = try stageTestUUID(0x30)
    let resolver = try makeStageResolver(
      calibratedSpaceID: spaceID,
      translation: Vector3(x: 10, y: 0, z: 0)
    )
    let snapshot = try makeSnapshot(
      resolver: resolver,
      trackingSpaceID: spaceID,
      trackers: [
        makeStageTrackerPose(
          trackerID: "sim://tracker/001",
          position: Vector3(x: 1, y: 2, z: 3)
        )
      ]
    )

    let frame = StageFrameProjection.makeFrame(from: snapshot, publishRateHz: 90)
    XCTAssertEqual(frame.deliveryMode, .production)
    XCTAssertEqual(frame.profileID, "stage-test")
    XCTAssertEqual(frame.profileRevision, 5)
    XCTAssertEqual(frame.publishRateHz, 90)
    XCTAssertEqual(frame.hubMonotonicNS, receivedNS)
    XCTAssertEqual(frame.trackers.count, 1)

    let tracker = try XCTUnwrap(frame.trackers.first)
    XCTAssertEqual(tracker.trackerID, "sim://tracker/001")
    XCTAssertEqual(tracker.role, "waist")
    XCTAssertEqual(tracker.delivery, .stage)
    XCTAssertEqual(tracker.idKind, .permanent)
    XCTAssertEqual(tracker.bridgeID, try stageTestUUID(0x20))
    XCTAssertEqual(tracker.trackingSpaceID, spaceID)
    XCTAssertEqual(tracker.spaceEpoch, 1)
    // 較正のtranslationが適用されたStage Spaceの値になる。
    XCTAssertEqual(tracker.pose?.position, Vector3(x: 11, y: 2, z: 3))
    XCTAssertEqual(tracker.liveness, .fresh)
    XCTAssertEqual(tracker.trackingState, .tracking)
    XCTAssertEqual(tracker.connected, true)
    XCTAssertEqual(tracker.battery, BatteryStatus(level: 0.5, charging: false))
    XCTAssertEqual(tracker.receiveAgeNS, 0)
    XCTAssertEqual(tracker.sourceFrameSequence, 1)
    XCTAssertEqual(tracker.captureMonotonicNS, 1_000)
  }

  func test未較正spaceのTrackerはposeを持たない() throws {
    let spaceID = try stageTestUUID(0x30)
    let resolver = try makeStageResolver(calibratedSpaceID: nil)
    let snapshot = try makeSnapshot(
      resolver: resolver,
      trackingSpaceID: spaceID,
      trackers: [makeStageTrackerPose(trackerID: "sim://tracker/001")]
    )

    let frame = StageFrameProjection.makeFrame(from: snapshot, publishRateHz: 90)
    let tracker = try XCTUnwrap(frame.trackers.first)
    XCTAssertEqual(tracker.delivery, .blocked)
    XCTAssertNil(tracker.pose)
    // poseを落としても、operatorとcontentが理由を示せる情報は残す。
    XCTAssertEqual(tracker.trackerID, "sim://tracker/001")
    XCTAssertEqual(tracker.role, "waist")
    XCTAssertEqual(tracker.trackingSpaceID, spaceID)
    XCTAssertEqual(tracker.liveness, .fresh)
  }

  func testPreviewModeは生のTrackerSpaceを明示して配信する() throws {
    let spaceID = try stageTestUUID(0x30)
    let resolver = try makeStageResolver(calibratedSpaceID: nil, mode: .preview)
    let snapshot = try makeSnapshot(
      resolver: resolver,
      trackingSpaceID: spaceID,
      trackers: [
        makeStageTrackerPose(
          trackerID: "sim://tracker/001",
          position: Vector3(x: 1, y: 2, z: 3)
        )
      ]
    )

    let frame = StageFrameProjection.makeFrame(from: snapshot, publishRateHz: 60)
    XCTAssertEqual(frame.deliveryMode, .preview)
    let tracker = try XCTUnwrap(frame.trackers.first)
    XCTAssertEqual(tracker.delivery, .rawTrackerSpace)
    XCTAssertEqual(tracker.pose?.position, Vector3(x: 1, y: 2, z: 3))
  }

  func testAge評価の結果をlivenessとtrackingStateへ反映する() throws {
    let spaceID = try stageTestUUID(0x30)
    let resolver = try makeStageResolver(calibratedSpaceID: spaceID)
    let snapshot = try makeSnapshot(
      resolver: resolver,
      trackingSpaceID: spaceID,
      evaluatedNS: receivedNS + 500_000_000,
      trackers: [makeStageTrackerPose(trackerID: "sim://tracker/001")]
    )

    let frame = StageFrameProjection.makeFrame(from: snapshot, publishRateHz: 90)
    let tracker = try XCTUnwrap(frame.trackers.first)
    XCTAssertEqual(tracker.liveness, .stale)
    XCTAssertEqual(tracker.trackingState, .lost)
    XCTAssertEqual(tracker.trackingReason, .networkStale)
    XCTAssertEqual(tracker.receiveAgeNS, 500_000_000)
    // Stage Space変換は続けるため、poseは残る。
    XCTAssertNotNil(tracker.pose)
  }

  func testProjectionしたframeをencodeできる() throws {
    let spaceID = try stageTestUUID(0x30)
    let resolver = try makeStageResolver(calibratedSpaceID: spaceID)
    let snapshot = try makeSnapshot(
      resolver: resolver,
      trackingSpaceID: spaceID,
      trackers: (0..<8).map {
        makeStageTrackerPose(trackerID: "sim://tracker/\(String(format: "%03d", $0))")
      }
    )

    let datagram = try StageFrameEncoder().encode(
      frame: StageFrameProjection.makeFrame(from: snapshot, publishRateHz: 90),
      sessionID: try stageTestUUID(0x20),
      sourceID: try stageTestUUID(0x40),
      frameSequence: 7
    )
    let decoded = try StageFrameDecoder().decode(datagram)

    XCTAssertLessThanOrEqual(datagram.count, StageWireProtocol.maximumDatagramSize)
    XCTAssertEqual(decoded.frame.trackers.count, 8)
    XCTAssertEqual(decoded.envelope.frameSequence, 7)
  }
}
