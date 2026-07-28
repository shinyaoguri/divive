import Foundation
import HubCalibration
import HubProtocol
import XCTest

final class CalibrationResolverTests: XCTestCase {
  private let yaw90 = Quaternion(x: 0, y: 0.7071068, z: 0, w: 0.7071068)

  func test較正済みspaceはStageSpaceへ変換される() throws {
    let spaceID = try calibrationTestUUID(0xA0)
    let resolver = CalibrationResolver(
      profile: try makeProfile(
        spaces: [
          try makeSpaceCalibration(
            trackingSpaceID: spaceID,
            spaceEpoch: 3,
            transform: try makeTransform(
              translation: Vector3(x: 1, y: 2, z: 3),
              rotation: yaw90
            )
          )
        ]
      )
    )

    let outcome = resolver.resolve(
      makePoseBatch(
        trackingSpaceID: spaceID,
        spaceEpoch: 3,
        trackers: [
          makeTrackerPose(
            position: Vector3(x: 1, y: 0, z: 0),
            linearVelocity: Vector3(x: 0, y: 0, z: -1),
            angularVelocity: Vector3(x: 0, y: 1, z: 0)
          )
        ]
      )
    )

    guard let batch = outcome.batch else {
      return XCTFail("配信されるべきbatchがblockedになりました: \(outcome)")
    }
    XCTAssertTrue(outcome.status.isCalibrated)
    XCTAssertEqual(batch.spaceState, .stage)
    XCTAssertEqual(batch.profileID, "studio-a")
    XCTAssertEqual(batch.profileRevision, 1)
    XCTAssertEqual(batch.backend, .openvr)
    XCTAssertEqual(batch.requestedRateHz, 120)

    let pose = try XCTUnwrap(batch.trackers.first)
    assertVector(pose.position, Vector3(x: 1, y: 2, z: 2))
    assertSameRotation(pose.orientation, yaw90)
    assertVector(try XCTUnwrap(pose.linearVelocity), Vector3(x: -1, y: 0, z: 0))
    assertVector(try XCTUnwrap(pose.angularVelocity), Vector3(x: 0, y: 1, z: 0))
    XCTAssertEqual(pose.trackerID, "tracker-1")
    XCTAssertEqual(pose.role, "left-foot")
    XCTAssertEqual(pose.trackingState, .tracking)
  }

  func testVelocityがnilのposeでもnilのまま変換する() throws {
    let spaceID = try calibrationTestUUID(0xA1)
    let resolver = CalibrationResolver(
      profile: try makeProfile(
        spaces: [
          try makeSpaceCalibration(
            trackingSpaceID: spaceID,
            transform: try makeTransform(rotation: yaw90)
          )
        ]
      )
    )

    let outcome = resolver.resolve(
      makePoseBatch(
        trackingSpaceID: spaceID,
        trackers: [makeTrackerPose(position: Vector3(x: 1, y: 0, z: 0))]
      )
    )

    let pose = try XCTUnwrap(outcome.batch?.trackers.first)
    XCTAssertNil(pose.linearVelocity)
    XCTAssertNil(pose.angularVelocity)
    assertVector(pose.position, Vector3(x: 0, y: 0, z: -1))
  }

  func test未較正spaceはproductionで配信されない() throws {
    let knownSpace = try calibrationTestUUID(0xB0)
    let unknownSpace = try calibrationTestUUID(0xB1)
    let resolver = CalibrationResolver(
      profile: try makeProfile(
        spaces: [try makeSpaceCalibration(trackingSpaceID: knownSpace)]
      ),
      mode: .production
    )

    let outcome = resolver.resolve(
      makePoseBatch(
        trackingSpaceID: unknownSpace,
        trackers: [makeTrackerPose(position: Vector3(x: 1, y: 0, z: 0))]
      )
    )

    XCTAssertNil(outcome.batch, "未較正spaceをcontentへ流してはいけません")
    XCTAssertEqual(outcome.status, .uncalibrated(trackingSpaceID: unknownSpace))
  }

  func test未較正spaceはpreviewで生TrackerSpaceとして配信される() throws {
    let unknownSpace = try calibrationTestUUID(0xB2)
    let resolver = CalibrationResolver(profile: try makeProfile(), mode: .preview)
    let position = Vector3(x: 1.25, y: -3, z: 0.5)

    let outcome = resolver.resolve(
      makePoseBatch(
        trackingSpaceID: unknownSpace,
        trackers: [makeTrackerPose(position: position)]
      )
    )

    guard let batch = outcome.batch else {
      return XCTFail("preview modeでは配信されるべきです: \(outcome)")
    }
    XCTAssertEqual(batch.spaceState, .rawTrackerSpace)
    XCTAssertEqual(outcome.status, .uncalibrated(trackingSpaceID: unknownSpace))
    assertVector(
      try XCTUnwrap(batch.trackers.first).position,
      position,
      "preview配信でidentity以外の変換を加えてはいけません"
    )
  }

  func testEpoch不一致は較正済みspaceでも配信されない() throws {
    let spaceID = try calibrationTestUUID(0xC0)
    let profile = try makeProfile(
      spaces: [
        try makeSpaceCalibration(
          trackingSpaceID: spaceID,
          spaceEpoch: 2,
          transform: try makeTransform(translation: Vector3(x: 5, y: 0, z: 0))
        )
      ]
    )

    let production = CalibrationResolver(profile: profile, mode: .production)
    let batch = makePoseBatch(
      trackingSpaceID: spaceID,
      spaceEpoch: 3,
      trackers: [makeTrackerPose(position: Vector3(x: 1, y: 0, z: 0))]
    )
    let blocked = production.resolve(batch)

    XCTAssertNil(blocked.batch)
    XCTAssertEqual(
      blocked.status,
      .epochMismatch(trackingSpaceID: spaceID, profileEpoch: 2, observedEpoch: 3)
    )

    let preview = CalibrationResolver(profile: profile, mode: .preview)
    let previewed = preview.resolve(batch)
    XCTAssertEqual(previewed.batch?.spaceState, .rawTrackerSpace)
    assertVector(
      try XCTUnwrap(previewed.batch?.trackers.first).position,
      Vector3(x: 1, y: 0, z: 0),
      "epoch不一致でも古い較正を適用してはいけません"
    )
  }

  func test統計が配信とblockの内訳を数える() throws {
    let calibratedSpace = try calibrationTestUUID(0xD0)
    let unknownSpace = try calibrationTestUUID(0xD1)
    let resolver = CalibrationResolver(
      profile: try makeProfile(
        spaces: [
          try makeSpaceCalibration(trackingSpaceID: calibratedSpace, spaceEpoch: 1)
        ]
      ),
      mode: .production
    )

    var statistics = CalibrationStatistics()
    let trackers = [makeTrackerPose(position: Vector3(x: 0, y: 0, z: 0))]
    statistics.record(
      resolver.resolve(
        makePoseBatch(trackingSpaceID: calibratedSpace, spaceEpoch: 1, trackers: trackers)
      )
    )
    statistics.record(
      resolver.resolve(
        makePoseBatch(trackingSpaceID: unknownSpace, spaceEpoch: 1, trackers: trackers)
      )
    )
    statistics.record(
      resolver.resolve(
        makePoseBatch(trackingSpaceID: calibratedSpace, spaceEpoch: 9, trackers: trackers)
      )
    )

    XCTAssertEqual(statistics.stageBatches, 1)
    XCTAssertEqual(statistics.rawTrackerSpaceBatches, 0)
    XCTAssertEqual(statistics.blockedUncalibratedBatches, 1)
    XCTAssertEqual(statistics.blockedEpochMismatchBatches, 1)

    var previewStatistics = CalibrationStatistics()
    previewStatistics.record(
      CalibrationResolver(profile: resolver.profile, mode: .preview).resolve(
        makePoseBatch(trackingSpaceID: unknownSpace, trackers: trackers)
      )
    )
    XCTAssertEqual(previewStatistics.rawTrackerSpaceBatches, 1)
    XCTAssertEqual(previewStatistics.blockedUncalibratedBatches, 0)
  }

  func testStatusは較正有無とepochを区別する() throws {
    let spaceID = try calibrationTestUUID(0xE0)
    let missing = try calibrationTestUUID(0xE1)
    let resolver = CalibrationResolver(
      profile: try makeProfile(
        spaces: [try makeSpaceCalibration(trackingSpaceID: spaceID, spaceEpoch: 4)]
      )
    )

    XCTAssertTrue(
      resolver.status(forTrackingSpaceID: spaceID, spaceEpoch: 4).isCalibrated
    )
    XCTAssertEqual(
      resolver.status(forTrackingSpaceID: spaceID, spaceEpoch: 5),
      .epochMismatch(trackingSpaceID: spaceID, profileEpoch: 4, observedEpoch: 5)
    )
    XCTAssertEqual(
      resolver.status(forTrackingSpaceID: missing, spaceEpoch: 4),
      .uncalibrated(trackingSpaceID: missing)
    )
  }
}
