import Foundation
import HubCalibration
import HubProtocol
import XCTest

final class OriginAndForwardEstimatorTests: XCTestCase {
  private func sample(_ x: Float, _ y: Float, _ z: Float) throws -> CalibrationSample {
    try CalibrationSample(position: Vector3(x: x, y: y, z: z))
  }

  func test原点サンプルがStage原点へ写る() throws {
    let estimate = try OriginAndForwardEstimator.estimate(
      origin: try sample(2, 1, -3),
      forward: try sample(2, 1, -5)
    )

    assertVector(
      estimate.transform.apply(toPosition: Vector3(x: 2, y: 1, z: -3)),
      Vector3(x: 0, y: 0, z: 0)
    )
    XCTAssertEqual(estimate.method, .originAndForward)
    XCTAssertEqual(estimate.sampleCount, 2)
    XCTAssertNil(estimate.rmsErrorM)
    XCTAssertNil(estimate.maxResidualM)
  }

  func test前方サンプルがStageのマイナスZへ向く() throws {
    // Tracker Spaceの+X方向を基準方向として指した場合。
    let estimate = try OriginAndForwardEstimator.estimate(
      origin: try sample(0, 0, 0),
      forward: try sample(2, 0, 0)
    )

    assertVector(
      estimate.transform.apply(toPosition: Vector3(x: 2, y: 0, z: 0)),
      Vector3(x: 0, y: 0, z: -2)
    )
  }

  func test基準方向が既にマイナスZならidentity回転になる() throws {
    let estimate = try OriginAndForwardEstimator.estimate(
      origin: try sample(0, 0, 0),
      forward: try sample(0, 0, -1.5)
    )

    assertSameRotation(estimate.transform.rotation, Quaternion(x: 0, y: 0, z: 0, w: 1))
    assertVector(
      estimate.transform.apply(toPosition: Vector3(x: 1, y: 2, z: 3)),
      Vector3(x: 1, y: 2, z: 3)
    )
  }

  func test推定結果はyawだけを持つ() throws {
    for forward in [
      try sample(1, 0.4, 0),
      try sample(-1, -0.9, 0.3),
      try sample(0.7, 2, -0.7),
    ] {
      let estimate = try OriginAndForwardEstimator.estimate(
        origin: try sample(0, 0, 0),
        forward: forward
      )

      let rotation = estimate.transform.rotation
      XCTAssertEqual(rotation.x, 0, accuracy: 1.0e-6, "pitchが混入しています")
      XCTAssertEqual(rotation.z, 0, accuracy: 1.0e-6, "rollが混入しています")
      assertVector(
        estimate.transform.apply(toDirection: Vector3(x: 0, y: 1, z: 0)),
        Vector3(x: 0, y: 1, z: 0),
        "up軸が+Yのままではありません"
      )
    }
  }

  func test前方サンプルの高さ差はyawへ影響しない() throws {
    let level = try OriginAndForwardEstimator.estimate(
      origin: try sample(0, 0, 0),
      forward: try sample(1, 0, 1)
    )
    let raised = try OriginAndForwardEstimator.estimate(
      origin: try sample(0, 0, 0),
      forward: try sample(1, 1.8, 1)
    )

    assertSameRotation(raised.transform.rotation, level.transform.rotation)
  }

  func test床面offsetで原点の高さを指定できる() throws {
    let estimate = try OriginAndForwardEstimator.estimate(
      origin: try sample(0.5, 0.92, -1),
      forward: try sample(0.5, 0.92, -3),
      floorHeightOffsetM: 0.92
    )

    assertVector(
      estimate.transform.apply(toPosition: Vector3(x: 0.5, y: 0.92, z: -1)),
      Vector3(x: 0, y: 0.92, z: 0)
    )
  }

  func test既知のtransformを合成サンプルから回復する() throws {
    // Stage原点とStageの-Z 2mの点を、既知のyaw変換の逆でTracker Spaceへ写す。
    let yaw = Quaternion(x: 0, y: 0.7071068, z: 0, w: 0.7071068)
    let known = try RigidTransform(
      translation: Vector3(x: 1.25, y: -0.5, z: 3),
      rotation: yaw
    )
    let inverse = known.inverse

    let estimate = try OriginAndForwardEstimator.estimate(
      origin: try CalibrationSample(
        position: inverse.apply(toPosition: Vector3(x: 0, y: 0, z: 0))
      ),
      forward: try CalibrationSample(
        position: inverse.apply(toPosition: Vector3(x: 0, y: 0, z: -2))
      )
    )

    XCTAssertTrue(
      estimate.transform.representsSameTransform(as: known, positionToleranceM: 1.0e-4),
      "既知のtransformを回復できません: \(estimate.transform)"
    )
  }

  func test検証点からRMSとmaxResidualを計算する() throws {
    let checkPoints = [
      try CalibrationCheckPoint(
        trackerPosition: Vector3(x: 2, y: 0, z: 0),
        expectedStagePosition: Vector3(x: 0, y: 0, z: -2)
      ),
      try CalibrationCheckPoint(
        trackerPosition: Vector3(x: 0, y: 0, z: 3),
        expectedStagePosition: Vector3(x: 3, y: 0, z: 0)
      ),
    ]

    let estimate = try OriginAndForwardEstimator.estimate(
      origin: try sample(0, 0, 0),
      forward: try sample(2, 0, 0),
      checkPoints: checkPoints
    )

    XCTAssertEqual(try XCTUnwrap(estimate.rmsErrorM), 0, accuracy: 1.0e-5)
    XCTAssertEqual(try XCTUnwrap(estimate.maxResidualM), 0, accuracy: 1.0e-5)
  }

  func test較正がずれていると残差が現れる() throws {
    let estimate = try OriginAndForwardEstimator.estimate(
      origin: try sample(0, 0, 0),
      forward: try sample(2, 0, 0),
      checkPoints: [
        try CalibrationCheckPoint(
          trackerPosition: Vector3(x: 2, y: 0, z: 0),
          expectedStagePosition: Vector3(x: 0, y: 0, z: -2)
        ),
        try CalibrationCheckPoint(
          trackerPosition: Vector3(x: 0, y: 0, z: 3),
          expectedStagePosition: Vector3(x: 3.4, y: 0, z: 0)
        ),
      ]
    )

    XCTAssertEqual(try XCTUnwrap(estimate.maxResidualM), 0.4, accuracy: 1.0e-4)
    XCTAssertEqual(
      try XCTUnwrap(estimate.rmsErrorM),
      (0.4 * 0.4 / 2).squareRoot(),
      accuracy: 1.0e-4
    )
  }

  func test退化した前方方向を拒否する() throws {
    XCTAssertThrowsError(
      try OriginAndForwardEstimator.estimate(
        origin: try sample(1, 1, 1),
        forward: try sample(1, 1, 1)
      )
    ) { error in
      guard
        case let .degenerateForwardDirection(length) = error as? CalibrationEstimationError
      else {
        return XCTFail("degenerateForwardDirectionを期待しました: \(error)")
      }
      XCTAssertEqual(length, 0, accuracy: 1.0e-6)
    }

    // 真上へ移動しただけでは水平成分が得られない。
    XCTAssertThrowsError(
      try OriginAndForwardEstimator.estimate(
        origin: try sample(0, 0, 0),
        forward: try sample(0, 2, 0)
      )
    )

    // 下限のすぐ手前は拒否し、下限ちょうどは受け入れる。
    XCTAssertThrowsError(
      try OriginAndForwardEstimator.estimate(
        origin: try sample(0, 0, 0),
        forward: try sample(0.09, 0, 0)
      )
    )
    XCTAssertNoThrow(
      try OriginAndForwardEstimator.estimate(
        origin: try sample(0, 0, 0),
        forward: try sample(0.1, 0, 0)
      )
    )
  }

  func test非有限のサンプルとoffsetを拒否する() throws {
    XCTAssertThrowsError(
      try CalibrationSample(position: Vector3(x: .nan, y: 0, z: 0))
    ) { error in
      XCTAssertEqual(error as? CalibrationEstimationError, .nonFiniteSample)
    }
    XCTAssertThrowsError(
      try CalibrationCheckPoint(
        trackerPosition: Vector3(x: 0, y: 0, z: 0),
        expectedStagePosition: Vector3(x: .infinity, y: 0, z: 0)
      )
    ) { error in
      XCTAssertEqual(error as? CalibrationEstimationError, .nonFiniteSample)
    }
    XCTAssertThrowsError(
      try OriginAndForwardEstimator.estimate(
        origin: try sample(0, 0, 0),
        forward: try sample(2, 0, 0),
        floorHeightOffsetM: .nan
      )
    ) { error in
      XCTAssertEqual(error as? CalibrationEstimationError, .nonFiniteFloorHeightOffset)
    }
  }

  func test静止frameは中央値でまとめ外れ値に引きずられない() throws {
    let stationary = Array(repeating: Vector3(x: 1.0, y: 0.5, z: -2.0), count: 8)
    let withOutlier = stationary + [Vector3(x: 41, y: -17, z: 88)]

    let sample = try CalibrationSample.fromStationaryFrames(withOutlier)
    assertVector(sample.position, Vector3(x: 1.0, y: 0.5, z: -2.0))
    XCTAssertEqual(sample.frameCount, 9)
  }

  func test偶数個のframeは中央2点の平均を取る() throws {
    let sample = try CalibrationSample.fromStationaryFrames([
      Vector3(x: 0, y: 0, z: 0),
      Vector3(x: 1, y: 2, z: 3),
      Vector3(x: 3, y: 4, z: 5),
      Vector3(x: 4, y: 6, z: 8),
    ])

    assertVector(sample.position, Vector3(x: 2, y: 3, z: 4))
    XCTAssertEqual(sample.frameCount, 4)
  }

  func test空のframe列と非有限frameを拒否する() throws {
    XCTAssertThrowsError(try CalibrationSample.fromStationaryFrames([])) { error in
      XCTAssertEqual(error as? CalibrationEstimationError, .emptySampleSet)
    }
    XCTAssertThrowsError(
      try CalibrationSample.fromStationaryFrames([
        Vector3(x: 0, y: 0, z: 0),
        Vector3(x: 0, y: .infinity, z: 0),
      ])
    ) { error in
      XCTAssertEqual(error as? CalibrationEstimationError, .nonFiniteSample)
    }
  }

  func test推定結果をprofileへ格納できる() throws {
    let spaceID = try calibrationTestUUID(0x90)
    let estimate = try OriginAndForwardEstimator.estimate(
      origin: try sample(0, 0, 0),
      forward: try sample(2, 0, 0),
      checkPoints: [
        try CalibrationCheckPoint(
          trackerPosition: Vector3(x: 2, y: 0, z: 0),
          expectedStagePosition: Vector3(x: 0, y: 0, z: -2)
        )
      ]
    )

    let calibration = try estimate.makeSpaceCalibration(
      trackingSpaceID: spaceID,
      spaceEpoch: 6,
      operatorNote: "原点と前方の2点",
      updatedAt: calibrationTestDate
    )
    let profile = try makeProfile().upserting(calibration, at: calibrationTestDate)

    let stored = try XCTUnwrap(profile.calibration(forTrackingSpaceID: spaceID))
    XCTAssertEqual(stored.method, .originAndForward)
    XCTAssertEqual(stored.spaceEpoch, 6)
    XCTAssertEqual(stored.sampleCount, 2)
    XCTAssertEqual(stored.operatorNote, "原点と前方の2点")
    XCTAssertEqual(try XCTUnwrap(stored.rmsErrorM), 0, accuracy: 1.0e-5)

    // 較正済みspaceとしてStage変換が効く。
    let resolver = CalibrationResolver(profile: profile)
    let outcome = resolver.resolve(
      makePoseBatch(
        trackingSpaceID: spaceID,
        spaceEpoch: 6,
        trackers: [makeTrackerPose(position: Vector3(x: 2, y: 0, z: 0))]
      )
    )
    assertVector(
      try XCTUnwrap(outcome.batch?.trackers.first).position,
      Vector3(x: 0, y: 0, z: -2)
    )
  }
}
