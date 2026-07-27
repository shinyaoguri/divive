import AppKit
import HubProtocol
import RealityKit
import SwiftUI

/// Quaternionと位置を同時に確認し、Trackerを直接移動できる3D preview。
struct TrackerSpatialPreview: View {
  let trackers: [TrackerDisplayState]
  let baseStations: [SimulatorBaseStation]
  let workspace: SimulatorWorkspaceDimensions
  @Binding var selectedTrackerID: String?
  @Binding var viewportCamera: SimulatorViewportCamera
  let isEditable: Bool
  let clampsToWorkspace: Bool
  let onMoveBegan: (String, Vector3) -> Void
  let onMoveChanged: (String, Vector3) -> Void
  let onMoveEnded: (String) -> Void

  var body: some View {
    if #available(macOS 15.0, *) {
      TrackerRealityPreview(
        trackers: trackers,
        baseStations: baseStations,
        workspace: workspace,
        selectedTrackerID: $selectedTrackerID,
        viewportCamera: $viewportCamera,
        isEditable: isEditable,
        clampsToWorkspace: clampsToWorkspace,
        onMoveBegan: onMoveBegan,
        onMoveChanged: onMoveChanged,
        onMoveEnded: onMoveEnded
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
  let baseStations: [SimulatorBaseStation]
  let workspace: SimulatorWorkspaceDimensions
  @Binding var selectedTrackerID: String?
  @Binding var viewportCamera: SimulatorViewportCamera
  let isEditable: Bool
  let clampsToWorkspace: Bool
  let onMoveBegan: (String, Vector3) -> Void
  let onMoveChanged: (String, Vector3) -> Void
  let onMoveEnded: (String) -> Void
  @StateObject private var scene = TrackerRealityScene()
  @State private var navigationTool: SimulatorViewportTool = .moveTracker
  @State private var dragOrigin: SimulatorViewportCamera?
  @State private var trackerDragState: SpatialTrackerDragState?
  @State private var magnificationOrigin: SimulatorViewportCamera?
  @State private var modifierKeys: EventModifiers = []

  var body: some View {
    GeometryReader { geometry in
      RealityView { content in
        scene.install(in: &content)
        scene.synchronize(
          trackers: trackers,
          baseStations: baseStations,
          workspace: workspace,
          selectedTrackerID: selectedTrackerID,
          viewportCamera: viewportCamera
        )
      } update: { content in
        scene.install(in: &content)
        scene.synchronize(
          trackers: trackers,
          baseStations: baseStations,
          workspace: workspace,
          selectedTrackerID: selectedTrackerID,
          viewportCamera: viewportCamera
        )
      }
      .simultaneousGesture(
        TapGesture()
          .targetedToAnyEntity()
          .onEnded { value in
            if let trackerID = scene.trackerID(for: value.entity) {
              selectedTrackerID = trackerID
            }
          }
      )
      .simultaneousGesture(
        trackerDragGesture
      )
      .simultaneousGesture(
        orbitGesture
      )
      .simultaneousGesture(magnificationGesture)
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
      .overlay {
        ViewportMouseInputView(
          onScroll: { deltaY, hasPreciseDeltas in
            guard effectiveNavigationTool == .navigate else {
              return
            }
            viewportCamera = viewportCamera.applyingScroll(
              deltaY: deltaY,
              hasPreciseDeltas: hasPreciseDeltas
            )
          },
          onMiddleDrag: { translation in
            guard effectiveNavigationTool == .navigate else {
              return
            }
            viewportCamera = viewportCamera.applyingPan(
              translation: translation,
              viewportSize: geometry.size
            )
          }
        )
        .accessibilityHidden(true)
      }
      .overlay(alignment: .bottomLeading) {
        TrackerOrientationLegend()
          .padding(18)
      }
      .overlay(alignment: .bottom) {
        ViewportNavigationBar(
          selectedTool: $navigationTool,
          effectiveTool: effectiveNavigationTool,
          canMoveTracker: isEditable,
          onFrameAll: frameAll
        )
        .padding(18)
      }
      .accessibilityLabel("Trackerの3D姿勢プレビュー")
      .accessibilityValue(accessibilityValue)
      .onModifierKeysChanged(
        mask: [.option]
      ) { _, newValue in
        modifierKeys = newValue
      }
    }
  }

  private var selectedTracker: TrackerDisplayState? {
    trackers.first(where: { $0.id == selectedTrackerID })
      ?? trackers.first
  }

  private var trackerDragGesture: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .targetedToAnyEntity()
      .onChanged { value in
        if trackerDragState == nil {
          guard
            isEditable,
            effectiveNavigationTool == .moveTracker,
            let trackerID = scene.trackerID(for: value.entity),
            let tracker = trackers.first(where: { $0.id == trackerID }),
            let coordinateSpace = value.entity.parent,
            let startRay = value.ray(
              through: value.startLocation,
              in: .local,
              to: coordinateSpace
            )
          else {
            return
          }

          let transform = SimulatorSceneTransform(workspace: workspace)
          let trackerPoint = transform.point(for: tracker.position)
          let plane = SimulatorPointerPlane(
            point: trackerPoint,
            normal: Vector3(
              x: startRay.direction.x,
              y: startRay.direction.y,
              z: startRay.direction.z
            )
          )
          guard
            let grabbedPoint = plane.intersection(
              rayOrigin: Vector3(
                x: startRay.origin.x,
                y: startRay.origin.y,
                z: startRay.origin.z
              ),
              rayDirection: Vector3(
                x: startRay.direction.x,
                y: startRay.direction.y,
                z: startRay.direction.z
              )
            )
          else {
            return
          }

          selectedTrackerID = trackerID
          trackerDragState = SpatialTrackerDragState(
            trackerID: trackerID,
            coordinateSpace: coordinateSpace,
            plane: plane,
            grabOffset: Vector3(
              x: trackerPoint.x - grabbedPoint.x,
              y: trackerPoint.y - grabbedPoint.y,
              z: trackerPoint.z - grabbedPoint.z
            )
          )
          onMoveBegan(trackerID, tracker.position)
        }

        guard let trackerDragState else { return }
        let didMove =
          abs(value.translation.width) > 0.1
          || abs(value.translation.height) > 0.1
        guard didMove else { return }

        guard
          let ray = value.ray(
            through: value.location,
            in: .local,
            to: trackerDragState.coordinateSpace
          ),
          let pointerPoint = trackerDragState.plane.intersection(
            rayOrigin: Vector3(
              x: ray.origin.x,
              y: ray.origin.y,
              z: ray.origin.z
            ),
            rayDirection: Vector3(
              x: ray.direction.x,
              y: ray.direction.y,
              z: ray.direction.z
            )
          )
        else {
          return
        }

        let transform = SimulatorSceneTransform(workspace: workspace)
        let resolved = transform.position(
          for: Vector3(
            x: pointerPoint.x + trackerDragState.grabOffset.x,
            y: pointerPoint.y + trackerDragState.grabOffset.y,
            z: pointerPoint.z + trackerDragState.grabOffset.z
          )
        )
        let position =
          clampsToWorkspace ? workspace.clamped(resolved) : resolved
        onMoveChanged(trackerDragState.trackerID, position)
      }
      .onEnded { _ in
        guard let trackerDragState else { return }
        onMoveEnded(trackerDragState.trackerID)
        self.trackerDragState = nil
      }
  }

  private var orbitGesture: some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        guard effectiveNavigationTool == .navigate else { return }
        let origin = dragOrigin ?? viewportCamera
        if dragOrigin == nil {
          dragOrigin = origin
        }
        viewportCamera = origin.applyingOrbit(
          translation: value.translation
        )
      }
      .onEnded { _ in
        dragOrigin = nil
      }
  }

  private var effectiveNavigationTool: SimulatorViewportTool {
    modifierKeys.contains(.option) ? .navigate : navigationTool
  }

  private var magnificationGesture: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        guard effectiveNavigationTool == .navigate else { return }
        let origin = magnificationOrigin ?? viewportCamera
        if magnificationOrigin == nil {
          magnificationOrigin = origin
        }
        viewportCamera = origin.applyingMagnification(
          value.magnification
        )
      }
      .onEnded { _ in
        magnificationOrigin = nil
      }
  }

  private func frameAll() {
    viewportCamera = viewportCamera.framingAll(workspace: workspace)
  }

  private var accessibilityValue: String {
    guard let tracker = selectedTracker else {
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

extension SimulatorViewportTool {
  fileprivate var helpText: String {
    switch self {
    case .moveTracker: "Trackerを掴んで画面に沿って移動"
    case .navigate:
      "視点操作：左ドラッグで回転、中ドラッグで移動、ホイールで拡大縮小"
    }
  }
}

private struct ViewportNavigationBar: View {
  @Binding var selectedTool: SimulatorViewportTool
  let effectiveTool: SimulatorViewportTool
  let canMoveTracker: Bool
  let onFrameAll: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      ForEach(SimulatorViewportTool.allCases) { tool in
        Button {
          selectedTool = tool
        } label: {
          Label(tool.displayName, systemImage: tool.symbolName)
            .labelStyle(.iconOnly)
        }
        .buttonStyle(
          ViewportToolButtonStyle(isSelected: effectiveTool == tool)
        )
        .disabled(tool == .moveTracker && !canMoveTracker)
        .help(
          tool == .moveTracker && !canMoveTracker
            ? "Tracker移動はSimulator実行中のみ利用できます"
            : tool.helpText
        )
        .accessibilityLabel("\(tool.displayName)ツール")
        .accessibilityValue(
          effectiveTool == tool ? "選択中" : "未選択"
        )
      }

      Divider()
        .frame(height: 20)
        .padding(.horizontal, 3)

      Button(action: onFrameAll) {
        Label("作業空間を全表示", systemImage: "square.resize")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(ViewportToolButtonStyle(isSelected: false))
      .help("視点を戻して作業空間全体を表示")

      Text(effectiveTool.statusText)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .frame(minWidth: 126, alignment: .leading)
    }
    .padding(4)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
    .overlay {
      RoundedRectangle(cornerRadius: 11)
        .stroke(.white.opacity(0.14), lineWidth: 0.5)
    }
    .accessibilityElement(children: .contain)
  }
}

extension SimulatorViewportTool {
  fileprivate var statusText: String {
    switch self {
    case .moveTracker: "Trackerをドラッグ"
    case .navigate: "左: 回転  中: 移動  ホイール: 拡大縮小"
    }
  }
}

private struct ViewportToolButtonStyle: ButtonStyle {
  let isSelected: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .frame(width: 30, height: 28)
      .background(
        isSelected
          ? Color.accentColor
          : Color.primary.opacity(configuration.isPressed ? 0.1 : 0),
        in: RoundedRectangle(cornerRadius: 7)
      )
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(
        .spring(response: 0.22, dampingFraction: 0.9),
        value: configuration.isPressed
      )
      .animation(
        .spring(response: 0.26, dampingFraction: 0.92),
        value: isSelected
      )
  }
}

private struct SpatialTrackerDragState {
  let trackerID: String
  let coordinateSpace: Entity
  let plane: SimulatorPointerPlane
  let grabOffset: Vector3
}

/// SwiftUIが直接公開しないwheelとmiddle-button dragをRealityViewへ渡す。
///
/// 左buttonはhit testを透過し、RealityKitのTracker選択とSwiftUI dragを妨げない。
private struct ViewportMouseInputView: NSViewRepresentable {
  let onScroll: (CGFloat, Bool) -> Void
  let onMiddleDrag: (CGSize) -> Void

  func makeNSView(context: Context) -> ViewportMouseInputNSView {
    let view = ViewportMouseInputNSView()
    view.onScroll = onScroll
    view.onMiddleDrag = onMiddleDrag
    return view
  }

  func updateNSView(
    _ nsView: ViewportMouseInputNSView,
    context: Context
  ) {
    nsView.onScroll = onScroll
    nsView.onMiddleDrag = onMiddleDrag
  }

  static func dismantleNSView(
    _ nsView: ViewportMouseInputNSView,
    coordinator: Void
  ) {
    nsView.invalidate()
  }
}

private final class ViewportMouseInputNSView: NSView {
  var onScroll: ((CGFloat, Bool) -> Void)?
  var onMiddleDrag: ((CGSize) -> Void)?
  private var eventMonitor: Any?
  private var isMiddleDragging = false

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    removeEventMonitor()
    guard window != nil else { return }

    eventMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [
        .scrollWheel,
        .otherMouseDown,
        .otherMouseDragged,
        .otherMouseUp,
      ]
    ) { [weak self] event in
      self?.handle(event) ?? event
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  private func handle(_ event: NSEvent) -> NSEvent? {
    guard
      let window,
      event.window === window
    else {
      return event
    }
    let isPointerInside = bounds.contains(
      convert(event.locationInWindow, from: nil)
    )

    switch event.type {
    case .scrollWheel where isPointerInside:
      onScroll?(
        event.scrollingDeltaY,
        event.hasPreciseScrollingDeltas
      )
      return nil
    case .otherMouseDown
    where event.buttonNumber == 2 && isPointerInside:
      isMiddleDragging = true
      return nil
    case .otherMouseDragged
    where event.buttonNumber == 2 && isMiddleDragging:
      // AppKitのY差分は上が正なので、SwiftUI dragの下が正へ揃える。
      onMiddleDrag?(
        CGSize(width: event.deltaX, height: -event.deltaY)
      )
      return nil
    case .otherMouseUp
    where event.buttonNumber == 2 && isMiddleDragging:
      isMiddleDragging = false
      return nil
    default:
      return event
    }
  }

  func invalidate() {
    isMiddleDragging = false
    removeEventMonitor()
  }

  private func removeEventMonitor() {
    guard let eventMonitor else { return }
    NSEvent.removeMonitor(eventMonitor)
    self.eventMonitor = nil
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
  private let navigationRoot = Entity()
  private let contentRoot = Entity()
  private let stageRoot = Entity()
  private let baseStationRoot = Entity()
  private let trackerRoot = Entity()
  private let cameraTarget = Entity()
  private var trackerEntities: [String: TrackerEntityParts] = [:]
  private var baseStationEntities: [String: BaseStationEntityParts] = [:]
  private var renderedWorkspace: SimulatorWorkspaceDimensions?

  init() {
    root.name = "divive-spatial-preview"
    navigationRoot.name = "viewport-navigation"
    contentRoot.name = "viewport-content"
    stageRoot.name = "stage"
    baseStationRoot.name = "base-stations"
    trackerRoot.name = "trackers"
    cameraTarget.name = "camera-target"
    // 仮想cameraは原点から−Zを見るため、sceneを前方へ離して配置する。
    // Tracker Spaceの正規化scaleは保ち、姿勢矢印と作業空間の比率を崩さない。
    root.position.z = -1
    root.scale = SIMD3(repeating: 1.5)
    root.addChild(navigationRoot)
    root.addChild(cameraTarget)
    navigationRoot.addChild(contentRoot)
    contentRoot.addChild(stageRoot)
    contentRoot.addChild(baseStationRoot)
    contentRoot.addChild(trackerRoot)
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
    baseStations: [SimulatorBaseStation],
    workspace: SimulatorWorkspaceDimensions,
    selectedTrackerID: String?,
    viewportCamera: SimulatorViewportCamera
  ) {
    let transform = SimulatorSceneTransform(workspace: workspace)
    if renderedWorkspace != workspace {
      rebuildStage(transform: transform)
      renderedWorkspace = workspace
    }
    synchronizeBaseStations(
      baseStations,
      transform: transform
    )

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

    updateViewport(viewportCamera)
  }

  private func synchronizeBaseStations(
    _ baseStations: [SimulatorBaseStation],
    transform: SimulatorSceneTransform
  ) {
    let liveIDs = Set(baseStations.map(\.id))
    for baseStationID in baseStationEntities.keys
    where !liveIDs.contains(baseStationID) {
      baseStationEntities.removeValue(forKey: baseStationID)?
        .root.removeFromParent()
    }

    for baseStation in baseStations {
      let parts =
        baseStationEntities[baseStation.id]
        ?? makeBaseStation(id: baseStation.id)
      baseStationEntities[baseStation.id] = parts
      update(
        parts,
        baseStation: baseStation,
        transform: transform
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
    let lineWidth: Float = 0.0025
    let gridMaterial = translucentMaterial(
      color: .secondaryLabelColor,
      opacity: 0.22
    )
    let boundaryMaterial = translucentMaterial(
      color: .secondaryLabelColor,
      opacity: 0.46
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

  private func updateViewport(
    _ camera: SimulatorViewportCamera
  ) {
    let radiansPerDegree = Float.pi / 180
    let yaw = simd_quatf(
      angle: camera.yawDegrees * radiansPerDegree,
      axis: SIMD3(0, 1, 0)
    )
    let pitch = simd_quatf(
      angle: camera.pitchDegrees * radiansPerDegree,
      axis: SIMD3(1, 0, 0)
    )
    navigationRoot.orientation = pitch * yaw
    navigationRoot.position = SIMD3(camera.panX, camera.panY, 0)
    navigationRoot.scale = SIMD3(repeating: camera.zoom)
    contentRoot.position = SIMD3(
      -camera.pivot.x,
      -camera.pivot.y,
      -camera.pivot.z
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

  private func makeBaseStation(id: String) -> BaseStationEntityParts {
    let station = Entity()
    station.name = "base-station:\(id)"

    let body = ModelEntity(
      mesh: .generateBox(
        size: SIMD3(0.04, 0.04, 0.02),
        cornerRadius: 0.004
      ),
      materials: [
        SimpleMaterial(color: .darkGray, isMetallic: false)
      ]
    )
    station.addChild(body)

    let front = box(
      size: SIMD3(0.032, 0.032, 0.002),
      position: SIMD3(0, 0, -0.011),
      material: translucentMaterial(
        color: .systemOrange,
        opacity: 0.32
      )
    )
    station.addChild(front)

    let status = ModelEntity(
      mesh: .generateSphere(radius: 0.003),
      materials: [UnlitMaterial(color: .systemGreen)]
    )
    status.position = SIMD3(0.012, 0.012, -0.013)
    station.addChild(status)

    let forwardShaft = box(
      size: SIMD3(0.0025, 0.0025, 0.055),
      position: SIMD3(0, 0, -0.04),
      material: translucentMaterial(
        color: .systemOrange,
        opacity: 0.58
      )
    )
    station.addChild(forwardShaft)

    let forwardHead = ModelEntity(
      mesh: .generateCone(height: 0.012, radius: 0.006),
      materials: [
        translucentMaterial(
          color: .systemOrange,
          opacity: 0.72
        )
      ]
    )
    forwardHead.position = SIMD3(0, 0, -0.073)
    forwardHead.orientation = simd_quatf(
      angle: -.pi / 2,
      axis: SIMD3(1, 0, 0)
    )
    station.addChild(forwardHead)

    baseStationRoot.addChild(station)
    return BaseStationEntityParts(root: station)
  }

  private func update(
    _ parts: BaseStationEntityParts,
    baseStation: SimulatorBaseStation,
    transform: SimulatorSceneTransform
  ) {
    let point = transform.point(for: baseStation.position)
    let target = transform.point(for: baseStation.target)
    let position = SIMD3(point.x, point.y, point.z)
    let direction = SIMD3(
      target.x - point.x,
      target.y - point.y,
      target.z - point.z
    )

    parts.root.position = position
    if simd_length_squared(direction) > 0.000_001 {
      parts.root.orientation = simd_quatf(
        from: SIMD3(0, 0, -1),
        to: simd_normalize(direction)
      )
    }
    parts.root.scale = SIMD3(repeating: 1.25)
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
        translucentMaterial(
          color: .controlAccentColor,
          opacity: 0.14
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

  private func translucentMaterial(
    color: NSColor,
    opacity: Float
  ) -> UnlitMaterial {
    var material = UnlitMaterial(color: color)
    material.blending = .transparent(
      opacity: .init(scale: opacity)
    )
    return material
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

@available(macOS 15.0, *)
private final class BaseStationEntityParts {
  let root: Entity

  init(root: Entity) {
    self.root = root
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
