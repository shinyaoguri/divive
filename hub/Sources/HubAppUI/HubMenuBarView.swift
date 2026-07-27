import Foundation
import HubProtocol
import SwiftUI

public enum HubMenuBarSeverity: Equatable, Sendable {
  case stopped
  case waiting
  case healthy
  case warning
  case error
}

public struct HubMenuBarStatus: Equatable, Sendable {
  public let severity: HubMenuBarSeverity
  public let menuTitle: String
  public let title: String
  public let detail: String
  public let systemImage: String

  @MainActor
  public init(model: HubAppModel) {
    self.init(
      source: model.displayedSource,
      isRunning: model.isRunning,
      trackerCount: model.trackers.count,
      attentionTrackerCount: model.trackers.count {
        $0.trackingState != .tracking && $0.trackingState != .simulated
      },
      anomalyCount: model.displayedSource == .simulator
        ? model.simulatorUndeliveredFrames + model.missedDeadlines
        : model.missingFrames + model.networkAnomalyCount,
      errorMessage: model.errorMessage
    )
  }

  init(
    source: HubInputSource,
    isRunning: Bool,
    trackerCount: Int,
    attentionTrackerCount: Int,
    anomalyCount: UInt64,
    errorMessage: String?
  ) {
    if let errorMessage, !errorMessage.isEmpty {
      severity = .error
      menuTitle = "エラー"
      title = "入力にエラーがあります"
      detail = errorMessage
      systemImage = "exclamationmark.octagon.fill"
    } else if !isRunning {
      severity = .stopped
      menuTitle = "停止"
      title = "入力は停止中です"
      detail = "必要なときに入力を開始してください。"
      systemImage = "pause.circle"
    } else if attentionTrackerCount > 0 {
      severity = .warning
      menuTitle = "要確認"
      title = "\(attentionTrackerCount)台のTrackerに問題があります"
      detail = "追跡喪失または接続状態を確認してください。"
      systemImage = "exclamationmark.triangle.fill"
    } else if anomalyCount > 0 {
      severity = .warning
      menuTitle = "要確認"
      title = "入力品質に問題があります"
      detail =
        source == .simulator
        ? "欠落、順序逆転、接続断または処理遅延を検出しました。"
        : "欠落フレームまたは受信異常を検出しました。"
      systemImage = "exclamationmark.triangle.fill"
    } else if trackerCount == 0 {
      severity = .waiting
      menuTitle = "待機"
      title = source == .network ? "UDPデータを待っています" : "準備中です"
      detail =
        source == .network
        ? "Windows Bridgeからまだ姿勢を受信していません。"
        : "Trackerの生成を待っています。"
      systemImage = "ellipsis.circle"
    } else {
      severity = .healthy
      menuTitle = "\(trackerCount)台"
      title = "正常に動作しています"
      detail = "\(trackerCount)台のTrackerを更新中です。"
      systemImage = "checkmark.circle.fill"
    }
  }
}

public struct HubMenuBarLabel: View {
  @ObservedObject private var model: HubAppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(model: HubAppModel) {
    self.model = model
  }

  public var body: some View {
    let status = HubMenuBarStatus(model: model)

    HStack(spacing: 5) {
      Image(systemName: status.systemImage)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(status.severity.displayColor)
        .symbolEffect(
          .pulse.wholeSymbol,
          isActive: !reduceMotion && status.severity == .error
        )

      Text(status.menuTitle)
        .font(
          .callout.weight(
            status.severity.emphasizesLabel ? .semibold : .medium
          )
        )
        .foregroundStyle(.primary)
    }
    .animation(
      reduceMotion ? nil : .easeOut(duration: 0.16),
      value: status.severity
    )
    .accessibilityElement(children: .combine)
    .help("\(status.title)。\(status.detail)")
    .accessibilityLabel("\(status.title)。\(status.detail)")
    .task {
      await model.refreshUntilCancelled()
    }
  }
}

public struct HubMenuBarContent: View {
  @ObservedObject private var model: HubAppModel
  @Environment(\.openWindow) private var openWindow
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(model: HubAppModel) {
    self.model = model
  }

  public var body: some View {
    let status = HubMenuBarStatus(model: model)

    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: status.systemImage)
          .font(.title2)
          .foregroundStyle(status.severity.displayColor)
          .symbolRenderingMode(.hierarchical)
          .symbolEffect(
            .pulse.wholeSymbol,
            isActive: !reduceMotion && status.severity == .error
          )

        VStack(alignment: .leading, spacing: 3) {
          Text(status.title)
            .font(.headline)
          Text(status.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(12)
      .background(
        status.severity.displayColor.opacity(0.11),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(status.severity.displayColor.opacity(0.2), lineWidth: 0.5)
      }
      .animation(
        reduceMotion
          ? nil
          : .spring(response: 0.3, dampingFraction: 1),
        value: status.severity
      )

      Divider()

      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
        statusRow("入力", value: model.displayedSource.displayName)
        statusRow(
          "更新",
          value: model.isRunning
            ? String(format: "%.1f Hz", model.observedRateHz)
            : "停止中"
        )
        statusRow("Tracker", value: "\(model.trackers.count)台")
      }

      HStack(spacing: 8) {
        Button {
          openWindow(id: "hub-window")
        } label: {
          Label("ウィンドウを表示", systemImage: "macwindow")
        }

        Spacer(minLength: 0)

        Button {
          Task {
            if model.isRunning {
              await model.stopActiveSource()
            } else {
              await model.startSelectedSource()
            }
          }
        } label: {
          Label(
            model.isRunning
              ? "停止"
              : (model.selectedSource == .network ? "受信開始" : "開始"),
            systemImage: model.isRunning ? "stop.fill" : "play.fill"
          )
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(18)
    .frame(width: 310)
  }

  private func statusRow(
    _ title: String,
    value: String
  ) -> some View {
    GridRow {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.callout.monospacedDigit().weight(.medium))
        .gridColumnAlignment(.trailing)
    }
  }
}

extension HubMenuBarSeverity {
  fileprivate var displayColor: Color {
    switch self {
    case .stopped: .secondary
    case .waiting: .blue
    case .healthy: .green
    case .warning: .orange
    case .error: .red
    }
  }

  fileprivate var emphasizesLabel: Bool {
    self == .warning || self == .error
  }
}
