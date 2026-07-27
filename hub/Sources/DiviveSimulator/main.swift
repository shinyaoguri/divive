import Dispatch
import Foundation
import HubCore
import HubProtocol
import HubSimulator

private enum MotionOption: String {
  case stationary = "static"
  case circle
  case walk
  case jump
  case random
}

private struct Options {
  var trackerCount = 3
  var rate: SimulatorRate = .hz90
  var frames: UInt64 = 0
  var seed: UInt64 = 1
  var motion: MotionOption = .stationary
  var frameLossProbability = 0.0
  var trackingLostProbability = 0.0
  var delayMilliseconds: UInt64 = 0
  var jitterMilliseconds: UInt64 = 0
  var reorderingProbability = 0.0
  var disconnectProbability = 0.0
  var disconnectDurationMilliseconds: UInt64 = 2_500
  var printPose = false

  static func parse(_ arguments: [String]) throws -> Self {
    var options = Self()
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--trackers":
        index += 1
        guard index < arguments.count,
          let count = Int(arguments[index]),
          (0...64).contains(count)
        else {
          throw OptionError.invalidTrackerCount
        }
        options.trackerCount = count
      case "--rate":
        index += 1
        guard index < arguments.count,
          let rawRate = UInt16(arguments[index]),
          let rate = SimulatorRate(rawValue: rawRate)
        else {
          throw OptionError.invalidRate
        }
        options.rate = rate
      case "--frames":
        index += 1
        guard index < arguments.count,
          let frames = UInt64(arguments[index])
        else {
          throw OptionError.invalidFrames
        }
        options.frames = frames
      case "--seed":
        index += 1
        guard index < arguments.count,
          let seed = UInt64(arguments[index])
        else {
          throw OptionError.invalidSeed
        }
        options.seed = seed
      case "--motion":
        index += 1
        guard index < arguments.count,
          let motion = MotionOption(rawValue: arguments[index])
        else {
          throw OptionError.invalidMotion
        }
        options.motion = motion
      case "--frame-loss":
        index += 1
        options.frameLossProbability = try parseProbability(
          arguments,
          index: index,
          option: "--frame-loss"
        )
      case "--tracking-lost":
        index += 1
        options.trackingLostProbability = try parseProbability(
          arguments,
          index: index,
          option: "--tracking-lost"
        )
      case "--delay-ms":
        index += 1
        options.delayMilliseconds = try parseDuration(
          arguments,
          index: index,
          option: "--delay-ms"
        )
      case "--jitter-ms":
        index += 1
        options.jitterMilliseconds = try parseDuration(
          arguments,
          index: index,
          option: "--jitter-ms"
        )
      case "--reordering":
        index += 1
        options.reorderingProbability = try parseProbability(
          arguments,
          index: index,
          option: "--reordering"
        )
      case "--disconnect":
        index += 1
        options.disconnectProbability = try parseProbability(
          arguments,
          index: index,
          option: "--disconnect"
        )
      case "--disconnect-ms":
        index += 1
        options.disconnectDurationMilliseconds = try parseDuration(
          arguments,
          index: index,
          option: "--disconnect-ms"
        )
      case "--print-pose":
        options.printPose = true
      case "--help", "-h":
        printUsage()
        exit(0)
      default:
        throw OptionError.unknownArgument(arguments[index])
      }
      index += 1
    }
    return options
  }

  private static func parseProbability(
    _ arguments: [String],
    index: Int,
    option: String
  ) throws -> Double {
    guard index < arguments.count else {
      throw OptionError.missingValue(option)
    }
    guard let value = Double(arguments[index]),
      value.isFinite,
      (0...1).contains(value)
    else {
      throw OptionError.invalidProbability(option)
    }
    return value
  }

  private static func parseDuration(
    _ arguments: [String],
    index: Int,
    option: String
  ) throws -> UInt64 {
    guard index < arguments.count else {
      throw OptionError.missingValue(option)
    }
    guard let value = UInt64(arguments[index]),
      value <= UInt64.max / 1_000_000
    else {
      throw OptionError.invalidDuration(option)
    }
    return value
  }
}

private enum OptionError: Error, CustomStringConvertible {
  case missingValue(String)
  case invalidTrackerCount
  case invalidRate
  case invalidFrames
  case invalidSeed
  case invalidMotion
  case invalidProbability(String)
  case invalidDuration(String)
  case unknownArgument(String)

  var description: String {
    switch self {
    case .missingValue(let option): "\(option) の値がありません"
    case .invalidTrackerCount: "--trackers は0〜64で指定してください"
    case .invalidRate: "--rate は30、60、90、120のいずれかです"
    case .invalidFrames: "--frames は0以上の整数で指定してください"
    case .invalidSeed: "--seed は0以上の整数で指定してください"
    case .invalidMotion:
      "--motion はstatic、circle、walk、jump、randomのいずれかです"
    case .invalidProbability(let option):
      "\(option) は0〜1の小数で指定してください"
    case .invalidDuration(let option):
      "\(option) は0以上の整数（ミリ秒）で指定してください"
    case .unknownArgument(let argument): "不明な引数です: \(argument)"
    }
  }
}

private func printUsage() {
  print(
    """
    使用方法: divive-simulator [options]

      --trackers COUNT       Tracker数。既定値: 3、最大: 64
      --rate HZ              30 / 60 / 90 / 120。既定値: 90
      --frames COUNT         生成frame数。0はControl-Cまで継続。既定値: 0
      --seed SEED            motionと障害注入の再現用seed。既定値: 1
      --motion PRESET        static / circle / walk / jump / random
                             既定値: static
      --frame-loss RATE      frame drop確率。0〜1、既定値: 0
      --tracking-lost RATE   Trackerごとのlost確率。0〜1、既定値: 0
      --delay-ms MS          固定配信遅延。既定値: 0
      --jitter-ms MS         配信遅延の±jitter。既定値: 0
      --reordering RATE      隣接frameの順序逆転確率。0〜1、既定値: 0
      --disconnect RATE      接続断開始確率。0〜1、既定値: 0
      --disconnect-ms MS     1回の接続断時間。既定値: 2500
      --print-pose           emitted frameごとの姿勢を表示
    """
  )
}

private final class StopFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false

  var isStopped: Bool {
    lock.withLock { stopped }
  }

  func requestStop() {
    lock.withLock {
      stopped = true
    }
  }
}

private func makeUUID(namespace: UInt8, seed: UInt64) throws -> UUIDBytes {
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

private func role(for index: Int) -> String {
  switch index {
  case 0: "waist"
  case 1: "left_foot"
  case 2: "right_foot"
  default: "prop_\(index - 2)"
  }
}

private func makeTrackers(_ options: Options) -> [SimulatorTrackerConfiguration] {
  let center = Float(options.trackerCount - 1) / 2
  return (0..<options.trackerCount).map { index in
    let motion: SimulatorMotionPreset =
      switch options.motion {
      case .stationary:
        .stationary
      case .circle:
        .circle(
          radiusMeters: 0.25,
          angularSpeedRadiansPerSecond: .pi / 2,
          phaseRadians: 2 * .pi * Float(index)
            / Float(max(options.trackerCount, 1))
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
          seed: options.seed &+ UInt64(index)
        )
      }
    return SimulatorTrackerConfiguration(
      trackerID: String(format: "sim://tracker/%03d", index + 1),
      role: role(for: index),
      position: Vector3(
        x: (Float(index) - center) * 0.4,
        y: 1,
        z: -1
      ),
      motion: motion
    )
  }
}

private func printStatistics(
  attemptedFrames: UInt64,
  emittedFrames: UInt64,
  droppedFrames: UInt64,
  staleFrames: UInt64,
  missedDeadlines: UInt64,
  transport: SimulatorTransportFaultStatistics,
  store: HubStateStore,
  monotonicNS: UInt64
) {
  let state = store.evaluatedSnapshot(atMonotonicNS: monotonicNS)
  let simulated = state.trackers.count { $0.trackingState == .simulated }
  let lost = state.trackers.count { $0.trackingState == .lost }
  let disconnected = state.trackers.count { $0.trackingState == .disconnected }
  print(
    "attempted=\(attemptedFrames) emitted=\(emittedFrames) "
      + "dropped=\(droppedFrames) stale=\(staleFrames) "
      + "disconnect_events=\(transport.disconnectEvents) "
      + "disconnect_dropped=\(transport.disconnectedFrames) "
      + "pending=\(transport.pendingFrames) "
      + "overflow=\(transport.overflowFrames) "
      + "missed_deadlines=\(missedDeadlines) "
      + "trackers=\(state.trackers.count) simulated=\(simulated) "
      + "lost=\(lost) trackers_disconnected=\(disconnected)"
  )
}

do {
  let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
  let source = SimulatorSourceConfiguration(
    sessionID: try makeUUID(namespace: 1, seed: options.seed),
    bridgeID: try makeUUID(namespace: 2, seed: options.seed),
    trackingSpaceID: try makeUUID(namespace: 3, seed: options.seed),
    rate: options.rate
  )
  let faults = try SimulatorFaultConfiguration(
    seed: options.seed,
    frameLossProbability: options.frameLossProbability,
    trackingLostProbability: options.trackingLostProbability
  )
  var simulator = try SimulatorEngine(
    source: source,
    trackers: makeTrackers(options),
    faults: faults
  )
  let frameIntervalNS = 1_000_000_000 / UInt64(options.rate.rawValue)
  var transport = try SimulatorTransportFaultPipeline(
    configuration: SimulatorTransportFaultConfiguration(
      seed: options.seed ^ 0x7472_616e_7370_6f72,
      delayNS: options.delayMilliseconds * 1_000_000,
      jitterNS: options.jitterMilliseconds * 1_000_000,
      reorderingProbability: options.reorderingProbability,
      disconnectProbability: options.disconnectProbability,
      disconnectDurationNS:
        options.disconnectDurationMilliseconds * 1_000_000
    ),
    frameIntervalNS: frameIntervalNS
  )
  let store = HubStateStore()
  let sink: any HubFrameSink = store
  let stopFlag = StopFlag()

  signal(SIGINT, SIG_IGN)
  let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT)
  interruptSource.setEventHandler(handler: stopFlag.requestStop)
  interruptSource.resume()

  print(
    "divive-simulatorを開始しました: rate=\(options.rate.rawValue)Hz "
      + "trackers=\(options.trackerCount) motion=\(options.motion.rawValue) "
      + "seed=\(options.seed)"
  )
  print("終了するにはControl-Cを押してください")

  var nextGenerationNS = DispatchTime.now().uptimeNanoseconds
  var attemptedFrames: UInt64 = 0
  var emittedFrames: UInt64 = 0
  var droppedFrames: UInt64 = 0
  var staleFrames: UInt64 = 0
  var missedDeadlines: UInt64 = 0

  while !stopFlag.isStopped,
    options.frames == 0 || attemptedFrames < options.frames
      || transport.statistics.pendingFrames > 0
  {
    let shouldContinueGenerating =
      options.frames == 0 || attemptedFrames < options.frames
    let nextWakeNS = min(
      shouldContinueGenerating ? nextGenerationNS : UInt64.max,
      transport.nextDeliveryMonotonicNS ?? UInt64.max
    )
    let beforeWait = DispatchTime.now().uptimeNanoseconds
    if beforeWait < nextWakeNS {
      Thread.sleep(
        forTimeInterval: Double(nextWakeNS - beforeWait) / 1_000_000_000
      )
    }
    let receivedNS = DispatchTime.now().uptimeNanoseconds

    var generatedFrame: AssembledPoseFrame?
    let shouldGenerate =
      shouldContinueGenerating && receivedNS >= nextGenerationNS
    if shouldGenerate {
      let (missThreshold, thresholdOverflow) =
        nextGenerationNS.addingReportingOverflow(frameIntervalNS)
      if thresholdOverflow || receivedNS > missThreshold {
        missedDeadlines += 1
        nextGenerationNS = receivedNS
      }
      let step = try simulator.step(receivedMonotonicNS: receivedNS)
      attemptedFrames += 1
      switch step {
      case .emitted(let frame):
        generatedFrame = frame
      case .dropped:
        droppedFrames += 1
      }
      let (advancedGeneration, generationOverflow) =
        nextGenerationNS.addingReportingOverflow(frameIntervalNS)
      nextGenerationNS =
        generationOverflow ? UInt64.max : advancedGeneration
    }

    let deliveredFrames = transport.advance(
      toMonotonicNS: receivedNS,
      offering: generatedFrame
    )
    for frame in deliveredFrames {
      switch sink.apply(frame) {
      case .applied:
        emittedFrames += 1
      case .stale:
        staleFrames += 1
      }
      if options.printPose {
        let first = frame.poseBatch.trackers.first
        print(
          "frame=\(frame.frameSequence) trackers=\(frame.poseBatch.trackers.count) "
            + "first=\(first?.trackerID ?? "-") "
            + "x=\(first?.position.x ?? 0) y=\(first?.position.y ?? 0) "
            + "z=\(first?.position.z ?? 0)"
        )
      }
    }

    if shouldGenerate,
      attemptedFrames.isMultiple(of: UInt64(options.rate.rawValue))
    {
      printStatistics(
        attemptedFrames: attemptedFrames,
        emittedFrames: emittedFrames,
        droppedFrames: droppedFrames,
        staleFrames: staleFrames,
        missedDeadlines: missedDeadlines,
        transport: transport.statistics,
        store: store,
        monotonicNS: receivedNS
      )
    }

  }

  interruptSource.cancel()
  printStatistics(
    attemptedFrames: attemptedFrames,
    emittedFrames: emittedFrames,
    droppedFrames: droppedFrames,
    staleFrames: staleFrames,
    missedDeadlines: missedDeadlines,
    transport: transport.statistics,
    store: store,
    monotonicNS: DispatchTime.now().uptimeNanoseconds
  )
  print("divive-simulatorを終了しました")
} catch {
  fputs("起動できませんでした: \(error)\n", stderr)
  printUsage()
  exit(1)
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
