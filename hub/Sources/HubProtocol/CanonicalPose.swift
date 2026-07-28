import Foundation

/// RFC 4122の16-byte表現を、言語runtimeのUUID layoutに依存せず保持する。
public struct UUIDBytes: Hashable, Sendable, CustomStringConvertible {
  public static let byteCount = 16

  /// 全ビットが0のnil UUID。未設定を表す既定値として使う。
  public static let zero = UUIDBytes(words: (0, 0, 0, 0))

  public let bytes: [UInt8]

  public init(bytes: [UInt8]) throws {
    guard bytes.count == Self.byteCount else {
      throw UUIDBytesError.invalidLength(actual: bytes.count)
    }
    self.bytes = bytes
  }

  init(words: (UInt32, UInt32, UInt32, UInt32)) {
    bytes =
      Self.bytes(of: words.0)
      + Self.bytes(of: words.1)
      + Self.bytes(of: words.2)
      + Self.bytes(of: words.3)
  }

  public var isNil: Bool {
    bytes.allSatisfy { $0 == 0 }
  }

  public var description: String {
    let hex = bytes.map { String(format: "%02x", $0) }
    return [
      hex[0..<4].joined(),
      hex[4..<6].joined(),
      hex[6..<8].joined(),
      hex[8..<10].joined(),
      hex[10..<16].joined(),
    ].joined(separator: "-")
  }

  private static func bytes(of word: UInt32) -> [UInt8] {
    [
      UInt8((word >> 24) & 0xff),
      UInt8((word >> 16) & 0xff),
      UInt8((word >> 8) & 0xff),
      UInt8(word & 0xff),
    ]
  }
}

public enum UUIDBytesError: Error, Equatable, Sendable {
  case invalidLength(actual: Int)
}

public enum Backend: String, Sendable {
  case unknown
  case openvr
  case openxr
  case simulator
  case playback
}

public enum TrackerIDKind: String, Sendable {
  case unknown
  case permanent
  case session
}

public enum TrackingState: String, Sendable {
  case unknown
  case tracking
  case lost
  case disconnected
  case simulated
}

public enum TrackingReason: String, Sendable {
  case unknown
  case none
  case runtimePoseInvalid = "runtime_pose_invalid"
  case outOfRange = "out_of_range"
  case deviceUnplugged = "device_unplugged"
  case bridgeTimeout = "bridge_timeout"
  case networkStale = "network_stale"
  case simulatedFault = "simulated_fault"
}

public struct Vector3: Equatable, Sendable {
  public let x: Float
  public let y: Float
  public let z: Float

  public init(x: Float, y: Float, z: Float) {
    self.x = x
    self.y = y
    self.z = z
  }
}

public struct Quaternion: Equatable, Sendable {
  public let x: Float
  public let y: Float
  public let z: Float
  public let w: Float

  public init(x: Float, y: Float, z: Float, w: Float) {
    self.x = x
    self.y = y
    self.z = z
    self.w = w
  }
}

public struct BatteryStatus: Equatable, Sendable {
  public let level: Float
  public let charging: Bool

  public init(level: Float, charging: Bool) {
    self.level = level
    self.charging = charging
  }
}

public struct TrackerPose: Equatable, Sendable {
  public let trackerID: String
  public let idKind: TrackerIDKind
  public let role: String
  public let runtimeRole: String
  public let position: Vector3
  public let orientation: Quaternion
  public let linearVelocity: Vector3?
  public let angularVelocity: Vector3?
  public let trackingState: TrackingState
  public let trackingReason: TrackingReason
  public let connected: Bool
  public let battery: BatteryStatus?
  public let deviceMetadataRevision: UInt32

  public init(
    trackerID: String,
    idKind: TrackerIDKind,
    role: String,
    runtimeRole: String,
    position: Vector3,
    orientation: Quaternion,
    linearVelocity: Vector3?,
    angularVelocity: Vector3?,
    trackingState: TrackingState,
    trackingReason: TrackingReason,
    connected: Bool,
    battery: BatteryStatus?,
    deviceMetadataRevision: UInt32
  ) {
    self.trackerID = trackerID
    self.idKind = idKind
    self.role = role
    self.runtimeRole = runtimeRole
    self.position = position
    self.orientation = orientation
    self.linearVelocity = linearVelocity
    self.angularVelocity = angularVelocity
    self.trackingState = trackingState
    self.trackingReason = trackingReason
    self.connected = connected
    self.battery = battery
    self.deviceMetadataRevision = deviceMetadataRevision
  }
}

public struct PoseBatch: Equatable, Sendable {
  public let trackingSpaceID: UUIDBytes
  public let spaceEpoch: UInt32
  public let captureMonotonicNS: UInt64
  public let sendMonotonicNS: UInt64
  public let requestedRateHz: UInt16
  public let backend: Backend
  public let trackers: [TrackerPose]

  public init(
    trackingSpaceID: UUIDBytes,
    spaceEpoch: UInt32,
    captureMonotonicNS: UInt64,
    sendMonotonicNS: UInt64,
    requestedRateHz: UInt16,
    backend: Backend,
    trackers: [TrackerPose]
  ) {
    self.trackingSpaceID = trackingSpaceID
    self.spaceEpoch = spaceEpoch
    self.captureMonotonicNS = captureMonotonicNS
    self.sendMonotonicNS = sendMonotonicNS
    self.requestedRateHz = requestedRateHz
    self.backend = backend
    self.trackers = trackers
  }
}
