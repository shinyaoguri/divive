import Foundation
import HubCalibration
import HubCore
import HubProtocol

extension HubAppModel {
  public var calibrationProfile: CalibrationProfile? {
    calibrationDocument?.profile
  }

  public var calibratedSpaceCount: Int {
    calibrationSpaces.filter { $0.status.isCalibrated }.count
  }

  public var uncalibratedSpaceCount: Int {
    calibrationSpaces.count - calibratedSpaceCount
  }

  public var calibrationSummaryText: String {
    guard !calibrationSpaces.isEmpty else {
      return "対象なし"
    }
    if uncalibratedSpaceCount == 0 {
      return "較正済み \(calibratedSpaceCount)空間"
    }
    return "較正済み \(calibratedSpaceCount) / 未較正 \(uncalibratedSpaceCount)空間"
  }

  public var hasUncalibratedSpace: Bool {
    uncalibratedSpaceCount > 0
  }

  public var canApplyCalibration: Bool {
    calibrationOriginSample != nil && calibrationForwardSample != nil
  }

  /// profileを読み込み、失敗した場合はidentityへ倒さず理由を表示する。
  func loadCalibrationDocument(store: CalibrationStore, now: Date) {
    calibrationStorePath = store.url.path
    do {
      let document = try CalibrationDocument.load(
        store: store,
        applicationVersion: Self.applicationVersion,
        now: now
      )
      applyDocument(document)
      calibrationErrorMessage = nil
    } catch {
      calibrationDocument = nil
      calibrationProfileName = "読み込み失敗"
      calibrationProfileRevision = 0
      calibrationErrorMessage =
        "calibration profileを読み込めませんでした: \(error)"
    }
  }

  /// 較正を適用したTracker一覧を作る。
  ///
  /// profileが無い場合も、未較正として扱ってTracker自体は表示する。
  func calibratedTrackers(
    from snapshot: EvaluatedHubStateSnapshot
  ) -> [TrackerDisplayState] {
    guard let document = calibrationDocument else {
      publish([], to: \.calibrationSpaces)
      return snapshot.trackers.map { TrackerDisplayState(uncalibrated: $0) }
    }

    let projection = CalibrationResolver(
      profile: document.profile,
      mode: calibrationMode
    ).project(snapshot)
    publish(projection.spaces, to: \.calibrationSpaces)
    return projection.trackers.map { TrackerDisplayState($0) }
  }

  /// 選択Trackerの現在位置を原点サンプルとして積む。
  public func captureCalibrationOrigin(trackerID: String?) {
    capture(trackerID: trackerID, into: \.calibrationOriginSample, label: "原点")
  }

  /// 選択Trackerの現在位置を前方サンプルとして積む。
  public func captureCalibrationForward(trackerID: String?) {
    capture(trackerID: trackerID, into: \.calibrationForwardSample, label: "前方")
  }

  public func clearCalibrationSamples() {
    calibrationOriginSample = nil
    calibrationForwardSample = nil
    lastCalibrationEstimate = nil
    calibrationMessage = nil
    calibrationErrorMessage = nil
  }

  /// origin and forward手順で較正し、profileへ保存する。
  public func applyOriginAndForwardCalibration(now: Date = Date()) {
    do {
      guard var document = calibrationDocument else {
        throw CalibrationCommandError.missingOriginSample
      }
      guard let origin = calibrationOriginSample else {
        throw CalibrationCommandError.missingOriginSample
      }
      guard let forward = calibrationForwardSample else {
        throw CalibrationCommandError.missingForwardSample
      }
      guard
        origin.trackingSpaceID == forward.trackingSpaceID,
        origin.spaceEpoch == forward.spaceEpoch
      else {
        throw CalibrationCommandError.sampleSpaceMismatch
      }

      let estimate = try OriginAndForwardEstimator.estimate(
        origin: try origin.makeSample(),
        forward: try forward.makeSample(),
        floorHeightOffsetM: floorHeightOffsetMeters
      )
      try document.upsert(
        try estimate.makeSpaceCalibration(
          trackingSpaceID: origin.trackingSpaceID,
          spaceEpoch: origin.spaceEpoch,
          operatorNote: "GUIの原点\(origin.captureCount)点 / 前方\(forward.captureCount)点",
          updatedAt: now
        ),
        at: now
      )
      applyDocument(document)

      lastCalibrationEstimate = estimate
      calibrationErrorMessage = nil
      calibrationMessage =
        "較正を適用しました（revision \(document.profile.revision)）"
      Task { await refresh() }
    } catch {
      calibrationMessage = nil
      calibrationErrorMessage = describe(error)
    }
  }

  /// 較正を取り消し、そのspaceを未較正へ戻す。
  public func clearCalibration(
    forTrackingSpaceID trackingSpaceID: UUIDBytes,
    now: Date = Date()
  ) {
    do {
      guard var document = calibrationDocument else { return }
      try document.removeCalibration(
        forTrackingSpaceID: trackingSpaceID,
        at: now
      )
      applyDocument(document)
      lastCalibrationEstimate = nil
      calibrationErrorMessage = nil
      calibrationMessage = "較正を取り消しました"
      Task { await refresh() }
    } catch {
      calibrationMessage = nil
      calibrationErrorMessage = describe(error)
    }
  }

  private var floorHeightOffsetMeters: Double {
    Double(calibrationFloorHeightOffsetText.trimmingCharacters(in: .whitespaces))
      ?? 0
  }

  private func capture(
    trackerID: String?,
    into keyPath: ReferenceWritableKeyPath<HubAppModel, CalibrationSampleSlot?>,
    label: String
  ) {
    guard
      let trackerID,
      let tracker = trackers.first(where: { $0.id == trackerID })
    else {
      calibrationMessage = nil
      calibrationErrorMessage = CalibrationCommandError.noSelectedTracker.description
      return
    }

    if var existing = self[keyPath: keyPath],
      existing.appendIfCompatible(
        trackerID: tracker.id,
        trackingSpaceID: tracker.trackingSpaceID,
        spaceEpoch: tracker.spaceEpoch,
        position: tracker.position
      )
    {
      self[keyPath: keyPath] = existing
    } else {
      self[keyPath: keyPath] = CalibrationSampleSlot(
        trackerID: tracker.id,
        trackingSpaceID: tracker.trackingSpaceID,
        spaceEpoch: tracker.spaceEpoch,
        position: tracker.position
      )
    }

    let count = self[keyPath: keyPath]?.captureCount ?? 0
    calibrationErrorMessage = nil
    calibrationMessage = "\(label)サンプルを\(count)点取得しました"
  }

  private func applyDocument(_ document: CalibrationDocument) {
    calibrationDocument = document
    calibrationProfileName = document.profile.name
    calibrationProfileRevision = document.profile.revision
    calibrationStorePath = document.storePath
  }

  private func describe(_ error: Error) -> String {
    if let command = error as? CalibrationCommandError {
      return command.description
    }
    if let estimation = error as? CalibrationEstimationError {
      return switch estimation {
      case let .degenerateForwardDirection(length):
        "前方サンプルが近すぎます（水平距離 \(String(format: "%.3f", length))m）。"
          + "\(OriginAndForwardEstimator.minimumForwardHorizontalLengthM)m以上離してください"
      case .emptySampleSet:
        "サンプルがありません"
      case .nonFiniteSample:
        "サンプルに有限でない値が含まれています"
      case .nonFiniteFloorHeightOffset:
        "床面offsetに数値を入力してください"
      default:
        "較正できませんでした: \(estimation)"
      }
    }
    return "較正できませんでした: \(error)"
  }
}

extension HubAppModel {
  static let applicationVersion = "0.1.0-dev"
}
