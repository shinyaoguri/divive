import Foundation
import HubProtocol

public enum RigidTransformError: Error, Equatable, Sendable {
  case nonFiniteComponent
  case quaternionNotNormalized(magnitude: Double)
}

/// Tracker SpaceからStage SpaceへのSE(3)剛体変換。
///
/// 物理空間の計測精度を保つため、この型はscaleを持たない。演出用の拡大縮小は
/// Content Profile Spaceの責務であり、ここへ混ぜてはいけない。
///
/// 変換規約はcolumn vectorで、[Calibration](../../../docs/calibration.md)の定義に従う。
///
/// ```text
/// p_stage = R * p_tracker + t
/// q_stage = q ⊗ q_tracker
/// ```
///
/// linear / angular velocityはrotationだけを適用し、translationを加算しない。
public struct RigidTransform: Equatable, Sendable {
  /// quaternion正規化の許容幅。
  ///
  /// wire上の姿勢はFloatで運ばれるため、Double基準の厳密な単位長は要求しない。
  public static let normalizationTolerance: Double = 1.0e-4

  public static let identity = RigidTransform(
    unvalidatedTranslation: Vector3(x: 0, y: 0, z: 0),
    rotation: Quaternion(x: 0, y: 0, z: 0, w: 1)
  )

  public let translation: Vector3

  /// 正規化済みのrotation。初期化時に単位quaternionへ揃える。
  public let rotation: Quaternion

  /// 非有限成分と非正規化quaternionを拒否する。
  ///
  /// 較正結果を無検査で受け入れると、原点が壊れたprofileが保存され、
  /// 後段のcontentが理由の分からない座標飛びを見ることになる。
  public init(translation: Vector3, rotation: Quaternion) throws {
    guard translation.isFinite, rotation.isFinite else {
      throw RigidTransformError.nonFiniteComponent
    }

    let magnitude = Rotation(rotation).magnitude
    guard abs(magnitude - 1.0) <= Self.normalizationTolerance else {
      throw RigidTransformError.quaternionNotNormalized(magnitude: magnitude)
    }

    self.translation = translation
    self.rotation = Rotation(rotation).normalized().quaternion
  }

  private init(unvalidatedTranslation: Vector3, rotation: Quaternion) {
    translation = unvalidatedTranslation
    self.rotation = rotation
  }

  /// 位置へrotationとtranslationを適用する。
  public func apply(toPosition position: Vector3) -> Vector3 {
    let rotated = Rotation(rotation).rotate(position.doubleComponents)
    return Vector3(
      x: Float(rotated.x + Double(translation.x)),
      y: Float(rotated.y + Double(translation.y)),
      z: Float(rotated.z + Double(translation.z))
    )
  }

  /// 方向ベクトルへrotationだけを適用する。
  ///
  /// linear velocity、angular velocity、前方軸などはtranslationの影響を受けない。
  public func apply(toDirection direction: Vector3) -> Vector3 {
    let rotated = Rotation(rotation).rotate(direction.doubleComponents)
    return Vector3(x: Float(rotated.x), y: Float(rotated.y), z: Float(rotated.z))
  }

  /// 姿勢へrotationを適用する。
  public func apply(toOrientation orientation: Quaternion) -> Quaternion {
    Rotation(rotation)
      .multiplied(by: Rotation(orientation))
      .normalized()
      .quaternion
  }

  /// `inner`を先に適用してからselfを適用する合成を返す。
  ///
  /// ```text
  /// T_c_from_a = T_c_from_b.composed(with: T_b_from_a)
  /// ```
  public func composed(with inner: RigidTransform) -> RigidTransform {
    let outerRotation = Rotation(rotation)
    let rotatedInnerTranslation = outerRotation.rotate(inner.translation.doubleComponents)
    let composedRotation = outerRotation.multiplied(by: Rotation(inner.rotation)).normalized()
    return RigidTransform(
      unvalidatedTranslation: Vector3(
        x: Float(rotatedInnerTranslation.x + Double(translation.x)),
        y: Float(rotatedInnerTranslation.y + Double(translation.y)),
        z: Float(rotatedInnerTranslation.z + Double(translation.z))
      ),
      rotation: composedRotation.quaternion
    )
  }

  /// Stage SpaceからTracker Spaceへ戻す逆変換。
  public var inverse: RigidTransform {
    let inverseRotation = Rotation(rotation).conjugate.normalized()
    let rotated = inverseRotation.rotate(translation.doubleComponents)
    return RigidTransform(
      unvalidatedTranslation: Vector3(
        x: Float(-rotated.x),
        y: Float(-rotated.y),
        z: Float(-rotated.z)
      ),
      rotation: inverseRotation.quaternion
    )
  }

  /// 回転として同じか比較する。
  ///
  /// quaternion `q`と`-q`は同じrotationのため、成分の一致では判定しない。
  public func representsSameTransform(
    as other: RigidTransform,
    positionToleranceM: Double = 1.0e-5,
    rotationTolerance: Double = 1.0e-5
  ) -> Bool {
    let translationMatches =
      abs(Double(translation.x - other.translation.x)) <= positionToleranceM
      && abs(Double(translation.y - other.translation.y)) <= positionToleranceM
      && abs(Double(translation.z - other.translation.z)) <= positionToleranceM
    guard translationMatches else {
      return false
    }
    return Rotation(rotation).representsSameRotation(
      as: Rotation(other.rotation),
      tolerance: rotationTolerance
    )
  }
}

extension Vector3 {
  var isFinite: Bool {
    x.isFinite && y.isFinite && z.isFinite
  }

  var doubleComponents: (x: Double, y: Double, z: Double) {
    (Double(x), Double(y), Double(z))
  }
}

extension Quaternion {
  var isFinite: Bool {
    x.isFinite && y.isFinite && z.isFinite && w.isFinite
  }
}

/// Float精度のquaternionをDoubleで扱う内部表現。
///
/// 合成と逆変換を繰り返してもStage原点が流れないよう、演算はDoubleで行う。
struct Rotation: Sendable {
  let x: Double
  let y: Double
  let z: Double
  let w: Double

  init(x: Double, y: Double, z: Double, w: Double) {
    self.x = x
    self.y = y
    self.z = z
    self.w = w
  }

  init(_ quaternion: Quaternion) {
    x = Double(quaternion.x)
    y = Double(quaternion.y)
    z = Double(quaternion.z)
    w = Double(quaternion.w)
  }

  var quaternion: Quaternion {
    Quaternion(x: Float(x), y: Float(y), z: Float(z), w: Float(w))
  }

  var magnitude: Double {
    (x * x + y * y + z * z + w * w).squareRoot()
  }

  var conjugate: Rotation {
    Rotation(x: -x, y: -y, z: -z, w: w)
  }

  func normalized() -> Rotation {
    let length = magnitude
    guard length > 0, length.isFinite else {
      return Rotation(x: 0, y: 0, z: 0, w: 1)
    }
    return Rotation(x: x / length, y: y / length, z: z / length, w: w / length)
  }

  /// Hamilton積 `self ⊗ other`。
  func multiplied(by other: Rotation) -> Rotation {
    Rotation(
      x: w * other.x + x * other.w + y * other.z - z * other.y,
      y: w * other.y - x * other.z + y * other.w + z * other.x,
      z: w * other.z + x * other.y - y * other.x + z * other.w,
      w: w * other.w - x * other.x - y * other.y - z * other.z
    )
  }

  func rotate(
    _ vector: (x: Double, y: Double, z: Double)
  ) -> (x: Double, y: Double, z: Double) {
    let ux = y * vector.z - z * vector.y
    let uy = z * vector.x - x * vector.z
    let uz = x * vector.y - y * vector.x
    let tx = 2.0 * ux
    let ty = 2.0 * uy
    let tz = 2.0 * uz
    let cx = y * tz - z * ty
    let cy = z * tx - x * tz
    let cz = x * ty - y * tx
    return (
      x: vector.x + w * tx + cx,
      y: vector.y + w * ty + cy,
      z: vector.z + w * tz + cz
    )
  }

  func representsSameRotation(as other: Rotation, tolerance: Double) -> Bool {
    let dot = x * other.x + y * other.y + z * other.z + w * other.w
    return abs(abs(dot) - 1.0) <= tolerance
  }
}
