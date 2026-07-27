import AppKit
import HubProtocol
import RealityKit
import SwiftUI

/// Quaternionと位置を同時に確認する3D preview。
///
/// 位置の精密編集は直交stageへ残し、このviewではcamera orbitと向きの把握を優先する。
struct TrackerSpatialPreview: View {
  let trackers: [TrackerDisplayState]
  let workspace: SimulatorWorkspaceDimensions
  @Binding var selectedTrackerID: String?

  var body: some View {
    if #available(macOS 15.0, *) {
      TrackerRealityPreview(
        trackers: trackers,
        workspace: workspace,
        selectedTrackerID: $selectedTrackerID
      )
    } else {
      ContentUnavailableView {
        Label("3D表示にはmacOS 15以降が必要です", systemImage: "view.3d")
      } description: {
        Text("上面・正面・側面ではmacOS 14でも位置を確認できます。")
      }
    }
  }
}

@available(macOS 15.0, *)
private struct TrackerRealityPreview: View {
  let trackers: [TrackerDisplayState]
  let workspace: SimulatorWorkspaceDimensions
  @Binding var selectedTrackerID: String?
  @StateObject private var scene = TrackerRealityScene()

  var body: some View {
    RealityView { content in
      scene.install(in: &content)
      scene.synchronize(
        trackers: trackers,
        workspace: workspace,
        selectedTrackerID: selectedTrackerID
      )
    } update: { content in
      scene.install(in: &content)
      scene.synchronize(
        trackers: trackers,
        workspace: workspace,
        selectedTrackerID: selectedTrackerID
      )
    }
    .realityViewCameraControls(.orbit)
    .gesture(
      TapGesture()
        .targetedToAnyEntity()
        .onEnded { value in
          if let trackerID = scene.trackerID(for: value.entity) {
            selectedTrackerID = trackerID
          }
        }
    )
    .background {
      ZStack {
        Color(nsColor: .controlBackgroundColor)
        RadialGradient(
          colors: [
            Color.accentColor.opacity(0.08),
            Color.clear,
          ],
          center: .topLeading,
          startRadius: 0,
          endRadius: 620
        )
      }
    }
    .overlay(alignment: .bottomLeading) {
      TrackerOrientationLegend()
        .padding(18)
    }
    .overlay(alignment: .bottomTrailing) {
      Label("ドラッグで視点を回転", systemImage: "rotate.3d")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(.regularMaterial, in: Capsule())
        .padding(18)
    }
    .accessibilityLabel("Trackerの3D姿勢プレビュー")
    .accessibilityValue(accessibilityValue)
  }

  private var accessibilityValue: String {
    guard
      let tracker = trackers.first(where: { $0.id == selectedTrackerID })
        ?? trackers.first
    else {
      return "Trackerはありません"
    }
    let forward = TrackerOrientationAxes(
      orientation: tracker.orientation
    ).forward
    return String(
      format: "%@、前方 X %.2f、Y %.2f、Z %.2f",
      tracker.role.isEmpty ? tracker.id : tracker.role,
      forward.x,
      forward.y,
      forward.z
    )
  }
}

private struct TrackerOrientationLegend: View {
  var body: some View {
    HStack(spacing: 10) {
      axis("X", color: .red)
      axis("Y", color: .green)
      axis("−Z 前方", color: .blue)
    }
    .font(.caption.monospaced())
    .foregroundStyle(.secondary)
    .padding(.horizontal, 11)
    .frame(height: 30)
    .background(.regularMaterial, in: Capsule())
    .accessibilityElement(children: .combine)
    .accessibilityLabel("姿勢軸、Xは赤、Yは緑、マイナスZ前方は青")
  }

  private func axis(_ label: String, color: Color) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)
      Text(label)
    }
  }
}

@available(macOS 15.0, *)
@MainActor
private final class TrackerRealityScene: ObservableObject {
  private let root = Entity()
  private let stageRoot = Entity()
  private let trackerRoot = Entity()
  private let cameraTarget = Entity()
  private var trackerEntities: [String: TrackerEntityParts] = [:]
  private var renderedWorkspace: SimulatorWorkspaceDimensions?

  init() {
    root.name = "divive-spatial-preview"
    stageRoot.name = "stage"
    trackerRoot.name = "trackers"
    cameraTarget.name = "camera-target"
    // 仮想cameraは原点から−Zを見るため、sceneを前方へ離して配置する。
    // Tracker Spaceの正規化scaleは保ち、姿勢矢印と作業空間の比率を崩さない。
    root.position.z = -1
    root.scale = SIMD3(repeating: 0.75)
    root.addChild(stageRoot)
    root.addChild(trackerRoot)
    root.addChild(cameraTarget)
  }

  func install(in content: inout RealityViewCameraContent) {
    if !content.entities.contains(where: { $0 === root }) {
      content.add(root)
      content.camera = .virtual
      content.cameraTarget = cameraTarget
    }
  }

  func synchronize(
    trackers: [TrackerDisplayState],
    workspace: SimulatorWorkspaceDimensions,
    selectedTrackerID: String?
  ) {
    let transform = SimulatorSceneTransform(workspace: workspace)
    if renderedWorkspace != workspace {
      rebuildStage(transform: transform)
      renderedWorkspace = workspace
    }

    let liveTrackerIDs = Set(trackers.map(\.id))
    for trackerID in trackerEntities.keys
    where !liveTrackerIDs.contains(trackerID) {
      trackerEntities.removeValue(forKey: trackerID)?
        .root.removeFromParent()
    }

    for tracker in trackers {
      let parts =
        trackerEntities[tracker.id]
        ?? makeTracker(id: tracker.id)
      trackerEntities[tracker.id] = parts
      update(
        parts,
        tracker: tracker,
        transform: transform,
        isSelected: tracker.id == selectedTrackerID
      )
    }
  }

  func trackerID(for entity: Entity) -> String? {
    var candidate: Entity? = entity
    while let current = candidate {
      if current.name.hasPrefix(Self.trackerNamePrefix) {
        return String(current.name.dropFirst(Self.trackerNamePrefix.count))
      }
      candidate = current.parent
    }
    return nil
  }

  private func rebuildStage(transform: SimulatorSceneTransform) {
    for child in stageRoot.children {
      child.removeFromParent()
    }

    let size = transform.workspaceSize
    let floorY = -size.y / 2
    // 床と通常の装着高を同時に見やすくするため、作業空間中央より少し下を注視する。
    cameraTarget.position.y = -size.y * 0.15
    let lineWidth: Float = 0.004
    let gridMaterial = UnlitMaterial(
      color: NSColor.secondaryLabelColor.withAlphaComponent(0.32)
    )
    let boundaryMaterial = UnlitMaterial(
      color: NSColor.secondaryLabelColor.withAlphaComponent(0.62)
    )

    let divisions = 10
    for index in 0...divisions {
      let ratio = Float(index) / Float(divisions) - 0.5
      stageRoot.addChild(
        box(
          size: SIMD3(lineWidth, lineWidth, max(size.z, lineWidth)),
          position: SIMD3(ratio * size.x, floorY + lineWidth, 0),
          material: gridMaterial
        )
      )
      stageRoot.addChild(
        box(
          size: SIMD3(max(size.x, lineWidth), lineWidth, lineWidth),
          position: SIMD3(0, floorY + lineWidth, ratio * size.z),
          material: gridMaterial
        )
      )
    }

    addWorkspaceEdges(
      size: SIMD3(size.x, size.y, size.z),
      lineWidth: lineWidth,
      material: boundaryMaterial
    )
    addWorldAxes(
      floorY: floorY,
      size: SIMD3(size.x, size.y, size.z)
    )
  }

  private func addWorkspaceEdges(
    size: SIMD3<Float>,
    lineWidth: Float,
    material: UnlitMaterial
  ) {
    let xPositions = [-size.x / 2, size.x / 2]
    let yPositions = [-size.y / 2, size.y / 2]
    let zPositions = [-size.z / 2, size.z / 2]

    for y in yPositions {
      for z in zPositions {
        stageRoot.addChild(
          box(
            size: SIMD3(max(size.x, lineWidth), lineWidth, lineWidth),
            position: SIMD3(0, y, z),
            material: material
          )
        )
      }
    }
    for x in xPositions {
      for z in zPositions {
        stageRoot.addChild(
          box(
            size: SIMD3(lineWidth, max(size.y, lineWidth), lineWidth),
            position: SIMD3(x, 0, z),
            material: material
          )
        )
      }
    }
    for x in xPositions {
      for y in yPositions {
        stageRoot.addChild(
          box(
            size: SIMD3(lineWidth, lineWidth, max(size.z, lineWidth)),
            position: SIMD3(x, y, 0),
            material: material
          )
        )
      }
    }
  }

  private func addWorldAxes(
    floorY: Float,
    size: SIMD3<Float>
  ) {
    let length = min(
      0.15,
      max(0.06, max(size.x, size.y, size.z) * 0.22)
    )
    let width: Float = 0.004
    stageRoot.addChild(
      box(
        size: SIMD3(length, width, width),
        position: SIMD3(length / 2, floorY + width * 2, 0),
        material: UnlitMaterial(color: .systemRed)
      )
    )
    stageRoot.addChild(
      box(
        size: SIMD3(width, length, width),
        position: SIMD3(0, floorY + length / 2, 0),
        material: UnlitMaterial(color: .systemGreen)
      )
    )
    stageRoot.addChild(
      box(
        size: SIMD3(width, width, length),
        position: SIMD3(0, floorY + width * 2, -length / 2),
        material: UnlitMaterial(color: .systemBlue)
      )
    )
  }

  private func makeTracker(id: String) -> TrackerEntityParts {
    let tracker = Entity()
    tracker.name = Self.trackerNamePrefix + id

    let body = ModelEntity(
      mesh: .generateBox(
        size: SIMD3(0.033, 0.013, 0.025),
        cornerRadius: 0.004
      ),
      materials: [
        SimpleMaterial(color: .systemBlue, isMetallic: false)
      ]
    )
    tracker.addChild(body)

    let forwardShaft = box(
      size: SIMD3(0.003, 0.003, 0.036),
      position: SIMD3(0, 0, -0.03),
      material: UnlitMaterial(color: .systemBlue)
    )
    tracker.addChild(forwardShaft)

    let forwardHead = ModelEntity(
      mesh: .generateCone(height: 0.015, radius: 0.008),
      materials: [UnlitMaterial(color: .systemBlue)]
    )
    forwardHead.position = SIMD3(0, 0, -0.054)
    forwardHead.orientation = simd_quatf(
      angle: -.pi / 2,
      axis: SIMD3(1, 0, 0)
    )
    tracker.addChild(forwardHead)

    let rightAxis = box(
      size: SIMD3(0.052, 0.003, 0.003),
      position: SIMD3(0.026, 0, 0),
      material: UnlitMaterial(color: .systemRed)
    )
    tracker.addChild(rightAxis)

    let upAxis = box(
      size: SIMD3(0.003, 0.052, 0.003),
      position: SIMD3(0, 0.026, 0),
      material: UnlitMaterial(color: .systemGreen)
    )
    tracker.addChild(upAxis)

    let selection = ModelEntity(
      mesh: .generatePlane(
        width: 0.05,
        depth: 0.05,
        cornerRadius: 0.025
      ),
      materials: [
        UnlitMaterial(
          color: NSColor.controlAccentColor.withAlphaComponent(0.12)
        )
      ]
    )
    selection.position.y = -0.011
    tracker.addChild(selection)

    tracker.components.set(InputTargetComponent())
    tracker.components.set(
      CollisionComponent(
        shapes: [
          .generateBox(size: SIMD3(0.06, 0.06, 0.075))
        ]
      )
    )
    trackerRoot.addChild(tracker)

    return TrackerEntityParts(
      root: tracker,
      body: body,
      rightAxis: rightAxis,
      upAxis: upAxis,
      selection: selection
    )
  }

  private func update(
    _ parts: TrackerEntityParts,
    tracker: TrackerDisplayState,
    transform: SimulatorSceneTransform,
    isSelected: Bool
  ) {
    let point = transform.point(for: tracker.position)
    parts.root.position = SIMD3(point.x, point.y, point.z)
    parts.root.orientation = simd_quatf(
      ix: tracker.orientation.x,
      iy: tracker.orientation.y,
      iz: tracker.orientation.z,
      r: tracker.orientation.w
    )
    parts.root.scale = SIMD3(repeating: isSelected ? 1.8 : 1.45)
    parts.rightAxis.isEnabled = isSelected
    parts.upAxis.isEnabled = isSelected
    parts.selection.isEnabled = isSelected
    if parts.renderedTrackingState != tracker.trackingState {
      parts.body.model?.materials = [
        SimpleMaterial(
          color: tracker.trackingState.sceneColor,
          isMetallic: false
        )
      ]
      parts.renderedTrackingState = tracker.trackingState
    }
  }

  private func box(
    size: SIMD3<Float>,
    position: SIMD3<Float>,
    material: UnlitMaterial
  ) -> ModelEntity {
    let entity = ModelEntity(
      mesh: .generateBox(size: size),
      materials: [material]
    )
    entity.position = position
    return entity
  }

  private static let trackerNamePrefix = "tracker:"
}

@available(macOS 15.0, *)
private final class TrackerEntityParts {
  let root: Entity
  let body: ModelEntity
  let rightAxis: ModelEntity
  let upAxis: ModelEntity
  let selection: ModelEntity
  var renderedTrackingState: TrackingState?

  init(
    root: Entity,
    body: ModelEntity,
    rightAxis: ModelEntity,
    upAxis: ModelEntity,
    selection: ModelEntity
  ) {
    self.root = root
    self.body = body
    self.rightAxis = rightAxis
    self.upAxis = upAxis
    self.selection = selection
  }
}

extension TrackingState {
  fileprivate var sceneColor: NSColor {
    switch self {
    case .tracking: .systemGreen
    case .simulated: .systemBlue
    case .lost: .systemOrange
    case .disconnected: .systemGray
    case .unknown: .secondaryLabelColor
    }
  }
}
