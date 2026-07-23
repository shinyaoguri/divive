import HubProtocol
import HubSimulator

public enum HubAppMotionPreset: String, CaseIterable, Identifiable, Sendable {
  case stationary
  case circle

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .stationary: "静止"
    case .circle: "円運動"
    }
  }
}

public enum HubAppConfigurationError: Error, Equatable, Sendable {
  case trackerCountOutOfRange
}

/// GUIの入力値を、決定論的なHeadless Simulator設定へ変換する。
public struct HubAppConfiguration: Equatable, Sendable {
  public let trackerCount: Int
  public let rate: SimulatorRate
  public let motion: HubAppMotionPreset
  public let seed: UInt64
  public let frameLossProbability: Double
  public let trackingLostProbability: Double

  public init(
    trackerCount: Int,
    rate: SimulatorRate,
    motion: HubAppMotionPreset,
    seed: UInt64,
    frameLossProbability: Double,
    trackingLostProbability: Double
  ) {
    self.trackerCount = trackerCount
    self.rate = rate
    self.motion = motion
    self.seed = seed
    self.frameLossProbability = frameLossProbability
    self.trackingLostProbability = trackingLostProbability
  }

  public func makeSimulator() throws -> SimulatorEngine {
    guard (1...16).contains(trackerCount) else {
      throw HubAppConfigurationError.trackerCountOutOfRange
    }
    let source = SimulatorSourceConfiguration(
      sessionID: try makeUUID(namespace: 1),
      bridgeID: try makeUUID(namespace: 2),
      trackingSpaceID: try makeUUID(namespace: 3),
      rate: rate
    )
    let faults = try SimulatorFaultConfiguration(
      seed: seed,
      frameLossProbability: frameLossProbability,
      trackingLostProbability: trackingLostProbability
    )
    return try SimulatorEngine(
      source: source,
      trackers: makeTrackers(),
      faults: faults
    )
  }

  private func makeUUID(namespace: UInt8) throws -> UUIDBytes {
    var bytes = [UInt8](repeating: 0, count: UUIDBytes.byteCount)
    bytes[0] = 0xd1
    bytes[1] = 0x56
    bytes[2] = namespace
    for index in 0..<8 {
      let shift = UInt64((7 - index) * 8)
      bytes[8 + index] = UInt8((seed >> shift) & 0xff)
    }
    return try UUIDBytes(bytes: bytes)
  }

  private func makeTrackers() -> [SimulatorTrackerConfiguration] {
    let center = Float(trackerCount - 1) / 2
    return (0..<trackerCount).map { index in
      SimulatorTrackerConfiguration(
        trackerID: String(format: "sim://tracker/%03d", index + 1),
        role: role(for: index),
        position: Vector3(
          x: (Float(index) - center) * 0.4,
          y: 1,
          z: -1
        ),
        motion: motionPreset(for: index)
      )
    }
  }

  private func role(for index: Int) -> String {
    switch index {
    case 0: "waist"
    case 1: "left_foot"
    case 2: "right_foot"
    default: "prop_\(index - 2)"
    }
  }

  private func motionPreset(for index: Int) -> SimulatorMotionPreset {
    switch motion {
    case .stationary:
      .stationary
    case .circle:
      .circle(
        radiusMeters: 0.25,
        angularSpeedRadiansPerSecond: .pi / 2,
        phaseRadians: 2 * .pi * Float(index) / Float(trackerCount)
      )
    }
  }
}
