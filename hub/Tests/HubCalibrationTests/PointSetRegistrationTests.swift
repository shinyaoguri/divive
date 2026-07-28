import Foundation
import HubCalibration
import HubProtocol
import XCTest

final class PointSetRegistrationTests: XCTestCase {
  /// 3軸すべてを含む回転。axis (1,1,1)/√3 まわり60度。
  private let tiltedRotation = Quaternion(
    x: 0.2886751,
    y: 0.2886751,
    z: 0.2886751,
    w: 0.8660254
  )

  private let spreadPoints = [
    Vector3(x: 0, y: 0, z: 0),
    Vector3(x: 2, y: 0, z: 0),
    Vector3(x: 0, y: 1.5, z: 0),
    Vector3(x: 0, y: 0, z: -1.2),
    Vector3(x: 1, y: 1, z: 1),
  ]

  private func makeCorrespondences(
    _ transform: RigidTransform,
    points: [Vector3]
  ) throws -> [PointCorrespondence] {
    try points.map {
      try PointCorrespondence(
        trackerPosition: $0,
        stagePosition: transform.apply(toPosition: $0)
      )
    }
  }

  func testYawのみの既知transformを3点から回復する() throws {
    let known = try makeTransform(
      translation: Vector3(x: 1.5, y: -0.5, z: 2),
      rotation: Quaternion(x: 0, y: 0.7071068, z: 0, w: 0.7071068)
    )
    let estimate = try PointSetRegistration.estimate(
      correspondences: try makeCorrespondences(
        known,
        points: Array(spreadPoints.prefix(3))
      )
    )

    XCTAssertTrue(
      estimate.transform.representsSameTransform(as: known, positionToleranceM: 1.0e-4),
      "回復したtransformが一致しません: \(estimate.transform)"
    )
    XCTAssertEqual(estimate.method, .pointSetRegistration)
    XCTAssertEqual(estimate.sampleCount, 3)
    XCTAssertEqual(try XCTUnwrap(estimate.rmsErrorM), 0, accuracy: 1.0e-4)
    XCTAssertEqual(try XCTUnwrap(estimate.maxResidualM), 0, accuracy: 1.0e-4)
  }

  func test3軸を含む回転を回復する() throws {
    let known = try makeTransform(
      translation: Vector3(x: -2, y: 0.75, z: 4),
      rotation: tiltedRotation
    )
    let estimate = try PointSetRegistration.estimate(
      correspondences: try makeCorrespondences(known, points: spreadPoints)
    )

    XCTAssertTrue(
      estimate.transform.representsSameTransform(as: known, positionToleranceM: 1.0e-4),
      "回復したtransformが一致しません: \(estimate.transform)"
    )
    XCTAssertEqual(estimate.sampleCount, 5)
    XCTAssertEqual(try XCTUnwrap(estimate.maxResidualM), 0, accuracy: 1.0e-4)
  }

  func test点数が増えても同じtransformを回復する() throws {
    let known = try makeTransform(
      translation: Vector3(x: 0.25, y: 1, z: -3),
      rotation: tiltedRotation
    )
    let extended =
      spreadPoints + [
        Vector3(x: -1.5, y: 0.5, z: 2),
        Vector3(x: 3, y: -1, z: 0.5),
        Vector3(x: 0.5, y: 2.5, z: -2),
      ]

    let fewer = try PointSetRegistration.estimate(
      correspondences: try makeCorrespondences(known, points: spreadPoints)
    )
    let more = try PointSetRegistration.estimate(
      correspondences: try makeCorrespondences(known, points: extended)
    )

    XCTAssertEqual(more.sampleCount, 8)
    XCTAssertTrue(more.transform.representsSameTransform(as: known, positionToleranceM: 1.0e-4))
    XCTAssertTrue(
      more.transform.representsSameTransform(
        as: fewer.transform,
        positionToleranceM: 1.0e-4
      )
    )
  }

  func test対応点をずらすとresidualが増える() throws {
    let known = try makeTransform(
      translation: Vector3(x: 1, y: 0, z: 0),
      rotation: Quaternion(x: 0, y: 0.7071068, z: 0, w: 0.7071068)
    )
    var correspondences = try makeCorrespondences(known, points: spreadPoints)

    let clean = try PointSetRegistration.estimate(correspondences: correspondences)
    XCTAssertEqual(try XCTUnwrap(clean.maxResidualM), 0, accuracy: 1.0e-4)

    // 1点だけ0.2mずらす。
    let displaced = try XCTUnwrap(correspondences.last)
    correspondences[correspondences.count - 1] = try PointCorrespondence(
      trackerPosition: displaced.trackerPosition,
      stagePosition: Vector3(
        x: displaced.stagePosition.x + 0.2,
        y: displaced.stagePosition.y,
        z: displaced.stagePosition.z
      )
    )

    let noisy = try PointSetRegistration.estimate(correspondences: correspondences)
    let maxResidual = try XCTUnwrap(noisy.maxResidualM)
    let rms = try XCTUnwrap(noisy.rmsErrorM)
    XCTAssertGreaterThan(maxResidual, 0.01)
    XCTAssertLessThanOrEqual(maxResidual, 0.2)
    XCTAssertGreaterThan(rms, 0)
    XCTAssertLessThan(rms, maxResidual)
  }

  func test鏡像の対応点でも反射ではなく回転を返す() throws {
    // Stage側をX軸で反転させた、回転では一致しない対応。
    let correspondences = try spreadPoints.map {
      try PointCorrespondence(
        trackerPosition: $0,
        stagePosition: Vector3(x: -$0.x, y: $0.y, z: $0.z)
      )
    }

    let estimate = try PointSetRegistration.estimate(correspondences: correspondences)

    // quaternionから作る以上、常に正しい向きの回転になる。
    // 基底`+X`、`+Y`、`+Z`の像が作る行列式は、回転なら+1、反射なら-1になる。
    let axisX = estimate.transform.apply(toDirection: Vector3(x: 1, y: 0, z: 0))
    let axisY = estimate.transform.apply(toDirection: Vector3(x: 0, y: 1, z: 0))
    let axisZ = estimate.transform.apply(toDirection: Vector3(x: 0, y: 0, z: 1))
    let determinant =
      Double(axisX.x) * (Double(axisY.y) * Double(axisZ.z) - Double(axisY.z) * Double(axisZ.y))
      - Double(axisX.y)
        * (Double(axisY.x) * Double(axisZ.z) - Double(axisY.z) * Double(axisZ.x))
      + Double(axisX.z)
        * (Double(axisY.x) * Double(axisZ.y) - Double(axisY.y) * Double(axisZ.x))
    XCTAssertEqual(determinant, 1, accuracy: 1.0e-4, "反射を返しています")

    // 鏡像は剛体変換で一致しないため、residualが残る。
    XCTAssertGreaterThan(try XCTUnwrap(estimate.maxResidualM), 0.1)
  }

  func test対応点が3点未満なら拒否する() throws {
    let known = RigidTransform.identity
    for count in 0...2 {
      let points = Array(spreadPoints.prefix(count))
      XCTAssertThrowsError(
        try PointSetRegistration.estimate(
          correspondences: try makeCorrespondences(known, points: points)
        )
      ) { error in
        XCTAssertEqual(
          error as? CalibrationEstimationError,
          .insufficientCorrespondences(count: count)
        )
      }
    }
  }

  func test対応点が集中しすぎていると拒否する() throws {
    let points = [
      Vector3(x: 0, y: 0, z: 0),
      Vector3(x: 0.01, y: 0, z: 0),
      Vector3(x: 0, y: 0.01, z: 0),
      Vector3(x: 0, y: 0, z: 0.01),
    ]

    XCTAssertThrowsError(
      try PointSetRegistration.estimate(
        correspondences: try makeCorrespondences(.identity, points: points)
      )
    ) { error in
      guard
        case let .correspondencesTooClose(spread) = error as? CalibrationEstimationError
      else {
        return XCTFail("correspondencesTooCloseを期待しました: \(error)")
      }
      XCTAssertLessThan(spread, PointSetRegistration.minimumSpreadM)
    }
  }

  func test対応点が同一直線上なら拒否する() throws {
    let points = [
      Vector3(x: 0, y: 0, z: 0),
      Vector3(x: 1, y: 0, z: 0),
      Vector3(x: 2, y: 0, z: 0),
      Vector3(x: 3, y: 0, z: 0),
    ]

    XCTAssertThrowsError(
      try PointSetRegistration.estimate(
        correspondences: try makeCorrespondences(.identity, points: points)
      )
    ) { error in
      guard
        case let .collinearCorrespondences(ratio) = error as? CalibrationEstimationError
      else {
        return XCTFail("collinearCorrespondencesを期待しました: \(error)")
      }
      XCTAssertLessThan(ratio, PointSetRegistration.minimumPlanarityRatio)
    }
  }

  func test同一平面上の対応点は受け入れる() throws {
    // 床に並べた3点のように、平面内でも回転は一意に決まる。
    let known = try makeTransform(
      translation: Vector3(x: 0.5, y: 0, z: -1),
      rotation: tiltedRotation
    )
    let points = [
      Vector3(x: 0, y: 0, z: 0),
      Vector3(x: 2, y: 0, z: 0),
      Vector3(x: 0, y: 0, z: -2),
      Vector3(x: 2, y: 0, z: -2),
    ]

    let estimate = try PointSetRegistration.estimate(
      correspondences: try makeCorrespondences(known, points: points)
    )
    XCTAssertTrue(
      estimate.transform.representsSameTransform(as: known, positionToleranceM: 1.0e-4)
    )
  }

  func test非有限の対応点を拒否する() throws {
    XCTAssertThrowsError(
      try PointCorrespondence(
        trackerPosition: Vector3(x: .nan, y: 0, z: 0),
        stagePosition: Vector3(x: 0, y: 0, z: 0)
      )
    ) { error in
      XCTAssertEqual(error as? CalibrationEstimationError, .nonFiniteSample)
    }
    XCTAssertThrowsError(
      try PointCorrespondence(
        trackerPosition: Vector3(x: 0, y: 0, z: 0),
        stagePosition: Vector3(x: 0, y: .infinity, z: 0)
      )
    ) { error in
      XCTAssertEqual(error as? CalibrationEstimationError, .nonFiniteSample)
    }
  }

  func test推定結果をprofileへ格納できる() throws {
    let spaceID = try calibrationTestUUID(0xA5)
    let known = try makeTransform(
      translation: Vector3(x: 1, y: 2, z: 3),
      rotation: tiltedRotation
    )
    let estimate = try PointSetRegistration.estimate(
      correspondences: try makeCorrespondences(known, points: spreadPoints)
    )

    let profile = try makeProfile().upserting(
      try estimate.makeSpaceCalibration(
        trackingSpaceID: spaceID,
        spaceEpoch: 2,
        operatorNote: "床の4点",
        updatedAt: calibrationTestDate
      ),
      at: calibrationTestDate
    )

    let stored = try XCTUnwrap(profile.calibration(forTrackingSpaceID: spaceID))
    XCTAssertEqual(stored.method, .pointSetRegistration)
    XCTAssertEqual(stored.sampleCount, 5)
    XCTAssertEqual(try XCTUnwrap(stored.rmsErrorM), 0, accuracy: 1.0e-4)

    let resolver = CalibrationResolver(profile: profile)
    let outcome = resolver.resolve(
      makePoseBatch(
        trackingSpaceID: spaceID,
        spaceEpoch: 2,
        trackers: [makeTrackerPose(position: Vector3(x: 2, y: 0, z: 0))]
      )
    )
    assertVector(
      try XCTUnwrap(outcome.batch?.trackers.first).position,
      known.apply(toPosition: Vector3(x: 2, y: 0, z: 0)),
      accuracy: 1.0e-4
    )
  }
}
