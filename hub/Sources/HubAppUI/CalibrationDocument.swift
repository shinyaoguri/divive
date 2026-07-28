import Foundation
import HubCalibration
import HubProtocol

/// GUIが編集するcalibration profileと、その保存先。
///
/// 読み込みに失敗したときにidentity transformの空profileへ黙って倒さない。
/// 壊れたprofileを無視すると、未較正の座標が較正済みとしてcontentへ流れる。
public struct CalibrationDocument: Sendable {
  public static let defaultProfileID = "divive-hub"
  public static let defaultProfileName = "Hub較正"

  public private(set) var profile: CalibrationProfile
  public let store: CalibrationStore

  public var storePath: String {
    store.url.path
  }

  public init(profile: CalibrationProfile, store: CalibrationStore) {
    self.profile = profile
    self.store = store
  }

  /// `~/Library/Application Support/divive/calibration.json`。
  public static func defaultStoreURL(
    fileManager: FileManager = .default
  ) -> URL {
    let base =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return
      base
      .appendingPathComponent("divive", isDirectory: true)
      .appendingPathComponent("calibration.json")
  }

  public static func emptyProfile(
    applicationVersion: String,
    now: Date
  ) throws -> CalibrationProfile {
    try CalibrationProfile(
      profileID: defaultProfileID,
      name: defaultProfileName,
      createdAt: now,
      updatedAt: now,
      applicationVersion: applicationVersion
    )
  }

  /// 保存済みprofileがあれば読み込み、無ければ空のprofileで開始する。
  ///
  /// ファイルが存在しないことは正常な初回起動。存在するのに読めない場合だけthrowする。
  public static func load(
    store: CalibrationStore,
    applicationVersion: String,
    now: Date
  ) throws -> CalibrationDocument {
    guard store.exists() else {
      return CalibrationDocument(
        profile: try emptyProfile(applicationVersion: applicationVersion, now: now),
        store: store
      )
    }
    return CalibrationDocument(profile: try store.load(), store: store)
  }

  public mutating func upsert(
    _ calibration: SpaceCalibration,
    at date: Date
  ) throws {
    profile = profile.upserting(calibration, at: date)
    try store.save(profile)
  }

  public mutating func removeCalibration(
    forTrackingSpaceID trackingSpaceID: UUIDBytes,
    at date: Date
  ) throws {
    let updated = profile.removingCalibration(
      forTrackingSpaceID: trackingSpaceID,
      at: date
    )
    guard updated.revision != profile.revision else {
      return
    }
    profile = updated
    try store.save(profile)
  }
}

/// GUIで取得した較正サンプル。
///
/// 取得を繰り返すと位置を蓄積し、中央値でまとめる。1回の観測だけで原点を決めると、
/// 遮蔽復帰やjitterで外れた1 frameがそのまま較正へ入る。
public struct CalibrationSampleSlot: Equatable, Sendable {
  public let trackerID: String
  public let trackingSpaceID: UUIDBytes
  public let spaceEpoch: UInt32
  public private(set) var positions: [Vector3]

  public init(
    trackerID: String,
    trackingSpaceID: UUIDBytes,
    spaceEpoch: UInt32,
    position: Vector3
  ) {
    self.trackerID = trackerID
    self.trackingSpaceID = trackingSpaceID
    self.spaceEpoch = spaceEpoch
    positions = [position]
  }

  public var captureCount: Int {
    positions.count
  }

  /// 同じTrackerと同じtracking spaceの観測だけを積む。
  public mutating func appendIfCompatible(
    trackerID: String,
    trackingSpaceID: UUIDBytes,
    spaceEpoch: UInt32,
    position: Vector3
  ) -> Bool {
    guard
      self.trackerID == trackerID,
      self.trackingSpaceID == trackingSpaceID,
      self.spaceEpoch == spaceEpoch
    else {
      return false
    }
    positions.append(position)
    return true
  }

  public func makeSample() throws -> CalibrationSample {
    try CalibrationSample.fromStationaryFrames(positions)
  }
}

public enum CalibrationCommandError: Error, Equatable, Sendable {
  case noSelectedTracker
  case missingOriginSample
  case missingForwardSample
  case sampleSpaceMismatch
}

extension CalibrationCommandError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .noSelectedTracker:
      "較正に使うTrackerを選択してください"
    case .missingOriginSample:
      "原点サンプルを取得してください"
    case .missingForwardSample:
      "前方サンプルを取得してください"
    case .sampleSpaceMismatch:
      "原点と前方のサンプルが同じtracking spaceではありません"
    }
  }
}
