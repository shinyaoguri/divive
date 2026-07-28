import Foundation
import HubProtocol

public enum CalibrationCodingError: Error, Equatable, Sendable {
  case invalidTranslationLength(actual: Int)
  case invalidRotationLength(actual: Int)
  case invalidTrackingSpaceID(String)
}

extension RigidTransform: Codable {
  private enum CodingKeys: String, CodingKey {
    case translation
    case rotation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let translation = try container.decode([Float].self, forKey: .translation)
    let rotation = try container.decode([Float].self, forKey: .rotation)
    try self.init(
      translation: Vector3(unpacking: translation),
      rotation: Quaternion(unpacking: rotation)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(translation.packed, forKey: .translation)
    try container.encode(rotation.packed, forKey: .rotation)
  }
}

extension SpaceCalibration: Codable {
  fileprivate enum CodingKeys: String, CodingKey {
    case trackingSpaceID = "trackingSpaceId"
    case spaceEpoch
    case translation
    case rotation
    case method
    case sampleCount
    case rmsErrorM
    case maxResidualM
    case operatorNote
    case updatedAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let identifier = try container.decode(String.self, forKey: .trackingSpaceID)
    try self.init(
      decoding: container,
      trackingSpaceID: UUIDBytes(calibrationString: identifier)
    )
  }

  /// tracking space IDをJSONのkeyから受け取る場合の復元。
  fileprivate init(
    from decoder: Decoder,
    trackingSpaceID: UUIDBytes
  ) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(decoding: container, trackingSpaceID: trackingSpaceID)
  }

  private init(
    decoding container: KeyedDecodingContainer<CodingKeys>,
    trackingSpaceID: UUIDBytes
  ) throws {
    let translation = try container.decode([Float].self, forKey: .translation)
    let rotation = try container.decode([Float].self, forKey: .rotation)
    try self.init(
      trackingSpaceID: trackingSpaceID,
      spaceEpoch: try container.decode(UInt32.self, forKey: .spaceEpoch),
      transform: RigidTransform(
        translation: Vector3(unpacking: translation),
        rotation: Quaternion(unpacking: rotation)
      ),
      method: try container.decode(CalibrationMethod.self, forKey: .method),
      sampleCount: try container.decodeIfPresent(UInt32.self, forKey: .sampleCount) ?? 0,
      rmsErrorM: try container.decodeIfPresent(Double.self, forKey: .rmsErrorM),
      maxResidualM: try container.decodeIfPresent(Double.self, forKey: .maxResidualM),
      operatorNote: try container.decodeIfPresent(String.self, forKey: .operatorNote),
      updatedAt: try container.decode(Date.self, forKey: .updatedAt)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(trackingSpaceID.description, forKey: .trackingSpaceID)
    try encodeBody(into: &container)
  }

  /// tracking space IDをJSONのkeyへ出す場合の本体だけの書き出し。
  fileprivate func encodeBody(
    into container: inout KeyedEncodingContainer<CodingKeys>
  ) throws {
    try container.encode(spaceEpoch, forKey: .spaceEpoch)
    try container.encode(transform.translation.packed, forKey: .translation)
    try container.encode(transform.rotation.packed, forKey: .rotation)
    try container.encode(method, forKey: .method)
    try container.encode(sampleCount, forKey: .sampleCount)
    try container.encodeIfPresent(rmsErrorM, forKey: .rmsErrorM)
    try container.encodeIfPresent(maxResidualM, forKey: .maxResidualM)
    try container.encodeIfPresent(operatorNote, forKey: .operatorNote)
    try container.encode(updatedAt, forKey: .updatedAt)
  }
}

extension CalibrationProfile: Codable {
  private enum CodingKeys: String, CodingKey {
    case formatVersion
    case profileID = "profileId"
    case name
    case revision
    case createdAt
    case updatedAt
    case applicationVersion
    case spaces
  }

  private struct SpaceKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
      self.stringValue = stringValue
    }

    init?(intValue: Int) {
      nil
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let formatVersion = try container.decode(Int.self, forKey: .formatVersion)
    guard formatVersion == Self.currentFormatVersion else {
      throw CalibrationProfileError.unsupportedFormatVersion(formatVersion)
    }

    let spacesContainer = try container.nestedContainer(
      keyedBy: SpaceKey.self,
      forKey: .spaces
    )
    var spaces: [SpaceCalibration] = []
    for key in spacesContainer.allKeys {
      let trackingSpaceID = try UUIDBytes(calibrationString: key.stringValue)
      let spaceDecoder = try spacesContainer.superDecoder(forKey: key)
      spaces.append(
        try SpaceCalibration(from: spaceDecoder, trackingSpaceID: trackingSpaceID)
      )
    }

    try self.init(
      profileID: try container.decode(String.self, forKey: .profileID),
      name: try container.decode(String.self, forKey: .name),
      revision: try container.decode(UInt32.self, forKey: .revision),
      createdAt: try container.decode(Date.self, forKey: .createdAt),
      updatedAt: try container.decode(Date.self, forKey: .updatedAt),
      applicationVersion: try container.decode(String.self, forKey: .applicationVersion),
      spaces: spaces,
      formatVersion: formatVersion
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(formatVersion, forKey: .formatVersion)
    try container.encode(profileID, forKey: .profileID)
    try container.encode(name, forKey: .name)
    try container.encode(revision, forKey: .revision)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(updatedAt, forKey: .updatedAt)
    try container.encode(applicationVersion, forKey: .applicationVersion)

    var spacesContainer = container.nestedContainer(
      keyedBy: SpaceKey.self,
      forKey: .spaces
    )
    for space in sortedSpaces {
      var spaceContainer = spacesContainer.nestedContainer(
        keyedBy: SpaceCalibration.CodingKeys.self,
        forKey: SpaceKey(stringValue: space.trackingSpaceID.description)
      )
      try space.encodeBody(into: &spaceContainer)
    }
  }
}

extension UUIDBytes {
  /// RFC 4122のcanonical文字列から復元する。
  public init(calibrationString string: String) throws {
    let hex = string.replacingOccurrences(of: "-", with: "")
    guard hex.count == UUIDBytes.byteCount * 2 else {
      throw CalibrationCodingError.invalidTrackingSpaceID(string)
    }

    var bytes: [UInt8] = []
    bytes.reserveCapacity(UUIDBytes.byteCount)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else {
        throw CalibrationCodingError.invalidTrackingSpaceID(string)
      }
      bytes.append(byte)
      index = next
    }

    try self.init(bytes: bytes)
  }
}

extension Vector3 {
  var packed: [Float] {
    [x, y, z]
  }

  init(unpacking components: [Float]) throws {
    guard components.count == 3 else {
      throw CalibrationCodingError.invalidTranslationLength(actual: components.count)
    }
    self.init(x: components[0], y: components[1], z: components[2])
  }
}

extension Quaternion {
  var packed: [Float] {
    [x, y, z, w]
  }

  init(unpacking components: [Float]) throws {
    guard components.count == 4 else {
      throw CalibrationCodingError.invalidRotationLength(actual: components.count)
    }
    self.init(x: components[0], y: components[1], z: components[2], w: components[3])
  }
}
