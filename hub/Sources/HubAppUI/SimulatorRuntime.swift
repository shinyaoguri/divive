import Dispatch
import Foundation
import HubCore
import HubProtocol
import HubSimulator

public struct SimulatorRuntimeMetrics: Equatable, Sendable {
  public let isRunning: Bool
  public let attemptedFrames: UInt64
  public let emittedFrames: UInt64
  public let droppedFrames: UInt64
  public let staleFrames: UInt64
  public let transport: SimulatorTransportFaultStatistics
  public let missedDeadlines: UInt64
  public let lastError: String?
}

public struct SimulatorRuntimeSnapshot: Sendable {
  public let monotonicNS: UInt64
  public let metrics: SimulatorRuntimeMetrics
  public let hubState: EvaluatedHubStateSnapshot
}

public enum SimulatorRuntimeError: Error, Equatable, Sendable {
  case notStarted
}

/// GUIのMainActorから姿勢生成を分離する実時間scheduler。
///
/// 描画eventをqueueせず、consumerは必要な頻度でlatest snapshotを取得する。
public actor SimulatorRuntime {
  private var simulator: SimulatorEngine?
  private var transport: SimulatorTransportFaultPipeline?
  private var store = HubStateStore()
  private var runTask: Task<Void, Never>?
  private var runID: UInt64 = 0
  private var isRunning = false
  private var attemptedFrames: UInt64 = 0
  private var emittedFrames: UInt64 = 0
  private var droppedFrames: UInt64 = 0
  private var staleFrames: UInt64 = 0
  private var missedDeadlines: UInt64 = 0
  private var lastError: String?

  public init() {}

  public func start(configuration: HubAppConfiguration) throws {
    runTask?.cancel()
    runID &+= 1
    let currentRunID = runID

    simulator = try configuration.makeSimulator()
    transport = try configuration.makeTransportFaultPipeline()
    store = HubStateStore()
    attemptedFrames = 0
    emittedFrames = 0
    droppedFrames = 0
    staleFrames = 0
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

  public func moveTracker(
    id: String,
    toDisplayedPosition position: Vector3
  ) throws {
    guard var currentSimulator = simulator else {
      throw SimulatorRuntimeError.notStarted
    }
    try currentSimulator.moveTracker(
      id: id,
      toDisplayedPosition: position
    )
    simulator = currentSimulator
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
        staleFrames: staleFrames,
        transport: transport?.statistics
          ?? SimulatorTransportFaultStatistics(),
        missedDeadlines: missedDeadlines,
        lastError: lastError
      ),
      hubState: store.evaluatedSnapshot(atMonotonicNS: now)
    )
  }

  private func run(id: UInt64, intervalNS: UInt64) async {
    var nextGenerationNS = DispatchTime.now().uptimeNanoseconds

    while !Task.isCancelled, id == runID {
      guard let currentTransport = transport else { break }
      let nextWakeNS = min(
        nextGenerationNS,
        currentTransport.nextDeliveryMonotonicNS ?? UInt64.max
      )
      let beforeWaitNS = DispatchTime.now().uptimeNanoseconds
      if beforeWaitNS < nextWakeNS {
        do {
          try await Task.sleep(
            nanoseconds: nextWakeNS - beforeWaitNS
          )
        } catch {
          break
        }
      }
      guard !Task.isCancelled, id == runID else { break }

      let receivedNS = DispatchTime.now().uptimeNanoseconds
      let shouldGenerate = receivedNS >= nextGenerationNS

      do {
        guard var currentSimulator = simulator,
          var currentTransport = transport
        else { break }
        var offeredFrame: AssembledPoseFrame?

        if shouldGenerate {
          if receivedNS > saturatingAdd(nextGenerationNS, intervalNS) {
            missedDeadlines += 1
            // 遅延分をburstで追い掛けず、常に現在時刻から再開する。
            nextGenerationNS = receivedNS
          }
          let step = try currentSimulator.step(
            receivedMonotonicNS: receivedNS
          )
          simulator = currentSimulator
          attemptedFrames += 1
          switch step {
          case .emitted(let frame):
            offeredFrame = frame
          case .dropped:
            droppedFrames += 1
          }

          nextGenerationNS = saturatingAdd(nextGenerationNS, intervalNS)
        }

        let deliveredFrames = currentTransport.advance(
          toMonotonicNS: receivedNS,
          offering: offeredFrame
        )
        transport = currentTransport
        for frame in deliveredFrames {
          switch store.apply(frame) {
          case .applied:
            emittedFrames += 1
          case .stale:
            staleFrames += 1
          }
        }
      } catch {
        lastError = String(describing: error)
        isRunning = false
        break
      }
    }

    if id == runID {
      isRunning = false
      runTask = nil
    }
  }

  private func saturatingAdd(_ left: UInt64, _ right: UInt64) -> UInt64 {
    let (result, overflow) = left.addingReportingOverflow(right)
    return overflow ? UInt64.max : result
  }
}
