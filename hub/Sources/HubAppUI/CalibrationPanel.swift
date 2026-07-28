import HubCalibration
import HubProtocol
import SwiftUI

extension CalibratedDelivery {
  var displayName: String {
    switch self {
    case .stage: "Stage"
    case .rawTrackerSpace: "Tracker Space"
    case .blocked: "非配信"
    }
  }

  var statusSymbol: String {
    switch self {
    case .stage: "checkmark.circle"
    case .rawTrackerSpace: "eye"
    case .blocked: "exclamationmark.triangle"
    }
  }

  var displayColor: Color {
    switch self {
    case .stage: .green
    case .rawTrackerSpace: .blue
    case .blocked: .orange
    }
  }
}

extension CalibrationDeliveryMode {
  var displayName: String {
    switch self {
    case .production: "配信"
    case .preview: "確認"
    }
  }

  var helpText: String {
    switch self {
    case .production: "未較正の空間をcontentへ配信しません"
    case .preview: "未較正でもTracker Spaceのまま観察します"
    }
  }
}

/// ツールバーから開く較正popover。
///
/// 較正は常時見る操作ではないためpopoverへ置き、状態のサマリだけを右インスペクタへ
/// 常時表示する。設定（歯車）とは別のボタンにして、操作を重複させない。
struct CalibrationPanel: View {
  @ObservedObject var model: HubAppModel
  let selectedTrackerID: String?

  private var selectedTracker: TrackerDisplayState? {
    model.trackers.first { $0.id == selectedTrackerID }
      ?? model.trackers.first
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      Divider()
      modeSection
      Divider()
      sampleSection
      if !model.calibrationSpaces.isEmpty {
        Divider()
        spaceSection
      }
      messageSection
    }
    .padding(16)
    .frame(width: 380)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("較正")
          .font(.headline)

        Spacer()

        if model.calibrationProfileRevision > 0 {
          Text("revision \(model.calibrationProfileRevision)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }

      Text(model.calibrationProfileName.isEmpty ? "未読込" : model.calibrationProfileName)
        .font(.callout)

      Text(model.calibrationStorePath)
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.head)
        .help(model.calibrationStorePath)
    }
  }

  private var modeSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Picker("未較正空間の扱い", selection: $model.calibrationMode) {
        ForEach(CalibrationDeliveryMode.allCases, id: \.self) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("calibration-mode-picker")

      Text(model.calibrationMode.helpText)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var sampleSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("原点と前方から較正")
          .font(.subheadline.weight(.medium))

        Spacer()

        if let selectedTracker {
          Text(selectedTracker.role.isEmpty ? selectedTracker.id : selectedTracker.role)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Text("基準Trackerを原点へ置いて取得し、前方へ動かしてもう一度取得します。")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        sampleButton(
          title: "原点を取得",
          slot: model.calibrationOriginSample,
          identifier: "capture-origin-button"
        ) {
          model.captureCalibrationOrigin(trackerID: selectedTracker?.id)
        }

        sampleButton(
          title: "前方を取得",
          slot: model.calibrationForwardSample,
          identifier: "capture-forward-button"
        ) {
          model.captureCalibrationForward(trackerID: selectedTracker?.id)
        }
      }

      HStack(spacing: 8) {
        Text("床面offset")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextField("0", text: $model.calibrationFloorHeightOffsetText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 80)
          .accessibilityIdentifier("floor-offset-field")

        Text("m")
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        Button("消去", role: .destructive) {
          model.clearCalibrationSamples()
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .disabled(
          model.calibrationOriginSample == nil
            && model.calibrationForwardSample == nil
        )
      }

      Button {
        model.applyOriginAndForwardCalibration()
      } label: {
        Text("較正を適用")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!model.canApplyCalibration)
      .accessibilityIdentifier("apply-calibration-button")

      if let estimate = model.lastCalibrationEstimate {
        residualSummary(estimate)
      }
    }
  }

  private func sampleButton(
    title: String,
    slot: CalibrationSampleSlot?,
    identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Text(title)
        Text(slot.map { "\($0.captureCount)点" } ?? "未取得")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
    }
    .accessibilityIdentifier(identifier)
  }

  private func residualSummary(_ estimate: CalibrationEstimate) -> some View {
    HStack(spacing: 10) {
      Text("sample \(estimate.sampleCount)")
      if let rms = estimate.rmsErrorM {
        Text(String(format: "RMS %.3fm", rms))
      } else {
        Text("検証点なし")
      }
    }
    .font(.caption.monospacedDigit())
    .foregroundStyle(.secondary)
  }

  private var spaceSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("tracking space")
        .font(.subheadline.weight(.medium))

      ForEach(model.calibrationSpaces, id: \.trackingSpaceID) { space in
        HStack(spacing: 8) {
          Image(systemName: space.status.isCalibrated ? "checkmark.circle" : "circle.dashed")
            .foregroundStyle(space.status.isCalibrated ? Color.green : Color.orange)

          VStack(alignment: .leading, spacing: 1) {
            Text(space.trackingSpaceID.description)
              .font(.caption2.monospaced())
              .lineLimit(1)
              .truncationMode(.middle)

            Text(spaceDetail(space))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }

          Spacer()

          if space.status.isCalibrated {
            Button("取り消し") {
              model.clearCalibration(forTrackingSpaceID: space.trackingSpaceID)
            }
            .buttonStyle(.borderless)
            .font(.caption)
          }
        }
      }
    }
  }

  private func spaceDetail(_ space: CalibratedSpaceState) -> String {
    let base = "epoch \(space.spaceEpoch) / \(space.trackerCount)台"
    return switch space.status {
    case .calibrated: "較正済み・\(base)"
    case .uncalibrated: "未較正・\(base)"
    case let .epochMismatch(_, profileEpoch, observedEpoch):
      "epoch不一致（profile \(profileEpoch) / 受信 \(observedEpoch)）・\(space.trackerCount)台"
    }
  }

  @ViewBuilder
  private var messageSection: some View {
    if let error = model.calibrationErrorMessage {
      Label(error, systemImage: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
    } else if let message = model.calibrationMessage {
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
