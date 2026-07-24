import HubProtocol
import HubSimulator
import SwiftUI

public struct HubAppView: View {
  @StateObject private var model: HubAppModel

  public init() {
    _model = StateObject(wrappedValue: HubAppModel())
  }

  public var body: some View {
    NavigationSplitView {
      SourceSidebarView(model: model)
        .navigationSplitViewColumnWidth(
          min: 250,
          ideal: 280,
          max: 320
        )
    } detail: {
      HubDashboardView(model: model)
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 1_000, minHeight: 680)
    .task {
      await model.refreshUntilCancelled()
    }
  }
}

private struct SourceSidebarView: View {
  @ObservedObject var model: HubAppModel
  @State private var showsAdvancedSettings = false

  var body: some View {
    VStack(spacing: 0) {
      SidebarHeader(model: model)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          SourceSelection(model: model)

          if model.selectedSource == .simulator {
            SimulatorSettings(
              model: model,
              showsAdvancedSettings: $showsAdvancedSettings
            )
          } else {
            NetworkSettings(model: model)
          }

          if let errorMessage = model.errorMessage {
            ErrorBanner(message: errorMessage)
          }
        }
        .padding(16)
      }

      Divider()

      SourceActions(model: model)
        .padding(16)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .navigationTitle("Divive Hub")
  }
}

private struct SidebarHeader: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: "scope")
          .font(.title2.weight(.semibold))
          .foregroundStyle(.white)
          .frame(width: 38, height: 38)
          .background(.tint, in: RoundedRectangle(cornerRadius: 11))

        VStack(alignment: .leading, spacing: 2) {
          Text("Divive Hub")
            .font(.headline)
          Text("Tracker workspace")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      StatusPill(
        title: model.statusTitle,
        isActive: model.isRunning
      )

      if model.activeSource == .network,
        let endpoint = model.boundEndpoint
      {
        Label(endpoint, systemImage: "network")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(18)
  }
}

private struct StatusPill: View {
  let title: String
  let isActive: Bool

  var body: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(isActive ? Color.green : Color.secondary)
        .frame(width: 7, height: 7)
      Text(title)
        .font(.caption.weight(.medium))
    }
    .foregroundStyle(isActive ? .primary : .secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      isActive ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1),
      in: Capsule()
    )
    .accessibilityElement(children: .combine)
  }
}

private struct SourceSelection: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SidebarSectionTitle("入力")

      Picker("入力Source", selection: $model.selectedSource) {
        ForEach(HubInputSource.allCases) { source in
          Label(source.displayName, systemImage: source.systemImage)
            .tag(source)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .accessibilityIdentifier("source-picker")
    }
  }
}

private struct SimulatorSettings: View {
  @ObservedObject var model: HubAppModel
  @Binding var showsAdvancedSettings: Bool

  var body: some View {
    SettingsSurface(
      title: "シーン",
      systemImage: "sparkles"
    ) {
      LabeledContent {
        Stepper(
          "\(model.trackerCount) 台",
          value: $model.trackerCount,
          in: 1...16
        )
        .fixedSize()
      } label: {
        Label("Tracker", systemImage: "dot.radiowaves.left.and.right")
      }

      SettingsDivider()

      LabeledContent {
        Picker("Motion", selection: $model.motion) {
          ForEach(HubAppMotionPreset.allCases) { motion in
            Label(motion.displayName, systemImage: motion.systemImage)
              .tag(motion)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 130, alignment: .trailing)
        .accessibilityIdentifier("motion-picker")
      } label: {
        Label("Motion", systemImage: model.motion.systemImage)
      }

      SettingsDivider()

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
        Label("更新頻度", systemImage: "waveform.path.ecg")
      }
    }

    SettingsSurface {
      DisclosureGroup(
        isExpanded: $showsAdvancedSettings
      ) {
        VStack(spacing: 14) {
          LabeledContent {
            TextField("Seed", text: $model.seedText)
              .textFieldStyle(.roundedBorder)
              .multilineTextAlignment(.trailing)
              .frame(width: 88)
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
        .padding(.top, 14)
      } label: {
        Label("詳細設定", systemImage: "slider.horizontal.3")
          .font(.subheadline.weight(.medium))
      }
    }
  }
}

private struct FaultControl: View {
  let title: String
  @Binding var value: Double

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
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

private struct NetworkSettings: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    SettingsSurface(
      title: "UDP Listener",
      systemImage: "network"
    ) {
      LabeledContent {
        TextField("Bind address", text: $model.networkBindHost)
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .frame(width: 125)
      } label: {
        Text("Address")
      }

      SettingsDivider()

      LabeledContent {
        TextField("UDP port", text: $model.networkPortText)
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.trailing)
          .frame(width: 80)
      } label: {
        Text("Port")
      }

      Text("LAN受信は0.0.0.0、Mac内の試験は127.0.0.1")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct SourceActions: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    HStack(spacing: 8) {
      Button {
        Task { await model.startSelectedSource() }
      } label: {
        Label(
          model.startButtonTitle,
          systemImage: model.isRunning
            ? "arrow.clockwise"
            : "play.fill"
        )
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .accessibilityIdentifier("source-start-button")

      if model.isRunning {
        Button(role: .destructive) {
          Task { await model.stopActiveSource() }
        } label: {
          Image(systemName: "stop.fill")
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help("停止")
        .accessibilityLabel("停止")
        .accessibilityIdentifier("source-stop-button")
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
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }
}

private struct SidebarSectionTitle: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title.uppercased())
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .tracking(0.8)
  }
}

private struct SettingsSurface<Content: View>: View {
  let title: String?
  let systemImage: String?
  let content: Content

  init(
    title: String? = nil,
    systemImage: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      if let title, let systemImage {
        Label(title, systemImage: systemImage)
          .font(.subheadline.weight(.semibold))
      }
      content
    }
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(.quaternary, lineWidth: 1)
    }
  }
}

private struct SettingsDivider: View {
  var body: some View {
    Divider()
      .opacity(0.55)
  }
}

private struct HubDashboardView: View {
  @ObservedObject var model: HubAppModel
  @State private var showsDiagnostics = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        DashboardHeader(model: model)
        HubSummaryBar(model: model)
        SpatialPreviewPanel(model: model)
        TrackerListPanel(model: model)
        DiagnosticsPanel(
          model: model,
          isExpanded: $showsDiagnostics
        )
      }
      .padding(.horizontal, 24)
      .padding(.top, 48)
      .padding(.bottom, 24)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct DashboardHeader: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Tracker Space")
          .font(.largeTitle.weight(.semibold))
        Text(model.dashboardSubtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Label(
        model.displayedSource.displayName,
        systemImage: model.displayedSource.systemImage
      )
      .font(.subheadline.weight(.medium))
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(.regularMaterial, in: Capsule())
    }
  }
}

private struct HubSummaryBar: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    DashboardSurface {
      HStack(spacing: 18) {
        SummaryValue(
          title: "更新レート",
          value: String(format: "%.1f Hz", model.observedRateHz),
          systemImage: "waveform.path.ecg"
        )

        Divider()
          .frame(height: 32)

        SummaryValue(
          title: "Tracker",
          value: "\(model.trackers.count) 台",
          systemImage: "dot.radiowaves.left.and.right"
        )

        Spacer()

        Text(model.summaryText)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct SummaryValue: View {
  let title: String
  let value: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 26)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.headline.monospacedDigit())
      }
    }
  }
}

private struct SpatialPreviewPanel: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    DashboardSurface {
      VStack(alignment: .leading, spacing: 14) {
        PanelHeader(
          title: "空間プレビュー",
          subtitle: "上面図  X / -Z  ·  表示範囲 ±2m",
          systemImage: "viewfinder"
        ) {
          EmptyView()
        }

        TrackerTopDownView(
          trackers: model.trackers,
          source: model.displayedSource
        )
        .frame(minHeight: 350)
        .accessibilityIdentifier("tracker-space-preview")
      }
    }
  }
}

private struct TrackerListPanel: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    DashboardSurface {
      VStack(alignment: .leading, spacing: 14) {
        PanelHeader(
          title: "Tracker",
          subtitle: "最新の正規化済みpose",
          systemImage: "list.bullet"
        ) {
          TrackerStateSummary(trackers: model.trackers)
        }

        TrackerTable(trackers: model.trackers)
          .frame(minHeight: 230)
          .accessibilityIdentifier("tracker-table")
      }
    }
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
      Label("\(attentionCount)件を確認", systemImage: "exclamationmark.circle.fill")
        .font(.caption.weight(.medium))
        .foregroundStyle(.orange)
    } else if !trackers.isEmpty {
      Label("正常", systemImage: "checkmark.circle.fill")
        .font(.caption.weight(.medium))
        .foregroundStyle(.green)
    }
  }
}

private struct DiagnosticsPanel: View {
  @ObservedObject var model: HubAppModel
  @Binding var isExpanded: Bool

  private var items: [DiagnosticItem] {
    switch model.displayedSource {
    case .simulator:
      [
        DiagnosticItem(title: "Attempted", value: "\(model.attemptedFrames)"),
        DiagnosticItem(title: "Emitted", value: "\(model.emittedFrames)"),
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
        DiagnosticItem(title: "Valid", value: "\(model.validPackets)"),
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
    DashboardSurface {
      DisclosureGroup(isExpanded: $isExpanded) {
        LazyVGrid(
          columns: [
            GridItem(.adaptive(minimum: 130), spacing: 12)
          ],
          spacing: 12
        ) {
          ForEach(items) { item in
            DiagnosticValue(item: item)
          }
        }
        .padding(.top, 14)
      } label: {
        HStack {
          Label("診断情報", systemImage: "waveform.path")
            .font(.headline)
          Spacer()
          Text("必要なときだけ表示")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityIdentifier("diagnostics-disclosure")
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
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color.secondary.opacity(0.06),
      in: RoundedRectangle(cornerRadius: 10)
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
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: systemImage)
        .font(.headline)
        .foregroundStyle(.tint)
        .frame(width: 28, height: 28)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

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

private struct DashboardSurface<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(16)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .stroke(.quaternary, lineWidth: 1)
      }
  }
}

private struct TrackerTable: View {
  let trackers: [TrackerDisplayState]

  var body: some View {
    Table(trackers) {
      TableColumn("Tracker") { tracker in
        VStack(alignment: .leading, spacing: 2) {
          Text(tracker.role.isEmpty ? "未割当" : tracker.role)
            .fontWeight(.medium)
          Text(tracker.id)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .width(min: 180, ideal: 230)

      TableColumn("状態") { tracker in
        Label(
          tracker.trackingState.displayName,
          systemImage: "circle.fill"
        )
        .foregroundStyle(tracker.trackingState.displayColor)
      }
      .width(min: 100, ideal: 120)

      TableColumn("位置 X / Y / Z") { tracker in
        Text(
          String(
            format: "%.3f  /  %.3f  /  %.3f",
            tracker.position.x,
            tracker.position.y,
            tracker.position.z
          )
        )
        .font(.body.monospacedDigit())
      }
      .width(min: 210, ideal: 250)

      TableColumn("Age") { tracker in
        Text(String(format: "%.0f ms", tracker.ageMilliseconds))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      .width(80)
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
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(.quaternary, lineWidth: 1)
    }
    .overlay {
      if trackers.isEmpty {
        ContentUnavailableView(
          "Trackerがありません",
          systemImage: "dot.radiowaves.left.and.right",
          description: Text(
            source == .simulator
              ? "サイドバーからSimulatorを開始してください。"
              : "UDP受信を開始し、Bridgeまたはtest senderを起動してください。"
          )
        )
      }
    }
  }

  private func drawGrid(context: inout GraphicsContext, size: CGSize) {
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let scale = min(size.width, size.height) / (visibleHalfRange * 2)
    var grid = Path()
    for meter in -2...2 {
      let offset = CGFloat(meter) * scale
      grid.move(to: CGPoint(x: center.x + offset, y: 0))
      grid.addLine(to: CGPoint(x: center.x + offset, y: size.height))
      grid.move(to: CGPoint(x: 0, y: center.y + offset))
      grid.addLine(to: CGPoint(x: size.width, y: center.y + offset))
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
