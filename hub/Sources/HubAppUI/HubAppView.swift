import Charts
import HubCalibration
import HubProtocol
import HubSimulator
import SwiftUI

public struct HubAppView: View {
  @ObservedObject private var model: HubAppModel
  @State private var showsConfiguration = false
  @State private var showsCalibration = false
  @State private var selectedTrackerID: String?

  public init(model: HubAppModel) {
    self.model = model
  }

  public var body: some View {
    NavigationStack {
      HubWorkspace(
        model: model,
        selectedTrackerID: $selectedTrackerID
      )
      .toolbar {
        ToolbarItem(placement: .navigation) {
          SourcePicker(model: model)
        }

        ToolbarItemGroup(placement: .primaryAction) {
          SourceActionButton(model: model)
        }

        #if compiler(>=6.2)
          if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
          }
        #endif

        ToolbarItem(placement: .primaryAction) {
          Button {
            showsCalibration = true
          } label: {
            Label("較正", systemImage: "scope")
          }
          .help("Tracker SpaceからStage Spaceへの較正")
          .accessibilityIdentifier("calibration-button")
          .popover(
            isPresented: $showsCalibration,
            arrowEdge: .top
          ) {
            CalibrationPanel(
              model: model,
              selectedTrackerID: selectedTrackerID
            )
          }
        }

        ToolbarItem(placement: .primaryAction) {
          Button {
            showsConfiguration = true
          } label: {
            Label("入力設定", systemImage: "gearshape")
          }
          .help("\(model.selectedSource.displayName)の設定")
          .accessibilityIdentifier("configuration-button")
          .popover(
            isPresented: $showsConfiguration,
            arrowEdge: .top
          ) {
            SourceConfigurationPanel(model: model)
          }
        }
      }
    }
    .frame(minWidth: 1_120, minHeight: 700)
  }
}

private struct SourcePicker: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    sourceControl
      .onChange(of: model.selectedSource) {
        guard model.isRunning else { return }
        Task {
          await model.startSelectedSource()
        }
      }
  }

  @ViewBuilder
  private var sourceControl: some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        LiquidGlassSourceToggle(model: model)
      } else {
        StandardSourcePicker(model: model)
      }
    #else
      StandardSourcePicker(model: model)
    #endif
  }
}

private struct StandardSourcePicker: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    Picker("入力元", selection: $model.selectedSource) {
      ForEach(HubInputSource.allCases) { source in
        Text(source.shortDisplayName)
          .tag(source)
      }
    }
    .labelsHidden()
    .pickerStyle(.segmented)
    .frame(width: 230)
    .accessibilityIdentifier("source-picker")
  }
}

#if compiler(>=6.2)
  @available(macOS 26.0, *)
  private struct LiquidGlassSourceToggle: View {
    @ObservedObject var model: HubAppModel
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    private let controlWidth: CGFloat = 246
    private let controlHeight: CGFloat = 40
    private let contentInset: CGFloat = 4

    private var segmentWidth: CGFloat {
      (controlWidth - contentInset * 2) / 2
    }

    private var selectionOffset: CGFloat {
      contentInset
        + (model.selectedSource == .simulator ? segmentWidth : 0)
    }

    private var selectionAnimation: Animation? {
      guard !reduceMotion else { return nil }
      return .spring(
        response: 0.34,
        dampingFraction: 1,
        blendDuration: 0
      )
    }

    var body: some View {
      ZStack(alignment: .leading) {
        selectionGlass
          .frame(
            width: segmentWidth,
            height: controlHeight - contentInset * 2
          )
          .offset(x: selectionOffset)
          .allowsHitTesting(false)
          .zIndex(0)

        HStack(spacing: 0) {
          ForEach(HubInputSource.allCases) { source in
            sourceButton(source)
          }
        }
        .padding(.horizontal, contentInset)
        .zIndex(1)
      }
      .frame(width: controlWidth, height: controlHeight)
      .background {
        Capsule()
          .fill(
            Color.primary.opacity(reduceTransparency ? 0.1 : 0.028)
          )
          .overlay {
            Capsule()
              .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
          }
      }
      .animation(selectionAnimation, value: model.selectedSource)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("入力元")
      .accessibilityIdentifier("source-picker")
    }

    @ViewBuilder
    private var selectionGlass: some View {
      if reduceTransparency {
        Capsule()
          .fill(Color.accentColor.opacity(0.2))
          .overlay {
            Capsule()
              .stroke(Color.accentColor.opacity(0.38), lineWidth: 1)
          }
      } else {
        Color.clear
          .glassEffect(
            .regular.tint(Color.accentColor.opacity(0.3)),
            in: Capsule()
          )
      }
    }

    private func sourceButton(
      _ source: HubInputSource
    ) -> some View {
      let isSelected = model.selectedSource == source

      return Button {
        guard !isSelected else { return }
        model.selectedSource = source
      } label: {
        Text(source.shortDisplayName)
          .font(.callout.weight(isSelected ? .semibold : .medium))
          .foregroundStyle(
            isSelected ? Color.primary : Color.secondary
          )
          .frame(
            width: segmentWidth,
            height: controlHeight - contentInset * 2
          )
          .contentShape(Capsule())
      }
      .buttonStyle(
        SourceTogglePressStyle(reduceMotion: reduceMotion)
      )
      .accessibilityLabel(source.shortDisplayName)
      .accessibilityValue(isSelected ? "選択中" : "未選択")
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      .accessibilityIdentifier("source-\(source.rawValue)-button")
    }
  }

  private struct SourceTogglePressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .opacity(configuration.isPressed ? 0.78 : 1)
        .animation(
          reduceMotion ? nil : .easeOut(duration: 0.1),
          value: configuration.isPressed
        )
    }
  }
#endif

private struct SourceActionButton: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    if model.isRunning {
      Button(role: .destructive) {
        Task {
          await model.stopActiveSource()
        }
      } label: {
        Label("停止", systemImage: "stop.fill")
          .labelStyle(.iconOnly)
          .frame(width: 28, height: 16)
      }
      .buttonStyle(.bordered)
      .help("\(model.displayedSource.displayName)を停止")
      .accessibilityIdentifier("source-stop-button")
    } else {
      Button {
        Task {
          await model.startSelectedSource()
        }
      } label: {
        Label(
          model.selectedSource == .network ? "受信開始" : "開始",
          systemImage: "play.fill"
        )
        .labelStyle(.iconOnly)
        .frame(width: 28, height: 16)
      }
      .buttonStyle(.borderedProminent)
      .help("\(model.selectedSource.displayName)を開始")
      .accessibilityIdentifier("source-start-button")
    }
  }
}

private struct HubWorkspace: View {
  @ObservedObject var model: HubAppModel
  @Binding var selectedTrackerID: String?

  var body: some View {
    HSplitView {
      SpatialStage(
        model: model,
        selectedTrackerID: $selectedTrackerID
      )
      .frame(minWidth: 690)
      .layoutPriority(1)

      TrackerInspector(
        model: model,
        selectedTrackerID: $selectedTrackerID
      )
      .frame(minWidth: 350, idealWidth: 380, maxWidth: 420)
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }
}

private struct SpatialStage: View {
  @ObservedObject var model: HubAppModel
  @Binding var selectedTrackerID: String?
  @State private var viewMode: SimulatorStageViewMode = .spatial
  @State private var viewportCamera = SimulatorViewportCamera()
  @State private var showsWorkspaceSettings = false

  private var effectiveSelectedTrackerID: String? {
    selectedTrackerID ?? model.trackers.first?.id
  }

  private var baseStations: [SimulatorBaseStation] {
    guard
      model.displayedSource == .simulator,
      model.showsSimulatorBaseStations
    else {
      return []
    }
    return SimulatorBaseStation.defaultPair(
      in: model.simulatorWorkspace
    )
  }

  var body: some View {
    ZStack {
      if let projection = viewMode.projection {
        TrackerProjectionView(
          trackers: model.trackers,
          baseStations: baseStations,
          projection: projection,
          workspace: model.simulatorWorkspace,
          selectedTrackerID: selectedTrackerBinding,
          isEditable: model.canDirectlyEditSimulator,
          clampsToWorkspace: model.clampsSimulatorToWorkspace,
          onMoveBegan: model.beginSimulatorMove,
          onMoveChanged: model.moveSimulatorTracker,
          onMoveEnded: model.endSimulatorMove
        )
        .accessibilityIdentifier("tracker-space-preview")
        .opacity(model.trackers.isEmpty ? 0 : 1)
      } else {
        TrackerSpatialPreview(
          trackers: model.trackers,
          baseStations: baseStations,
          workspace: model.simulatorWorkspace,
          selectedTrackerID: selectedTrackerBinding,
          viewportCamera: $viewportCamera,
          isEditable: model.canDirectlyEditSimulator,
          clampsToWorkspace: model.clampsSimulatorToWorkspace,
          onMoveBegan: model.beginSimulatorMove,
          onMoveChanged: model.moveSimulatorTracker,
          onMoveEnded: model.endSimulatorMove
        )
        .accessibilityIdentifier("tracker-spatial-preview")
        .opacity(model.trackers.isEmpty ? 0 : 1)
      }

      VStack {
        HStack(alignment: .top) {
          StageStatusPill(model: model)
          Spacer()
          VStack(alignment: .trailing, spacing: 10) {
            StageControls(
              model: model,
              viewMode: viewMode,
              showsWorkspaceSettings: $showsWorkspaceSettings
            )
            ViewportOrientationGizmo(
              viewMode: $viewMode,
              viewportCamera: $viewportCamera
            )
          }
        }

        Spacer()
      }
      .padding(18)
    }
    .overlay(alignment: .center) {
      if model.trackers.isEmpty {
        EmptyStage(model: model)
      }
    }
  }

  private var selectedTrackerBinding: Binding<String?> {
    Binding(
      get: { effectiveSelectedTrackerID },
      set: { selectedTrackerID = $0 }
    )
  }
}

private struct StageStatusPill: View {
  @ObservedObject var model: HubAppModel
  @Environment(\.accessibilityReduceTransparency)
  private var reduceTransparency

  private var content: some View {
    HStack(spacing: 10) {
      Image(
        systemName: model.isRunning
          ? "dot.radiowaves.left.and.right"
          : "pause.fill"
      )
      .font(.caption.weight(.semibold))
      .foregroundStyle(model.isRunning ? .green : .secondary)

      Text(model.statusTitle)
        .font(.subheadline.weight(.semibold))

      Divider()
        .frame(height: 16)

      Text(String(format: "%.1f Hz", model.observedRateHz))
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)

      Text("\(model.trackers.count)台")
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
    .frame(height: 38)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  var body: some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *), !reduceTransparency {
        content
          .glassEffect(.regular, in: Capsule())
      } else if reduceTransparency {
        content
          .background(
            Color(nsColor: .windowBackgroundColor),
            in: Capsule()
          )
          .overlay {
            Capsule()
              .stroke(.separator, lineWidth: 1)
          }
      } else {
        content
          .background(.regularMaterial, in: Capsule())
      }
    #else
      if reduceTransparency {
        content
          .background(
            Color(nsColor: .windowBackgroundColor),
            in: Capsule()
          )
          .overlay {
            Capsule()
              .stroke(.separator, lineWidth: 1)
          }
      } else {
        content
          .background(.regularMaterial, in: Capsule())
      }
    #endif
  }
}

private struct StageControls: View {
  @ObservedObject var model: HubAppModel
  let viewMode: SimulatorStageViewMode
  @Binding var showsWorkspaceSettings: Bool

  var body: some View {
    HStack(spacing: 8) {
      Text(viewMode.displayName)
        .font(.caption.weight(.semibold))
      Text(viewMode.axisDescription)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .frame(minWidth: 76)

      Button {
        model.undoSimulatorMove()
      } label: {
        Label("移動を取り消す", systemImage: "arrow.uturn.backward")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .disabled(!model.canUndoSimulatorMove)
      .help("直前のTracker移動を取り消す")

      Button {
        showsWorkspaceSettings = true
      } label: {
        Label("作業空間", systemImage: "view.3d")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help("表示する作業空間の広さ")
      .popover(
        isPresented: $showsWorkspaceSettings,
        arrowEdge: .top
      ) {
        SimulatorWorkspaceSettings(model: model)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 34)
    .background(.regularMaterial, in: Capsule())
    .accessibilityElement(children: .contain)
  }
}

private struct ViewportOrientationGizmo: View {
  @Binding var viewMode: SimulatorStageViewMode
  @Binding var viewportCamera: SimulatorViewportCamera
  @Environment(\.accessibilityReduceTransparency)
  private var reduceTransparency

  var body: some View {
    VStack(spacing: 5) {
      ZStack {
        cubeFace(
          .top,
          title: "Y",
          color: .green,
          mode: .top
        )
        cubeFace(
          .front,
          title: "−Z",
          color: .blue,
          mode: .front
        )
        cubeFace(
          .side,
          title: "X",
          color: .red,
          mode: .side
        )
      }
      .frame(width: 72, height: 64)

      Button {
        withAnimation(
          .spring(response: 0.3, dampingFraction: 0.92)
        ) {
          viewMode = .spatial
          viewportCamera = viewportCamera.restoringPerspective()
        }
      } label: {
        Label("3D", systemImage: "cube.transparent")
          .font(.caption2.weight(.semibold))
          .labelStyle(.titleAndIcon)
          .frame(width: 62, height: 22)
          .background(
            viewMode == .spatial
              ? Color.accentColor
              : Color.primary.opacity(0.06),
            in: Capsule()
          )
          .foregroundStyle(
            viewMode == .spatial ? Color.white : Color.primary
          )
      }
      .buttonStyle(.plain)
      .help("3D透視表示へ戻す")
    }
    .padding(8)
    .background {
      RoundedRectangle(cornerRadius: 14)
        .fill(
          reduceTransparency
            ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            : AnyShapeStyle(.regularMaterial)
        )
    }
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(.white.opacity(0.15), lineWidth: 0.5)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("視点方向")
  }

  private func cubeFace(
    _ face: ViewportCubeFace,
    title: String,
    color: Color,
    mode: SimulatorStageViewMode
  ) -> some View {
    let shape = ViewportCubeFaceShape(face: face)
    let isSelected = viewMode == mode

    return Button {
      withAnimation(
        .spring(response: 0.3, dampingFraction: 0.92)
      ) {
        viewMode = mode
      }
    } label: {
      ZStack {
        shape
          .fill(
            color.opacity(isSelected ? 0.82 : 0.2)
          )
        shape
          .stroke(
            color.opacity(isSelected ? 1 : 0.65),
            lineWidth: isSelected ? 1.5 : 1
          )
        Text(title)
          .font(.caption2.weight(.bold))
          .foregroundStyle(isSelected ? Color.white : color)
          .offset(face.labelOffset)
      }
      .frame(width: 72, height: 58)
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .help("\(mode.displayName)へ切り替える")
    .accessibilityLabel("\(mode.displayName)へ切り替える")
  }
}

private enum ViewportCubeFace {
  case top
  case front
  case side

  var labelOffset: CGSize {
    switch self {
    case .top: CGSize(width: 0, height: -15)
    case .front: CGSize(width: -14, height: 8)
    case .side: CGSize(width: 14, height: 8)
    }
  }
}

private struct ViewportCubeFaceShape: Shape {
  let face: ViewportCubeFace

  func path(in rect: CGRect) -> Path {
    let geometry = ViewportCubeGeometry(in: rect)

    var path = Path()
    switch face {
    case .top:
      path.move(to: geometry.top)
      path.addLine(to: geometry.rightShoulder)
      path.addLine(to: geometry.center)
      path.addLine(to: geometry.leftShoulder)
    case .front:
      path.move(to: geometry.leftShoulder)
      path.addLine(to: geometry.center)
      path.addLine(to: geometry.bottom)
      path.addLine(to: geometry.leftBottom)
    case .side:
      path.move(to: geometry.center)
      path.addLine(to: geometry.rightShoulder)
      path.addLine(to: geometry.rightBottom)
      path.addLine(to: geometry.bottom)
    }
    path.closeSubpath()
    return path
  }
}

/// 3面が同じ7頂点を共有する等角投影の立方体。
///
/// 上面と側面をそれぞれ平行四辺形にし、隣接面の境界が必ず一致するようにする。
private struct ViewportCubeGeometry {
  let top: CGPoint
  let leftShoulder: CGPoint
  let center: CGPoint
  let rightShoulder: CGPoint
  let leftBottom: CGPoint
  let bottom: CGPoint
  let rightBottom: CGPoint

  init(in rect: CGRect) {
    let topY = rect.minY + 2
    let bottomY = rect.maxY - 2
    let slantHeight = (bottomY - topY) * 0.25
    let shoulderY = topY + slantHeight
    let centerY = shoulderY + slantHeight
    let lowerY = bottomY - slantHeight
    let leftX = rect.minX + 8
    let rightX = rect.maxX - 8

    top = CGPoint(x: rect.midX, y: topY)
    leftShoulder = CGPoint(x: leftX, y: shoulderY)
    center = CGPoint(x: rect.midX, y: centerY)
    rightShoulder = CGPoint(x: rightX, y: shoulderY)
    leftBottom = CGPoint(x: leftX, y: lowerY)
    bottom = CGPoint(x: rect.midX, y: bottomY)
    rightBottom = CGPoint(x: rightX, y: lowerY)
  }
}

private struct SimulatorWorkspaceSettings: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text("作業空間")
          .font(.headline)
        Text("全体が画面へ収まるよう自動調整します。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 9) {
        workspaceRow(
          "幅 X",
          axis: .width,
          value: model.simulatorWorkspace.widthMeters
        )
        workspaceRow(
          "高さ Y",
          axis: .height,
          value: model.simulatorWorkspace.heightMeters
        )
        workspaceRow(
          "奥行き Z",
          axis: .depth,
          value: model.simulatorWorkspace.depthMeters
        )
      }

      Toggle(
        "Trackerを作業空間内に制限",
        isOn: $model.clampsSimulatorToWorkspace
      )
      .font(.caption)

      if model.displayedSource == .simulator {
        Toggle(
          "ベースステーションを表示",
          isOn: $model.showsSimulatorBaseStations
        )
        .font(.caption)
      }

      Text(
        "\(SimulatorWorkspaceDimensions.minimumMeters)"
          + "〜\(SimulatorWorkspaceDimensions.maximumMeters)m"
      )
      .font(.caption2.monospacedDigit())
      .foregroundStyle(.tertiary)
    }
    .padding(18)
    .frame(width: 270)
  }

  private func workspaceRow(
    _ title: String,
    axis: SimulatorWorkspaceAxis,
    value: Double
  ) -> some View {
    GridRow {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      TextField(
        title,
        value: Binding(
          get: { value },
          set: { model.updateSimulatorWorkspace(axis, meters: $0) }
        ),
        format: .number.precision(.fractionLength(0...2))
      )
      .textFieldStyle(.roundedBorder)
      .multilineTextAlignment(.trailing)
      .frame(width: 92)
      Text("m")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }
}

private struct EmptyStage: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    ContentUnavailableView {
      Label(
        "Trackerを待っています",
        systemImage: "sensor.tag.radiowaves.forward"
      )
    } description: {
      Text(
        model.selectedSource == .simulator
          ? "シミュレータを開始すると、ここに動きが表示されます。"
          : "受信を開始して、Windows Bridgeを接続してください。"
      )
    } actions: {
      if !model.isRunning {
        Button {
          Task {
            await model.startSelectedSource()
          }
        } label: {
          Text(
            model.selectedSource == .network
              ? "受信を開始"
              : "シミュレータを開始"
          )
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .frame(maxWidth: 360)
  }
}

private struct TrackerInspector: View {
  @ObservedObject var model: HubAppModel
  @Binding var selectedTrackerID: String?

  private var selectedTracker: TrackerDisplayState? {
    model.trackers.first {
      $0.id == selectedTrackerID
    } ?? model.trackers.first
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      InspectorHeader(
        trackers: model.trackers
      )

      if let errorMessage = model.errorMessage {
        ErrorBanner(message: errorMessage)
      }

      if model.trackers.isEmpty {
        Spacer()
        Text("接続するとTrackerの状態がここに表示されます。")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
        Spacer()
      } else {
        TrackerGrid(
          trackers: model.trackers,
          selectedTrackerID: selectedTracker?.id
        ) { trackerID in
          selectedTrackerID = trackerID
        }
        .accessibilityIdentifier("tracker-grid")

        Spacer(minLength: 6)

        Divider()

        if let selectedTracker {
          SelectedTrackerPanel(
            tracker: selectedTracker,
            history: model.trackerHistory(for: selectedTracker.id),
            usesCompactLayout: model.trackers.count > 8
          )
        }
      }

      Divider()

      CalibrationSummaryRow(model: model)

      Divider()

      DiagnosticsSection(model: model)
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.regularMaterial)
  }
}

private struct InspectorHeader: View {
  let trackers: [TrackerDisplayState]

  var body: some View {
    HStack(spacing: 10) {
      Text("トラッカー")
        .font(.title2.weight(.semibold))

      Text("\(trackers.count)")
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
          Color.secondary.opacity(0.1),
          in: Capsule()
        )

      Spacer()

      TrackerStateSummary(trackers: trackers)
    }
  }
}

private struct TrackerGrid: View {
  let trackers: [TrackerDisplayState]
  let selectedTrackerID: String?
  let onSelect: (String) -> Void

  private var usesCompactRows: Bool {
    trackers.count > 8
  }

  private var rowSpacing: CGFloat {
    usesCompactRows ? 4 : 7
  }

  private var columns: [GridItem] {
    [
      GridItem(.flexible(), spacing: rowSpacing),
      GridItem(.flexible(), spacing: rowSpacing),
    ]
  }

  var body: some View {
    LazyVGrid(
      columns: columns,
      alignment: .leading,
      spacing: rowSpacing
    ) {
      ForEach(trackers.prefix(16)) { tracker in
        Button {
          onSelect(tracker.id)
        } label: {
          TrackerTile(
            tracker: tracker,
            isSelected: selectedTrackerID == tracker.id,
            usesCompactRows: usesCompactRows
          )
        }
        .buttonStyle(.plain)
        .help(tracker.id)
      }
    }
  }
}

private struct TrackerTile: View {
  let tracker: TrackerDisplayState
  let isSelected: Bool
  let usesCompactRows: Bool

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: tracker.trackingState.statusSymbol)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tracker.trackingState.displayColor)
        .frame(width: 12)
        .accessibilityLabel(tracker.trackingState.displayName)

      Text(tracker.role.isEmpty ? "未割当" : tracker.role)
        .font(.caption.weight(.medium))
        .lineLimit(1)

      Spacer(minLength: 3)

      Text(String(format: "%.0f", tracker.ageMilliseconds))
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.tertiary)
        .accessibilityLabel(
          String(format: "更新から%.0fミリ秒", tracker.ageMilliseconds)
        )
    }
    .padding(.horizontal, 9)
    .frame(
      maxWidth: .infinity,
      minHeight: usesCompactRows ? 32 : 36
    )
    .contentShape(RoundedRectangle(cornerRadius: 9))
    .background(
      isSelected
        ? Color.accentColor.opacity(0.16)
        : Color.primary.opacity(0.045),
      in: RoundedRectangle(cornerRadius: 9)
    )
    .overlay {
      if isSelected {
        RoundedRectangle(cornerRadius: 9)
          .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct SelectedTrackerPanel: View {
  let tracker: TrackerDisplayState
  let history: [TrackerHistorySample]
  let usesCompactLayout: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text(tracker.role.isEmpty ? "未割当" : tracker.role)
          .font(.headline)
          .lineLimit(1)

        Spacer()

        Label(
          tracker.trackingState.displayName,
          systemImage: tracker.trackingState.statusSymbol
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(tracker.trackingState.displayColor)
      }

      Text(tracker.id)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(tracker.id)

      HStack(spacing: 8) {
        PositionValue(axis: "X", value: tracker.position.x)
        PositionValue(axis: "Y", value: tracker.position.y)
        PositionValue(axis: "Z", value: tracker.position.z)
      }

      HStack(spacing: 8) {
        Text("前方 −Z")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)

        Spacer()

        DirectionComponent(axis: "X", value: forward.x)
        DirectionComponent(axis: "Y", value: forward.y)
        DirectionComponent(axis: "Z", value: forward.z)
      }

      StagePositionRow(tracker: tracker)

      TrackerQualityHistory(
        history: history,
        height: usesCompactLayout ? 62 : 82
      )

      LabeledContent("最終更新") {
        Text(String(format: "%.0f ms前", tracker.ageMilliseconds))
          .monospacedDigit()
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .contain)
  }

  private var forward: Vector3 {
    TrackerOrientationAxes(
      orientation: tracker.orientation
    ).forward
  }
}

/// 選択Trackerの較正後の位置。プレビューの座標はTracker Spaceのまま変えない。
private struct StagePositionRow: View {
  let tracker: TrackerDisplayState

  var body: some View {
    HStack(spacing: 8) {
      Label(
        tracker.calibrationDelivery.displayName,
        systemImage: tracker.calibrationDelivery.statusSymbol
      )
      .font(.caption.weight(.medium))
      .foregroundStyle(tracker.calibrationDelivery.displayColor)
      .labelStyle(.titleAndIcon)

      Spacer()

      if let stagePosition = tracker.stagePosition {
        DirectionComponent(axis: "X", value: stagePosition.x)
        DirectionComponent(axis: "Y", value: stagePosition.y)
        DirectionComponent(axis: "Z", value: stagePosition.z)
      } else {
        Text("未較正のため配信しません")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityIdentifier("stage-position-row")
  }
}

/// 右インスペクタへ常時表示する較正状態のサマリ。
private struct CalibrationSummaryRow: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    HStack(spacing: 8) {
      Text("較正")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      Text(model.calibrationMode.displayName)
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer()

      if let error = model.calibrationErrorMessage {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .lineLimit(1)
          .truncationMode(.tail)
          .help(error)
      } else {
        Text(model.calibrationSummaryText)
          .font(.caption.monospacedDigit())
          .foregroundStyle(model.hasUncalibratedSpace ? Color.orange : .secondary)
      }
    }
    .accessibilityIdentifier("calibration-summary")
  }
}

private struct DirectionComponent: View {
  let axis: String
  let value: Float

  var body: some View {
    Text(String(format: "%@ %.2f", axis, value))
      .font(.caption2.monospacedDigit())
      .foregroundStyle(.secondary)
      .accessibilityLabel(
        String(format: "前方%@ %.2f", axis, value)
      )
  }
}

private struct TrackerQualityInterval: Identifiable {
  let id: UInt64
  let startSeconds: Double
  let endSeconds: Double
}

private struct TrackerQualityHistory: View {
  let history: [TrackerHistorySample]
  let height: CGFloat

  private let visibleDurationSeconds = 6.0

  private var visibleSamples: [TrackerHistorySample] {
    guard let latestTimestamp = history.last?.sampledAtNS else { return [] }
    let durationNS = UInt64(visibleDurationSeconds * 1_000_000_000)
    let lowerBound =
      latestTimestamp > durationNS
      ? latestTimestamp - durationNS
      : 0
    return history.filter { $0.sampledAtNS >= lowerBound }
  }

  private var latestTimestamp: UInt64 {
    visibleSamples.last?.sampledAtNS ?? 0
  }

  private var frameLossIntervals: [TrackerQualityInterval] {
    visibleSamples.enumerated().compactMap { index, sample in
      guard sample.frameLossCount > 0 else { return nil }
      let endSeconds = seconds(for: sample)
      let startSeconds =
        index > 0
        ? seconds(for: visibleSamples[index - 1])
        : max(-visibleDurationSeconds, endSeconds - 0.1)
      return TrackerQualityInterval(
        id: sample.sampledAtNS,
        startSeconds: startSeconds,
        endSeconds: endSeconds
      )
    }
  }

  private var trackingLossIntervals: [TrackerQualityInterval] {
    var intervals: [TrackerQualityInterval] = []
    var lossStartIndex: Int?

    for (index, sample) in visibleSamples.enumerated() {
      if !sample.trackingState.hasUsablePose {
        lossStartIndex = lossStartIndex ?? index
        continue
      }
      guard let startIndex = lossStartIndex else { continue }
      let startSample = visibleSamples[startIndex]
      intervals.append(
        TrackerQualityInterval(
          id: startSample.sampledAtNS,
          startSeconds: seconds(for: startSample),
          endSeconds: seconds(for: sample)
        )
      )
      lossStartIndex = nil
    }

    if let startIndex = lossStartIndex {
      let startSample = visibleSamples[startIndex]
      intervals.append(
        TrackerQualityInterval(
          id: startSample.sampledAtNS,
          startSeconds: seconds(for: startSample),
          endSeconds: 0
        )
      )
    }
    return intervals
  }

  private var trackingLossStarts: [TrackerHistorySample] {
    visibleSamples.enumerated().compactMap { index, sample in
      guard !sample.trackingState.hasUsablePose else { return nil }
      guard
        index == 0
          || visibleSamples[index - 1].trackingState.hasUsablePose
      else {
        return nil
      }
      return sample
    }
  }

  private var qualitySummary: TrackerQualitySummary {
    TrackerQualitySummary(samples: visibleSamples)
  }

  private var hasTrackingLoss: Bool {
    visibleSamples.contains {
      !$0.trackingState.hasUsablePose
    }
  }

  private var accessibilityValue: String {
    guard !visibleSamples.isEmpty else {
      return "履歴はまだありません"
    }
    return
      "フレーム欠落\(qualitySummary.frameLossCount)件、"
      + "\(frameLossPercentText)、"
      + "追跡喪失\(trackingLossPercentText)"
  }

  private var frameLossPercentText: String {
    String(format: "%.1f%%", qualitySummary.frameLossPercent)
  }

  private var trackingLossPercentText: String {
    String(format: "%.1f%%", qualitySummary.trackingLossPercent)
  }

  private func seconds(
    for sample: TrackerHistorySample
  ) -> Double {
    let ageNanoseconds = latestTimestamp - sample.sampledAtNS
    return -Double(ageNanoseconds) / 1_000_000_000
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("品質の推移")
          .font(.caption.weight(.semibold))

        Text("直近6秒")
          .font(.caption2)
          .foregroundStyle(.tertiary)

        Spacer()

        HStack(spacing: 10) {
          Text(
            "欠落 \(qualitySummary.frameLossCount)件 "
              + frameLossPercentText
          )
          .foregroundStyle(
            qualitySummary.frameLossCount > 0
              ? Color.orange : Color.secondary
          )

          Text("喪失 \(trackingLossPercentText)")
            .foregroundStyle(
              hasTrackingLoss ? Color.red : Color.secondary
            )
        }
        .font(.caption2.monospacedDigit().weight(.medium))
      }

      if visibleSamples.isEmpty {
        Text("受信を開始すると品質履歴が表示されます")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 70)
          .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 8)
          )
      } else {
        Chart {
          RuleMark(
            y: .value("フレーム欠落", 1.5)
          )
          .foregroundStyle(Color.secondary.opacity(0.22))
          .lineStyle(
            StrokeStyle(
              lineWidth: 1,
              lineCap: .round,
              lineJoin: .round
            )
          )

          RuleMark(
            y: .value("追跡状態", 0.5)
          )
          .foregroundStyle(Color.green.opacity(0.38))
          .lineStyle(
            StrokeStyle(
              lineWidth: 2,
              lineCap: .round
            )
          )

          ForEach(frameLossIntervals) { interval in
            RectangleMark(
              xStart: .value("検出区間の開始", interval.startSeconds),
              xEnd: .value("検出区間の終了", interval.endSeconds),
              yStart: .value("欠落lane下端", 1.18),
              yEnd: .value("欠落lane上端", 1.82)
            )
            .foregroundStyle(Color.orange.opacity(0.82))
            .cornerRadius(2)
          }

          ForEach(trackingLossIntervals) { interval in
            RectangleMark(
              xStart: .value("喪失区間の開始", interval.startSeconds),
              xEnd: .value("喪失区間の終了", interval.endSeconds),
              yStart: .value("追跡lane下端", 0.18),
              yEnd: .value("追跡lane上端", 0.82)
            )
            .foregroundStyle(Color.red.opacity(0.72))
            .cornerRadius(2)
          }

          ForEach(trackingLossStarts) { sample in
            PointMark(
              x: .value("追跡喪失の検出時刻", seconds(for: sample)),
              y: .value("追跡状態", 0.5)
            )
            .foregroundStyle(.red)
            .symbolSize(18)
          }
        }
        .chartXScale(domain: -visibleDurationSeconds...0)
        .chartYScale(domain: 0...2)
        .chartXAxis {
          AxisMarks(values: [-visibleDurationSeconds, 0]) { value in
            AxisGridLine()
              .foregroundStyle(Color.secondary.opacity(0.1))
            AxisValueLabel {
              if let seconds = value.as(Double.self) {
                Text(seconds == 0 ? "現在" : "6秒前")
              }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
          }
        }
        .chartYAxis {
          AxisMarks(
            position: .leading,
            values: [0.5, 1.5]
          ) { value in
            AxisValueLabel {
              if let number = value.as(Double.self) {
                Text(number < 1 ? "追跡" : "欠落")
              }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
          }
        }
        .chartPlotStyle { plotArea in
          plotArea
            .background(Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("直近6秒の品質の推移")
        .accessibilityValue(accessibilityValue)
        .help(
          "欠落率は期待frame数、喪失率は選択Trackerの観測時間に対する割合です"
        )
      }
    }
    .accessibilityIdentifier("tracker-quality-history")
  }
}

private struct PositionValue: View {
  let axis: String
  let value: Float

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(axis)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
      Text(String(format: "%.3f m", value))
        .font(.caption.monospacedDigit())
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color.primary.opacity(0.045),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .accessibilityElement(children: .combine)
  }
}

private struct DiagnosticsSection: View {
  @ObservedObject var model: HubAppModel

  private var items: [DiagnosticItem] {
    switch model.displayedSource {
    case .simulator:
      [
        DiagnosticItem(
          title: "生成 / 出力",
          value: "\(model.attemptedFrames) / \(model.emittedFrames)"
        ),
        DiagnosticItem(
          title: "欠落率",
          value: String(format: "%.1f%%", model.droppedPercent)
        ),
        DiagnosticItem(
          title: "接続断 / 逆転",
          value:
            "\(model.disconnectedFrames) / \(model.staleSimulatorFrames)"
        ),
        DiagnosticItem(
          title: "保留 / 期限",
          value:
            "\(model.simulatorPendingFrames) / \(model.missedDeadlines)"
        ),
      ]
    case .network:
      [
        DiagnosticItem(
          title: "受信",
          value: "\(model.receivedDatagrams)"
        ),
        DiagnosticItem(
          title: "有効",
          value: "\(model.validPackets)"
        ),
        DiagnosticItem(
          title: "欠落",
          value: "\(model.missingFrames)"
        ),
        DiagnosticItem(
          title: "順序逆転",
          value: "\(model.outOfOrderPackets)"
        ),
        DiagnosticItem(
          title: "異常",
          value: "\(model.networkAnomalyCount)"
        ),
        DiagnosticItem(
          title: "受信処理",
          value: "\(model.lastProcessingMicroseconds) µs"
        ),
      ]
    }
  }

  private var needsAttention: Bool {
    switch model.displayedSource {
    case .simulator:
      model.simulatorUndeliveredFrames > 0
        || model.missedDeadlines > 0
    case .network:
      model.missingFrames > 0 || model.networkAnomalyCount > 0
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text("診断")
          .font(.subheadline.weight(.semibold))

        Spacer()

        Label(
          needsAttention ? "要確認" : "問題なし",
          systemImage: needsAttention
            ? "exclamationmark.circle.fill"
            : "checkmark.circle.fill"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(needsAttention ? .orange : .green)
      }

      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 14),
          GridItem(.flexible(), spacing: 14),
        ],
        alignment: .leading,
        spacing: 6
      ) {
        ForEach(items) { item in
          DiagnosticValue(item: item)
        }
      }
    }
    .accessibilityIdentifier("diagnostics-section")
  }
}

private struct DiagnosticItem: Identifiable {
  let title: String
  let value: String

  var id: String { title }
}

private struct DiagnosticValue: View {
  let item: DiagnosticItem

  var body: some View {
    HStack(spacing: 6) {
      Text(item.title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Spacer(minLength: 4)

      Text(item.value)
        .font(.caption.monospacedDigit().weight(.medium))
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct TrackerStateSummary: View {
  let trackers: [TrackerDisplayState]

  private var attentionCount: Int {
    trackers.count {
      $0.trackingState == .lost || $0.trackingState == .disconnected
    }
  }

  var body: some View {
    if attentionCount > 0 {
      Label(
        "\(attentionCount)件",
        systemImage: "exclamationmark.circle.fill"
      )
      .font(.caption.weight(.medium))
      .foregroundStyle(.orange)
    } else if !trackers.isEmpty {
      Label("正常", systemImage: "checkmark.circle.fill")
        .font(.caption.weight(.medium))
        .foregroundStyle(.green)
    }
  }
}

private struct SourceConfigurationPanel: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 3) {
        Text("\(model.selectedSource.displayName)の設定")
          .font(.title3.weight(.semibold))
        Text(
          model.isRunning
            ? "変更後に「設定を反映」を押してください。"
            : "次回の開始時に反映されます。"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Divider()

      if model.selectedSource == .simulator {
        SimulatorConfiguration(model: model)
      } else {
        NetworkConfiguration(model: model)
      }

      if let errorMessage = model.errorMessage {
        ErrorBanner(message: errorMessage)
      }

      if model.isRunning {
        Divider()

        HStack {
          Spacer()
          Button {
            Task {
              await model.startSelectedSource()
            }
          } label: {
            Text("設定を反映")
          }
          .buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(20)
    .frame(width: 360)
  }
}

private struct SimulatorConfiguration: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ConfigurationSectionTitle("動き")

      LabeledContent("Tracker数") {
        Stepper(
          "\(model.trackerCount) 台",
          value: $model.trackerCount,
          in: 1...16
        )
        .fixedSize()
      }

      LabeledContent("モーション") {
        Picker("モーション", selection: $model.motion) {
          ForEach(HubAppMotionPreset.allCases) { motion in
            Label(motion.displayName, systemImage: motion.systemImage)
              .tag(motion)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 145, alignment: .trailing)
        .accessibilityIdentifier("motion-picker")
      }

      LabeledContent("更新頻度") {
        Picker("更新頻度", selection: $model.rate) {
          ForEach(SimulatorRate.allCases, id: \.rawValue) { rate in
            Text("\(rate.rawValue) Hz").tag(rate)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 95, alignment: .trailing)
      }

      Divider()

      ConfigurationSectionTitle("障害のシミュレーション")

      LabeledContent("再現用Seed") {
        TextField("Seed", text: $model.seedText)
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .frame(width: 96)
      }

      FaultControl(
        title: "フレーム欠落",
        value: $model.frameLossPercent
      )

      FaultControl(
        title: "トラッキング喪失",
        value: $model.trackingLostPercent
      )

      Divider()

      ConfigurationSectionTitle("配信経路")

      CompactFaultValue(
        title: "遅延",
        value: $model.delayMilliseconds,
        suffix: "ms"
      )

      CompactFaultValue(
        title: "ジッター ±",
        value: $model.jitterMilliseconds,
        suffix: "ms"
      )

      FaultControl(
        title: "順序逆転率",
        value: $model.reorderingPercent,
        range: 0...100
      )

      FaultControl(
        title: "接続断の開始率",
        value: $model.disconnectPercent,
        range: 0...100
      )

      CompactFaultValue(
        title: "切断時間",
        value: $model.disconnectDurationMilliseconds,
        suffix: "ms"
      )
    }
  }
}

private struct NetworkConfiguration: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ConfigurationSectionTitle("受信先")

      LabeledContent("アドレス") {
        TextField("Bind address", text: $model.networkBindHost)
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .frame(width: 160)
      }

      LabeledContent("UDPポート") {
        TextField("UDP port", text: $model.networkPortText)
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .frame(width: 96)
      }

      Text("LANから受信する場合は0.0.0.0、Mac内だけで試す場合は127.0.0.1を使用します。")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct ConfigurationSectionTitle: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
  }
}

private struct FaultControl: View {
  let title: String
  @Binding var value: Double
  var range: ClosedRange<Double> = 0...50

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Text(
          value.formatted(
            .number.precision(.fractionLength(1))
          ) + "%"
        )
        .font(.caption.monospacedDigit())
      }

      Slider(value: $value, in: range, step: 0.5)
    }
  }
}

private struct CompactFaultValue: View {
  let title: String
  @Binding var value: Double
  let suffix: String

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 5) {
        TextField(
          title,
          value: $value,
          format: .number.precision(.fractionLength(0...1))
        )
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 72)

        Text(suffix)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 24, alignment: .leading)
      }
    }
  }
}

private struct ErrorBanner: View {
  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.caption)
      .foregroundStyle(.red)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color.red.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 10)
      )
  }
}

private struct TrackerProjectionView: View {
  let trackers: [TrackerDisplayState]
  let baseStations: [SimulatorBaseStation]
  let projection: SimulatorStageProjection
  let workspace: SimulatorWorkspaceDimensions
  @Binding var selectedTrackerID: String?
  let isEditable: Bool
  let clampsToWorkspace: Bool
  let onMoveBegan: (String, Vector3) -> Void
  let onMoveChanged: (String, Vector3) -> Void
  let onMoveEnded: (String) -> Void
  @State private var dragState: TrackerDragState?

  var body: some View {
    GeometryReader { geometry in
      let transform = SimulatorStageTransform(
        projection: projection,
        workspace: workspace,
        size: geometry.size
      )

      Canvas { context, size in
        drawGrid(
          context: &context,
          transform: transform
        )
        for baseStation in baseStations {
          draw(
            baseStation,
            context: &context,
            transform: transform
          )
        }
        for tracker in trackers {
          draw(
            displayedTracker(tracker),
            context: &context,
            transform: transform
          )
        }
      }
      .contentShape(Rectangle())
      .gesture(
        dragGesture(transform: transform),
        including: isEditable ? .all : .none
      )
    }
    .background {
      ZStack {
        Color(nsColor: .controlBackgroundColor)
        RadialGradient(
          colors: [
            Color.accentColor.opacity(0.09),
            Color.clear,
          ],
          center: .topLeading,
          startRadius: 0,
          endRadius: 620
        )
      }
    }
    .help(
      isEditable
        ? "Trackerをドラッグして\(projection.displayName)の2軸を移動"
        : "直接操作はSimulator実行中のみ利用できます"
    )
  }

  private func drawGrid(
    context: inout GraphicsContext,
    transform: SimulatorStageTransform
  ) {
    let plotRect = transform.plotRect
    var grid = Path()

    for value in gridValues(
      in: transform.horizontalRange,
      step: transform.gridStepMeters
    ) {
      let x =
        plotRect.minX
        + CGFloat(value - transform.horizontalRange.lowerBound)
        * transform.scale
      grid.move(to: CGPoint(x: x, y: plotRect.minY))
      grid.addLine(to: CGPoint(x: x, y: plotRect.maxY))
    }
    for value in gridValues(
      in: transform.verticalRange,
      step: transform.gridStepMeters
    ) {
      let y =
        plotRect.maxY
        - CGFloat(value - transform.verticalRange.lowerBound)
        * transform.scale
      grid.move(to: CGPoint(x: plotRect.minX, y: y))
      grid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
    }

    context.stroke(
      grid,
      with: .color(.secondary.opacity(0.1)),
      lineWidth: 1
    )

    context.stroke(
      Path(roundedRect: plotRect, cornerRadius: 2),
      with: .color(.secondary.opacity(0.18)),
      lineWidth: 1
    )

    var axes = Path()
    if transform.horizontalRange.contains(0) {
      let x =
        plotRect.minX
        + CGFloat(-transform.horizontalRange.lowerBound)
        * transform.scale
      axes.move(to: CGPoint(x: x, y: plotRect.minY))
      axes.addLine(to: CGPoint(x: x, y: plotRect.maxY))
    }
    if transform.verticalRange.contains(0) {
      let y =
        plotRect.maxY
        + CGFloat(transform.verticalRange.lowerBound)
        * transform.scale
      axes.move(to: CGPoint(x: plotRect.minX, y: y))
      axes.addLine(to: CGPoint(x: plotRect.maxX, y: y))
    }
    context.stroke(
      axes,
      with: .color(.secondary.opacity(0.28)),
      lineWidth: 1.5
    )

    let label = String(
      format: "grid %.3g m",
      transform.gridStepMeters
    )
    context.draw(
      Text(label)
        .font(.caption2.monospaced())
        .foregroundStyle(.tertiary),
      at: CGPoint(x: plotRect.minX, y: plotRect.maxY + 10),
      anchor: .topLeading
    )
  }

  private func draw(
    _ baseStation: SimulatorBaseStation,
    context: inout GraphicsContext,
    transform: SimulatorStageTransform
  ) {
    let point = transform.point(for: baseStation.position)
    let target = transform.point(for: baseStation.target)
    var direction = Path()
    direction.move(to: point)
    direction.addLine(to: target)
    context.stroke(
      direction,
      with: .color(.orange.opacity(0.28)),
      style: StrokeStyle(lineWidth: 1, dash: [4, 5])
    )

    let marker = CGRect(
      x: point.x - 7,
      y: point.y - 7,
      width: 14,
      height: 14
    )
    context.fill(
      Path(roundedRect: marker, cornerRadius: 3),
      with: .color(.black.opacity(0.72))
    )
    context.stroke(
      Path(roundedRect: marker, cornerRadius: 3),
      with: .color(.orange.opacity(0.9)),
      lineWidth: 1.5
    )
    context.draw(
      Text(baseStation.displayName)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary),
      at: CGPoint(x: point.x, y: point.y - 11),
      anchor: .bottom
    )
  }

  private func draw(
    _ tracker: TrackerDisplayState,
    context: inout GraphicsContext,
    transform: SimulatorStageTransform
  ) {
    let point = transform.point(for: tracker.position)
    let isSelected = selectedTrackerID == tracker.id
    let isDragging = dragState?.trackerID == tracker.id
    let diameter: CGFloat = isSelected ? 20 : 14
    let marker = CGRect(
      x: point.x - diameter / 2,
      y: point.y - diameter / 2,
      width: diameter,
      height: diameter
    )

    if isSelected {
      drawAxisGuides(
        context: &context,
        point: point,
        isDragging: isDragging
      )
      let halo = marker.insetBy(dx: -7, dy: -7)
      context.fill(
        Path(ellipseIn: halo),
        with: .color(
          Color.accentColor.opacity(isDragging ? 0.24 : 0.15)
        )
      )
    }

    context.fill(
      Path(ellipseIn: marker),
      with: .color(tracker.trackingState.displayColor)
    )
    context.stroke(
      Path(ellipseIn: marker),
      with: .color(.white.opacity(0.92)),
      lineWidth: 2
    )
    if isSelected || trackers.count <= 8 {
      context.draw(
        Text(tracker.role.isEmpty ? "未割当" : tracker.role)
          .font(.caption.weight(isSelected ? .semibold : .medium))
          .foregroundStyle(.primary),
        at: CGPoint(x: point.x, y: point.y - diameter / 2 - 8),
        anchor: .bottom
      )
    }
  }

  private func drawAxisGuides(
    context: inout GraphicsContext,
    point: CGPoint,
    isDragging: Bool
  ) {
    let length: CGFloat = isDragging ? 30 : 22
    var horizontal = Path()
    horizontal.move(to: CGPoint(x: point.x - length, y: point.y))
    horizontal.addLine(to: CGPoint(x: point.x + length, y: point.y))
    context.stroke(
      horizontal,
      with: .color(horizontalAxisColor.opacity(isDragging ? 0.9 : 0.55)),
      lineWidth: isDragging ? 2.5 : 1.5
    )

    var vertical = Path()
    vertical.move(to: CGPoint(x: point.x, y: point.y - length))
    vertical.addLine(to: CGPoint(x: point.x, y: point.y + length))
    context.stroke(
      vertical,
      with: .color(verticalAxisColor.opacity(isDragging ? 0.9 : 0.55)),
      lineWidth: isDragging ? 2.5 : 1.5
    )
  }

  private var horizontalAxisColor: Color {
    switch projection {
    case .top, .front: .red
    case .side: .blue
    }
  }

  private var verticalAxisColor: Color {
    switch projection {
    case .top: .blue
    case .front, .side: .green
    }
  }

  private func displayedTracker(
    _ tracker: TrackerDisplayState
  ) -> TrackerDisplayState {
    guard let dragState, dragState.trackerID == tracker.id else {
      return tracker
    }
    return TrackerDisplayState(
      id: tracker.id,
      role: tracker.role,
      position: dragState.latestPosition,
      orientation: tracker.orientation,
      trackingState: tracker.trackingState,
      trackingReason: tracker.trackingReason,
      liveness: tracker.liveness,
      ageMilliseconds: tracker.ageMilliseconds,
      frameSequence: tracker.frameSequence
    )
  }

  private func dragGesture(
    transform: SimulatorStageTransform
  ) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        if dragState == nil {
          guard
            let tracker = hitTest(
              at: value.startLocation,
              transform: transform
            )
          else {
            return
          }
          selectedTrackerID = tracker.id
          dragState = TrackerDragState(
            trackerID: tracker.id,
            originalPosition: tracker.position,
            latestPosition: tracker.position
          )
          onMoveBegan(tracker.id, tracker.position)
        }

        guard var dragState else { return }
        let didMove =
          abs(value.translation.width) > 0.1
          || abs(value.translation.height) > 0.1
        guard didMove else { return }

        let originalPoint = transform.point(
          for: dragState.originalPosition
        )
        let targetPoint = CGPoint(
          x: originalPoint.x + value.translation.width,
          y: originalPoint.y + value.translation.height
        )
        let position = transform.position(
          at: targetPoint,
          preserving: dragState.originalPosition,
          clampsToWorkspace: clampsToWorkspace
        )
        dragState.latestPosition = position
        self.dragState = dragState
        onMoveChanged(dragState.trackerID, position)
      }
      .onEnded { _ in
        guard let dragState else { return }
        onMoveEnded(dragState.trackerID)
        self.dragState = nil
      }
  }

  private func hitTest(
    at point: CGPoint,
    transform: SimulatorStageTransform
  ) -> TrackerDisplayState? {
    trackers
      .map { tracker in
        (
          tracker: tracker,
          distance: hypot(
            transform.point(for: tracker.position).x - point.x,
            transform.point(for: tracker.position).y - point.y
          )
        )
      }
      .filter { $0.distance <= 22 }
      .sorted {
        if $0.distance == $1.distance {
          return $0.tracker.id == selectedTrackerID
        }
        return $0.distance < $1.distance
      }
      .first?
      .tracker
  }

  private func gridValues(
    in range: ClosedRange<Double>,
    step: Double
  ) -> [Double] {
    guard step.isFinite, step > 0 else { return [] }
    var value = ceil(range.lowerBound / step) * step
    var values: [Double] = []
    while value <= range.upperBound + step * 0.000_001,
      values.count < 200
    {
      values.append(abs(value) < step * 0.000_001 ? 0 : value)
      value += step
    }
    return values
  }
}

private struct TrackerDragState {
  let trackerID: String
  let originalPosition: Vector3
  var latestPosition: Vector3
}

extension HubInputSource {
  fileprivate var shortDisplayName: String {
    switch self {
    case .network: "UDP受信"
    case .simulator: "Simulator"
    }
  }
}

extension HubAppMotionPreset {
  fileprivate var systemImage: String {
    switch self {
    case .stationary: "pause.circle"
    case .circle: "arrow.triangle.2.circlepath"
    case .walk: "figure.walk"
    case .jump: "arrow.up.circle"
    case .random: "shuffle"
    }
  }
}

extension TrackingState {
  fileprivate var hasUsablePose: Bool {
    self == .tracking || self == .simulated
  }

  fileprivate var displayName: String {
    switch self {
    case .unknown: "不明"
    case .tracking: "追跡中"
    case .lost: "追跡喪失"
    case .disconnected: "未接続"
    case .simulated: "シミュレーション"
    }
  }

  fileprivate var displayColor: Color {
    switch self {
    case .unknown: .secondary
    case .tracking: .green
    case .lost: .orange
    case .disconnected: .red
    case .simulated: .cyan
    }
  }

  fileprivate var statusSymbol: String {
    switch self {
    case .unknown: "questionmark.circle.fill"
    case .tracking: "checkmark.circle.fill"
    case .lost: "exclamationmark.circle.fill"
    case .disconnected: "xmark.circle.fill"
    case .simulated: "waveform.circle.fill"
    }
  }
}
