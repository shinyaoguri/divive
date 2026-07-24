import Foundation
import HubCore
import HubNetworking
import NIOCore
import NIOPosix
import XCTest

final class UDPReceiverTests: XCTestCase {
  func testLoopbackでgoldenPacketを受信する() throws {
    let receiver = UDPReceiver()
    let hubState = HubStateStore()
    let received = expectation(description: "golden packetを受信")
    let address = try receiver.start(
      configuration: .init(host: "127.0.0.1", port: 0),
      onPacket: { packet in
        XCTAssertEqual(packet.packet.poseBatch.trackers.count, 2)
        hubState.ingest(
          packet.packet,
          receivedMonotonicNS: packet.receivedMonotonicNS
        )
        received.fulfill()
      }
    )
    XCTAssertTrue(receiver.isActive())

    let senderGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let sender = try DatagramBootstrap(group: senderGroup)
      .bind(host: "127.0.0.1", port: 0)
      .wait()
    var buffer = sender.allocator.buffer(capacity: 456)
    buffer.writeBytes(try goldenPacket())
    try sender.writeAndFlush(
      AddressedEnvelope(remoteAddress: address, data: buffer)
    ).wait()

    wait(for: [received], timeout: 2)
    try sender.close().wait()
    try senderGroup.syncShutdownGracefully()
    try receiver.shutdown()
    XCTAssertFalse(receiver.isActive())

    let statistics = receiver.statistics()
    XCTAssertEqual(statistics.datagrams, 1)
    XCTAssertEqual(statistics.validPackets, 1)
    XCTAssertEqual(statistics.appliedPackets, 1)
    XCTAssertEqual(statistics.trackerRecords, 2)
    XCTAssertEqual(statistics.invalidPackets, 0)

    let state = hubState.snapshot()
    XCTAssertEqual(state.generation, 1)
    XCTAssertEqual(state.stateStatistics.completeFrames, 1)
    XCTAssertEqual(state.trackers.count, 2)
  }

  private func goldenPacket() throws -> [UInt8] {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
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
