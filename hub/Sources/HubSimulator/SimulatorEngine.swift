import Foundation
import HubCore
import HubProtocol

public enum SimulatorRate: UInt16, CaseIterable, Sendable {
  case hz30 = 30
  case hz60 = 60
  case hz90 = 90
  case hz120 = 120
}

public enum SimulatorMotionPreset: Equatable, Sendable {
  case stationary
  case circle(
    radiusMeters: Float,
    angularSpeedRadiansPerSecond: Float,
    phaseRadians: Float
  )
  case walk(
    strideLengthMeters: Float,
    stepHeightMeters: Float,
    cadenceHz: Float,
    phaseRadians: Float
  )
  case jump(
    heightMeters: Float,
    frequencyHz: Float,
    phaseRadians: Float
  )
  case random(
    maximumOffsetMeters: Vector3,
    frequencyHz: Float,
    seed: UInt64
  )
}

public struct SimulatorTrackerConfiguration: Equatable, Sendable {
  public let trackerID: String
  public let role: String
  public let position: Vector3
  public let orientation: Quaternion
  public let motion: SimulatorMotionPreset
  public let trackingState: TrackingState
  public let trackingReason: TrackingReason
  public let connected: Bool
  public let deviceMetadataRevision: UInt32

  public init(
    trackerID: String,
    role: String,
    position: Vector3,
    orientation: Quaternion = Quaternion(x: 0, y: 0, z: 0, w: 1),
    motion: SimulatorMotionPreset = .stationary,
    trackingState: TrackingState = .simulated,
    trackingReason: TrackingReason = .none,
    connected: Bool = true,
    deviceMetadataRevision: UInt32 = 1
  ) {
    self.trackerID = trackerID
    self.role = role
    self.position = position
    self.orientation = orientation
    self.motion = motion
    self.trackingState = trackingState
    self.trackingReason = trackingReason
    self.connected = connected
    self.deviceMetadataRevision = deviceMetadataRevision
  }
}

public struct SimulatorSourceConfiguration: Equatable, Sendable {
  public let sessionID: UUIDBytes
  public let bridgeID: UUIDBytes
  public let trackingSpaceID: UUIDBytes
  public let spaceEpoch: UInt32
  public let rate: SimulatorRate

  public init(
    sessionID: UUIDBytes,
    bridgeID: UUIDBytes,
    trackingSpaceID: UUIDBytes,
    spaceEpoch: UInt32 = 1,
    rate: SimulatorRate = .hz90
  ) {
    self.sessionID = sessionID
    self.bridgeID = bridgeID
    self.trackingSpaceID = trackingSpaceID
    self.spaceEpoch = spaceEpoch
    self.rate = rate
  }
}

public enum SimulatorFaultConfigurationError: Error, Equatable, Sendable {
  case invalidFrameLossProbability
  case invalidTrackingLostProbability
}

public struct SimulatorFaultConfiguration: Equatable, Sendable {
  public let seed: UInt64
  public let frameLossProbability: Double
  public let trackingLostProbability: Double

  public init() {
    seed = 1
    frameLossProbability = 0
    trackingLostProbability = 0
  }

  public init(
    seed: UInt64,
    frameLossProbability: Double,
    trackingLostProbability: Double
  ) throws {
    guard frameLossProbability.isFinite,
      (0...1).contains(frameLossProbability)
    else {
      throw SimulatorFaultConfigurationError.invalidFrameLossProbability
    }
    guard trackingLostProbability.isFinite,
      (0...1).contains(trackingLostProbability)
    else {
      throw SimulatorFaultConfigurationError.invalidTrackingLostProbability
    }
    self.seed = seed
    self.frameLossProbability = frameLossProbability
    self.trackingLostProbability = trackingLostProbability
  }
}

public enum SimulatorConfigurationError: Error, Equatable, Sendable {
  case nilSessionID
  case nilBridgeID
  case nilTrackingSpaceID
  case emptyTrackerID
  case duplicateTrackerID(String)
  case trackerNotFound(String)
  case nonFinitePose(String)
  case nonNormalizedOrientation(String)
  case invalidCircle(String)
  case invalidWalk(String)
  case invalidJump(String)
  case invalidRandom(String)
  case sequenceExhausted
}

public enum SimulatorStep: Equatable, Sendable {
  case emitted(AssembledPoseFrame)
  case dropped(frameSequence: UInt64)

  public var frameSequence: UInt64 {
    switch self {
    case .emitted(let frame): frame.frameSequence
    case .dropped(let sequence): sequence
    }
  }
}

/// GUIや実時間clockから独立した固定step Simulator。
///
/// motion timeは`frameSequence / rate`から求めるため、同じ設定とseedなら
/// 実行速度や開始時刻に依存せず同じ結果を生成する。
public struct SimulatorEngine: Sendable {
  public let source: SimulatorSourceConfiguration

  private var trackers: [String: SimulatorTrackerConfiguration] = [:]
  private var faults: SimulatorFaultConfiguration
  private var random: SplitMix64
  private var nextFrameSequence: UInt64 = 0

  public init(
    source: SimulatorSourceConfiguration,
    trackers: [SimulatorTrackerConfiguration] = [],
    faults: SimulatorFaultConfiguration = SimulatorFaultConfiguration()
  ) throws {
    guard !source.sessionID.isNil else {
      throw SimulatorConfigurationError.nilSessionID
    }
    guard !source.bridgeID.isNil else {
      throw SimulatorConfigurationError.nilBridgeID
    }
    guard !source.trackingSpaceID.isNil else {
      throw SimulatorConfigurationError.nilTrackingSpaceID
    }
    self.source = source
    self.faults = faults
    random = SplitMix64(seed: faults.seed)

    for tracker in trackers {
      try addTracker(tracker)
    }
  }

  public var frameSequence: UInt64 {
    nextFrameSequence
  }

  public var trackerConfigurations: [SimulatorTrackerConfiguration] {
    trackers.values.sorted { $0.trackerID < $1.trackerID }
  }

  public mutating func setFaultConfiguration(
    _ configuration: SimulatorFaultConfiguration
  ) {
    faults = configuration
    random = SplitMix64(seed: configuration.seed)
  }

  public mutating func addTracker(
    _ configuration: SimulatorTrackerConfiguration
  ) throws {
    try validate(configuration)
    guard trackers[configuration.trackerID] == nil else {
      throw SimulatorConfigurationError.duplicateTrackerID(
        configuration.trackerID
      )
    }
    trackers[configuration.trackerID] = configuration
  }

  public mutating func updateTracker(
    existingID: String,
    configuration: SimulatorTrackerConfiguration
  ) throws {
    guard trackers[existingID] != nil else {
      throw SimulatorConfigurationError.trackerNotFound(existingID)
    }
    try validate(configuration)
    if configuration.trackerID != existingID,
      trackers[configuration.trackerID] != nil
    {
      throw SimulatorConfigurationError.duplicateTrackerID(
        configuration.trackerID
      )
    }
    trackers.removeValue(forKey: existingID)
    trackers[configuration.trackerID] = configuration
  }

  @discardableResult
  public mutating func removeTracker(
    id: String
  ) throws -> SimulatorTrackerConfiguration {
    guard let removed = trackers.removeValue(forKey: id) else {
      throw SimulatorConfigurationError.trackerNotFound(id)
    }
    return removed
  }

  public mutating func step(
    receivedMonotonicNS: UInt64
  ) throws -> SimulatorStep {
    guard nextFrameSequence < UInt64.max else {
      throw SimulatorConfigurationError.sequenceExhausted
    }
    let sequence = nextFrameSequence
    nextFrameSequence += 1
    let simulationTime =
      Double(sequence) / Double(source.rate.rawValue)

    let shouldDrop = random.nextUnitInterval() < faults.frameLossProbability
    let poses = trackerConfigurations.map { configuration in
      let forceLost =
        random.nextUnitInterval() < faults.trackingLostProbability
      return pose(
        configuration,
        simulationTime: simulationTime,
        forceLost: forceLost
      )
    }

    guard !shouldDrop else {
      return .dropped(frameSequence: sequence)
    }

    return .emitted(
      AssembledPoseFrame(
        sessionID: source.sessionID,
        bridgeID: source.bridgeID,
        frameSequence: sequence,
        expectedBatchCount: 1,
        receivedBatchIndices: [0],
        firstReceivedMonotonicNS: receivedMonotonicNS,
        lastReceivedMonotonicNS: receivedMonotonicNS,
        completeness: .complete,
        poseBatch: PoseBatch(
          trackingSpaceID: source.trackingSpaceID,
          spaceEpoch: source.spaceEpoch,
          captureMonotonicNS: receivedMonotonicNS,
          sendMonotonicNS: receivedMonotonicNS,
          requestedRateHz: source.rate.rawValue,
          backend: .simulator,
          trackers: poses
        )
      )
    )
  }

  private func pose(
    _ configuration: SimulatorTrackerConfiguration,
    simulationTime: Double,
    forceLost: Bool
  ) -> TrackerPose {
    let motion = resolveMotion(configuration, simulationTime: simulationTime)
    let canInjectLost =
      configuration.connected
      && configuration.trackingState != .disconnected
    let trackingState: TrackingState =
      forceLost && canInjectLost ? .lost : configuration.trackingState
    let trackingReason: TrackingReason =
      forceLost && canInjectLost ? .simulatedFault : configuration.trackingReason

    return TrackerPose(
      trackerID: configuration.trackerID,
      idKind: .permanent,
      role: configuration.role,
      runtimeRole: "",
      position: motion.position,
      orientation: configuration.orientation,
      linearVelocity: motion.linearVelocity,
      angularVelocity: nil,
      trackingState: trackingState,
      trackingReason: trackingReason,
      connected: configuration.connected,
      battery: nil,
      deviceMetadataRevision: configuration.deviceMetadataRevision
    )
  }

  private func resolveMotion(
    _ configuration: SimulatorTrackerConfiguration,
    simulationTime: Double
  ) -> (position: Vector3, linearVelocity: Vector3?) {
    switch configuration.motion {
    case .stationary:
      return (configuration.position, Vector3(x: 0, y: 0, z: 0))
    case .circle(let radius, let angularSpeed, let phase):
      let angle =
        Double(phase) + Double(angularSpeed) * simulationTime
      let cosine = cos(angle)
      let sine = sin(angle)
      return (
        Vector3(
          x: configuration.position.x + radius * Float(cosine),
          y: configuration.position.y,
          z: configuration.position.z - radius * Float(sine)
        ),
        Vector3(
          x: -radius * angularSpeed * Float(sine),
          y: 0,
          z: -radius * angularSpeed * Float(cosine)
        )
      )
    case .walk(let strideLength, let stepHeight, let cadence, let phase):
      let angularSpeed = 2 * Double.pi * Double(cadence)
      let angle = Double(phase) + angularSpeed * simulationTime
      let sine = sin(angle)
      let cosine = cos(angle)
      let liftSine = max(0, sine)
      let halfStride = Double(strideLength) / 2

      return (
        Vector3(
          x: configuration.position.x,
          y: configuration.position.y
            + stepHeight * Float(liftSine * liftSine),
          z: configuration.position.z - Float(halfStride * cosine)
        ),
        Vector3(
          x: 0,
          y: liftSine > 0
            ? stepHeight * Float(angularSpeed * sin(2 * angle))
            : 0,
          z: Float(halfStride * angularSpeed * sine)
        )
      )
    case .jump(let height, let frequency, let phase):
      let angularSpeed = 2 * Double.pi * Double(frequency)
      let angle = Double(phase) + angularSpeed * simulationTime
      let verticalOffset = Double(height) * (1 - cos(angle)) / 2
      let verticalVelocity =
        Double(height) * angularSpeed * sin(angle) / 2

      return (
        Vector3(
          x: configuration.position.x,
          y: configuration.position.y + Float(verticalOffset),
          z: configuration.position.z
        ),
        Vector3(x: 0, y: Float(verticalVelocity), z: 0)
      )
    case .random(let maximumOffset, let frequency, let seed):
      let x = randomAxisMotion(
        maximumOffset: maximumOffset.x,
        frequencyHz: frequency,
        seed: seed,
        axis: 0,
        simulationTime: simulationTime
      )
      let y = randomAxisMotion(
        maximumOffset: maximumOffset.y,
        frequencyHz: frequency,
        seed: seed,
        axis: 1,
        simulationTime: simulationTime
      )
      let z = randomAxisMotion(
        maximumOffset: maximumOffset.z,
        frequencyHz: frequency,
        seed: seed,
        axis: 2,
        simulationTime: simulationTime
      )
      return (
        Vector3(
          x: configuration.position.x + x.offset,
          y: configuration.position.y + y.offset,
          z: configuration.position.z + z.offset
        ),
        Vector3(x: x.velocity, y: y.velocity, z: z.velocity)
      )
    }
  }

  /// seedから2つの正弦波を生成し、wall clockやfault用乱数列に依存しない
  /// 滑らかな疑似random軌道を返す。
  private func randomAxisMotion(
    maximumOffset: Float,
    frequencyHz: Float,
    seed: UInt64,
    axis: UInt64,
    simulationTime: Double
  ) -> (offset: Float, velocity: Float) {
    var random = SplitMix64(
      seed: seed &+ axis &* 0x9e37_79b9_7f4a_7c15
    )
    let primaryPhase = 2 * Double.pi * random.nextUnitInterval()
    let secondaryPhase = 2 * Double.pi * random.nextUnitInterval()
    let secondaryRatio = 1.3 + 0.4 * random.nextUnitInterval()
    let primaryAngularSpeed = 2 * Double.pi * Double(frequencyHz)
    let secondaryAngularSpeed = primaryAngularSpeed * secondaryRatio
    let primaryAngle =
      primaryPhase + primaryAngularSpeed * simulationTime
    let secondaryAngle =
      secondaryPhase + secondaryAngularSpeed * simulationTime
    let maximum = Double(maximumOffset)

    let offset =
      maximum
      * (0.65 * sin(primaryAngle) + 0.35 * sin(secondaryAngle))
    let velocity =
      maximum
      * (0.65 * primaryAngularSpeed * cos(primaryAngle)
        + 0.35 * secondaryAngularSpeed * cos(secondaryAngle))
    return (Float(offset), Float(velocity))
  }

  private func validate(
    _ configuration: SimulatorTrackerConfiguration
  ) throws {
    guard !configuration.trackerID.isEmpty else {
      throw SimulatorConfigurationError.emptyTrackerID
    }
    guard configuration.position.isFinite,
      configuration.orientation.isFinite
    else {
      throw SimulatorConfigurationError.nonFinitePose(
        configuration.trackerID
      )
    }
    guard configuration.orientation.isNormalized else {
      throw SimulatorConfigurationError.nonNormalizedOrientation(
        configuration.trackerID
      )
    }
    switch configuration.motion {
    case .stationary:
      break
    case .circle(let radius, let angularSpeed, let phase):
      guard radius.isFinite,
        radius >= 0,
        angularSpeed.isFinite,
        phase.isFinite
      else {
        throw SimulatorConfigurationError.invalidCircle(
          configuration.trackerID
        )
      }
    case .walk(let strideLength, let stepHeight, let cadence, let phase):
      guard strideLength.isFinite,
        strideLength >= 0,
        stepHeight.isFinite,
        stepHeight >= 0,
        cadence.isFinite,
        cadence > 0,
        phase.isFinite
      else {
        throw SimulatorConfigurationError.invalidWalk(
          configuration.trackerID
        )
      }
    case .jump(let height, let frequency, let phase):
      guard height.isFinite,
        height >= 0,
        frequency.isFinite,
        frequency > 0,
        phase.isFinite
      else {
        throw SimulatorConfigurationError.invalidJump(
          configuration.trackerID
        )
      }
    case .random(let maximumOffset, let frequency, _):
      guard maximumOffset.isFinite,
        maximumOffset.x >= 0,
        maximumOffset.y >= 0,
        maximumOffset.z >= 0,
        frequency.isFinite,
        frequency > 0
      else {
        throw SimulatorConfigurationError.invalidRandom(
          configuration.trackerID
        )
      }
    }
  }
}

private struct SplitMix64: Sendable {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func nextUnitInterval() -> Double {
    let upper53Bits = next() >> 11
    return Double(upper53Bits) * (1.0 / 9_007_199_254_740_992.0)
  }

  private mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var value = state
    value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
    value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
    return value ^ (value >> 31)
  }
}

extension Vector3 {
  fileprivate var isFinite: Bool {
    x.isFinite && y.isFinite && z.isFinite
  }
}

extension Quaternion {
  fileprivate var isFinite: Bool {
    x.isFinite && y.isFinite && z.isFinite && w.isFinite
  }

  fileprivate var isNormalized: Bool {
    let normSquared =
      Double(x) * Double(x)
      + Double(y) * Double(y)
      + Double(z) * Double(z)
      + Double(w) * Double(w)
    return abs(normSquared - 1) <= 1e-3
  }
}
