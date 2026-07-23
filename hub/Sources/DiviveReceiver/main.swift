import Dispatch
import Foundation
import HubCore
import HubNetworking
import HubProtocol

private struct Options {
  var host = "0.0.0.0"
  var port = 41_320
  var printPose = false
  var lostAfterMS: UInt64 = 250
  var disconnectedAfterMS: UInt64 = 2_000

  static func parse(_ arguments: [String]) throws -> Self {
    var options = Self()
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--bind":
        index += 1
        guard index < arguments.count else { throw OptionError.missingValue("--bind") }
        options.host = arguments[index]
      case "--port":
        index += 1
        guard index < arguments.count, let port = Int(arguments[index]),
          (0...65_535).contains(port)
        else {
          throw OptionError.invalidPort
        }
        options.port = port
      case "--print-pose":
        options.printPose = true
      case "--lost-after-ms":
        index += 1
        options.lostAfterMS = try parseMilliseconds(
          arguments,
          index: index,
          option: "--lost-after-ms"
        )
      case "--disconnected-after-ms":
        index += 1
        options.disconnectedAfterMS = try parseMilliseconds(
          arguments,
          index: index,
          option: "--disconnected-after-ms"
        )
      case "--help", "-h":
        printUsage()
        exit(0)
      default:
        throw OptionError.unknownArgument(arguments[index])
      }
      index += 1
    }
    guard options.disconnectedAfterMS > options.lostAfterMS else {
      throw OptionError.invalidLivenessThresholds
    }
    return options
  }

  var livenessPolicy: HubLivenessPolicy {
    get throws {
      try HubLivenessPolicy(
        lostAfterNS: lostAfterMS * 1_000_000,
        disconnectedAfterNS: disconnectedAfterMS * 1_000_000
      )
    }
  }

  private static func parseMilliseconds(
    _ arguments: [String],
    index: Int,
    option: String
  ) throws -> UInt64 {
    guard index < arguments.count else {
      throw OptionError.missingValue(option)
    }
    guard let value = UInt64(arguments[index]),
      value > 0,
      value <= UInt64.max / 1_000_000
    else {
      throw OptionError.invalidMilliseconds(option)
    }
    return value
  }
}

private enum OptionError: Error, CustomStringConvertible {
  case missingValue(String)
  case invalidPort
  case invalidMilliseconds(String)
  case invalidLivenessThresholds
  case unknownArgument(String)

  var description: String {
    switch self {
    case .missingValue(let argument): "\(argument) の値がありません"
    case .invalidPort: "portは0〜65535の整数で指定してください"
    case .invalidMilliseconds(let argument):
      "\(argument) は1以上のミリ秒で指定してください"
    case .invalidLivenessThresholds:
      "--disconnected-after-ms は --lost-after-ms より大きくしてください"
    case .unknownArgument(let argument): "不明な引数です: \(argument)"
    }
  }
}

private func printUsage() {
  print(
    """
    使用方法: divive-receiver [options]

      --bind ADDRESS              UDP bind先。既定値: 0.0.0.0
      --port PORT                 UDP port。既定値: 41320
      --print-pose                受信したTracker姿勢をpacketごとに表示
      --lost-after-ms MS          stale/lost判定。既定値: 250
      --disconnected-after-ms MS  disconnect判定。既定値: 2000
    """
  )
}

/// NIO event loopとDispatch workerから呼ばれる処理をMainActorから分離する。
private final class ConsoleReporter: @unchecked Sendable {
  private let receiver: UDPReceiver
  private let hubState = HubStateStore()
  private let printPose: Bool
  private let livenessPolicy: HubLivenessPolicy

  init(
    receiver: UDPReceiver,
    printPose: Bool,
    livenessPolicy: HubLivenessPolicy
  ) {
    self.receiver = receiver
    self.printPose = printPose
    self.livenessPolicy = livenessPolicy
  }

  func receive(_ received: ReceivedPosePacket) {
    let assembly = hubState.ingest(
      received.packet,
      receivedMonotonicNS: received.receivedMonotonicNS
    )
    guard printPose else { return }
    let packet = received.packet
    print(
      "frame=\(packet.envelope.frameSequence) "
        + "batch=\(packet.envelope.batchIndex + 1)/\(packet.envelope.batchCount) "
        + "trackers=\(packet.poseBatch.trackers.count) "
        + "emitted_frames=\(assembly.emittedFrames.count) "
        + "processing_us=\(received.processingTimeNS / 1_000)"
    )
  }

  func reject(_ error: PacketDecodeError) {
    fputs("packetを拒否しました: \(error)\n", stderr)
  }

  func printStatistics() {
    let stats = receiver.statistics()
    let state = hubState.evaluatedSnapshot(
      atMonotonicNS: DispatchTime.now().uptimeNanoseconds,
      policy: livenessPolicy
    )
    let fresh = state.trackers.count { $0.liveness == .fresh }
    let stale = state.trackers.count { $0.liveness == .stale }
    let disconnected = state.trackers.count { $0.liveness == .disconnected }
    let tracking = state.trackers.count { $0.trackingState == .tracking }
    let lost = state.trackers.count { $0.trackingState == .lost }
    let simulated = state.trackers.count { $0.trackingState == .simulated }
    print(
      "received=\(stats.datagrams) valid=\(stats.validPackets) "
        + "invalid=\(stats.invalidPackets) loss=\(stats.missingFrames) "
        + "duplicate=\(stats.duplicatePackets) "
        + "out_of_order=\(stats.outOfOrderPackets) "
        + "hub_frames=\(state.stateStatistics.appliedFrames) "
        + "partial=\(state.stateStatistics.partialFrames) "
        + "pending=\(state.assemblerStatistics.pendingFrames) "
        + "latest_trackers=\(state.trackers.count) "
        + "fresh=\(fresh) stale=\(stale) "
        + "tracking=\(tracking) lost=\(lost) "
        + "disconnected=\(disconnected) simulated=\(simulated)"
    )
  }

  func flushPendingFrames() {
    _ = hubState.flushPendingFrames()
  }

  func stateSnapshot() -> HubStateSnapshot {
    hubState.snapshot()
  }

  func stop() {
    try? receiver.close()
  }
}

do {
  let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
  let receiver = UDPReceiver()
  let reporter = ConsoleReporter(
    receiver: receiver,
    printPose: options.printPose,
    livenessPolicy: try options.livenessPolicy
  )
  let address = try receiver.start(
    configuration: .init(host: options.host, port: options.port),
    onPacket: reporter.receive,
    onDecodeError: reporter.reject
  )

  print("divive-receiverを開始しました: \(address)")
  print("終了するにはControl-Cを押してください")

  signal(SIGINT, SIG_IGN)
  let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT)
  interruptSource.setEventHandler(handler: reporter.stop)
  interruptSource.resume()

  let metricsTimer = DispatchSource.makeTimerSource()
  metricsTimer.schedule(deadline: .now() + 1, repeating: 1)
  metricsTimer.setEventHandler(handler: reporter.printStatistics)
  metricsTimer.resume()

  try receiver.waitUntilClosed()
  reporter.flushPendingFrames()
  metricsTimer.cancel()
  interruptSource.cancel()
  try receiver.shutdown()

  let stats = receiver.statistics()
  let state = reporter.stateSnapshot()
  print(
    "終了: received=\(stats.datagrams) valid=\(stats.validPackets) "
      + "invalid=\(stats.invalidPackets) "
      + "hub_frames=\(state.stateStatistics.appliedFrames) "
      + "latest_trackers=\(state.trackers.count)"
  )
} catch {
  fputs("起動できませんでした: \(error)\n", stderr)
  printUsage()
  exit(1)
}
