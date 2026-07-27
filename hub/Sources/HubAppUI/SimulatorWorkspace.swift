import CoreGraphics
import Foundation
import HubProtocol

public enum SimulatorStageViewMode: String, CaseIterable, Identifiable,
  Sendable
{
  case spatial
  case top
  case front
  case side

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .spatial: "3D"
    case .top: "上面"
    case .front: "正面"
    case .side: "側面"
    }
  }

  public var projection: SimulatorStageProjection? {
    switch self {
    case .spatial: nil
    case .top: .top
    case .front: .front
    case .side: .side
    }
  }

  public var axisDescription: String {
    switch self {
    case .spatial: "−Z = 前方"
    case .top: "X →   −Z ↑"
    case .front: "X →   Y ↑"
    case .side: "−Z →   Y ↑"
    }
  }
}

/// 3D viewportの左dragがTracker操作か視点操作かを明示するmode。
public enum SimulatorViewportTool: String, CaseIterable, Identifiable,
  Sendable
{
  case moveTracker
  case navigate

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .moveTracker: "Tracker移動"
    case .navigate: "視点操作"
    }
  }

  public var symbolName: String {
    switch self {
    case .moveTracker: "move.3d"
    case .navigate: "rotate.3d"
    }
  }
}

/// RealityKitのcameraを直接公開せず、3D sceneをcamera前で操作するviewport状態。
///
/// turntable方式でworldの上方向を維持する。drag中は開始時点から計算するため、
/// GUI更新が挟まってもpointerとsceneがずれない。
public struct SimulatorViewportCamera: Equatable, Sendable {
  public static let minimumZoom: Float = 0.35
  public static let maximumZoom: Float = 4

  public private(set) var yawDegrees: Float
  public private(set) var pitchDegrees: Float
  public private(set) var zoom: Float
  public private(set) var panX: Float
  public private(set) var panY: Float
  public private(set) var pivot: Vector3

  public init(
    yawDegrees: Float = -22,
    pitchDegrees: Float = -14,
    zoom: Float = 1,
    panX: Float = 0,
    panY: Float = 0,
    pivot: Vector3 = Vector3(x: 0, y: 0, z: 0)
  ) {
    self.yawDegrees = yawDegrees
    self.pitchDegrees = pitchDegrees
    self.zoom = Self.clampZoom(zoom)
    self.panX = panX
    self.panY = panY
    self.pivot = pivot
  }

  public func applyingOrbit(translation: CGSize) -> Self {
    var next = self
    next.yawDegrees = yawDegrees + Float(translation.width) * 0.32
    next.pitchDegrees = min(
      85,
      max(-85, pitchDegrees + Float(translation.height) * 0.32)
    )
    return next
  }

  public func applyingPan(
    translation: CGSize,
    viewportSize: CGSize
  ) -> Self {
    var next = self
    let width = max(Float(viewportSize.width), 1)
    let height = max(Float(viewportSize.height), 1)
    next.panX =
      panX + Float(translation.width) / width
      * 0.9
    next.panY =
      panY - Float(translation.height) / height
      * 0.9
    return next
  }

  public func applyingScroll(
    deltaY: CGFloat,
    hasPreciseDeltas: Bool
  ) -> Self {
    var next = self
    let sensitivity: Float = hasPreciseDeltas ? 0.012 : 0.12
    next.zoom = Self.clampZoom(
      zoom * exp(Float(deltaY) * sensitivity)
    )
    return next
  }

  public func applyingMagnification(_ magnification: CGFloat) -> Self {
    var next = self
    next.zoom = Self.clampZoom(zoom * Float(magnification))
    return next
  }

  public func framingAll(
    workspace: SimulatorWorkspaceDimensions
  ) -> Self {
    let size = SimulatorSceneTransform(workspace: workspace).workspaceSize
    return SimulatorViewportCamera(
      pivot: Vector3(x: 0, y: -size.y * 0.15, z: 0)
    )
  }

  public func framingSelected(_ point: Vector3) -> Self {
    SimulatorViewportCamera(
      yawDegrees: yawDegrees,
      pitchDegrees: pitchDegrees,
      zoom: max(zoom, 1.8),
      pivot: point
    )
  }

  public func restoringPerspective() -> Self {
    SimulatorViewportCamera(
      pivot: pivot
    )
  }

  private static func clampZoom(_ value: Float) -> Float {
    min(maximumZoom, max(minimumZoom, value))
  }
}

/// RealityKitのpointer rayと固定された視点平面の交点を求める。
///
/// drag開始時のTracker中心を通り、開始rayへ正対する平面を固定することで、
/// pointerとTrackerの画面上の移動量をRealityKitの実投影に一致させる。
public struct SimulatorPointerPlane: Equatable, Sendable {
  public let point: Vector3
  public let normal: Vector3

  public init(
    point: Vector3,
    normal: Vector3
  ) {
    self.point = point
    self.normal = normal
  }

  public func intersection(
    rayOrigin: Vector3,
    rayDirection: Vector3
  ) -> Vector3? {
    let denominator = dot(rayDirection, normal)
    guard
      isFinite(point),
      isFinite(normal),
      isFinite(rayOrigin),
      isFinite(rayDirection),
      abs(denominator) > 0.000_001
    else {
      return nil
    }

    let offset = Vector3(
      x: point.x - rayOrigin.x,
      y: point.y - rayOrigin.y,
      z: point.z - rayOrigin.z
    )
    let distance = dot(offset, normal) / denominator
    guard distance.isFinite else { return nil }

    return Vector3(
      x: rayOrigin.x + rayDirection.x * distance,
      y: rayOrigin.y + rayDirection.y * distance,
      z: rayOrigin.z + rayDirection.z * distance
    )
  }

  private func dot(_ lhs: Vector3, _ rhs: Vector3) -> Float {
    lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
  }

  private func isFinite(_ value: Vector3) -> Bool {
    value.x.isFinite && value.y.isFinite && value.z.isFinite
  }
}

public enum SimulatorStageProjection: String, CaseIterable, Identifiable,
  Sendable
{
  case top
  case front
  case side

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .top: "上面"
    case .front: "正面"
    case .side: "側面"
    }
  }

  public var axisDescription: String {
    switch self {
    case .top: "X →   −Z ↑"
    case .front: "X →   Y ↑"
    case .side: "−Z →   Y ↑"
    }
  }
}

public enum SimulatorWorkspaceDimensionsError: Error, Equatable, Sendable {
  case invalidWidth
  case invalidHeight
  case invalidDepth
}

/// Simulator stageで表示・編集する有限な作業空間。
///
/// X/Zは原点を中心、Yは床面0mからheightまでを表示する。上限は描画精度と
/// 誤入力による操作不能を避けるためのもので、通常の部屋や展示空間より十分広い。
public struct SimulatorWorkspaceDimensions: Equatable, Sendable {
  public static let minimumMeters = 0.25
  public static let maximumMeters = 1_000.0
  public static let `default` = SimulatorWorkspaceDimensions(
    validatedWidthMeters: 4,
    heightMeters: 3,
    depthMeters: 4
  )

  public let widthMeters: Double
  public let heightMeters: Double
  public let depthMeters: Double

  private init(
    validatedWidthMeters widthMeters: Double,
    heightMeters: Double,
    depthMeters: Double
  ) {
    self.widthMeters = widthMeters
    self.heightMeters = heightMeters
    self.depthMeters = depthMeters
  }

  public init(
    widthMeters: Double,
    heightMeters: Double,
    depthMeters: Double
  ) throws {
    guard Self.validRange.contains(widthMeters), widthMeters.isFinite else {
      throw SimulatorWorkspaceDimensionsError.invalidWidth
    }
    guard Self.validRange.contains(heightMeters), heightMeters.isFinite else {
      throw SimulatorWorkspaceDimensionsError.invalidHeight
    }
    guard Self.validRange.contains(depthMeters), depthMeters.isFinite else {
      throw SimulatorWorkspaceDimensionsError.invalidDepth
    }
    self.widthMeters = widthMeters
    self.heightMeters = heightMeters
    self.depthMeters = depthMeters
  }

  public func updating(
    widthMeters: Double? = nil,
    heightMeters: Double? = nil,
    depthMeters: Double? = nil
  ) throws -> Self {
    try Self(
      widthMeters: widthMeters ?? self.widthMeters,
      heightMeters: heightMeters ?? self.heightMeters,
      depthMeters: depthMeters ?? self.depthMeters
    )
  }

  public func contains(_ position: Vector3) -> Bool {
    let halfWidth = Float(widthMeters / 2)
    let halfDepth = Float(depthMeters / 2)
    return (-halfWidth...halfWidth).contains(position.x)
      && (0...Float(heightMeters)).contains(position.y)
      && (-halfDepth...halfDepth).contains(position.z)
  }

  public func clamped(_ position: Vector3) -> Vector3 {
    let halfWidth = Float(widthMeters / 2)
    let halfDepth = Float(depthMeters / 2)
    return Vector3(
      x: min(max(position.x, -halfWidth), halfWidth),
      y: min(max(position.y, 0), Float(heightMeters)),
      z: min(max(position.z, -halfDepth), halfDepth)
    )
  }

  private static var validRange: ClosedRange<Double> {
    minimumMeters...maximumMeters
  }
}

/// 直交stage viewとcanonical XYZの相互変換。
///
/// aspect ratioを維持して作業空間全体を自動fitし、余白部分は座標範囲に含めない。
public struct SimulatorStageTransform: Equatable, Sendable {
  public static let defaultPadding: CGFloat = 42

  public let projection: SimulatorStageProjection
  public let workspace: SimulatorWorkspaceDimensions
  public let size: CGSize
  public let padding: CGFloat

  public init(
    projection: SimulatorStageProjection,
    workspace: SimulatorWorkspaceDimensions,
    size: CGSize,
    padding: CGFloat = Self.defaultPadding
  ) {
    self.projection = projection
    self.workspace = workspace
    self.size = size
    self.padding = max(0, padding)
  }

  public var plotRect: CGRect {
    let width = CGFloat(horizontalSpanMeters) * scale
    let height = CGFloat(verticalSpanMeters) * scale
    return CGRect(
      x: (size.width - width) / 2,
      y: (size.height - height) / 2,
      width: width,
      height: height
    )
  }

  public var scale: CGFloat {
    let availableWidth = max(1, size.width - padding * 2)
    let availableHeight = max(1, size.height - padding * 2)
    return min(
      availableWidth / CGFloat(horizontalSpanMeters),
      availableHeight / CGFloat(verticalSpanMeters)
    )
  }

  public var horizontalRange: ClosedRange<Double> {
    switch projection {
    case .top, .front:
      (-workspace.widthMeters / 2)...(workspace.widthMeters / 2)
    case .side:
      (-workspace.depthMeters / 2)...(workspace.depthMeters / 2)
    }
  }

  public var verticalRange: ClosedRange<Double> {
    switch projection {
    case .top:
      (-workspace.depthMeters / 2)...(workspace.depthMeters / 2)
    case .front, .side:
      0...workspace.heightMeters
    }
  }

  public var gridStepMeters: Double {
    niceStep(for: 64 / max(Double(scale), 0.000_001))
  }

  public func point(for position: Vector3) -> CGPoint {
    let horizontal = horizontalValue(position)
    let vertical = verticalValue(position)
    return CGPoint(
      x: plotRect.minX
        + CGFloat(horizontal - horizontalRange.lowerBound) * scale,
      y: plotRect.maxY
        - CGFloat(vertical - verticalRange.lowerBound) * scale
    )
  }

  public func position(
    at point: CGPoint,
    preserving position: Vector3,
    clampsToWorkspace: Bool
  ) -> Vector3 {
    let horizontal =
      horizontalRange.lowerBound
      + Double((point.x - plotRect.minX) / scale)
    let vertical =
      verticalRange.lowerBound
      + Double((plotRect.maxY - point.y) / scale)
    let resolved: Vector3

    switch projection {
    case .top:
      resolved = Vector3(
        x: Float(horizontal),
        y: position.y,
        z: Float(-vertical)
      )
    case .front:
      resolved = Vector3(
        x: Float(horizontal),
        y: Float(vertical),
        z: position.z
      )
    case .side:
      resolved = Vector3(
        x: position.x,
        y: Float(vertical),
        z: Float(-horizontal)
      )
    }

    return clampsToWorkspace ? workspace.clamped(resolved) : resolved
  }

  private var horizontalSpanMeters: Double {
    horizontalRange.upperBound - horizontalRange.lowerBound
  }

  private var verticalSpanMeters: Double {
    verticalRange.upperBound - verticalRange.lowerBound
  }

  private func horizontalValue(_ position: Vector3) -> Double {
    switch projection {
    case .top, .front: Double(position.x)
    case .side: Double(-position.z)
    }
  }

  private func verticalValue(_ position: Vector3) -> Double {
    switch projection {
    case .top: Double(-position.z)
    case .front, .side: Double(position.y)
    }
  }

  private func niceStep(for target: Double) -> Double {
    guard target.isFinite, target > 0 else { return 1 }
    let magnitude = pow(10, floor(log10(target)))
    let normalized = target / magnitude
    let factor: Double
    if normalized <= 1 {
      factor = 1
    } else if normalized <= 2 {
      factor = 2
    } else if normalized <= 5 {
      factor = 5
    } else {
      factor = 10
    }
    return factor * magnitude
  }
}

/// canonical空間を、cameraから読みやすい一定サイズの3D preview空間へ写す。
///
/// metre値の比率は保ち、X/Zは原点中心、Yは床面からの高さを中央揃えする。
/// これは表示だけの変換で、Hubのposeやcalibration値は変更しない。
public struct SimulatorSceneTransform: Equatable, Sendable {
  public static let defaultPreviewSpan: Float = 0.7

  public let workspace: SimulatorWorkspaceDimensions
  public let previewSpan: Float

  public init(
    workspace: SimulatorWorkspaceDimensions,
    previewSpan: Float = Self.defaultPreviewSpan
  ) {
    self.workspace = workspace
    self.previewSpan = max(0.1, previewSpan)
  }

  public var scale: Float {
    let maximumDimension = Float(
      max(
        workspace.widthMeters,
        workspace.heightMeters,
        workspace.depthMeters
      )
    )
    return previewSpan / maximumDimension
  }

  public var workspaceSize: Vector3 {
    Vector3(
      x: Float(workspace.widthMeters) * scale,
      y: Float(workspace.heightMeters) * scale,
      z: Float(workspace.depthMeters) * scale
    )
  }

  public func point(for position: Vector3) -> Vector3 {
    Vector3(
      x: position.x * scale,
      y: (position.y - Float(workspace.heightMeters / 2)) * scale,
      z: position.z * scale
    )
  }

  public func position(for point: Vector3) -> Vector3 {
    Vector3(
      x: point.x / scale,
      y: point.y / scale + Float(workspace.heightMeters / 2),
      z: point.z / scale
    )
  }
}

/// Trackerのlocal axisをorientation Quaternionでcanonical空間へ回転した方向。
///
/// forwardは共通座標規約のlocal -Zを指す。物理Trackerの装着offsetは含まない。
public struct TrackerOrientationAxes: Equatable, Sendable {
  public let right: Vector3
  public let up: Vector3
  public let forward: Vector3

  public init(orientation: Quaternion) {
    right = Self.rotate(
      Vector3(x: 1, y: 0, z: 0),
      by: orientation
    )
    up = Self.rotate(
      Vector3(x: 0, y: 1, z: 0),
      by: orientation
    )
    forward = Self.rotate(
      Vector3(x: 0, y: 0, z: -1),
      by: orientation
    )
  }

  private static func rotate(
    _ vector: Vector3,
    by quaternion: Quaternion
  ) -> Vector3 {
    let q = Vector3(
      x: quaternion.x,
      y: quaternion.y,
      z: quaternion.z
    )
    let firstCross = cross(q, vector)
    let secondCross = cross(q, firstCross)
    return Vector3(
      x: vector.x + 2 * quaternion.w * firstCross.x
        + 2 * secondCross.x,
      y: vector.y + 2 * quaternion.w * firstCross.y
        + 2 * secondCross.y,
      z: vector.z + 2 * quaternion.w * firstCross.z
        + 2 * secondCross.z
    )
  }

  private static func cross(_ lhs: Vector3, _ rhs: Vector3) -> Vector3 {
    Vector3(
      x: lhs.y * rhs.z - lhs.z * rhs.y,
      y: lhs.z * rhs.x - lhs.x * rhs.z,
      z: lhs.x * rhs.y - lhs.y * rhs.x
    )
  }
}
