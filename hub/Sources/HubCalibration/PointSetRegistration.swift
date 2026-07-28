import Foundation
import HubProtocol

/// Tracker SpaceとStage Spaceの対応点。
public struct PointCorrespondence: Equatable, Sendable {
  public let trackerPosition: Vector3
  public let stagePosition: Vector3

  public init(trackerPosition: Vector3, stagePosition: Vector3) throws {
    guard trackerPosition.isFinite, stagePosition.isFinite else {
      throw CalibrationEstimationError.nonFiniteSample
    }
    self.trackerPosition = trackerPosition
    self.stagePosition = stagePosition
  }
}

/// 3点以上の対応点からrigid transformを推定する。
///
/// Hornのquaternion法を使い、対応点から作った4x4対称行列の最大固有ベクトルを
/// rotationとして取り出す。quaternionを直接得るため、SVDベースの解法で必要な
/// 反射補正が不要で、鏡像解（det = -1）を構造的に作れない。
///
/// 外れ値は自動で除外しない。[Calibration](../../../docs/calibration.md)のとおり、
/// 採否はresidualを見たoperatorが決める。黙って点を捨てると、較正が良く見えたまま
/// 実空間とずれる。
public enum PointSetRegistration {
  /// 対応点の広がりとして要求する最小の標準偏差。
  public static let minimumSpreadM: Double = 0.05

  /// 同一直線とみなす、第2主成分と第1主成分の分散比の下限。
  public static let minimumPlanarityRatio: Double = 1.0e-4

  public static func estimate(
    correspondences: [PointCorrespondence]
  ) throws -> CalibrationEstimate {
    guard correspondences.count >= 3 else {
      throw CalibrationEstimationError.insufficientCorrespondences(
        count: correspondences.count
      )
    }

    let trackerPoints = correspondences.map(\.trackerPosition.doubleComponents)
    let stagePoints = correspondences.map(\.stagePosition.doubleComponents)
    let trackerCentroid = centroid(of: trackerPoints)
    let stageCentroid = centroid(of: stagePoints)

    try validateSpread(of: trackerPoints, around: trackerCentroid)

    let rotation = try estimateRotation(
      trackerPoints: trackerPoints,
      stagePoints: stagePoints,
      trackerCentroid: trackerCentroid,
      stageCentroid: stageCentroid
    )

    let rotatedCentroid = rotation.rotate(trackerCentroid)
    let transform = try RigidTransform(
      translation: Vector3(
        x: Float(stageCentroid.x - rotatedCentroid.x),
        y: Float(stageCentroid.y - rotatedCentroid.y),
        z: Float(stageCentroid.z - rotatedCentroid.z)
      ),
      rotation: rotation.quaternion
    )

    let checkPoints = try correspondences.map {
      try CalibrationCheckPoint(
        trackerPosition: $0.trackerPosition,
        expectedStagePosition: $0.stagePosition
      )
    }
    let residuals = OriginAndForwardEstimator.residuals(
      of: transform,
      checkPoints: checkPoints
    )

    return CalibrationEstimate(
      transform: transform,
      method: .pointSetRegistration,
      sampleCount: UInt32(correspondences.count),
      rmsErrorM: residuals?.rms,
      maxResidualM: residuals?.max
    )
  }

  private static func estimateRotation(
    trackerPoints: [(x: Double, y: Double, z: Double)],
    stagePoints: [(x: Double, y: Double, z: Double)],
    trackerCentroid: (x: Double, y: Double, z: Double),
    stageCentroid: (x: Double, y: Double, z: Double)
  ) throws -> Rotation {
    // 重心を引いた対応点の相関行列。
    var sxx = 0.0, sxy = 0.0, sxz = 0.0
    var syx = 0.0, syy = 0.0, syz = 0.0
    var szx = 0.0, szy = 0.0, szz = 0.0

    for (tracker, stage) in zip(trackerPoints, stagePoints) {
      let tx = tracker.x - trackerCentroid.x
      let ty = tracker.y - trackerCentroid.y
      let tz = tracker.z - trackerCentroid.z
      let sx = stage.x - stageCentroid.x
      let sy = stage.y - stageCentroid.y
      let sz = stage.z - stageCentroid.z

      sxx += tx * sx
      sxy += tx * sy
      sxz += tx * sz
      syx += ty * sx
      syy += ty * sy
      syz += ty * sz
      szx += tz * sx
      szy += tz * sy
      szz += tz * sz
    }

    // Horn 1987の4x4対称行列。最大固有ベクトルが(w, x, y, z)。
    let n: [Double] = [
      sxx + syy + szz, syz - szy, szx - sxz, sxy - syx,
      syz - szy, sxx - syy - szz, sxy + syx, szx + sxz,
      szx - sxz, sxy + syx, -sxx + syy - szz, syz + szy,
      sxy - syx, szx + sxz, syz + szy, -sxx - syy + szz,
    ]

    let decomposition = SymmetricEigenSolver.decompose(n, size: 4)
    guard let principal = decomposition.vectors.first else {
      throw CalibrationEstimationError.degenerateCorrespondences
    }

    let rotation = Rotation(
      x: principal[1],
      y: principal[2],
      z: principal[3],
      w: principal[0]
    )
    guard rotation.magnitude > 0, rotation.magnitude.isFinite else {
      throw CalibrationEstimationError.degenerateCorrespondences
    }
    return rotation.normalized()
  }

  /// 対応点が回転を一意に決められる広がりを持つか検査する。
  private static func validateSpread(
    of points: [(x: Double, y: Double, z: Double)],
    around centroid: (x: Double, y: Double, z: Double)
  ) throws {
    var covariance = [Double](repeating: 0, count: 9)
    for point in points {
      let d = [point.x - centroid.x, point.y - centroid.y, point.z - centroid.z]
      for row in 0..<3 {
        for column in 0..<3 {
          covariance[row * 3 + column] += d[row] * d[column]
        }
      }
    }
    let count = Double(points.count)
    for index in covariance.indices {
      covariance[index] /= count
    }

    let eigen = SymmetricEigenSolver.decompose(covariance, size: 3)
    let primary = max(eigen.values[0], 0)
    let secondary = max(eigen.values[1], 0)

    let spread = primary.squareRoot()
    guard spread >= minimumSpreadM else {
      throw CalibrationEstimationError.correspondencesTooClose(spreadM: spread)
    }

    let ratio = secondary / primary
    guard ratio >= minimumPlanarityRatio else {
      throw CalibrationEstimationError.collinearCorrespondences(
        planarityRatio: ratio
      )
    }
  }

  private static func centroid(
    of points: [(x: Double, y: Double, z: Double)]
  ) -> (x: Double, y: Double, z: Double) {
    let count = Double(points.count)
    var sum = (x: 0.0, y: 0.0, z: 0.0)
    for point in points {
      sum.x += point.x
      sum.y += point.y
      sum.z += point.z
    }
    return (x: sum.x / count, y: sum.y / count, z: sum.z / count)
  }
}
