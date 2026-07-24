import Foundation
import NIOCore
import NIOPosix
import XCTest

@testable import HubAppUI

final class NetworkRuntimeTests: XCTestCase {
  func testLoopback受信をGUI用latestSnapshotへ反映する() async throws {
    let runtime = NetworkRuntime()
    let endpoint = try await runtime.start(
      configuration: NetworkRuntimeConfiguration(
        host: "127.0.0.1",
        port: 0
      )
    )
    XCTAssertGreaterThan(endpoint.port, 0)

    try send(
      try goldenPacket(),
      to: SocketAddress(ipAddress: "127.0.0.1", port: endpoint.port)
    )

    let received = try await waitForTrackers(2, runtime: runtime)
    XCTAssertTrue(received.metrics.isRunning)
    XCTAssertEqual(received.metrics.receiver.datagrams, 1)
    XCTAssertEqual(received.metrics.receiver.validPackets, 1)
    XCTAssertEqual(received.metrics.receiver.invalidPackets, 0)
    XCTAssertEqual(received.hubState.trackers.count, 2)
    XCTAssertTrue(
      try XCTUnwrap(received.metrics.lastRemoteAddress)
        .contains("127.0.0.1")
    )

    try await runtime.stop()
    let stopped = await runtime.snapshot()
    XCTAssertFalse(stopped.metrics.isRunning)
    XCTAssertEqual(stopped.metrics.receiver.validPackets, 1)
    XCTAssertEqual(stopped.hubState.trackers.count, 2)
  }

  func test停止後に新しいUDPReceiverで再開できる() async throws {
    let runtime = NetworkRuntime()
    let first = try await runtime.start(
      configuration: .init(host: "127.0.0.1", port: 0)
    )
    XCTAssertGreaterThan(first.port, 0)
    try await runtime.stop()

    let second = try await runtime.start(
      configuration: .init(host: "127.0.0.1", port: 0)
    )
    XCTAssertGreaterThan(second.port, 0)
    let restarted = await runtime.snapshot()
    XCTAssertTrue(restarted.metrics.isRunning)
    try await runtime.stop()
  }

  func test不正なNetwork設定を拒否する() async {
    let runtime = NetworkRuntime()
    do {
      _ = try await runtime.start(
        configuration: .init(host: "", port: 41_320)
      )
      XCTFail("空のhostを受理してはいけない")
    } catch {
      XCTAssertEqual(
        error as? NetworkRuntimeConfigurationError,
        .emptyHost
      )
    }

    do {
      _ = try await runtime.start(
        configuration: .init(host: "127.0.0.1", port: 65_536)
      )
      XCTFail("範囲外portを受理してはいけない")
    } catch {
      XCTAssertEqual(
        error as? NetworkRuntimeConfigurationError,
        .invalidPort
      )
    }
  }

  private func waitForTrackers(
    _ count: Int,
    runtime: NetworkRuntime
  ) async throws -> NetworkRuntimeSnapshot {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while clock.now < deadline {
      let snapshot = await runtime.snapshot()
      if snapshot.hubState.trackers.count == count {
        return snapshot
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Tracker受信がtimeoutした")
    return await runtime.snapshot()
  }

  private func send(
    _ bytes: [UInt8],
    to address: SocketAddress
  ) throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer { try? group.syncShutdownGracefully() }
    let sender = try DatagramBootstrap(group: group)
      .bind(host: "127.0.0.1", port: 0)
      .wait()
    defer { try? sender.close().wait() }

    var buffer = sender.allocator.buffer(capacity: bytes.count)
    buffer.writeBytes(bytes)
    try sender.writeAndFlush(
      AddressedEnvelope(remoteAddress: address, data: buffer)
    ).wait()
  }

  private func goldenPacket() throws -> [UInt8] {
    let testDirectory =
      URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repositoryRoot =
      testDirectory
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fixtureURL =
      repositoryRoot
      .appendingPathComponent("protocol/golden/pose_v1.packet.hex")
    let hex = try String(contentsOf: fixtureURL, encoding: .utf8)
      .filter { !$0.isWhitespace }
    return stride(from: 0, to: hex.count, by: 2).map { offset in
      let start = hex.index(hex.startIndex, offsetBy: offset)
      let end = hex.index(start, offsetBy: 2)
      return UInt8(hex[start..<end], radix: 16)!
    }
  }
}
