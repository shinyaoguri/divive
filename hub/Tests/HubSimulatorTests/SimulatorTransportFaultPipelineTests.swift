import HubCore
import HubProtocol
import HubSimulator
import XCTest

final class SimulatorTransportFaultPipelineTests: XCTestCase {
  func test障害なしでは同じstepで配信する() throws {
    var pipeline = try makePipeline()
    let frame = try makeFrame(sequence: 0, generatedAtNS: 100)

    let delivered = pipeline.advance(
      toMonotonicNS: 100,
      offering: frame
    )

    XCTAssertEqual(delivered.map(\.frameSequence), [0])
    XCTAssertEqual(delivered[0].firstReceivedMonotonicNS, 100)
    XCTAssertEqual(delivered[0].lastReceivedMonotonicNS, 100)
    XCTAssertEqual(delivered[0].poseBatch.captureMonotonicNS, 100)
    XCTAssertEqual(pipeline.statistics.offeredFrames, 1)
    XCTAssertEqual(pipeline.statistics.deliveredFrames, 1)
    XCTAssertEqual(pipeline.statistics.pendingFrames, 0)
  }

  func test固定遅延後に受信時刻だけを更新する() throws {
    var pipeline = try makePipeline(delayNS: 50)
    let frame = try makeFrame(sequence: 0, generatedAtNS: 100)

    XCTAssertTrue(
      pipeline.advance(toMonotonicNS: 100, offering: frame).isEmpty
    )
    XCTAssertTrue(
      pipeline.advance(toMonotonicNS: 149).isEmpty
    )
    XCTAssertEqual(pipeline.nextDeliveryMonotonicNS, 150)
    let delivered = pipeline.advance(toMonotonicNS: 150)

    XCTAssertEqual(delivered.map(\.frameSequence), [0])
    XCTAssertEqual(delivered[0].lastReceivedMonotonicNS, 150)
    XCTAssertEqual(delivered[0].poseBatch.captureMonotonicNS, 100)
    XCTAssertEqual(delivered[0].poseBatch.sendMonotonicNS, 100)
    XCTAssertNil(pipeline.nextDeliveryMonotonicNS)
  }

  func test同じseedと時刻列ならjitterを再現する() throws {
    var first = try makePipeline(seed: 42, delayNS: 100, jitterNS: 80)
    var second = try makePipeline(seed: 42, delayNS: 100, jitterNS: 80)
    var firstDeliveries: [[UInt64]] = []
    var secondDeliveries: [[UInt64]] = []

    for sequence in 0..<20 {
      let now = UInt64(sequence) * 10
      let frame = try makeFrame(
        sequence: UInt64(sequence),
        generatedAtNS: now
      )
      firstDeliveries.append(
        first.advance(toMonotonicNS: now, offering: frame)
          .map(\.frameSequence)
      )
      secondDeliveries.append(
        second.advance(toMonotonicNS: now, offering: frame)
          .map(\.frameSequence)
      )
    }
    firstDeliveries.append(
      first.advance(toMonotonicNS: 1_000).map(\.frameSequence)
    )
    secondDeliveries.append(
      second.advance(toMonotonicNS: 1_000).map(\.frameSequence)
    )

    XCTAssertEqual(firstDeliveries, secondDeliveries)
    XCTAssertEqual(first.statistics, second.statistics)
    XCTAssertEqual(first.statistics.deliveredFrames, 20)
  }

  func test順序逆転をHubのstale判定まで通す() throws {
    var pipeline = try makePipeline(
      reorderingProbability: 1,
      frameIntervalNS: 10
    )
    let store = HubStateStore()

    XCTAssertTrue(
      pipeline.advance(
        toMonotonicNS: 0,
        offering: try makeFrame(sequence: 0, generatedAtNS: 0)
      ).isEmpty
    )
    let second = pipeline.advance(
      toMonotonicNS: 10,
      offering: try makeFrame(sequence: 1, generatedAtNS: 10)
    )
    XCTAssertEqual(second.map(\.frameSequence), [1])
    XCTAssertEqual(store.apply(second[0]), .applied)

    let reordered = pipeline.advance(
      toMonotonicNS: 20,
      offering: try makeFrame(sequence: 2, generatedAtNS: 20)
    )
    XCTAssertEqual(reordered.map(\.frameSequence), [0])
    XCTAssertEqual(store.apply(reordered[0]), .stale)
    XCTAssertEqual(store.snapshot().stateStatistics.staleFrames, 1)
    XCTAssertEqual(pipeline.statistics.reorderingCandidates, 2)
  }

  func test接続断は継続時間中のframeを破棄する() throws {
    var pipeline = try makePipeline(
      disconnectProbability: 1,
      disconnectDurationNS: 300
    )

    XCTAssertTrue(
      pipeline.advance(
        toMonotonicNS: 100,
        offering: try makeFrame(sequence: 0, generatedAtNS: 100)
      ).isEmpty
    )
    XCTAssertTrue(pipeline.isDisconnected(atMonotonicNS: 399))
    XCTAssertTrue(
      pipeline.advance(
        toMonotonicNS: 200,
        offering: try makeFrame(sequence: 1, generatedAtNS: 200)
      ).isEmpty
    )
    XCTAssertFalse(pipeline.isDisconnected(atMonotonicNS: 400))
    XCTAssertTrue(
      pipeline.advance(
        toMonotonicNS: 400,
        offering: try makeFrame(sequence: 2, generatedAtNS: 400)
      ).isEmpty
    )

    XCTAssertEqual(pipeline.statistics.disconnectEvents, 2)
    XCTAssertEqual(pipeline.statistics.disconnectedFrames, 3)
    XCTAssertEqual(pipeline.statistics.pendingFrames, 0)
  }

  func test接続断中は既存Hub状態がageでdisconnectedになる() throws {
    let store = HubStateStore()
    XCTAssertEqual(
      store.apply(try makeFrame(sequence: 0, generatedAtNS: 0)),
      .applied
    )
    var pipeline = try makePipeline(
      disconnectProbability: 1,
      disconnectDurationNS: 3_000_000_000
    )
    _ = pipeline.advance(
      toMonotonicNS: 1,
      offering: try makeFrame(sequence: 1, generatedAtNS: 1)
    )

    let stale = try XCTUnwrap(
      store.evaluatedSnapshot(
        atMonotonicNS: HubLivenessPolicy.defaultLostAfterNS
      ).trackers.first
    )
    XCTAssertEqual(stale.liveness, .stale)
    XCTAssertEqual(stale.trackingState, .lost)
    XCTAssertEqual(stale.trackingReason, .networkStale)

    let disconnected = try XCTUnwrap(
      store.evaluatedSnapshot(
        atMonotonicNS: HubLivenessPolicy.defaultDisconnectedAfterNS
      ).trackers.first
    )
    XCTAssertEqual(disconnected.liveness, .disconnected)
    XCTAssertEqual(disconnected.trackingState, .disconnected)
    XCTAssertEqual(disconnected.trackingReason, .bridgeTimeout)
  }

  func test保留上限では最古sequenceを破棄する() throws {
    var pipeline = try makePipeline(
      delayNS: 100,
      maximumPendingFrames: 2
    )
    for sequence in 0..<3 {
      XCTAssertTrue(
        pipeline.advance(
          toMonotonicNS: UInt64(sequence),
          offering: try makeFrame(
            sequence: UInt64(sequence),
            generatedAtNS: UInt64(sequence)
          )
        ).isEmpty
      )
    }

    XCTAssertEqual(pipeline.statistics.pendingFrames, 2)
    XCTAssertEqual(pipeline.statistics.overflowFrames, 1)
    XCTAssertEqual(
      pipeline.advance(toMonotonicNS: 1_000).map(\.frameSequence),
      [1, 2]
    )
  }

  func test不正な設定を拒否する() {
    XCTAssertThrowsError(
      try SimulatorTransportFaultConfiguration(
        seed: 1,
        delayNS: 0,
        jitterNS: 0,
        reorderingProbability: -0.1,
        disconnectProbability: 0,
        disconnectDurationNS: 0
      )
    )
    XCTAssertThrowsError(
      try SimulatorTransportFaultConfiguration(
        seed: 1,
        delayNS: 0,
        jitterNS: 0,
        reorderingProbability: 0,
        disconnectProbability: 0.1,
        disconnectDurationNS: 0
      )
    )
    XCTAssertThrowsError(
      try SimulatorTransportFaultPipeline(
        configuration: SimulatorTransportFaultConfiguration(),
        frameIntervalNS: 0
      )
    )
  }

  private func makePipeline(
    seed: UInt64 = 1,
    delayNS: UInt64 = 0,
    jitterNS: UInt64 = 0,
    reorderingProbability: Double = 0,
    disconnectProbability: Double = 0,
    disconnectDurationNS: UInt64 = 0,
    maximumPendingFrames: Int = 1_024,
    frameIntervalNS: UInt64 = 10
  ) throws -> SimulatorTransportFaultPipeline {
    try SimulatorTransportFaultPipeline(
      configuration: SimulatorTransportFaultConfiguration(
        seed: seed,
        delayNS: delayNS,
        jitterNS: jitterNS,
        reorderingProbability: reorderingProbability,
        disconnectProbability: disconnectProbability,
        disconnectDurationNS: disconnectDurationNS,
        maximumPendingFrames: maximumPendingFrames
      ),
      frameIntervalNS: frameIntervalNS
    )
  }

  private func makeFrame(
    sequence: UInt64,
    generatedAtNS: UInt64
  ) throws -> AssembledPoseFrame {
    let sessionID = try uuid(1)
    let bridgeID = try uuid(20)
    return AssembledPoseFrame(
      sessionID: sessionID,
      bridgeID: bridgeID,
      frameSequence: sequence,
      expectedBatchCount: 1,
      receivedBatchIndices: [0],
      firstReceivedMonotonicNS: generatedAtNS,
      lastReceivedMonotonicNS: generatedAtNS,
      completeness: .complete,
      poseBatch: PoseBatch(
        trackingSpaceID: try uuid(40),
        spaceEpoch: 1,
        captureMonotonicNS: generatedAtNS,
        sendMonotonicNS: generatedAtNS,
        requestedRateHz: 90,
        backend: .simulator,
        trackers: [
          TrackerPose(
            trackerID: "sim://tracker/001",
            idKind: .permanent,
            role: "waist",
            runtimeRole: "",
            position: Vector3(x: 0, y: 1, z: -1),
            orientation: Quaternion(x: 0, y: 0, z: 0, w: 1),
            linearVelocity: Vector3(x: 0, y: 0, z: 0),
            angularVelocity: nil,
            trackingState: .simulated,
            trackingReason: .none,
            connected: true,
            battery: nil,
            deviceMetadataRevision: 1
          )
        ]
      )
    )
  }

  private func uuid(_ seed: UInt8) throws -> UUIDBytes {
    try UUIDBytes(bytes: (0..<16).map { seed &+ UInt8($0) })
  }
}
