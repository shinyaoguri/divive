@testable import HubAppUI
import HubCore
import HubProtocol
import HubSimulator
import XCTest

final class HubAppConfigurationTests: XCTestCase {
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
      motion: .stationary,
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
