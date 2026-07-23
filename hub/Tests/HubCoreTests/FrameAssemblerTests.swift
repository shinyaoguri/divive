import HubCore
import HubProtocol
import XCTest

final class FrameAssemblerTests: XCTestCase {
  func test順序が逆の複数batchをindex順で完全frameへ再構成する() throws {
    let session = try testUUID(1)
    let bridge = try testUUID(20)
    let space = try testUUID(40)
    var assembler = FrameAssembler()

    let second = assembler.ingest(
      testPacket(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 7,
        batchIndex: 1,
        batchCount: 2,
        trackers: [testTracker("b")]
      ),
      receivedMonotonicNS: 200
    )
    XCTAssertEqual(second.packetDisposition, .accepted)
    XCTAssertTrue(second.emittedFrames.isEmpty)
    XCTAssertEqual(assembler.statistics().pendingFrames, 1)

    let first = assembler.ingest(
      testPacket(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 7,
        batchIndex: 0,
        batchCount: 2,
        trackers: [testTracker("a")]
      ),
      receivedMonotonicNS: 220
    )
    XCTAssertEqual(first.packetDisposition, .accepted)
    XCTAssertEqual(first.emittedFrames.count, 1)

    let frame = try XCTUnwrap(first.emittedFrames.first)
    XCTAssertEqual(frame.frameSequence, 7)
    XCTAssertEqual(frame.completeness, .complete)
    XCTAssertEqual(frame.receivedBatchIndices, [0, 1])
    XCTAssertEqual(frame.poseBatch.trackers.map(\.trackerID), ["a", "b"])
    XCTAssertEqual(frame.firstReceivedMonotonicNS, 200)
    XCTAssertEqual(frame.lastReceivedMonotonicNS, 220)
    XCTAssertEqual(assembler.statistics().pendingFrames, 0)
  }

  func test次sequenceで未完成frameをpartialとして確定する() throws {
    let session = try testUUID(1)
    let bridge = try testUUID(20)
    let space = try testUUID(40)
    var assembler = FrameAssembler()

    _ = assembler.ingest(
      testPacket(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 10,
        batchIndex: 0,
        batchCount: 3,
        trackers: [testTracker("old")]
      ),
      receivedMonotonicNS: 100
    )
    let advanced = assembler.ingest(
      testPacket(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 12,
        trackers: [testTracker("new")]
      ),
      receivedMonotonicNS: 120
    )

    XCTAssertEqual(advanced.emittedFrames.count, 2)
    XCTAssertEqual(advanced.emittedFrames[0].frameSequence, 10)
    XCTAssertEqual(
      advanced.emittedFrames[0].completeness,
      .partial(missingBatchIndices: [1, 2])
    )
    XCTAssertEqual(advanced.emittedFrames[1].frameSequence, 12)
    XCTAssertEqual(advanced.emittedFrames[1].completeness, .complete)

    let statistics = assembler.statistics()
    XCTAssertEqual(statistics.partialFrames, 1)
    XCTAssertEqual(statistics.completedFrames, 1)
    XCTAssertEqual(statistics.pendingFrames, 0)
  }

  func test矛盾packetを拒否してpendingFrameを維持する() throws {
    let session = try testUUID(1)
    let bridge = try testUUID(20)
    let space = try testUUID(40)
    var assembler = FrameAssembler()

    let firstPacket = testPacket(
      session: session,
      bridge: bridge,
      trackingSpace: space,
      sequence: 5,
      batchIndex: 0,
      batchCount: 2,
      trackers: [testTracker("a")]
    )
    _ = assembler.ingest(firstPacket, receivedMonotonicNS: 100)
    XCTAssertEqual(
      assembler.ingest(firstPacket, receivedMonotonicNS: 101).packetDisposition,
      .duplicateBatch
    )
    XCTAssertEqual(
      assembler.ingest(
        testPacket(
          session: session,
          bridge: bridge,
          trackingSpace: space,
          sequence: 5,
          batchIndex: 1,
          batchCount: 3,
          trackers: [testTracker("b")]
        ),
        receivedMonotonicNS: 102
      ).packetDisposition,
      .inconsistentBatchCount
    )
    XCTAssertEqual(
      assembler.ingest(
        testPacket(
          session: session,
          bridge: bridge,
          trackingSpace: space,
          sequence: 5,
          batchIndex: 1,
          batchCount: 2,
          trackers: [testTracker("b")],
          captureMonotonicNS: 9_999
        ),
        receivedMonotonicNS: 103
      ).packetDisposition,
      .inconsistentMetadata
    )
    XCTAssertEqual(
      assembler.ingest(
        testPacket(
          session: session,
          bridge: bridge,
          trackingSpace: space,
          sequence: 5,
          batchIndex: 1,
          batchCount: 2,
          trackers: [testTracker("a")]
        ),
        receivedMonotonicNS: 104
      ).packetDisposition,
      .duplicateTrackerID
    )

    let completed = assembler.ingest(
      testPacket(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 5,
        batchIndex: 1,
        batchCount: 2,
        trackers: [testTracker("b")]
      ),
      receivedMonotonicNS: 105
    )
    XCTAssertEqual(completed.emittedFrames.count, 1)
    XCTAssertEqual(
      assembler.ingest(firstPacket, receivedMonotonicNS: 106).packetDisposition,
      .duplicateBatch
    )
    XCTAssertEqual(
      assembler.ingest(
        testPacket(
          session: session,
          bridge: bridge,
          trackingSpace: space,
          sequence: 4,
          trackers: [testTracker("past")]
        ),
        receivedMonotonicNS: 107
      ).packetDisposition,
      .outOfOrder
    )
  }

  func testSession切替とflushでpendingFrameを確定する() throws {
    let sessionA = try testUUID(1)
    let sessionB = try testUUID(2)
    let bridge = try testUUID(20)
    let space = try testUUID(40)
    var assembler = FrameAssembler()

    _ = assembler.ingest(
      testPacket(
        session: sessionA,
        bridge: bridge,
        trackingSpace: space,
        sequence: 99,
        batchIndex: 0,
        batchCount: 2,
        trackers: [testTracker("old")]
      ),
      receivedMonotonicNS: 100
    )
    let changed = assembler.ingest(
      testPacket(
        session: sessionB,
        bridge: bridge,
        trackingSpace: space,
        sequence: 0,
        batchIndex: 0,
        batchCount: 2,
        trackers: [testTracker("new")]
      ),
      receivedMonotonicNS: 200
    )
    XCTAssertTrue(changed.sessionChanged)
    XCTAssertEqual(changed.emittedFrames.count, 1)
    XCTAssertEqual(
      changed.emittedFrames[0].completeness,
      .partial(missingBatchIndices: [1])
    )

    let flushed = assembler.flush()
    XCTAssertEqual(flushed.count, 1)
    XCTAssertEqual(flushed[0].sessionID, sessionB)
    XCTAssertEqual(
      flushed[0].completeness,
      .partial(missingBatchIndices: [1])
    )
    XCTAssertEqual(assembler.statistics().pendingFrames, 0)
  }

  func test同じbatch内のTracker重複を拒否する() throws {
    let session = try testUUID(1)
    let bridge = try testUUID(20)
    let trackingSpace = try testUUID(40)
    var assembler = FrameAssembler()
    _ = assembler.ingest(
      testPacket(
        session: session,
        bridge: bridge,
        trackingSpace: trackingSpace,
        sequence: 0,
        batchIndex: 0,
        batchCount: 2,
        trackers: [testTracker("old")]
      ),
      receivedMonotonicNS: 90
    )

    let packet = testPacket(
      session: session,
      bridge: bridge,
      trackingSpace: trackingSpace,
      sequence: 1,
      trackers: [testTracker("same"), testTracker("same")]
    )
    let result = assembler.ingest(packet, receivedMonotonicNS: 100)
    XCTAssertEqual(result.packetDisposition, .duplicateTrackerID)
    XCTAssertEqual(result.emittedFrames.count, 1)
    XCTAssertEqual(result.emittedFrames[0].frameSequence, 0)
    XCTAssertEqual(
      result.emittedFrames[0].completeness,
      .partial(missingBatchIndices: [1])
    )
    XCTAssertEqual(assembler.statistics().pendingFrames, 0)

    let recovered = assembler.ingest(
      testPacket(
        session: session,
        bridge: bridge,
        trackingSpace: trackingSpace,
        sequence: 1,
        trackers: [testTracker("valid")]
      ),
      receivedMonotonicNS: 110
    )
    XCTAssertEqual(recovered.emittedFrames.count, 1)
    XCTAssertEqual(recovered.emittedFrames[0].frameSequence, 1)
  }
}
