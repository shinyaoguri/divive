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
      SourceControlView(model: model)
        .navigationSplitViewColumnWidth(
          min: 270,
          ideal: 300,
          max: 340
        )
    } detail: {
      HubDashboardView(model: model)
    }
    .frame(minWidth: 1_050, minHeight: 700)
    .task {
      await model.refreshUntilCancelled()
    }
  }
}

private struct SourceControlView: View {
  @ObservedObject var model: HubAppModel

  var body: some View {
    Form {
      Section {
        HStack(spacing: 8) {
          Circle()
            .fill(model.isRunning ? Color.green : Color.secondary)
            .frame(width: 10, height: 10)
          Text(model.statusTitle)
            .font(.headline)
        }
        if model.activeSource == .network,
          let endpoint = model.boundEndpoint
        {
          Text(endpoint)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }

      Section("入力Source") {
        Picker("入力Source", selection: $model.selectedSource) {
          ForEach(HubInputSource.allCases) { source in
            Text(source.displayName).tag(source)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }

      if model.selectedSource == .simulator {
        Section("シーン") {
          Stepper(
            "Tracker: \(model.trackerCount)台",
            value: $model.trackerCount,
            in: 1...16
          )

          Picker("Motion", selection: $model.motion) {
            ForEach(HubAppMotionPreset.allCases) { motion in
              Text(motion.displayName).tag(motion)
            }
          }

          Picker("更新頻度", selection: $model.rate) {
            ForEach(SimulatorRate.allCases, id: \.rawValue) { rate in
              Text("\(rate.rawValue) Hz").tag(rate)
            }
          }
          .pickerStyle(.segmented)

          TextField("Seed", text: $model.seedText)
            .textFieldStyle(.roundedBorder)
        }

        Section("障害注入") {
          LabeledContent(
            "Frame loss",
            value: model.frameLossPercent,
            format: .number.precision(.fractionLength(1)),
            suffix: "%"
          )
          Slider(value: $model.frameLossPercent, in: 0...50, step: 0.5)

          LabeledContent(
            "Tracking lost",
            value: model.trackingLostPercent,
            format: .number.precision(.fractionLength(1)),
            suffix: "%"
          )
          Slider(
            value: $model.trackingLostPercent,
            in: 0...50,
            step: 0.5
          )
        }
      } else {
        Section("UDP Listener") {
          TextField("Bind address", text: $model.networkBindHost)
            .textFieldStyle(.roundedBorder)
          TextField("UDP port", text: $model.networkPortText)
            .textFieldStyle(.roundedBorder)
          Text(
            "`127.0.0.1`はMac内の試験用、`0.0.0.0`はLAN上のBridgeを受信します。"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Section {
        Button {
          Task { await model.startSelectedSource() }
        } label: {
          Label(
            model.startButtonTitle,
            systemImage: model.isRunning ? "arrow.clockwise" : "play.fill"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)

        Button(role: .destructive) {
          Task { await model.stopActiveSource() }
        } label: {
          Label("停止", systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .disabled(!model.isRunning)
      }

      if let errorMessage = model.errorMessage {
        Section {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.caption)
        }
      }

      Section {
        Text("Source切替時は現在のSourceを停止し、選択した設定で再開します。")
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Divive Hub")
  }
}

private struct HubDashboardView: View {
  @ObservedObject var model: HubAppModel

  private let columns = [
    GridItem(.adaptive(minimum: 150), spacing: 12)
  ]

  private var metricItems: [MetricItem] {
    var items = [
      MetricItem(
        title: "Hub更新レート",
        value: String(format: "%.1f Hz", model.observedRateHz),
        systemImage: "waveform.path.ecg"
      ),
      MetricItem(
        title: "Tracker",
        value: "\(model.trackers.count) 台",
        systemImage: "dot.radiowaves.left.and.right"
      ),
    ]
    switch model.displayedSource {
    case .simulator:
      items.append(
        MetricItem(
          title: "Frame loss",
          value: String(format: "%.1f%%", model.droppedPercent),
          systemImage: "arrow.down.right.and.arrow.up.left"
        )
      )
      items.append(
        MetricItem(
          title: "Deadline miss",
          value: "\(model.missedDeadlines)",
          systemImage: "clock.badge.exclamationmark"
        )
      )
    case .network:
      items.append(
        MetricItem(
          title: "UDP datagram",
          value: "\(model.receivedDatagrams)",
          systemImage: "network"
        )
      )
      items.append(
        MetricItem(
          title: "欠落Frame",
          value: "\(model.missingFrames)",
          systemImage: "arrow.down.right.and.arrow.up.left"
        )
      )
      items.append(
        MetricItem(
          title: "順序逆転",
          value: "\(model.outOfOrderPackets)",
          systemImage: "arrow.up.arrow.down"
        )
      )
      items.append(
        MetricItem(
          title: "受信異常",
          value: "\(model.networkAnomalyCount)",
          systemImage: "exclamationmark.triangle"
        )
      )
      items.append(
        MetricItem(
          title: "受信処理",
          value: "\(model.lastProcessingMicroseconds) µs",
          systemImage: "timer"
        )
      )
    }
    return items
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Tracker Monitor")
            .font(.largeTitle.bold())
          Text(model.dashboardSubtitle)
            .foregroundStyle(.secondary)
        }

        LazyVGrid(columns: columns, spacing: 12) {
          ForEach(metricItems) { item in
            MetricCard(
              title: item.title,
              value: item.value,
              systemImage: item.systemImage
            )
          }
        }

        GroupBox("空間プレビュー — 上面図 X / -Z（±2m）") {
          TrackerTopDownView(
            trackers: model.trackers,
            source: model.displayedSource
          )
            .frame(minHeight: 300)
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Tracker一覧")
              .font(.title2.bold())
            Spacer()
            Text(model.summaryText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          }
          TrackerTable(trackers: model.trackers)
            .frame(minHeight: 230)
        }
      }
      .padding(22)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct MetricItem: Identifiable {
  let title: String
  let value: String
  let systemImage: String

  var id: String { title }
}

private struct MetricCard: View {
  let title: String
  let value: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.title3.monospacedDigit().bold())
      }
      Spacer(minLength: 0)
    }
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
  }
}

private struct TrackerTable: View {
  let trackers: [TrackerDisplayState]

  var body: some View {
    Table(trackers) {
      TableColumn("Role") { tracker in
        VStack(alignment: .leading, spacing: 2) {
          Text(tracker.role)
          Text(tracker.id)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
      .width(min: 160, ideal: 190)

      TableColumn("状態") { tracker in
        Label(
          tracker.trackingState.displayName,
          systemImage: "circle.fill"
        )
        .foregroundStyle(tracker.trackingState.displayColor)
      }
      .width(min: 95, ideal: 110)

      TableColumn("X") { tracker in
        coordinate(tracker.position.x)
      }
      .width(70)

      TableColumn("Y") { tracker in
        coordinate(tracker.position.y)
      }
      .width(70)

      TableColumn("Z") { tracker in
        coordinate(tracker.position.z)
      }
      .width(70)

      TableColumn("Age") { tracker in
        Text(String(format: "%.0f ms", tracker.ageMilliseconds))
          .monospacedDigit()
      }
      .width(75)
    }
  }

  private func coordinate(_ value: Float) -> some View {
    Text(String(format: "%.3f", value))
      .monospacedDigit()
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
    .background(
      Color(nsColor: .controlBackgroundColor),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .overlay {
      if trackers.isEmpty {
        ContentUnavailableView(
          "Trackerがありません",
          systemImage: "dot.radiowaves.left.and.right",
          description: Text(
            source == .simulator
              ? "左側の「開始」でSimulatorを起動してください。"
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
      with: .color(.secondary.opacity(0.18)),
      lineWidth: 1
    )

    var axes = Path()
    axes.move(to: CGPoint(x: center.x, y: 0))
    axes.addLine(to: CGPoint(x: center.x, y: size.height))
    axes.move(to: CGPoint(x: 0, y: center.y))
    axes.addLine(to: CGPoint(x: size.width, y: center.y))
    context.stroke(
      axes,
      with: .color(.secondary.opacity(0.45)),
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
      x: point.x - 7,
      y: point.y - 7,
      width: 14,
      height: 14
    )
    context.fill(
      Path(ellipseIn: marker),
      with: .color(tracker.trackingState.displayColor)
    )
    context.stroke(
      Path(ellipseIn: marker),
      with: .color(.white.opacity(0.85)),
      lineWidth: 1.5
    )
    context.draw(
      Text(tracker.role)
        .font(.caption.bold())
        .foregroundStyle(.primary),
      at: CGPoint(x: point.x, y: point.y - 17),
      anchor: .bottom
    )
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

extension LabeledContent where Label == Text, Content == Text {
  fileprivate init(
    _ title: String,
    value: Double,
    format: FloatingPointFormatStyle<Double>,
    suffix: String
  ) {
    self.init {
      Text("\(value.formatted(format))\(suffix)")
        .monospacedDigit()
    } label: {
      Text(title)
    }
  }
}
