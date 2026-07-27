import HubProtocol
import HubSimulator

public enum HubAppMotionPreset: String, CaseIterable, Identifiable, Sendable {
  case stationary
  case circle
  case walk
  case jump
  case random

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .stationary: "静止"
    case .circle: "円運動"
    case .walk: "歩行"
    case .jump: "ジャンプ"
    case .random: "ランダム移動"
    }
  }
}

public enum HubAppConfigurationError: Error, Equatable, Sendable {
  case trackerCountOutOfRange
  case invalidDuration(HubAppDurationField)
}

/// GUIの入力値を、決定論的なHeadless Simulator設定へ変換する。
public struct HubAppConfiguration: Equatable, Sendable {
  public let trackerCount: Int
  public let rate: SimulatorRate
  public let motion: HubAppMotionPreset
  public let seed: UInt64
  public let frameLossProbability: Double
  public let trackingLostProbability: Double
  public let delayMilliseconds: Double
  public let jitterMilliseconds: Double
  public let reorderingProbability: Double
  public let disconnectProbability: Double
  public let disconnectDurationMilliseconds: Double

  public init(
    trackerCount: Int,
    rate: SimulatorRate,
    motion: HubAppMotionPreset,
    seed: UInt64,
    frameLossProbability: Double,
    trackingLostProbability: Double,
    delayMilliseconds: Double = 0,
    jitterMilliseconds: Double = 0,
    reorderingProbability: Double = 0,
    disconnectProbability: Double = 0,
    disconnectDurationMilliseconds: Double = 2_500
  ) {
    self.trackerCount = trackerCount
    self.rate = rate
    self.motion = motion
    self.seed = seed
    self.frameLossProbability = frameLossProbability
    self.trackingLostProbability = trackingLostProbability
    self.delayMilliseconds = delayMilliseconds
    self.jitterMilliseconds = jitterMilliseconds
    self.reorderingProbability = reorderingProbability
    self.disconnectProbability = disconnectProbability
    self.disconnectDurationMilliseconds = disconnectDurationMilliseconds
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

  public func makeTransportFaultPipeline() throws
    -> SimulatorTransportFaultPipeline
  {
    let frameIntervalNS = 1_000_000_000 / UInt64(rate.rawValue)
    return try SimulatorTransportFaultPipeline(
      configuration: SimulatorTransportFaultConfiguration(
        seed: seed ^ 0x7472_616e_7370_6f72,
        delayNS: try nanoseconds(
          fromMilliseconds: delayMilliseconds,
          field: .delay
        ),
        jitterNS: try nanoseconds(
          fromMilliseconds: jitterMilliseconds,
          field: .jitter
        ),
        reorderingProbability: reorderingProbability,
        disconnectProbability: disconnectProbability,
        disconnectDurationNS: try nanoseconds(
          fromMilliseconds: disconnectDurationMilliseconds,
          field: .disconnectDuration
        )
      ),
      frameIntervalNS: frameIntervalNS
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
    // 16台でも既定の±2mプレビュー内へ収まるよう、全体幅を3m以内にする。
    let spacing = min(0.4, 3 / Float(max(trackerCount - 1, 1)))
    return (0..<trackerCount).map { index in
      SimulatorTrackerConfiguration(
        trackerID: String(format: "sim://tracker/%03d", index + 1),
        role: role(for: index),
        position: Vector3(
          x: (Float(index) - center) * spacing,
          y: 1,
          z: -1
        ),
        motion: motionPreset(for: index)
      )
    }
  }

  private func nanoseconds(
    fromMilliseconds milliseconds: Double,
    field: HubAppDurationField
  ) throws -> UInt64 {
    guard milliseconds.isFinite,
      milliseconds >= 0,
      milliseconds <= Double(UInt64.max) / 1_000_000
    else {
      throw HubAppConfigurationError.invalidDuration(field)
    }
    return UInt64((milliseconds * 1_000_000).rounded())
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
    case .walk:
      .walk(
        strideLengthMeters: index == 0 ? 0.08 : 0.3,
        stepHeightMeters: index == 0 ? 0.04 : 0.12,
        cadenceHz: 1.6,
        phaseRadians: index == 2 ? .pi : 0
      )
    case .jump:
      .jump(
        heightMeters: 0.35,
        frequencyHz: 0.75,
        phaseRadians: 0
      )
    case .random:
      .random(
        maximumOffsetMeters: Vector3(x: 0.4, y: 0.25, z: 0.4),
        frequencyHz: 0.2,
        seed: seed &+ UInt64(index)
      )
    }
  }
}

public enum HubAppDurationField: Equatable, Sendable {
  case delay
  case jitter
  case disconnectDuration
}
