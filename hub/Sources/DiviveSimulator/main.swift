import Dispatch
import Foundation
import HubCore
import HubProtocol
import HubSimulator

private enum MotionOption: String {
  case stationary = "static"
  case circle
}

private struct Options {
  var trackerCount = 3
  var rate: SimulatorRate = .hz90
  var frames: UInt64 = 0
  var seed: UInt64 = 1
  var motion: MotionOption = .stationary
  var frameLossProbability = 0.0
  var trackingLostProbability = 0.0
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
}

private enum OptionError: Error, CustomStringConvertible {
  case missingValue(String)
  case invalidTrackerCount
  case invalidRate
  case invalidFrames
  case invalidSeed
  case invalidMotion
  case invalidProbability(String)
  case unknownArgument(String)

  var description: String {
    switch self {
    case .missingValue(let option): "\(option) の値がありません"
    case .invalidTrackerCount: "--trackers は0〜64で指定してください"
    case .invalidRate: "--rate は30、60、90、120のいずれかです"
    case .invalidFrames: "--frames は0以上の整数で指定してください"
    case .invalidSeed: "--seed は0以上の整数で指定してください"
    case .invalidMotion: "--motion はstaticまたはcircleです"
    case .invalidProbability(let option):
      "\(option) は0〜1の小数で指定してください"
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
      --seed SEED            障害注入seed。既定値: 1
      --motion PRESET        static / circle。既定値: static
      --frame-loss RATE      frame drop確率。0〜1、既定値: 0
      --tracking-lost RATE   Trackerごとのlost確率。0〜1、既定値: 0
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
  missedDeadlines: UInt64,
  store: HubStateStore,
  monotonicNS: UInt64
) {
  let state = store.evaluatedSnapshot(atMonotonicNS: monotonicNS)
  let simulated = state.trackers.count { $0.trackingState == .simulated }
  let lost = state.trackers.count { $0.trackingState == .lost }
  let disconnected = state.trackers.count { $0.trackingState == .disconnected }
  print(
    "attempted=\(attemptedFrames) emitted=\(emittedFrames) "
      + "dropped=\(droppedFrames) missed_deadlines=\(missedDeadlines) "
      + "trackers=\(state.trackers.count) simulated=\(simulated) "
      + "lost=\(lost) disconnected=\(disconnected)"
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
  let store = HubStateStore()
  let sink: any HubFrameSink = store
  let stopFlag = StopFlag()

  signal(SIGINT, SIG_IGN)
  let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT)
  interruptSource.setEventHandler(handler: stopFlag.requestStop)
  interruptSource.resume()

  print(
    "divive-simulatorを開始しました: rate=\(options.rate.rawValue)Hz "
      + "trackers=\(options.trackerCount) seed=\(options.seed)"
  )
  print("終了するにはControl-Cを押してください")

  let frameIntervalNS = 1_000_000_000 / UInt64(options.rate.rawValue)
  var nextDeadlineNS = DispatchTime.now().uptimeNanoseconds
  var attemptedFrames: UInt64 = 0
  var emittedFrames: UInt64 = 0
  var droppedFrames: UInt64 = 0
  var missedDeadlines: UInt64 = 0
  var lastReportedAttemptedFrames: UInt64?

  while !stopFlag.isStopped,
    options.frames == 0 || attemptedFrames < options.frames
  {
    let beforeWait = DispatchTime.now().uptimeNanoseconds
    if beforeWait < nextDeadlineNS {
      Thread.sleep(
        forTimeInterval: Double(nextDeadlineNS - beforeWait) / 1_000_000_000
      )
    }
    let receivedNS = DispatchTime.now().uptimeNanoseconds
    if receivedNS > nextDeadlineNS + frameIntervalNS {
      missedDeadlines += 1
    }

    let step = try simulator.step(receivedMonotonicNS: receivedNS)
    attemptedFrames += 1
    switch step {
    case .emitted(let frame):
      _ = sink.apply(frame)
      emittedFrames += 1
      if options.printPose {
        let first = frame.poseBatch.trackers.first
        print(
          "frame=\(frame.frameSequence) trackers=\(frame.poseBatch.trackers.count) "
            + "first=\(first?.trackerID ?? "-") "
            + "x=\(first?.position.x ?? 0) y=\(first?.position.y ?? 0) "
            + "z=\(first?.position.z ?? 0)"
        )
      }
    case .dropped:
      droppedFrames += 1
    }

    if attemptedFrames.isMultiple(of: UInt64(options.rate.rawValue)) {
      printStatistics(
        attemptedFrames: attemptedFrames,
        emittedFrames: emittedFrames,
        droppedFrames: droppedFrames,
        missedDeadlines: missedDeadlines,
        store: store,
        monotonicNS: receivedNS
      )
      lastReportedAttemptedFrames = attemptedFrames
    }

    let (advancedDeadline, overflow) =
      nextDeadlineNS.addingReportingOverflow(frameIntervalNS)
    nextDeadlineNS = overflow ? receivedNS : advancedDeadline
  }

  interruptSource.cancel()
  if lastReportedAttemptedFrames != attemptedFrames {
    printStatistics(
      attemptedFrames: attemptedFrames,
      emittedFrames: emittedFrames,
      droppedFrames: droppedFrames,
      missedDeadlines: missedDeadlines,
      store: store,
      monotonicNS: DispatchTime.now().uptimeNanoseconds
    )
  }
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
