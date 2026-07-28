import Foundation
import HubProtocol

public enum CalibrationEstimationError: Error, Equatable, Sendable {
  case emptySampleSet
  case nonFiniteSample
  case nonFiniteFloorHeightOffset
  case degenerateForwardDirection(horizontalLengthM: Double)
}

/// 静止させたTrackerの複数frameからまとめた1つの観測点。
public struct CalibrationSample: Equatable, Sendable {
  public let position: Vector3
  public let frameCount: UInt32

  public init(position: Vector3, frameCount: UInt32 = 1) throws {
    guard position.isFinite else {
      throw CalibrationEstimationError.nonFiniteSample
    }
    self.position = position
    self.frameCount = frameCount
  }

  /// 成分ごとの中央値でサンプルをまとめる。
  ///
  /// 静止中でも遮蔽復帰やjitterで1 frameだけ大きく外れることがある。平均だと
  /// その1点に原点が引きずられるため、中央値を使う。
  public static func fromStationaryFrames(_ positions: [Vector3]) throws -> CalibrationSample {
    guard !positions.isEmpty else {
      throw CalibrationEstimationError.emptySampleSet
    }
    guard positions.allSatisfy(\.isFinite) else {
      throw CalibrationEstimationError.nonFiniteSample
    }

    return try CalibrationSample(
      position: Vector3(
        x: median(positions.map { Double($0.x) }),
        y: median(positions.map { Double($0.y) }),
        z: median(positions.map { Double($0.z) })
      ),
      frameCount: UInt32(positions.count)
    )
  }

  private static func median(_ values: [Double]) -> Float {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return Float((sorted[middle - 1] + sorted[middle]) / 2)
    }
    return Float(sorted[middle])
  }
}

/// 較正後のStage座標が既知の検証点。
public struct CalibrationCheckPoint: Equatable, Sendable {
  public let trackerPosition: Vector3
  public let expectedStagePosition: Vector3

  public init(trackerPosition: Vector3, expectedStagePosition: Vector3) throws {
    guard trackerPosition.isFinite, expectedStagePosition.isFinite else {
      throw CalibrationEstimationError.nonFiniteSample
    }
    self.trackerPosition = trackerPosition
    self.expectedStagePosition = expectedStagePosition
  }
}

/// 推定した変換と、その品質を示すmetadata。
public struct CalibrationEstimate: Equatable, Sendable {
  public let transform: RigidTransform
  public let method: CalibrationMethod
  public let sampleCount: UInt32
  public let rmsErrorM: Double?
  public let maxResidualM: Double?

  /// 推定結果をそのままprofileへ格納できる形にする。
  public func makeSpaceCalibration(
    trackingSpaceID: UUIDBytes,
    spaceEpoch: UInt32,
    operatorNote: String? = nil,
    updatedAt: Date
  ) throws -> SpaceCalibration {
    try SpaceCalibration(
      trackingSpaceID: trackingSpaceID,
      spaceEpoch: spaceEpoch,
      transform: transform,
      method: method,
      sampleCount: sampleCount,
      rmsErrorM: rmsErrorM,
      maxResidualM: maxResidualM,
      operatorNote: operatorNote,
      updatedAt: updatedAt
    )
  }
}

/// [Calibration](../../../docs/calibration.md)のMVP手順「origin and forward」。
///
/// 基準Trackerを原点へ置いた観測点と、基準方向へ移動した観測点から、translationと
/// yawだけを決める。up軸は`+Y`に固定し、pitchとrollを持ち込まない。実測の床面や
/// 壁面に対して意図しない傾きを与えないためで、傾きが必要な場合はpoint-set
/// registrationを使う。
public enum OriginAndForwardEstimator {
  /// 前方方向とみなす水平距離の下限。
  ///
  /// これより短いと、わずかなjitterでyawが大きく振れる。
  public static let minimumForwardHorizontalLengthM: Double = 0.1

  public static func estimate(
    origin: CalibrationSample,
    forward: CalibrationSample,
    floorHeightOffsetM: Double = 0,
    checkPoints: [CalibrationCheckPoint] = []
  ) throws -> CalibrationEstimate {
    guard floorHeightOffsetM.isFinite else {
      throw CalibrationEstimationError.nonFiniteFloorHeightOffset
    }

    let originPosition = origin.position.doubleComponents
    let forwardPosition = forward.position.doubleComponents
    let deltaX = forwardPosition.x - originPosition.x
    let deltaZ = forwardPosition.z - originPosition.z
    let horizontalLength = (deltaX * deltaX + deltaZ * deltaZ).squareRoot()

    guard horizontalLength >= minimumForwardHorizontalLengthM else {
      throw CalibrationEstimationError.degenerateForwardDirection(
        horizontalLengthM: horizontalLength
      )
    }

    // 水平面へ投影した前方方向をStageの-Zへ向けるyaw。
    let yaw = atan2(deltaZ, deltaX) + Double.pi / 2
    let rotation = Rotation(
      x: 0,
      y: sin(yaw / 2),
      z: 0,
      w: cos(yaw / 2)
    ).normalized()

    // 原点サンプルがStageの(0, floorHeightOffsetM, 0)へ来るtranslation。
    let rotatedOrigin = rotation.rotate(originPosition)
    let transform = try RigidTransform(
      translation: Vector3(
        x: Float(-rotatedOrigin.x),
        y: Float(floorHeightOffsetM - rotatedOrigin.y),
        z: Float(-rotatedOrigin.z)
      ),
      rotation: rotation.quaternion
    )

    let residuals = residuals(of: transform, checkPoints: checkPoints)
    return CalibrationEstimate(
      transform: transform,
      method: .originAndForward,
      sampleCount: origin.frameCount + forward.frameCount,
      rmsErrorM: residuals?.rms,
      maxResidualM: residuals?.max
    )
  }

  /// 検証点のStage座標との残差を返す。検証点が無い場合はnil。
  public static func residuals(
    of transform: RigidTransform,
    checkPoints: [CalibrationCheckPoint]
  ) -> (rms: Double, max: Double)? {
    guard !checkPoints.isEmpty else {
      return nil
    }

    var squaredSum = 0.0
    var maximum = 0.0
    for checkPoint in checkPoints {
      let actual = transform.apply(toPosition: checkPoint.trackerPosition).doubleComponents
      let expected = checkPoint.expectedStagePosition.doubleComponents
      let dx = actual.x - expected.x
      let dy = actual.y - expected.y
      let dz = actual.z - expected.z
      let distance = (dx * dx + dy * dy + dz * dz).squareRoot()
      squaredSum += distance * distance
      maximum = Swift.max(maximum, distance)
    }

    return (
      rms: (squaredSum / Double(checkPoints.count)).squareRoot(),
      max: maximum
    )
  }
}
