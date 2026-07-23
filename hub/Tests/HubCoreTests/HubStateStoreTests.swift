import HubCore
import HubProtocol
import XCTest

final class HubStateStoreTests: XCTestCase {
  func testpartialFrameは未更新Trackerの前回値を保持する() throws {
    let session = try testUUID(1)
    let bridge = try testUUID(20)
    let space = try testUUID(40)
    let store = HubStateStore()

    XCTAssertEqual(
      store.apply(
        testFrame(
          session: session,
          bridge: bridge,
          trackingSpace: space,
          sequence: 1,
          trackers: [testTracker("a", x: 1), testTracker("b", x: 2)],
          receivedMonotonicNS: 100
        )
      ),
      .applied
    )
    XCTAssertEqual(
      store.apply(
        testFrame(
          session: session,
          bridge: bridge,
          trackingSpace: space,
          sequence: 2,
          trackers: [testTracker("a", x: 3)],
          receivedMonotonicNS: 300,
          completeness: .partial(missingBatchIndices: [1])
        )
      ),
      .applied
    )

    let snapshot = store.snapshot()
    XCTAssertEqual(snapshot.generation, 2)
    XCTAssertEqual(snapshot.bridges.count, 1)
    XCTAssertEqual(snapshot.trackers.map(\.key.trackerID), ["a", "b"])

    let a = try XCTUnwrap(snapshot.trackers.first { $0.key.trackerID == "a" })
    let b = try XCTUnwrap(snapshot.trackers.first { $0.key.trackerID == "b" })
    XCTAssertEqual(a.frameSequence, 2)
    XCTAssertEqual(a.pose.position.x, 3)
    XCTAssertEqual(a.receiveAgeNS(at: 350), 50)
    XCTAssertEqual(b.frameSequence, 1)
    XCTAssertEqual(b.pose.position.x, 2)
    XCTAssertEqual(b.receiveAgeNS(at: 350), 250)
    XCTAssertEqual(snapshot.stateStatistics.completeFrames, 1)
    XCTAssertEqual(snapshot.stateStatistics.partialFrames, 1)
    XCTAssertEqual(store.bridgeState(for: bridge)?.frameSequence, 2)
    XCTAssertEqual(
      store.trackerState(for: TrackerKey(bridgeID: bridge, trackerID: "a"))?.pose.position.x,
      3
    )
  }

  func testtrackingSpace変更時に古いTrackerを混在させない() throws {
    let session = try testUUID(1)
    let bridge = try testUUID(20)
    let oldSpace = try testUUID(40)
    let newSpace = try testUUID(60)
    let store = HubStateStore()

    store.apply(
      testFrame(
        session: session,
        bridge: bridge,
        trackingSpace: oldSpace,
        sequence: 1,
        trackers: [testTracker("old")],
        receivedMonotonicNS: 100
      )
    )
    store.apply(
      testFrame(
        session: session,
        bridge: bridge,
        trackingSpace: newSpace,
        sequence: 2,
        trackers: [testTracker("new")],
        receivedMonotonicNS: 200,
        spaceEpoch: 2
      )
    )

    let snapshot = store.snapshot()
    XCTAssertEqual(snapshot.trackers.map(\.key.trackerID), ["new"])
    XCTAssertEqual(snapshot.bridges[0].trackingSpaceID, newSpace)
    XCTAssertEqual(snapshot.bridges[0].spaceEpoch, 2)
    XCTAssertEqual(snapshot.stateStatistics.trackingSpaceResets, 1)
  }

  func test同一sessionの古いframeを拒否しsession変更時はsequenceをresetする() throws {
    let sessionA = try testUUID(1)
    let sessionB = try testUUID(2)
    let bridge = try testUUID(20)
    let space = try testUUID(40)
    let store = HubStateStore()

    XCTAssertEqual(
      store.apply(
        testFrame(
          session: sessionA,
          bridge: bridge,
          trackingSpace: space,
          sequence: 10,
          trackers: [testTracker("a")],
          receivedMonotonicNS: 100
        )
      ),
      .applied
    )
    XCTAssertEqual(
      store.apply(
        testFrame(
          session: sessionA,
          bridge: bridge,
          trackingSpace: space,
          sequence: 9,
          trackers: [testTracker("stale")],
          receivedMonotonicNS: 110
        )
      ),
      .stale
    )
    XCTAssertEqual(
      store.apply(
        testFrame(
          session: sessionB,
          bridge: bridge,
          trackingSpace: space,
          sequence: 0,
          trackers: [testTracker("b")],
          receivedMonotonicNS: 120
        )
      ),
      .applied
    )

    let snapshot = store.snapshot()
    XCTAssertEqual(snapshot.generation, 2)
    XCTAssertEqual(snapshot.bridges[0].sessionID, sessionB)
    XCTAssertEqual(snapshot.bridges[0].frameSequence, 0)
    XCTAssertEqual(snapshot.trackers.map(\.key.trackerID), ["b"])
    XCTAssertEqual(snapshot.stateStatistics.staleFrames, 1)
    XCTAssertEqual(snapshot.stateStatistics.sessionResets, 1)
  }

  func testNetworkPacketの再構成結果をlatestStateへ反映する() throws {
    let session = try testUUID(1)
    let bridge = try testUUID(20)
    let space = try testUUID(40)
    let store = HubStateStore()

    let first = store.ingest(
      testPacket(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 4,
        batchIndex: 1,
        batchCount: 2,
        trackers: [testTracker("b")]
      ),
      receivedMonotonicNS: 100
    )
    XCTAssertTrue(first.emittedFrames.isEmpty)
    XCTAssertEqual(store.snapshot().generation, 0)

    let second = store.ingest(
      testPacket(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 4,
        batchIndex: 0,
        batchCount: 2,
        trackers: [testTracker("a")]
      ),
      receivedMonotonicNS: 110
    )
    XCTAssertEqual(second.emittedFrames.count, 1)

    var snapshot = store.snapshot()
    XCTAssertEqual(snapshot.generation, 1)
    XCTAssertEqual(snapshot.trackers.map(\.key.trackerID), ["a", "b"])
    XCTAssertEqual(snapshot.assemblerStatistics.completedFrames, 1)

    _ = store.ingest(
      testPacket(
        session: session,
        bridge: bridge,
        trackingSpace: space,
        sequence: 5,
        batchIndex: 0,
        batchCount: 2,
        trackers: [testTracker("a", x: 5)]
      ),
      receivedMonotonicNS: 120
    )
    let flushed = store.flushPendingFrames()
    XCTAssertEqual(flushed.count, 1)
    snapshot = store.snapshot()
    XCTAssertEqual(snapshot.generation, 2)
    XCTAssertEqual(snapshot.stateStatistics.partialFrames, 1)
  }
}
