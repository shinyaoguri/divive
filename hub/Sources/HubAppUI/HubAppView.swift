import HubProtocol
import HubSimulator
import SwiftUI

public struct HubAppView: View {
  @ObservedObject private var model: HubAppModel
  @State private var showsConfiguration = false
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

          SourceActionButton(model: model)
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
        selectedTrackerID: selectedTrackerID ?? model.trackers.first?.id
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
  let selectedTrackerID: String?

  var body: some View {
    ZStack {
      TrackerTopDownView(
        trackers: model.trackers,
        source: model.displayedSource,
        selectedTrackerID: selectedTrackerID
      )
      .accessibilityIdentifier("tracker-space-preview")

      VStack {
        HStack(alignment: .top) {
          StageStatusPill(model: model)
          Spacer()
          CoordinateLegend()
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

private struct CoordinateLegend: View {
  var body: some View {
    Text("X →   −Z ↑   ±2 m")
      .font(.caption.monospaced())
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .frame(height: 30)
      .background(
        Color(nsColor: .controlBackgroundColor).opacity(0.82),
        in: Capsule()
      )
      .accessibilityLabel("表示範囲は前後左右2メートル")
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
          SelectedTrackerPanel(tracker: selectedTracker)
        }
      }

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

  private let columns = [
    GridItem(.flexible(), spacing: 7),
    GridItem(.flexible(), spacing: 7),
  ]

  var body: some View {
    LazyVGrid(
      columns: columns,
      alignment: .leading,
      spacing: 7
    ) {
      ForEach(trackers.prefix(16)) { tracker in
        Button {
          onSelect(tracker.id)
        } label: {
          TrackerTile(
            tracker: tracker,
            isSelected: selectedTrackerID == tracker.id
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
    .frame(maxWidth: .infinity, minHeight: 36)
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

      LabeledContent("最終更新") {
        Text(String(format: "%.0f ms前", tracker.ageMilliseconds))
          .monospacedDigit()
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .contain)
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
          title: "生成",
          value: "\(model.attemptedFrames)"
        ),
        DiagnosticItem(
          title: "出力",
          value: "\(model.emittedFrames)"
        ),
        DiagnosticItem(
          title: "欠落率",
          value: String(format: "%.1f%%", model.droppedPercent)
        ),
        DiagnosticItem(
          title: "期限超過",
          value: "\(model.missedDeadlines)"
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
      model.droppedFrames > 0 || model.missedDeadlines > 0
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

      Slider(value: $value, in: 0...50, step: 0.5)
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

private struct TrackerTopDownView: View {
  let trackers: [TrackerDisplayState]
  let source: HubInputSource
  let selectedTrackerID: String?
  private let visibleHalfRange = 2.0

  var body: some View {
    Canvas { context, size in
      drawGrid(context: &context, size: size)
      for tracker in trackers {
        draw(tracker, context: &context, size: size)
      }
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
  }

  private func drawGrid(
    context: inout GraphicsContext,
    size: CGSize
  ) {
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let scale = min(size.width, size.height) / (visibleHalfRange * 2)
    var grid = Path()

    for meter in -2...2 {
      let offset = CGFloat(meter) * scale
      grid.move(to: CGPoint(x: center.x + offset, y: 0))
      grid.addLine(
        to: CGPoint(x: center.x + offset, y: size.height)
      )
      grid.move(to: CGPoint(x: 0, y: center.y + offset))
      grid.addLine(
        to: CGPoint(x: size.width, y: center.y + offset)
      )
    }

    context.stroke(
      grid,
      with: .color(.secondary.opacity(0.1)),
      lineWidth: 1
    )

    var axes = Path()
    axes.move(to: CGPoint(x: center.x, y: 0))
    axes.addLine(to: CGPoint(x: center.x, y: size.height))
    axes.move(to: CGPoint(x: 0, y: center.y))
    axes.addLine(to: CGPoint(x: size.width, y: center.y))
    context.stroke(
      axes,
      with: .color(.secondary.opacity(0.28)),
      lineWidth: 1.5
    )
  }

  private func draw(
    _ tracker: TrackerDisplayState,
    context: inout GraphicsContext,
    size: CGSize
  ) {
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let scale = min(size.width, size.height) / (visibleHalfRange * 2)
    let point = CGPoint(
      x: center.x + CGFloat(tracker.position.x) * scale,
      y: center.y + CGFloat(tracker.position.z) * scale
    )
    let isSelected = selectedTrackerID == tracker.id
    let diameter: CGFloat = isSelected ? 20 : 14
    let marker = CGRect(
      x: point.x - diameter / 2,
      y: point.y - diameter / 2,
      width: diameter,
      height: diameter
    )

    if isSelected {
      let halo = marker.insetBy(dx: -7, dy: -7)
      context.fill(
        Path(ellipseIn: halo),
        with: .color(Color.accentColor.opacity(0.15))
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
