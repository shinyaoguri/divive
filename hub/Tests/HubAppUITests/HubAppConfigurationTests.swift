import Combine
import HubCore
import HubProtocol
import HubSimulator
import XCTest

@testable import HubAppUI

final class HubAppConfigurationTests: XCTestCase {
  func testGUIで全motionPresetを選択できる() {
    XCTAssertEqual(
      HubAppMotionPreset.allCases,
      [.stationary, .circle, .walk, .jump, .random]
    )
    XCTAssertEqual(
      HubAppMotionPreset.allCases.map(\.displayName),
      ["静止", "円運動", "歩行", "ジャンプ", "ランダム移動"]
    )
  }

  @MainActor
  func testSource未開始のrefreshはUI更新をpublishしない() async {
    let model = HubAppModel()
    var notifications = 0
    let observation = model.objectWillChange.sink {
      notifications += 1
    }

    await model.refresh()

    XCTAssertEqual(notifications, 0)
    withExtendedLifetime(observation) {}
  }

  func testGUI設定から既定roleと円運動を生成する() throws {
    var simulator = try configuration(
      trackerCount: 5,
      rate: .hz120,
      motion: .circle
    ).makeSimulator()

    XCTAssertEqual(simulator.source.rate, .hz120)
    XCTAssertEqual(
      simulator.trackerConfigurations.map(\.role),
      ["waist", "left_foot", "right_foot", "prop_1", "prop_2"]
    )

    let frame = try emitted(
      simulator.step(receivedMonotonicNS: 1_000)
    )
    XCTAssertEqual(frame.poseBatch.trackers.count, 5)
    XCTAssertEqual(frame.poseBatch.backend, .simulator)
    XCTAssertEqual(frame.poseBatch.requestedRateHz, 120)
    XCTAssertNotEqual(
      frame.poseBatch.trackers[0].position,
      simulator.trackerConfigurations[0].position
    )
  }

  func test同じGUI設定は同じsource識別子と姿勢を生成する() throws {
    let configuration = configuration(
      trackerCount: 3,
      rate: .hz90,
      motion: .random,
      seed: 42
    )
    var first = try configuration.makeSimulator()
    var second = try configuration.makeSimulator()

    XCTAssertEqual(first.source, second.source)
    XCTAssertEqual(
      try first.step(receivedMonotonicNS: 10),
      try second.step(receivedMonotonicNS: 10)
    )
  }

  func testGUIの歩行は左右footへ逆位相を設定する() throws {
    var simulator = try configuration(
      trackerCount: 3,
      rate: .hz120,
      motion: .walk
    ).makeSimulator()

    let frame = try emitted(
      simulator.step(receivedMonotonicNS: 0)
    )
    let leftFoot = try XCTUnwrap(
      frame.poseBatch.trackers.first { $0.role == "left_foot" }
    )
    let rightFoot = try XCTUnwrap(
      frame.poseBatch.trackers.first { $0.role == "right_foot" }
    )
    XCTAssertLessThan(leftFoot.position.z, -1)
    XCTAssertGreaterThan(rightFoot.position.z, -1)
  }

  func testGUIのTracker上限を検証する() {
    XCTAssertThrowsError(
      try configuration(trackerCount: 0).makeSimulator()
    ) { error in
      XCTAssertEqual(
        error as? HubAppConfigurationError,
        .trackerCountOutOfRange
      )
    }
    XCTAssertThrowsError(
      try configuration(trackerCount: 17).makeSimulator()
    )
  }

  func test16台の初期位置をプレビュー範囲内に配置する() throws {
    let simulator = try configuration(
      trackerCount: 16
    ).makeSimulator()
    let xPositions = simulator.trackerConfigurations.map(\.position.x)

    XCTAssertEqual(try XCTUnwrap(xPositions.min()), -1.5, accuracy: 0.0001)
    XCTAssertEqual(try XCTUnwrap(xPositions.max()), 1.5, accuracy: 0.0001)
    XCTAssertTrue(xPositions.allSatisfy { abs($0) <= 2 })
  }

  func testGUI設定から配信障害pipelineを生成する() throws {
    let configuration = HubAppConfiguration(
      trackerCount: 3,
      rate: .hz120,
      motion: .circle,
      seed: 42,
      frameLossProbability: 0.1,
      trackingLostProbability: 0.2,
      delayMilliseconds: 12.5,
      jitterMilliseconds: 3.5,
      reorderingProbability: 0.3,
      disconnectProbability: 0.4,
      disconnectDurationMilliseconds: 2_500
    )

    let pipeline = try configuration.makeTransportFaultPipeline()

    XCTAssertEqual(pipeline.frameIntervalNS, 8_333_333)
    XCTAssertEqual(pipeline.configuration.delayNS, 12_500_000)
    XCTAssertEqual(pipeline.configuration.jitterNS, 3_500_000)
    XCTAssertEqual(pipeline.configuration.reorderingProbability, 0.3)
    XCTAssertEqual(pipeline.configuration.disconnectProbability, 0.4)
    XCTAssertEqual(
      pipeline.configuration.disconnectDurationNS,
      2_500_000_000
    )
  }

  func testGUIの負の配信時間を拒否する() {
    let configuration = HubAppConfiguration(
      trackerCount: 3,
      rate: .hz90,
      motion: .stationary,
      seed: 1,
      frameLossProbability: 0,
      trackingLostProbability: 0,
      delayMilliseconds: -1
    )

    XCTAssertThrowsError(try configuration.makeTransportFaultPipeline()) {
      error in
      XCTAssertEqual(
        error as? HubAppConfigurationError,
        .invalidDuration(.delay)
      )
    }
  }

  func testRuntimeは生成を開始停止できる() async throws {
    let runtime = SimulatorRuntime()
    try await runtime.start(
      configuration: configuration(
        trackerCount: 3,
        rate: .hz120,
        motion: .circle
      )
    )
    try await Task.sleep(for: .milliseconds(100))

    let running = await runtime.snapshot()
    XCTAssertTrue(running.metrics.isRunning)
    XCTAssertGreaterThan(running.metrics.attemptedFrames, 0)
    XCTAssertEqual(running.hubState.trackers.count, 3)

    await runtime.stop()
    let stopped = await runtime.snapshot()
    try await Task.sleep(for: .milliseconds(30))
    let stoppedAgain = await runtime.snapshot()
    XCTAssertFalse(stopped.metrics.isRunning)
    XCTAssertFalse(stoppedAgain.metrics.isRunning)
    XCTAssertGreaterThanOrEqual(
      stopped.metrics.attemptedFrames,
      running.metrics.attemptedFrames
    )
    XCTAssertEqual(
      stoppedAgain.metrics.attemptedFrames,
      stopped.metrics.attemptedFrames
    )
  }

  func testRuntime実行中にTrackerの表示位置を変更できる() async throws {
    let runtime = SimulatorRuntime()
    try await runtime.start(
      configuration: configuration(
        trackerCount: 1,
        rate: .hz120,
        motion: .stationary
      )
    )
    try await Task.sleep(for: .milliseconds(30))
    let before = await runtime.snapshot()
    let trackerID = try XCTUnwrap(
      before.hubState.trackers.first?.latest.pose.trackerID
    )
    let target = Vector3(x: 5, y: 2, z: -7)

    try await runtime.moveTracker(
      id: trackerID,
      toDisplayedPosition: target
    )
    try await Task.sleep(for: .milliseconds(30))

    let after = await runtime.snapshot()
    let position = try XCTUnwrap(
      after.hubState.trackers.first?.latest.pose.position
    )
    XCTAssertEqual(position, target)
    await runtime.stop()
  }

  func testRuntime開始前のTracker移動を拒否する() async {
    let runtime = SimulatorRuntime()

    do {
      try await runtime.moveTracker(
        id: "missing",
        toDisplayedPosition: Vector3(x: 0, y: 0, z: 0)
      )
      XCTFail("開始前の移動が成功しました")
    } catch {
      XCTAssertEqual(error as? SimulatorRuntimeError, .notStarted)
    }
  }

  private func configuration(
    trackerCount: Int,
    rate: SimulatorRate = .hz90,
    motion: HubAppMotionPreset = .stationary,
    seed: UInt64 = 1
  ) -> HubAppConfiguration {
    HubAppConfiguration(
      trackerCount: trackerCount,
      rate: rate,
      motion: motion,
      seed: seed,
      frameLossProbability: 0,
      trackingLostProbability: 0
    )
  }

  private func emitted(_ step: SimulatorStep) throws -> AssembledPoseFrame {
    switch step {
    case .emitted(let frame):
      frame
    case .dropped:
      throw UnexpectedStep.dropped
    }
  }
}

private enum UnexpectedStep: Error {
  case dropped
}
