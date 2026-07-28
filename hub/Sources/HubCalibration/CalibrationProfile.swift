import Foundation
import HubProtocol

/// 較正の求め方。証跡として保存し、UIとlogで手順を再現できるようにする。
public enum CalibrationMethod: String, Sendable, Codable, CaseIterable {
  case identity
  case originAndForward = "origin_and_forward"
  case pointSetRegistration = "point_set_registration"
  case manual
}

public enum CalibrationProfileError: Error, Equatable, Sendable {
  case emptyProfileID
  case unsupportedFormatVersion(Int)
  case invalidTrackingSpaceID(String)
  case negativeResidual
}

/// 単一tracking spaceに対するStage較正。
///
/// `spaceEpoch`はBridgeが報告する空間世代で、値が変わった較正を自動流用しない。
public struct SpaceCalibration: Equatable, Sendable {
  public let trackingSpaceID: UUIDBytes
  public let spaceEpoch: UInt32
  public let transform: RigidTransform
  public let method: CalibrationMethod
  public let sampleCount: UInt32
  public let rmsErrorM: Double?
  public let maxResidualM: Double?
  public let operatorNote: String?
  public let updatedAt: Date

  public init(
    trackingSpaceID: UUIDBytes,
    spaceEpoch: UInt32,
    transform: RigidTransform,
    method: CalibrationMethod,
    sampleCount: UInt32 = 0,
    rmsErrorM: Double? = nil,
    maxResidualM: Double? = nil,
    operatorNote: String? = nil,
    updatedAt: Date
  ) throws {
    if let rmsErrorM, !(rmsErrorM.isFinite && rmsErrorM >= 0) {
      throw CalibrationProfileError.negativeResidual
    }
    if let maxResidualM, !(maxResidualM.isFinite && maxResidualM >= 0) {
      throw CalibrationProfileError.negativeResidual
    }

    self.trackingSpaceID = trackingSpaceID
    self.spaceEpoch = spaceEpoch
    self.transform = transform
    self.method = method
    self.sampleCount = sampleCount
    self.rmsErrorM = rmsErrorM
    self.maxResidualM = maxResidualM
    self.operatorNote = operatorNote
    self.updatedAt = updatedAt
  }
}

/// tracking spaceごとの較正をまとめた永続profile。
///
/// role mappingはここへ含めない。同じ空間較正のままTrackerの役割だけを
/// 変更できるようにするため、別のprofileとして扱う。
public struct CalibrationProfile: Equatable, Sendable {
  /// 保存形式のversion。読み込み時に未知の値を拒否する。
  public static let currentFormatVersion = 1

  public let formatVersion: Int
  public let profileID: String
  public let name: String
  public let revision: UInt32
  public let createdAt: Date
  public let updatedAt: Date
  public let applicationVersion: String

  private let spacesByID: [UUIDBytes: SpaceCalibration]

  public init(
    profileID: String,
    name: String,
    revision: UInt32 = 1,
    createdAt: Date,
    updatedAt: Date,
    applicationVersion: String,
    spaces: [SpaceCalibration] = [],
    formatVersion: Int = CalibrationProfile.currentFormatVersion
  ) throws {
    guard !profileID.isEmpty else {
      throw CalibrationProfileError.emptyProfileID
    }
    guard formatVersion == Self.currentFormatVersion else {
      throw CalibrationProfileError.unsupportedFormatVersion(formatVersion)
    }

    self.formatVersion = formatVersion
    self.profileID = profileID
    self.name = name
    self.revision = revision
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.applicationVersion = applicationVersion
    spacesByID = Dictionary(
      spaces.map { ($0.trackingSpaceID, $0) },
      uniquingKeysWith: { _, latest in latest }
    )
  }

  /// tracking space ID順に整列した較正一覧。
  public var sortedSpaces: [SpaceCalibration] {
    spacesByID.values.sorted {
      $0.trackingSpaceID.bytes.lexicographicallyPrecedes($1.trackingSpaceID.bytes)
    }
  }

  public var spaceCount: Int {
    spacesByID.count
  }

  public func calibration(forTrackingSpaceID id: UUIDBytes) -> SpaceCalibration? {
    spacesByID[id]
  }

  /// 較正を追加または置換し、revisionを1つ進めたprofileを返す。
  public func upserting(
    _ calibration: SpaceCalibration,
    at date: Date
  ) -> CalibrationProfile {
    var updated = spacesByID
    updated[calibration.trackingSpaceID] = calibration
    return replacingSpaces(updated, at: date)
  }

  /// 較正を取り消し、revisionを1つ進めたprofileを返す。
  ///
  /// 取り消したspaceはidentityではなく未較正として扱われる。
  public func removingCalibration(
    forTrackingSpaceID id: UUIDBytes,
    at date: Date
  ) -> CalibrationProfile {
    guard spacesByID[id] != nil else {
      return self
    }
    var updated = spacesByID
    updated.removeValue(forKey: id)
    return replacingSpaces(updated, at: date)
  }

  private func replacingSpaces(
    _ spaces: [UUIDBytes: SpaceCalibration],
    at date: Date
  ) -> CalibrationProfile {
    CalibrationProfile(
      formatVersion: formatVersion,
      profileID: profileID,
      name: name,
      revision: revision &+ 1,
      createdAt: createdAt,
      updatedAt: date,
      applicationVersion: applicationVersion,
      spacesByID: spaces
    )
  }

  private init(
    formatVersion: Int,
    profileID: String,
    name: String,
    revision: UInt32,
    createdAt: Date,
    updatedAt: Date,
    applicationVersion: String,
    spacesByID: [UUIDBytes: SpaceCalibration]
  ) {
    self.formatVersion = formatVersion
    self.profileID = profileID
    self.name = name
    self.revision = revision
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.applicationVersion = applicationVersion
    self.spacesByID = spacesByID
  }
}
