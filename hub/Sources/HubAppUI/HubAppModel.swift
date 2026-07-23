import Combine
import Foundation
import HubCore
import HubProtocol
import HubSimulator

public struct TrackerDisplayState: Equatable, Identifiable, Sendable {
  public let id: String
  public let role: String
  public let position: Vector3
  public let trackingState: TrackingState
  public let trackingReason: TrackingReason
  public let liveness: HubLivenessState
  public let ageMilliseconds: Double
  public let frameSequence: UInt64

  init(_ state: EvaluatedTrackerState) {
    id = state.latest.pose.trackerID
    role = state.latest.pose.role
    position = state.latest.pose.position
    trackingState = state.trackingState
    trackingReason = state.trackingReason
    liveness = state.liveness
    ageMilliseconds = Double(state.receiveAgeNS) / 1_000_000
    frameSequence = state.latest.frameSequence
  }
}

@MainActor
public final class HubAppModel: ObservableObject {
  @Published public var trackerCount = 3
  @Published public var rate: SimulatorRate = .hz90
  @Published public var motion: HubAppMotionPreset = .circle
  @Published public var seedText = "42"
  @Published public var frameLossPercent = 0.0
  @Published public var trackingLostPercent = 0.0

  @Published public private(set) var isRunning = false
  @Published public private(set) var attemptedFrames: UInt64 = 0
  @Published public private(set) var emittedFrames: UInt64 = 0
  @Published public private(set) var droppedFrames: UInt64 = 0
  @Published public private(set) var missedDeadlines: UInt64 = 0
  @Published public private(set) var observedRateHz = 0.0
  @Published public private(set) var trackers: [TrackerDisplayState] = []
  @Published public private(set) var errorMessage: String?

  private let runtime: SimulatorRuntime
  private var previousSample: (monotonicNS: UInt64, emittedFrames: UInt64)?

  public init(runtime: SimulatorRuntime = SimulatorRuntime()) {
    self.runtime = runtime
  }

  public var droppedPercent: Double {
    guard attemptedFrames > 0 else { return 0 }
    return Double(droppedFrames) / Double(attemptedFrames) * 100
  }

  public func startSimulator() async {
    guard let seed = UInt64(seedText) else {
      errorMessage = "Seedは0以上の整数で入力してください。"
      return
    }
    let configuration = HubAppConfiguration(
      trackerCount: trackerCount,
      rate: rate,
      motion: motion,
      seed: seed,
      frameLossProbability: frameLossPercent / 100,
      trackingLostProbability: trackingLostPercent / 100
    )

    do {
      try await runtime.start(configuration: configuration)
      previousSample = nil
      errorMessage = nil
      await refresh()
    } catch {
      errorMessage = "Simulatorを開始できませんでした: \(error)"
    }
  }

  public func stopSimulator() async {
    await runtime.stop()
    await refresh()
  }

  /// SwiftUIの`.task`から呼び、画面表示中だけlatest stateを10Hzで読む。
  public func refreshUntilCancelled() async {
    while !Task.isCancelled {
      await refresh()
      do {
        try await Task.sleep(for: .milliseconds(100))
      } catch {
        break
      }
    }
  }

  public func refresh() async {
    let snapshot = await runtime.snapshot()
    updateObservedRate(snapshot)

    isRunning = snapshot.metrics.isRunning
    attemptedFrames = snapshot.metrics.attemptedFrames
    emittedFrames = snapshot.metrics.emittedFrames
    droppedFrames = snapshot.metrics.droppedFrames
    missedDeadlines = snapshot.metrics.missedDeadlines
    trackers = snapshot.hubState.trackers.map(TrackerDisplayState.init)
    if let runtimeError = snapshot.metrics.lastError {
      errorMessage = "Simulatorが停止しました: \(runtimeError)"
    }
  }

  private func updateObservedRate(_ snapshot: SimulatorRuntimeSnapshot) {
    defer {
      previousSample = (
        monotonicNS: snapshot.monotonicNS,
        emittedFrames: snapshot.metrics.emittedFrames
      )
    }
    guard let previousSample,
      snapshot.metrics.emittedFrames >= previousSample.emittedFrames,
      snapshot.monotonicNS > previousSample.monotonicNS
    else {
      observedRateHz = 0
      return
    }
    let elapsedSeconds =
      Double(snapshot.monotonicNS - previousSample.monotonicNS)
      / 1_000_000_000
    let emitted =
      snapshot.metrics.emittedFrames - previousSample.emittedFrames
    observedRateHz = Double(emitted) / elapsedSeconds
  }
}
