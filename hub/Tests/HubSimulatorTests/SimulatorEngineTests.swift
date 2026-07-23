import HubCore
import HubProtocol
import HubSimulator
import XCTest

final class SimulatorEngineTests: XCTestCase {
  func test対応rateを固定する() {
    XCTAssertEqual(
      SimulatorRate.allCases.map(\.rawValue),
      [30, 60, 90, 120]
    )
  }

  func testTrackerを追加更新削除してID順を維持する() throws {
    var simulator = try SimulatorEngine(source: try source())
    try simulator.addTracker(tracker("b", role: "right"))
    try simulator.addTracker(tracker("a", role: "left"))

    XCTAssertEqual(
      simulator.trackerConfigurations.map(\.trackerID),
      ["a", "b"]
    )
    XCTAssertThrowsError(try simulator.addTracker(tracker("a")))

    try simulator.updateTracker(
      existingID: "b",
      configuration: tracker("c", role: "prop")
    )
    XCTAssertEqual(
      simulator.trackerConfigurations.map(\.trackerID),
      ["a", "c"]
    )
    XCTAssertEqual(
      simulator.trackerConfigurations.first { $0.trackerID == "c" }?.role,
      "prop"
    )
    XCTAssertThrowsError(
      try simulator.updateTracker(
        existingID: "c",
        configuration: tracker("a")
      )
    )

    let removed = try simulator.removeTracker(id: "a")
    XCTAssertEqual(removed.trackerID, "a")
    XCTAssertEqual(simulator.trackerConfigurations.map(\.trackerID), ["c"])
    XCTAssertThrowsError(try simulator.removeTracker(id: "missing"))
  }

  func test不正なTracker設定を拒否する() throws {
    var simulator = try SimulatorEngine(source: try source())
    XCTAssertThrowsError(try simulator.addTracker(tracker("")))
    XCTAssertThrowsError(
      try simulator.addTracker(
        SimulatorTrackerConfiguration(
          trackerID: "non-finite",
          role: "",
          position: Vector3(x: .infinity, y: 0, z: 0)
        )
      )
    )
    XCTAssertThrowsError(
      try simulator.addTracker(
        SimulatorTrackerConfiguration(
          trackerID: "quaternion",
          role: "",
          position: Vector3(x: 0, y: 0, z: 0),
          orientation: Quaternion(x: 0, y: 0, z: 0, w: 2)
        )
      )
    )
    XCTAssertThrowsError(
      try simulator.addTracker(
        SimulatorTrackerConfiguration(
          trackerID: "circle",
          role: "",
          position: Vector3(x: 0, y: 0, z: 0),
          motion: .circle(
            radiusMeters: -1,
            angularSpeedRadiansPerSecond: 1,
            phaseRadians: 0
          )
        )
      )
    )
  }

  func testnilのsource識別子を拒否する() throws {
    let nilID = try UUIDBytes(bytes: [UInt8](repeating: 0, count: 16))
    let validID = try uuid(1)
    XCTAssertThrowsError(
      try SimulatorEngine(
        source: SimulatorSourceConfiguration(
          sessionID: nilID,
          bridgeID: validID,
          trackingSpaceID: validID
        )
      )
    )
    XCTAssertThrowsError(
      try SimulatorEngine(
        source: SimulatorSourceConfiguration(
          sessionID: validID,
          bridgeID: nilID,
          trackingSpaceID: validID
        )
      )
    )
    XCTAssertThrowsError(
      try SimulatorEngine(
        source: SimulatorSourceConfiguration(
          sessionID: validID,
          bridgeID: validID,
          trackingSpaceID: nilID
        )
      )
    )
  }

  func testStatic姿勢をcanonicalFrameとして生成する() throws {
    let source = try source(rate: .hz60)
    var simulator = try SimulatorEngine(
      source: source,
      trackers: [
        tracker(
          "sim://tracker/001",
          role: "waist",
          position: Vector3(x: 1, y: 2, z: -3)
        )
      ]
    )

    let first = try emitted(
      simulator.step(receivedMonotonicNS: 1_000)
    )
    XCTAssertEqual(first.sessionID, source.sessionID)
    XCTAssertEqual(first.bridgeID, source.bridgeID)
    XCTAssertEqual(first.frameSequence, 0)
    XCTAssertEqual(first.completeness, .complete)
    XCTAssertEqual(first.firstReceivedMonotonicNS, 1_000)
    XCTAssertEqual(first.poseBatch.captureMonotonicNS, 1_000)
    XCTAssertEqual(first.poseBatch.sendMonotonicNS, 1_000)
    XCTAssertEqual(first.poseBatch.requestedRateHz, 60)
    XCTAssertEqual(first.poseBatch.backend, .simulator)

    let pose = try XCTUnwrap(first.poseBatch.trackers.first)
    XCTAssertEqual(pose.trackerID, "sim://tracker/001")
    XCTAssertEqual(pose.idKind, .permanent)
    XCTAssertEqual(pose.role, "waist")
    XCTAssertEqual(pose.position, Vector3(x: 1, y: 2, z: -3))
    XCTAssertEqual(pose.linearVelocity, Vector3(x: 0, y: 0, z: 0))
    XCTAssertEqual(pose.trackingState, .simulated)
    XCTAssertTrue(pose.connected)

    let second = try emitted(
      simulator.step(receivedMonotonicNS: 2_000)
    )
    XCTAssertEqual(second.frameSequence, 1)
    XCTAssertEqual(simulator.frameSequence, 2)
  }

  func testCircleは固定step時刻から位置と速度を生成する() throws {
    var simulator = try SimulatorEngine(
      source: try source(rate: .hz120),
      trackers: [
        SimulatorTrackerConfiguration(
          trackerID: "circle",
          role: "prop",
          position: Vector3(x: 1, y: 2, z: -3),
          motion: .circle(
            radiusMeters: 2,
            angularSpeedRadiansPerSecond: 2 * .pi,
            phaseRadians: 0
          )
        )
      ]
    )

    let atZero = try emitted(
      simulator.step(receivedMonotonicNS: 10)
    ).poseBatch.trackers[0]
    XCTAssertEqual(atZero.position.x, 3, accuracy: 1e-5)
    XCTAssertEqual(atZero.position.y, 2, accuracy: 1e-5)
    XCTAssertEqual(atZero.position.z, -3, accuracy: 1e-5)
    XCTAssertEqual(atZero.linearVelocity?.x ?? 1, 0, accuracy: 1e-5)
    XCTAssertEqual(
      atZero.linearVelocity?.z ?? 0,
      -4 * .pi,
      accuracy: 1e-5
    )

    var quarterTurn = atZero
    for timestamp in 11...40 {
      quarterTurn = try emitted(
        simulator.step(receivedMonotonicNS: UInt64(timestamp))
      ).poseBatch.trackers[0]
    }
    XCTAssertEqual(simulator.frameSequence, 31)
    XCTAssertEqual(quarterTurn.position.x, 1, accuracy: 1e-5)
    XCTAssertEqual(quarterTurn.position.z, -5, accuracy: 1e-5)
    XCTAssertEqual(
      quarterTurn.linearVelocity?.x ?? 0,
      -4 * .pi,
      accuracy: 1e-5
    )
    XCTAssertEqual(
      quarterTurn.linearVelocity?.z ?? 1,
      0,
      accuracy: 1e-5
    )
  }

  func test同じseedならfault結果を再現できる() throws {
    let faults = try SimulatorFaultConfiguration(
      seed: 42,
      frameLossProbability: 0.35,
      trackingLostProbability: 0.45
    )
    let trackers = (0..<4).map { tracker("tracker-\($0)") }
    var first = try SimulatorEngine(
      source: try source(),
      trackers: trackers,
      faults: faults
    )
    var second = try SimulatorEngine(
      source: try source(),
      trackers: trackers,
      faults: faults
    )
    var dropped = 0
    var injectedLost = 0

    for index in 0..<100 {
      let firstStep = try first.step(receivedMonotonicNS: UInt64(index))
      let secondStep = try second.step(receivedMonotonicNS: UInt64(index))
      XCTAssertEqual(firstStep, secondStep)
      switch firstStep {
      case .dropped:
        dropped += 1
      case .emitted(let frame):
        injectedLost += frame.poseBatch.trackers.count {
          $0.trackingReason == .simulatedFault
        }
      }
    }

    XCTAssertGreaterThan(dropped, 0)
    XCTAssertLessThan(dropped, 100)
    XCTAssertGreaterThan(injectedLost, 0)
  }

  func testFrameLossでもsequenceを進めtrackingLostを共通sinkへ渡す() throws {
    var dropSimulator = try SimulatorEngine(
      source: try source(),
      trackers: [tracker("a")],
      faults: try SimulatorFaultConfiguration(
        seed: 1,
        frameLossProbability: 1,
        trackingLostProbability: 0
      )
    )
    XCTAssertEqual(
      try dropSimulator.step(receivedMonotonicNS: 100),
      .dropped(frameSequence: 0)
    )
    XCTAssertEqual(
      try dropSimulator.step(receivedMonotonicNS: 200),
      .dropped(frameSequence: 1)
    )
    XCTAssertEqual(dropSimulator.frameSequence, 2)

    var lostSimulator = try SimulatorEngine(
      source: try source(),
      trackers: [tracker("a")],
      faults: try SimulatorFaultConfiguration(
        seed: 1,
        frameLossProbability: 0,
        trackingLostProbability: 1
      )
    )
    let frame = try emitted(
      lostSimulator.step(receivedMonotonicNS: 300)
    )
    let store = HubStateStore()
    let sink: any HubFrameSink = store
    XCTAssertEqual(sink.apply(frame), .applied)

    let pose = try XCTUnwrap(store.snapshot().trackers.first?.pose)
    XCTAssertEqual(pose.trackingState, .lost)
    XCTAssertEqual(pose.trackingReason, .simulatedFault)
    XCTAssertTrue(pose.connected)
  }

  func testFault確率の範囲を検証する() {
    XCTAssertThrowsError(
      try SimulatorFaultConfiguration(
        seed: 1,
        frameLossProbability: -0.1,
        trackingLostProbability: 0
      )
    )
    XCTAssertThrowsError(
      try SimulatorFaultConfiguration(
        seed: 1,
        frameLossProbability: 0,
        trackingLostProbability: 1.1
      )
    )
    XCTAssertThrowsError(
      try SimulatorFaultConfiguration(
        seed: 1,
        frameLossProbability: .nan,
        trackingLostProbability: 0
      )
    )
  }

  private func source(
    rate: SimulatorRate = .hz90
  ) throws -> SimulatorSourceConfiguration {
    SimulatorSourceConfiguration(
      sessionID: try uuid(1),
      bridgeID: try uuid(20),
      trackingSpaceID: try uuid(40),
      rate: rate
    )
  }

  private func tracker(
    _ id: String,
    role: String = "",
    position: Vector3 = Vector3(x: 0, y: 1, z: -1)
  ) -> SimulatorTrackerConfiguration {
    SimulatorTrackerConfiguration(
      trackerID: id,
      role: role,
      position: position
    )
  }

  private func uuid(_ seed: UInt8) throws -> UUIDBytes {
    try UUIDBytes(bytes: (0..<16).map { seed &+ UInt8($0) })
  }

  private func emitted(_ step: SimulatorStep) throws -> AssembledPoseFrame {
    guard case .emitted(let frame) = step else {
      XCTFail("frameがdropされました")
      throw TestError.expectedFrame
    }
    return frame
  }
}

private enum TestError: Error {
  case expectedFrame
}
