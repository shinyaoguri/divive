import Dispatch
import Foundation
import HubCore
import HubSimulator

public struct SimulatorRuntimeMetrics: Equatable, Sendable {
  public let isRunning: Bool
  public let attemptedFrames: UInt64
  public let emittedFrames: UInt64
  public let droppedFrames: UInt64
  public let missedDeadlines: UInt64
  public let lastError: String?
}

public struct SimulatorRuntimeSnapshot: Sendable {
  public let monotonicNS: UInt64
  public let metrics: SimulatorRuntimeMetrics
  public let hubState: EvaluatedHubStateSnapshot
}

/// GUIのMainActorから姿勢生成を分離する実時間scheduler。
///
/// 描画eventをqueueせず、consumerは必要な頻度でlatest snapshotを取得する。
public actor SimulatorRuntime {
  private var simulator: SimulatorEngine?
  private var store = HubStateStore()
  private var runTask: Task<Void, Never>?
  private var runID: UInt64 = 0
  private var isRunning = false
  private var attemptedFrames: UInt64 = 0
  private var emittedFrames: UInt64 = 0
  private var droppedFrames: UInt64 = 0
  private var missedDeadlines: UInt64 = 0
  private var lastError: String?

  public init() {}

  public func start(configuration: HubAppConfiguration) throws {
    runTask?.cancel()
    runID &+= 1
    let currentRunID = runID

    simulator = try configuration.makeSimulator()
    store = HubStateStore()
    attemptedFrames = 0
    emittedFrames = 0
    droppedFrames = 0
    missedDeadlines = 0
    lastError = nil
    isRunning = true

    let intervalNS = 1_000_000_000 / UInt64(configuration.rate.rawValue)
    runTask = Task { [weak self] in
      await self?.run(id: currentRunID, intervalNS: intervalNS)
    }
  }

  public func stop() {
    runID &+= 1
    runTask?.cancel()
    runTask = nil
    isRunning = false
  }

  public func snapshot() -> SimulatorRuntimeSnapshot {
    let now = DispatchTime.now().uptimeNanoseconds
    return SimulatorRuntimeSnapshot(
      monotonicNS: now,
      metrics: SimulatorRuntimeMetrics(
        isRunning: isRunning,
        attemptedFrames: attemptedFrames,
        emittedFrames: emittedFrames,
        droppedFrames: droppedFrames,
        missedDeadlines: missedDeadlines,
        lastError: lastError
      ),
      hubState: store.evaluatedSnapshot(atMonotonicNS: now)
    )
  }

  private func run(id: UInt64, intervalNS: UInt64) async {
    var nextDeadlineNS = DispatchTime.now().uptimeNanoseconds

    while !Task.isCancelled, id == runID {
      let beforeWaitNS = DispatchTime.now().uptimeNanoseconds
      if beforeWaitNS < nextDeadlineNS {
        do {
          try await Task.sleep(
            nanoseconds: nextDeadlineNS - beforeWaitNS
          )
        } catch {
          break
        }
      }
      guard !Task.isCancelled, id == runID else { break }

      let receivedNS = DispatchTime.now().uptimeNanoseconds
      if receivedNS > nextDeadlineNS + intervalNS {
        missedDeadlines += 1
        // 遅延分をburstで追い掛けず、常に現在時刻から再開する。
        nextDeadlineNS = receivedNS
      }

      do {
        guard var currentSimulator = simulator else { break }
        let step = try currentSimulator.step(
          receivedMonotonicNS: receivedNS
        )
        simulator = currentSimulator
        attemptedFrames += 1
        switch step {
        case .emitted(let frame):
          _ = store.apply(frame)
          emittedFrames += 1
        case .dropped:
          droppedFrames += 1
        }
      } catch {
        lastError = String(describing: error)
        isRunning = false
        break
      }

      let (advancedDeadline, overflow) =
        nextDeadlineNS.addingReportingOverflow(intervalNS)
      nextDeadlineNS = overflow ? receivedNS : advancedDeadline
    }

    if id == runID {
      isRunning = false
      runTask = nil
    }
  }
}
