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
/// 上面視は120度ごとに張り出す3つのlobeを持つ丸い三角形で、lobe間はくぼみます。
/// 前方(local −Z)はくぼみ側にあたり、実機と同じく状態LEDを置く面になります。
/// 残る2つのlobeは前方左右、1つは後方へ張り出します。上面はlobeが高く、くぼみが
/// 低い鞍状で、実機の外寸比70.9 : 79.0 : 44.1mmを保ちます。
///
/// local軸は共通pose規約に合わせ、+Yを上面、−Zを前方、+Xを右とします。
public struct ViveTrackerShape: Equatable, Sendable {
  public static let referenceWidthMeters: Float = 0.070_9
  public static let referenceDepthMeters: Float = 0.079_0
  public static let referenceHeightMeters: Float = 0.044_1

  /// lobeの張り出し量。0で円、大きいほどlobe間のくぼみが深くなる。
  public static let lobeDepth: Float = 0.28
  /// lobe間で上面が下がる量。実機の鞍状の凹みを表す。
  public static let saddleDepth: Float = 0.34
  /// 円周方向の分割数。実表示サイズで輪郭が滑らかに見える最小限とする。
  public static let radialSegments = 60
  /// 前方(local −Z)のoutline媒介変数。lobe間のくぼみにあたる。
  public static let frontAngle: Float = 0
  /// 後方(local +Z)のoutline媒介変数。後方lobeの中心にあたる。
  public static let rearAngle: Float = .pi
  /// 3つのlobe中心の媒介変数。前方左右と後方の順。
  public static let lobeAngles: [Float] = [
    .pi / 3, 5 * .pi / 3, .pi,
  ]

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

  /// 下端の面取りから上端の丸みまでの断面。下端寄りが最も太い。
  public static let profile: [ProfilePoint] = [
    ProfilePoint(heightRatio: 0, radiusRatio: 0.8),
    ProfilePoint(heightRatio: 0.1, radiusRatio: 1),
    ProfilePoint(heightRatio: 0.4, radiusRatio: 0.99),
    ProfilePoint(heightRatio: 0.62, radiusRatio: 0.94),
    ProfilePoint(heightRatio: 0.78, radiusRatio: 0.86),
    ProfilePoint(heightRatio: 0.88, radiusRatio: 0.74),
    ProfilePoint(heightRatio: 0.95, radiusRatio: 0.56),
    ProfilePoint(heightRatio: 0.99, radiusRatio: 0.33),
    ProfilePoint(heightRatio: 1, radiusRatio: 0.14),
  ]

  public let widthMeters: Float
  public let depthMeters: Float
  public let heightMeters: Float

  private let outlineScaleX: Float
  private let outlineScaleZ: Float
  private let outlineCenterZ: Float

  public init(widthMeters: Float) {
    let width = max(0.001, widthMeters.isFinite ? widthMeters : 0.001)
    self.widthMeters = width
    depthMeters =
      width * Self.referenceDepthMeters / Self.referenceWidthMeters
    heightMeters =
      width * Self.referenceHeightMeters / Self.referenceWidthMeters

    // 3つのlobeを含む外形が、実機の外寸比ちょうどに収まる係数を求める。
    var minimumX = Float.greatestFiniteMagnitude
    var maximumX = -Float.greatestFiniteMagnitude
    var minimumZ = Float.greatestFiniteMagnitude
    var maximumZ = -Float.greatestFiniteMagnitude
    for index in 0..<Self.normalizationSamples {
      let angle =
        2 * .pi * Float(index) / Float(Self.normalizationSamples)
      let radius = Self.unitOutlineRadius(angle: angle)
      let x = radius * sin(angle)
      let z = -radius * cos(angle)
      minimumX = min(minimumX, x)
      maximumX = max(maximumX, x)
      minimumZ = min(minimumZ, z)
      maximumZ = max(maximumZ, z)
    }
    outlineScaleX = width / max(maximumX - minimumX, 1e-6)
    outlineScaleZ = depthMeters / max(maximumZ - minimumZ, 1e-6)
    outlineCenterZ = (minimumZ + maximumZ) / 2
  }

  /// 底面へ張り出すマウント台座(1/4インチねじ穴)の半径。
  public var mountRadius: Float {
    widthMeters * 0.13
  }

  /// マウント台座の高さ。
  public var mountHeight: Float {
    heightMeters * 0.09
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
    widthMeters * 0.05
  }

  /// 前面くぼみに置く状態LEDの取り付け点。
  public var statusLightAnchor: ViveTrackerSurfaceAnchor {
    surfaceAnchor(heightRatio: 0.45, angle: Self.frontAngle)
  }

  /// 後方lobeのUSB端子の取り付け点。前後を見分ける手掛かりにする。
  public var connectorAnchor: ViveTrackerSurfaceAnchor {
    surfaceAnchor(heightRatio: 0.4, angle: Self.rearAngle)
  }

  /// 後方lobeのUSB端子の寸法。幅、高さ、厚みの順。
  public var connectorSize: SIMD3<Float> {
    SIMD3(widthMeters * 0.2, heightMeters * 0.14, depthMeters * 0.035)
  }

  /// sensor窪みの半径。
  public var sensorWellRadius: Float {
    widthMeters * 0.075
  }

  /// 実機の赤外sensor窪みを模した配置。各lobeへ3つずつ置く。
  public func sensorWellAnchors() -> [ViveTrackerSurfaceAnchor] {
    Self.lobeAngles.flatMap { center in
      [
        surfaceAnchor(heightRatio: 0.88, angle: center),
        surfaceAnchor(heightRatio: 0.55, angle: center - 0.44),
        surfaceAnchor(heightRatio: 0.55, angle: center + 0.44),
      ]
    }
  }

  /// 指定した角度で上面が届く高さ比。lobeで1、くぼみで小さくなる。
  public func topHeightScale(angle: Float) -> Float {
    1 - Self.saddleDepth * (1 - Self.lobeFactor(angle: angle))
  }

  /// 指定した高さ比と角度の外形表面上の座標。
  ///
  /// `heightRatio`はその角度の上面までの比率で、0が底面、1が上面になる。
  public func surfacePoint(
    heightRatio: Float,
    angle: Float
  ) -> SIMD3<Float> {
    let height = clampedHeightRatio(heightRatio)
    let offset = outlineOffset(angle: angle) * radiusRatio(atHeightRatio: height)
    return SIMD3(
      offset.x,
      -heightMeters / 2 + height * heightMeters * topHeightScale(angle: angle),
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
    guard simd_length_squared(normal) > 1e-18 else {
      return SIMD3(0, 1, 0)
    }
    normal = simd_normalize(normal)
    let radial = outlineOffset(angle: angle)
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

  /// 底面と上面を閉じた本体mesh。
  ///
  /// 三角形は外から見て反時計回りに並べる。
  public func bodyMesh() -> ViveTrackerMesh {
    let segments = Self.radialSegments
    let rows = Self.profile
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    positions.reserveCapacity(rows.count * segments + 2 * segments + 2)
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

    appendCap(
      heightRatio: 0,
      facingUp: false,
      into: &positions,
      normals: &normals,
      indices: &indices
    )
    appendCap(
      heightRatio: 1,
      facingUp: true,
      into: &positions,
      normals: &normals,
      indices: &indices
    )

    return ViveTrackerMesh(
      positions: positions,
      normals: normals,
      indices: indices
    )
  }

  /// 最大径におけるoutline上の点。X, Zをmetreで返す。
  ///
  /// `angle`は前方を0、右を`π/2`、後方を`π`とする媒介変数で、120度ごとに
  /// lobeが張り出す丸い三角形を描く。
  public func outlineOffset(angle: Float) -> SIMD2<Float> {
    let radius = Self.unitOutlineRadius(angle: angle)
    return SIMD2(
      radius * sin(angle) * outlineScaleX,
      (-radius * cos(angle) - outlineCenterZ) * outlineScaleZ
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

  /// 上下端を1点へ閉じる扇状の面を足す。
  ///
  /// 上面はlobeとくぼみで高さが異なるため、中心は外周の平均高さへ置く。
  /// 上面の外周は側面と法線を共有し、丸みが途切れて見えないようにする。
  private func appendCap(
    heightRatio: Float,
    facingUp: Bool,
    into positions: inout [SIMD3<Float>],
    normals: inout [SIMD3<Float>],
    indices: inout [UInt32]
  ) {
    let segments = Self.radialSegments
    let angles = (0..<segments).map {
      Self.angle(atSegment: $0, segments: segments)
    }
    let ring = angles.map {
      surfacePoint(heightRatio: heightRatio, angle: $0)
    }
    let centerY =
      ring.reduce(Float(0)) { $0 + $1.y } / Float(max(segments, 1))
    let center = UInt32(positions.count)
    let centerNormal = SIMD3<Float>(0, facingUp ? 1 : -1, 0)
    positions.append(SIMD3(0, centerY, 0))
    normals.append(centerNormal)
    for (index, point) in ring.enumerated() {
      positions.append(point)
      normals.append(
        facingUp
          ? surfaceNormal(heightRatio: heightRatio, angle: angles[index])
          : centerNormal
      )
    }
    for segment in 0..<segments {
      let current = center + 1 + UInt32(segment)
      let next = center + 1 + UInt32((segment + 1) % segments)
      indices.append(
        contentsOf: facingUp
          ? [center, next, current]
          : [center, current, next]
      )
    }
  }

  private func clampedHeightRatio(_ heightRatio: Float) -> Float {
    guard heightRatio.isFinite else { return 0 }
    return min(1, max(0, heightRatio))
  }

  private static func angle(atSegment segment: Int, segments: Int) -> Float {
    2 * .pi * Float(segment) / Float(segments)
  }

  /// lobe中心で1、lobe間のくぼみで0になる重み。
  private static func lobeFactor(angle: Float) -> Float {
    (1 - cos(3 * angle)) / 2
  }

  /// 正規化前のoutline半径。前方(`angle`が0)がくぼみ、120度ごとにlobeが立つ。
  private static func unitOutlineRadius(angle: Float) -> Float {
    1 - lobeDepth * cos(3 * angle)
  }
}
