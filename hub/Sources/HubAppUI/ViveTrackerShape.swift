import Foundation
import simd

/// 表面上の取り付け点と、その点の外向き法線。
///
/// 状態LEDやsensor窪みのように、本体表面へ沿わせて置く部品の姿勢を決める。
public struct ViveTrackerSurfaceAnchor: Equatable, Sendable {
  public let position: SIMD3<Float>
  public let normal: SIMD3<Float>

  public init(position: SIMD3<Float>, normal: SIMD3<Float>) {
    self.position = position
    self.normal = normal
  }
}

/// 三角形listで表した表示用mesh。
///
/// RealityKitに依存しないため、寸法比と面の向きをunit testで検証できる。
public struct ViveTrackerMesh: Equatable, Sendable {
  public let positions: [SIMD3<Float>]
  public let normals: [SIMD3<Float>]
  public let indices: [UInt32]

  public init(
    positions: [SIMD3<Float>],
    normals: [SIMD3<Float>],
    indices: [UInt32]
  ) {
    self.positions = positions
    self.normals = normals
    self.indices = indices
  }

  public var triangleCount: Int {
    indices.count / 3
  }

  /// 頂点bounding boxの最小と最大。
  public var bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
    guard let first = positions.first else {
      return (.zero, .zero)
    }
    var minimum = first
    var maximum = first
    for position in positions.dropFirst() {
      minimum = simd_min(minimum, position)
      maximum = simd_max(maximum, position)
    }
    return (minimum, maximum)
  }
}

/// 実機VIVE Tracker (3.0)の外形をGUI表示用へ単純化した本体geometry。
///
/// 上面視は後方が太く前方(local −Z)へ細まるteardrop、側面視は下端が最も太い
/// 円錐台とし、実機の外寸比70.9 : 79.0 : 44.1mmを保つ。姿勢を読み違えないよう
/// 前後と上下の非対称を残しつつ、Tracker 16台でも軽い頂点数に収める。
///
/// local軸は共通pose規約に合わせ、+Yを上面、−Zを前方、+Xを右とする。
public struct ViveTrackerShape: Equatable, Sendable {
  public static let referenceWidthMeters: Float = 0.070_9
  public static let referenceDepthMeters: Float = 0.079_0
  public static let referenceHeightMeters: Float = 0.044_1

  /// 上面視outlineの前後非対称度。0で楕円、大きいほど前方が細くなる。
  public static let noseTaper: Float = 0.34
  /// 円周方向の分割数。実表示サイズで輪郭が滑らかに見える最小限とする。
  public static let radialSegments = 48
  /// 前方(local −Z)のoutline媒介変数。
  public static let frontAngle: Float = 0
  /// 後方(local +Z)のoutline媒介変数。
  public static let rearAngle: Float = .pi

  /// 分割数と独立に外寸比を確定させるための、正規化専用のsample数。
  private static let normalizationSamples = 720

  /// 側面視の断面。`heightRatio`は下端0・上端1、`radiusRatio`は最大径を1とする。
  public struct ProfilePoint: Equatable, Sendable {
    public let heightRatio: Float
    public let radiusRatio: Float

    public init(heightRatio: Float, radiusRatio: Float) {
      self.heightRatio = heightRatio
      self.radiusRatio = radiusRatio
    }
  }

  /// 下端の面取りから上面plateまでの断面。下端側が最も太い。
  public static let profile: [ProfilePoint] = [
    ProfilePoint(heightRatio: 0, radiusRatio: 0.82),
    ProfilePoint(heightRatio: 0.05, radiusRatio: 1),
    ProfilePoint(heightRatio: 0.28, radiusRatio: 0.98),
    ProfilePoint(heightRatio: 0.52, radiusRatio: 0.93),
    ProfilePoint(heightRatio: 0.72, radiusRatio: 0.86),
    ProfilePoint(heightRatio: 0.87, radiusRatio: 0.75),
    ProfilePoint(heightRatio: 0.96, radiusRatio: 0.65),
    ProfilePoint(heightRatio: 1, radiusRatio: 0.56),
  ]

  public let widthMeters: Float
  public let depthMeters: Float
  public let heightMeters: Float

  private let outlineWidthScale: Float

  public init(widthMeters: Float) {
    let width = max(0.001, widthMeters.isFinite ? widthMeters : 0.001)
    self.widthMeters = width
    depthMeters =
      width * Self.referenceDepthMeters / Self.referenceWidthMeters
    heightMeters =
      width * Self.referenceHeightMeters / Self.referenceWidthMeters

    // 最大幅がwidthMetersちょうどになるよう、outlineの正規化係数を求める。
    var maximumHalfWidth: Float = 0
    for index in 0..<Self.normalizationSamples {
      let angle =
        2 * .pi * Float(index) / Float(Self.normalizationSamples)
      maximumHalfWidth = max(
        maximumHalfWidth,
        abs(Self.unitOutlineHalfWidth(angle: angle))
      )
    }
    outlineWidthScale = width / 2 / max(maximumHalfWidth, 1e-6)
  }

  /// 上面plateの半径比。
  public var topRadiusRatio: Float {
    Self.profile.last?.radiusRatio ?? 1
  }

  /// 底面へ張り出すマウント台座(1/4インチねじ穴)の半径。
  public var mountRadius: Float {
    widthMeters * 0.17
  }

  /// マウント台座の高さ。
  public var mountHeight: Float {
    heightMeters * 0.18
  }

  /// マウント台座の中心Y。底面より下へ出る。
  public var mountCenterY: Float {
    -heightMeters / 2 - mountHeight / 2
  }

  /// 本体と台座を含めた最下端のY。
  public var bottomY: Float {
    mountCenterY - mountHeight / 2
  }

  /// 前面の状態LEDの半径。
  public var statusLightRadius: Float {
    widthMeters * 0.06
  }

  /// 前面の状態LEDの取り付け点。
  public var statusLightAnchor: ViveTrackerSurfaceAnchor {
    surfaceAnchor(heightRatio: 0.55, angle: Self.frontAngle)
  }

  /// 背面のUSB端子の取り付け点。前後を見分ける手掛かりにする。
  public var connectorAnchor: ViveTrackerSurfaceAnchor {
    surfaceAnchor(heightRatio: 0.5, angle: Self.rearAngle)
  }

  /// 背面のUSB端子の寸法。幅、高さ、厚みの順。
  public var connectorSize: SIMD3<Float> {
    SIMD3(widthMeters * 0.22, heightMeters * 0.16, depthMeters * 0.035)
  }

  /// sensor窪みの半径。
  public var sensorWellRadius: Float {
    widthMeters * 0.055
  }

  /// 上面視の向きを読み取る手掛かりになる赤外sensor窪みの配置。
  ///
  /// 状態LEDと重ならないよう、前方を基準に半区画ずらして一周させる。
  public func sensorWellAnchors(count: Int = 8) -> [ViveTrackerSurfaceAnchor] {
    guard count > 0 else { return [] }
    return (0..<count).map { index in
      let angle =
        Self.frontAngle
        + 2 * .pi * (Float(index) + 0.5) / Float(count)
      return surfaceAnchor(heightRatio: 0.79, angle: angle)
    }
  }

  /// 指定した高さ比と角度の外形表面上の座標。
  public func surfacePoint(
    heightRatio: Float,
    angle: Float
  ) -> SIMD3<Float> {
    let offset =
      outlineOffset(angle: angle) * radiusRatio(atHeightRatio: heightRatio)
    return SIMD3(
      offset.x,
      (clampedHeightRatio(heightRatio) - 0.5) * heightMeters,
      offset.y
    )
  }

  /// 指定した高さ比と角度の外向き法線。
  public func surfaceNormal(
    heightRatio: Float,
    angle: Float
  ) -> SIMD3<Float> {
    let height = clampedHeightRatio(heightRatio)
    let angleDelta: Float = 0.002
    let heightDelta: Float = 0.002
    let alongAngle =
      surfacePoint(heightRatio: height, angle: angle + angleDelta)
      - surfacePoint(heightRatio: height, angle: angle - angleDelta)
    let alongHeight =
      surfacePoint(
        heightRatio: min(1, height + heightDelta),
        angle: angle
      )
      - surfacePoint(
        heightRatio: max(0, height - heightDelta),
        angle: angle
      )

    var normal = simd_cross(alongAngle, alongHeight)
    let radial = outlineOffset(angle: angle)
    if simd_length_squared(normal) < 1e-18 {
      return SIMD3(0, 1, 0)
    }
    normal = simd_normalize(normal)
    if simd_dot(normal, SIMD3(radial.x, 0, radial.y)) < 0 {
      normal = -normal
    }
    return normal
  }

  /// 表面上の取り付け点と法線をまとめて求める。
  public func surfaceAnchor(
    heightRatio: Float,
    angle: Float
  ) -> ViveTrackerSurfaceAnchor {
    ViveTrackerSurfaceAnchor(
      position: surfacePoint(heightRatio: heightRatio, angle: angle),
      normal: surfaceNormal(heightRatio: heightRatio, angle: angle)
    )
  }

  /// 側面と底面を閉じた本体shell。
  ///
  /// 三角形は外から見て反時計回りに並べ、RealityKitの表面判定へ合わせる。
  public func shellMesh() -> ViveTrackerMesh {
    let segments = Self.radialSegments
    let rows = Self.profile
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    positions.reserveCapacity(rows.count * segments + segments + 1)
    normals.reserveCapacity(positions.capacity)

    for row in rows {
      for segment in 0..<segments {
        let angle = Self.angle(atSegment: segment, segments: segments)
        positions.append(
          surfacePoint(heightRatio: row.heightRatio, angle: angle)
        )
        normals.append(
          surfaceNormal(heightRatio: row.heightRatio, angle: angle)
        )
      }
    }

    for row in 0..<(rows.count - 1) {
      for segment in 0..<segments {
        let nextSegment = (segment + 1) % segments
        let lower = UInt32(row * segments + segment)
        let lowerNext = UInt32(row * segments + nextSegment)
        let upper = UInt32((row + 1) * segments + segment)
        let upperNext = UInt32((row + 1) * segments + nextSegment)
        indices.append(contentsOf: [lower, upperNext, lowerNext])
        indices.append(contentsOf: [lower, upper, upperNext])
      }
    }

    let bottomCenter = UInt32(positions.count)
    positions.append(SIMD3(0, -heightMeters / 2, 0))
    normals.append(SIMD3(0, -1, 0))
    for segment in 0..<segments {
      let angle = Self.angle(atSegment: segment, segments: segments)
      positions.append(
        surfacePoint(heightRatio: 0, angle: angle)
      )
      normals.append(SIMD3(0, -1, 0))
    }
    for segment in 0..<segments {
      let current = bottomCenter + 1 + UInt32(segment)
      let next = bottomCenter + 1 + UInt32((segment + 1) % segments)
      indices.append(contentsOf: [bottomCenter, current, next])
    }

    return ViveTrackerMesh(
      positions: positions,
      normals: normals,
      indices: indices
    )
  }

  /// 上面plate。本体shellと別materialで暗く塗るため独立させる。
  public func topPlateMesh() -> ViveTrackerMesh {
    let segments = Self.radialSegments
    var positions: [SIMD3<Float>] = [SIMD3(0, heightMeters / 2, 0)]
    var normals: [SIMD3<Float>] = [SIMD3(0, 1, 0)]
    var indices: [UInt32] = []
    positions.reserveCapacity(segments + 1)
    normals.reserveCapacity(segments + 1)

    for segment in 0..<segments {
      let angle = Self.angle(atSegment: segment, segments: segments)
      positions.append(surfacePoint(heightRatio: 1, angle: angle))
      normals.append(SIMD3(0, 1, 0))
    }
    for segment in 0..<segments {
      let current = UInt32(1 + segment)
      let next = UInt32(1 + (segment + 1) % segments)
      indices.append(contentsOf: [0, next, current])
    }

    return ViveTrackerMesh(
      positions: positions,
      normals: normals,
      indices: indices
    )
  }

  /// 最大径におけるoutline上の点。X, Zをmetreで返す。
  ///
  /// `angle`は前方を0、右を`π/2`、後方を`π`とする媒介変数で、前方ほど幅が
  /// 狭くなる卵形を描く。
  public func outlineOffset(angle: Float) -> SIMD2<Float> {
    SIMD2(
      Self.unitOutlineHalfWidth(angle: angle) * outlineWidthScale,
      -cos(angle) * depthMeters / 2
    )
  }

  /// 断面を線形補間した半径比。
  public func radiusRatio(atHeightRatio heightRatio: Float) -> Float {
    let height = clampedHeightRatio(heightRatio)
    let profile = Self.profile
    guard let first = profile.first else { return 1 }
    if height <= first.heightRatio { return first.radiusRatio }
    for index in 1..<profile.count {
      let lower = profile[index - 1]
      let upper = profile[index]
      guard height <= upper.heightRatio else { continue }
      let span = upper.heightRatio - lower.heightRatio
      guard span > 0 else { return upper.radiusRatio }
      let ratio = (height - lower.heightRatio) / span
      return lower.radiusRatio
        + (upper.radiusRatio - lower.radiusRatio) * ratio
    }
    return profile[profile.count - 1].radiusRatio
  }

  private func clampedHeightRatio(_ heightRatio: Float) -> Float {
    guard heightRatio.isFinite else { return 0 }
    return min(1, max(0, heightRatio))
  }

  private static func angle(atSegment segment: Int, segments: Int) -> Float {
    2 * .pi * Float(segment) / Float(segments)
  }

  /// 正規化前のoutline半幅。後方(`cos`が−1側)ほど太くなる卵形を作る。
  private static func unitOutlineHalfWidth(angle: Float) -> Float {
    sin(angle) * (1 - noseTaper * cos(angle))
  }
}
