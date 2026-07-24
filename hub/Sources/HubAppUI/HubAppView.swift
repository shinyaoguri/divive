import HubProtocol
import HubSimulator
import SwiftUI

public struct HubAppView: View {
  @StateObject private var model: HubAppModel
  @State private var showsConfiguration = false
  @State private var showsDiagnostics = false

  public init() {
    _model = StateObject(wrappedValue: HubAppModel())
  }

  public var body: some View {
    NavigationStack {
      HubDashboardView(model: model)
        .navigationTitle("Divive Hub")
        .toolbar {
          ToolbarItem(placement: .navigation) {
            SourcePicker(model: model)
          }

          ToolbarItemGroup(placement: .primaryAction) {
            Button {
              showsConfiguration.toggle()
            } label: {
              Label("設定", systemImage: "slider.horizontal.3")
            }
            .help("入力とSimulatorの設定")
            .accessibilityIdentifier("configuration-button")
            .popover(
              isPresented: $showsConfiguration,
              arrowEdge: .top
            ) {
              SourceConfigurationPanel(model: model)
            }
            .diviveGlassButton()

            Button {
              showsDiagnostics.toggle()
            } label: {
              Label("診断", systemImage: "waveform.path.ecg")
            }
            .help("通信とSimulatorの診断情報")
            .accessibilityIdentifier("diagnostics-button")
            .popover(
              isPresented: $showsDiagnostics,
              arrowEdge: .top
            ) {
              DiagnosticsPopover(model: model)
            }
            .diviveGlassButton()

            StartSourceButton(model: model)

            if model.isRunning {
              StopSourceButton(model: model)
            }
          }
        }
    }
    .frame(minWidth: 1_120, minHeight: 700)
    .task {
      await model.refreshUntilCancelled()
    }
  }
}

private struct SourcePicker: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    Picker("入力", selection: $model.selectedSource) {
      ForEach(HubInputSource.allCases) { source in
        Text(source.displayName)
          .tag(source)
      }
    }
    .pickerStyle(.menu)
    .frame(width: 150)
    .accessibilityIdentifier("source-picker")
  }
}

private struct StartSourceButton: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    Button {
      Task { await model.startSelectedSource() }
    } label: {
      Label(
        model.startButtonTitle,
        systemImage: model.isRunning
          ? "arrow.clockwise"
          : "play.fill"
      )
    }
    .help(
      model.isRunning
        ? "現在の設定を反映して再起動"
        : "選択した入力を開始"
    )
    .accessibilityIdentifier("source-start-button")
    .diviveGlassProminentButton()
  }
}

private struct StopSourceButton: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    Button(role: .destructive) {
      Task { await model.stopActiveSource() }
    } label: {
      Label("停止", systemImage: "stop.fill")
        .labelStyle(.iconOnly)
    }
    .help("入力を停止")
    .accessibilityIdentifier("source-stop-button")
    .diviveGlassButton()
  }
}

private struct HubDashboardView: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      DashboardHeader(model: model)

      HStack(spacing: 16) {
        SpatialPreviewPanel(model: model)
          .layoutPriority(1)

        TrackerGridPanel(model: model)
          .frame(width: 440)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 20)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct DashboardHeader: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    HStack(spacing: 20) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 9) {
          Image(systemName: "scope")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.tint)

          Text("Tracker空間")
            .font(.title2.weight(.semibold))
        }

        Text(headerSubtitle)
          .font(.subheadline)
          .foregroundStyle(
            model.errorMessage == nil ? .secondary : Color.red
          )
          .lineLimit(1)
      }

      Spacer(minLength: 16)

      HeaderMetric(
        title: "更新レート",
        value: String(format: "%.1f Hz", model.observedRateHz),
        systemImage: "waveform.path"
      )

      Divider()
        .frame(height: 34)

      HeaderMetric(
        title: "Tracker",
        value: "\(model.trackers.count) 台",
        systemImage: "dot.radiowaves.left.and.right"
      )

      StatusBadge(
        title: model.statusTitle,
        isActive: model.isRunning
      )
    }
    .frame(height: 54)
  }

  private var headerSubtitle: String {
    model.errorMessage ?? model.dashboardSubtitle
  }
}

private struct HeaderMetric: View {
  let title: String
  let value: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: systemImage)
        .foregroundStyle(.tint)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.headline.monospacedDigit())
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct StatusBadge: View {
  let title: String
  let isActive: Bool

  var body: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(isActive ? Color.green : Color.secondary)
        .frame(width: 7, height: 7)

      Text(title)
        .font(.caption.weight(.medium))
        .lineLimit(1)
    }
    .foregroundStyle(isActive ? .primary : .secondary)
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .background(
      isActive
        ? Color.green.opacity(0.12)
        : Color.secondary.opacity(0.09),
      in: Capsule()
    )
    .accessibilityElement(children: .combine)
  }
}

private struct SpatialPreviewPanel: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    ContentSurface {
      VStack(alignment: .leading, spacing: 14) {
        PanelHeader(
          title: "空間プレビュー",
          subtitle: "上面図  X / -Z  ·  表示範囲 ±2m",
          systemImage: "viewfinder"
        ) {
          Text(model.summaryText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        TrackerTopDownView(
          trackers: model.trackers,
          source: model.displayedSource
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("tracker-space-preview")
      }
    }
  }
}

private struct TrackerGridPanel: View {
  @ObservedObject var model: HubAppModel

  private var columns: [GridItem] {
    let count = model.trackers.count > 8 ? 2 : 1
    return Array(
      repeating: GridItem(.flexible(), spacing: 8),
      count: count
    )
  }

  var body: some View {
    ContentSurface {
      VStack(alignment: .leading, spacing: 12) {
        PanelHeader(
          title: "Tracker",
          subtitle: "正規化済みlatest state",
          systemImage: "sensor.tag.radiowaves.forward"
        ) {
          TrackerStateSummary(trackers: model.trackers)
        }

        if model.trackers.isEmpty {
          ContentUnavailableView(
            "Trackerがありません",
            systemImage: "dot.radiowaves.left.and.right",
            description: Text(
              model.displayedSource == .simulator
                ? "ツールバーからSimulatorを開始してください。"
                : "UDP受信を開始し、Bridgeを接続してください。"
            )
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: 7
          ) {
            ForEach(model.trackers.prefix(16)) { tracker in
              TrackerCompactCard(tracker: tracker)
            }
          }
          .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
          )
          .accessibilityIdentifier("tracker-grid")
        }
      }
    }
  }
}

private struct TrackerCompactCard: View {
  let tracker: TrackerDisplayState

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Circle()
          .fill(tracker.trackingState.displayColor)
          .frame(width: 7, height: 7)
          .accessibilityLabel(tracker.trackingState.displayName)

        Text(tracker.role.isEmpty ? "未割当" : tracker.role)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)

        Spacer(minLength: 4)

        Text(String(format: "%.0f ms", tracker.ageMilliseconds))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      Text(tracker.id)
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)

      Text(positionText)
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    .background(
      Color.secondary.opacity(0.065),
      in: RoundedRectangle(cornerRadius: 11)
    )
    .accessibilityElement(children: .combine)
  }

  private var positionText: String {
    String(
      format: "x %.2f  y %.2f  z %.2f",
      tracker.position.x,
      tracker.position.y,
      tracker.position.z
    )
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
        "\(attentionCount)件を確認",
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
      PopoverHeader(
        title: "入力設定",
        subtitle: "変更は開始または再起動時に反映",
        systemImage: "slider.horizontal.3"
      )

      Picker("入力", selection: $model.selectedSource) {
        ForEach(HubInputSource.allCases) { source in
          Label(source.displayName, systemImage: source.systemImage)
            .tag(source)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("configuration-source-picker")

      Divider()

      if model.selectedSource == .simulator {
        SimulatorConfiguration(model: model)
      } else {
        NetworkConfiguration(model: model)
      }

      if let errorMessage = model.errorMessage {
        ErrorBanner(message: errorMessage)
      }
    }
    .padding(20)
    .frame(width: 350)
  }
}

private struct SimulatorConfiguration: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ConfigurationSectionTitle("シーン")

      LabeledContent {
        Stepper(
          "\(model.trackerCount) 台",
          value: $model.trackerCount,
          in: 1...16
        )
        .fixedSize()
      } label: {
        Label(
          "Tracker",
          systemImage: "dot.radiowaves.left.and.right"
        )
      }

      LabeledContent {
        Picker("モーション", selection: $model.motion) {
          ForEach(HubAppMotionPreset.allCases) { motion in
            Label(motion.displayName, systemImage: motion.systemImage)
              .tag(motion)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 140, alignment: .trailing)
        .accessibilityIdentifier("motion-picker")
      } label: {
        Label("モーション", systemImage: model.motion.systemImage)
      }

      LabeledContent {
        Picker("更新頻度", selection: $model.rate) {
          ForEach(SimulatorRate.allCases, id: \.rawValue) { rate in
            Text("\(rate.rawValue) Hz").tag(rate)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 90, alignment: .trailing)
      } label: {
        Label("更新頻度", systemImage: "waveform.path")
      }

      Divider()

      ConfigurationSectionTitle("障害注入")

      LabeledContent {
        TextField("Seed", text: $model.seedText)
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .frame(width: 92)
      } label: {
        Label("再現用Seed", systemImage: "number")
      }

      FaultControl(
        title: "Frame loss",
        value: $model.frameLossPercent
      )

      FaultControl(
        title: "Tracking lost",
        value: $model.trackingLostPercent
      )
    }
  }
}

private struct NetworkConfiguration: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ConfigurationSectionTitle("UDP Listener")

      LabeledContent {
        TextField("Bind address", text: $model.networkBindHost)
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .frame(width: 150)
      } label: {
        Label("Address", systemImage: "network")
      }

      LabeledContent {
        TextField("UDP port", text: $model.networkPortText)
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .frame(width: 90)
      } label: {
        Label("Port", systemImage: "number")
      }

      Text("LAN受信は0.0.0.0、Mac内の試験は127.0.0.1")
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

private struct DiagnosticsPopover: View {
  @ObservedObject var model: HubAppModel

  private var items: [DiagnosticItem] {
    switch model.displayedSource {
    case .simulator:
      [
        DiagnosticItem(
          title: "Attempted",
          value: "\(model.attemptedFrames)"
        ),
        DiagnosticItem(
          title: "Emitted",
          value: "\(model.emittedFrames)"
        ),
        DiagnosticItem(
          title: "Frame loss",
          value: String(format: "%.1f%%", model.droppedPercent)
        ),
        DiagnosticItem(
          title: "Deadline miss",
          value: "\(model.missedDeadlines)"
        ),
      ]
    case .network:
      [
        DiagnosticItem(
          title: "Datagram",
          value: "\(model.receivedDatagrams)"
        ),
        DiagnosticItem(
          title: "Valid",
          value: "\(model.validPackets)"
        ),
        DiagnosticItem(
          title: "欠落Frame",
          value: "\(model.missingFrames)"
        ),
        DiagnosticItem(
          title: "順序逆転",
          value: "\(model.outOfOrderPackets)"
        ),
        DiagnosticItem(
          title: "受信異常",
          value: "\(model.networkAnomalyCount)"
        ),
        DiagnosticItem(
          title: "受信処理",
          value: "\(model.lastProcessingMicroseconds) µs"
        ),
      ]
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      PopoverHeader(
        title: "診断情報",
        subtitle: model.displayedSource.displayName,
        systemImage: "waveform.path.ecg"
      )

      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 10),
          GridItem(.flexible(), spacing: 10),
        ],
        spacing: 10
      ) {
        ForEach(items) { item in
          DiagnosticValue(item: item)
        }
      }

      if model.activeSource == .network,
        let endpoint = model.boundEndpoint
      {
        Label(endpoint, systemImage: "network")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(20)
    .frame(width: 370)
  }
}

private struct PopoverHeader: View {
  let title: String
  let subtitle: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.tint)
        .frame(width: 34, height: 34)
        .background(
          Color.accentColor.opacity(0.1),
          in: RoundedRectangle(cornerRadius: 10)
        )

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
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
    VStack(alignment: .leading, spacing: 4) {
      Text(item.title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(item.value)
        .font(.title3.monospacedDigit().weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color.secondary.opacity(0.065),
      in: RoundedRectangle(cornerRadius: 11)
    )
  }
}

private struct PanelHeader<Trailing: View>: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let trailing: Trailing

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.trailing = trailing()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 11) {
      Image(systemName: systemImage)
        .font(.headline)
        .foregroundStyle(.tint)
        .frame(width: 28, height: 28)
        .background(
          Color.accentColor.opacity(0.1),
          in: RoundedRectangle(cornerRadius: 8)
        )

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
      trailing
    }
  }
}

private struct ContentSurface<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        .regularMaterial,
        in: RoundedRectangle(cornerRadius: 18)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .stroke(.quaternary, lineWidth: 1)
      }
  }
}

private struct TrackerTopDownView: View {
  let trackers: [TrackerDisplayState]
  let source: HubInputSource
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
        LinearGradient(
          colors: [
            Color.accentColor.opacity(0.07),
            Color.clear,
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
      .clipShape(RoundedRectangle(cornerRadius: 13))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 13)
        .stroke(.quaternary, lineWidth: 1)
    }
    .overlay {
      if trackers.isEmpty {
        ContentUnavailableView(
          "Trackerがありません",
          systemImage: "dot.radiowaves.left.and.right",
          description: Text(
            source == .simulator
              ? "ツールバーからSimulatorを開始してください。"
              : "UDP受信を開始し、Bridgeを接続してください。"
          )
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
      with: .color(.secondary.opacity(0.12)),
      lineWidth: 1
    )

    var axes = Path()
    axes.move(to: CGPoint(x: center.x, y: 0))
    axes.addLine(to: CGPoint(x: center.x, y: size.height))
    axes.move(to: CGPoint(x: 0, y: center.y))
    axes.addLine(to: CGPoint(x: size.width, y: center.y))
    context.stroke(
      axes,
      with: .color(.secondary.opacity(0.35)),
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
    let marker = CGRect(
      x: point.x - 8,
      y: point.y - 8,
      width: 16,
      height: 16
    )
    context.fill(
      Path(ellipseIn: marker),
      with: .color(tracker.trackingState.displayColor)
    )
    context.stroke(
      Path(ellipseIn: marker),
      with: .color(.white.opacity(0.9)),
      lineWidth: 2
    )
    context.draw(
      Text(tracker.role.isEmpty ? "未割当" : tracker.role)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary),
      at: CGPoint(x: point.x, y: point.y - 19),
      anchor: .bottom
    )
  }
}

private struct GlassButtonModifier: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        content.buttonStyle(.glass)
      } else {
        content.buttonStyle(.bordered)
      }
    #else
      content.buttonStyle(.bordered)
    #endif
  }
}

private struct GlassProminentButtonModifier: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        content.buttonStyle(.glassProminent)
      } else {
        content.buttonStyle(.borderedProminent)
      }
    #else
      content.buttonStyle(.borderedProminent)
    #endif
  }
}

extension View {
  fileprivate func diviveGlassButton() -> some View {
    modifier(GlassButtonModifier())
  }

  fileprivate func diviveGlassProminentButton() -> some View {
    modifier(GlassProminentButtonModifier())
  }
}

extension HubInputSource {
  fileprivate var systemImage: String {
    switch self {
    case .network: "network"
    case .simulator: "sparkles"
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
    case .unknown: "Unknown"
    case .tracking: "Tracking"
    case .lost: "Lost"
    case .disconnected: "Disconnected"
    case .simulated: "Simulated"
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
}
