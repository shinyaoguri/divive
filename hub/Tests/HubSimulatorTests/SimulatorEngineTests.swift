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
    XCTAssertThrowsError(
      try simulator.addTracker(
        SimulatorTrackerConfiguration(
          trackerID: "walk",
          role: "",
          position: Vector3(x: 0, y: 0, z: 0),
          motion: .walk(
            strideLengthMeters: 0.3,
            stepHeightMeters: -0.1,
            cadenceHz: 1.6,
            phaseRadians: 0
          )
        )
      )
    )
    XCTAssertThrowsError(
      try simulator.addTracker(
        SimulatorTrackerConfiguration(
          trackerID: "jump",
          role: "",
          position: Vector3(x: 0, y: 0, z: 0),
          motion: .jump(
            heightMeters: 0.3,
            frequencyHz: 0,
            phaseRadians: 0
          )
        )
      )
    )
    XCTAssertThrowsError(
      try simulator.addTracker(
        SimulatorTrackerConfiguration(
          trackerID: "random",
          role: "",
          position: Vector3(x: 0, y: 0, z: 0),
          motion: .random(
            maximumOffsetMeters: Vector3(x: 1, y: -.infinity, z: 1),
            frequencyHz: 0.2,
            seed: 1
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

  func test表示中の静止Trackerを指定位置へ移動する() throws {
    var simulator = try SimulatorEngine(
      source: try source(rate: .hz90),
      trackers: [
        tracker(
          "movable",
          role: "prop",
          position: Vector3(x: 1, y: 2, z: -3)
        )
      ]
    )
    _ = try simulator.step(receivedMonotonicNS: 10)

    let target = Vector3(x: -4, y: 1.5, z: 6)
    try simulator.moveTracker(
      id: "movable",
      toDisplayedPosition: target
    )

    let moved = try emitted(
      simulator.step(receivedMonotonicNS: 20)
    ).poseBatch.trackers[0]
    XCTAssertEqual(moved.position, target)
    XCTAssertEqual(
      simulator.trackerConfigurations[0].position,
      target
    )
  }

  func test移動後もmotionPresetと現在の軌道位相を維持する() throws {
    let motion = SimulatorMotionPreset.circle(
      radiusMeters: 2,
      angularSpeedRadiansPerSecond: 2 * .pi,
      phaseRadians: 0
    )
    var simulator = try SimulatorEngine(
      source: try source(rate: .hz120),
      trackers: [
        SimulatorTrackerConfiguration(
          trackerID: "circle",
          role: "prop",
          position: Vector3(x: 1, y: 2, z: -3),
          motion: motion
        )
      ]
    )
    _ = try simulator.step(receivedMonotonicNS: 10)

    let target = Vector3(x: 10, y: 2, z: -4)
    try simulator.moveTracker(
      id: "circle",
      toDisplayedPosition: target
    )

    let configuration = try XCTUnwrap(
      simulator.trackerConfigurations.first
    )
    XCTAssertEqual(configuration.motion, motion)
    XCTAssertEqual(
      configuration.position,
      Vector3(x: 8, y: 2, z: -4)
    )

    let next = try emitted(
      simulator.step(receivedMonotonicNS: 20)
    ).poseBatch.trackers[0]
    XCTAssertEqual(next.position.y, target.y, accuracy: 1e-5)
    XCTAssertEqual(next.position.x, target.x, accuracy: 0.01)
    XCTAssertEqual(next.position.z, target.z, accuracy: 0.11)
  }

  func test存在しないTrackerと非有限位置への移動を拒否する() throws {
    var simulator = try SimulatorEngine(
      source: try source(),
      trackers: [tracker("movable")]
    )

    XCTAssertThrowsError(
      try simulator.moveTracker(
        id: "missing",
        toDisplayedPosition: Vector3(x: 0, y: 0, z: 0)
      )
    ) { error in
      XCTAssertEqual(
        error as? SimulatorConfigurationError,
        .trackerNotFound("missing")
      )
    }
    XCTAssertThrowsError(
      try simulator.moveTracker(
        id: "movable",
        toDisplayedPosition: Vector3(x: .nan, y: 0, z: 0)
      )
    ) { error in
      XCTAssertEqual(
        error as? SimulatorConfigurationError,
        .nonFinitePose("movable")
      )
    }
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

  func testWalkは位相付き歩行軌道と速度を生成する() throws {
    var simulator = try SimulatorEngine(
      source: try source(rate: .hz120),
      trackers: [
        SimulatorTrackerConfiguration(
          trackerID: "walk",
          role: "left_foot",
          position: Vector3(x: 1, y: 2, z: -3),
          motion: .walk(
            strideLengthMeters: 2,
            stepHeightMeters: 1,
            cadenceHz: 1,
            phaseRadians: 0
          )
        )
      ]
    )

    let atContact = try emitted(
      simulator.step(receivedMonotonicNS: 0)
    ).poseBatch.trackers[0]
    XCTAssertEqual(atContact.position.x, 1, accuracy: 1e-5)
    XCTAssertEqual(atContact.position.y, 2, accuracy: 1e-5)
    XCTAssertEqual(atContact.position.z, -4, accuracy: 1e-5)
    XCTAssertEqual(atContact.linearVelocity?.y ?? 1, 0, accuracy: 1e-5)
    XCTAssertEqual(atContact.linearVelocity?.z ?? 1, 0, accuracy: 1e-5)

    var atLift = atContact
    for timestamp in 1...30 {
      atLift = try emitted(
        simulator.step(receivedMonotonicNS: UInt64(timestamp))
      ).poseBatch.trackers[0]
    }
    XCTAssertEqual(atLift.position.y, 3, accuracy: 1e-5)
    XCTAssertEqual(atLift.position.z, -3, accuracy: 1e-5)
    XCTAssertEqual(atLift.linearVelocity?.y ?? 1, 0, accuracy: 1e-5)
    XCTAssertEqual(
      atLift.linearVelocity?.z ?? 0,
      2 * .pi,
      accuracy: 1e-5
    )
  }

  func testJumpは滑らかな反復上下動と速度を生成する() throws {
    var simulator = try SimulatorEngine(
      source: try source(rate: .hz120),
      trackers: [
        SimulatorTrackerConfiguration(
          trackerID: "jump",
          role: "waist",
          position: Vector3(x: 1, y: 2, z: -3),
          motion: .jump(
            heightMeters: 3,
            frequencyHz: 1,
            phaseRadians: 0
          )
        )
      ]
    )

    let atGround = try emitted(
      simulator.step(receivedMonotonicNS: 0)
    ).poseBatch.trackers[0]
    XCTAssertEqual(atGround.position.y, 2, accuracy: 1e-5)
    XCTAssertEqual(atGround.linearVelocity?.y ?? 1, 0, accuracy: 1e-5)

    var ascending = atGround
    for timestamp in 1...30 {
      ascending = try emitted(
        simulator.step(receivedMonotonicNS: UInt64(timestamp))
      ).poseBatch.trackers[0]
    }
    XCTAssertEqual(ascending.position.y, 3.5, accuracy: 1e-5)
    XCTAssertEqual(
      ascending.linearVelocity?.y ?? 0,
      3 * .pi,
      accuracy: 1e-5
    )

    var atApex = ascending
    for timestamp in 31...60 {
      atApex = try emitted(
        simulator.step(receivedMonotonicNS: UInt64(timestamp))
      ).poseBatch.trackers[0]
    }
    XCTAssertEqual(atApex.position.y, 5, accuracy: 1e-5)
    XCTAssertEqual(atApex.linearVelocity?.y ?? 1, 0, accuracy: 1e-5)
  }

  func testRandomはseedごとに滑らかで有界な軌道を再現する() throws {
    let configuration = SimulatorTrackerConfiguration(
      trackerID: "random",
      role: "prop",
      position: Vector3(x: 1, y: 2, z: -3),
      motion: .random(
        maximumOffsetMeters: Vector3(x: 0.4, y: 0.25, z: 0.6),
        frequencyHz: 0.2,
        seed: 42
      )
    )
    var first = try SimulatorEngine(
      source: try source(rate: .hz120),
      trackers: [configuration]
    )
    var second = try SimulatorEngine(
      source: try source(rate: .hz120),
      trackers: [configuration],
      faults: try SimulatorFaultConfiguration(
        seed: 999,
        frameLossProbability: 0,
        trackingLostProbability: 1
      )
    )
    var firstPosition: Vector3?
    var changed = false

    for index in 0..<1_000 {
      let firstFrame = try emitted(
        first.step(receivedMonotonicNS: UInt64(index))
      )
      let secondFrame = try emitted(
        second.step(receivedMonotonicNS: UInt64(index))
      )
      let firstPose = try XCTUnwrap(firstFrame.poseBatch.trackers.first)
      let secondPose = try XCTUnwrap(secondFrame.poseBatch.trackers.first)

      XCTAssertEqual(firstPose.position, secondPose.position)
      XCTAssertEqual(firstPose.linearVelocity, secondPose.linearVelocity)
      XCTAssertEqual(secondPose.trackingState, .lost)
      XCTAssertLessThanOrEqual(abs(firstPose.position.x - 1), 0.400_001)
      XCTAssertLessThanOrEqual(abs(firstPose.position.y - 2), 0.250_001)
      XCTAssertLessThanOrEqual(abs(firstPose.position.z + 3), 0.600_001)
      XCTAssertNotNil(firstPose.linearVelocity)

      if let firstPosition, firstPosition != firstPose.position {
        changed = true
      }
      firstPosition = firstPose.position
    }

    XCTAssertTrue(changed)
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
