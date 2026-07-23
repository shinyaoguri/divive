import Dispatch
import Foundation
import HubNetworking
import HubProtocol

private struct Options {
  var host = "0.0.0.0"
  var port = 41_320
  var printPose = false

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
}

private enum OptionError: Error, CustomStringConvertible {
  case missingValue(String)
  case invalidPort
  case unknownArgument(String)

  var description: String {
    switch self {
    case .missingValue(let argument): "\(argument) の値がありません"
    case .invalidPort: "portは0〜65535の整数で指定してください"
    case .unknownArgument(let argument): "不明な引数です: \(argument)"
    }
  }
}

private func printUsage() {
  print(
    """
    使用方法: divive-receiver [--bind ADDRESS] [--port PORT] [--print-pose]

      --bind ADDRESS  UDP bind先。既定値: 0.0.0.0
      --port PORT     UDP port。既定値: 41320
      --print-pose    受信したTracker姿勢をpacketごとに表示
    """
  )
}

/// NIO event loopとDispatch workerから呼ばれる処理をMainActorから分離する。
private final class ConsoleReporter: @unchecked Sendable {
  private let receiver: UDPReceiver
  private let printPose: Bool

  init(receiver: UDPReceiver, printPose: Bool) {
    self.receiver = receiver
    self.printPose = printPose
  }

  func receive(_ received: ReceivedPosePacket) {
    guard printPose else { return }
    let packet = received.packet
    print(
      "frame=\(packet.envelope.frameSequence) "
        + "batch=\(packet.envelope.batchIndex + 1)/\(packet.envelope.batchCount) "
        + "trackers=\(packet.poseBatch.trackers.count) "
        + "processing_us=\(received.processingTimeNS / 1_000)"
    )
  }

  func reject(_ error: PacketDecodeError) {
    fputs("packetを拒否しました: \(error)\n", stderr)
  }

  func printStatistics() {
    let stats = receiver.statistics()
    print(
      "received=\(stats.datagrams) valid=\(stats.validPackets) "
        + "invalid=\(stats.invalidPackets) loss=\(stats.missingFrames) "
        + "duplicate=\(stats.duplicatePackets) "
        + "out_of_order=\(stats.outOfOrderPackets)"
    )
  }

  func stop() {
    try? receiver.close()
  }
}

do {
  let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
  let receiver = UDPReceiver()
  let reporter = ConsoleReporter(receiver: receiver, printPose: options.printPose)
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
  metricsTimer.cancel()
  interruptSource.cancel()
  try receiver.shutdown()

  let stats = receiver.statistics()
  print(
    "終了: received=\(stats.datagrams) valid=\(stats.validPackets) "
      + "invalid=\(stats.invalidPackets)"
  )
} catch {
  fputs("起動できませんでした: \(error)\n", stderr)
  printUsage()
  exit(1)
}
