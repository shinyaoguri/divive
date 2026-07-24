import Combine
import Foundation
import HubCore
import HubNetworking
import HubProtocol
import HubSimulator

public enum HubInputSource: String, CaseIterable, Identifiable, Sendable {
  case network
  case simulator

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .network: "UDP受信"
    case .simulator: "Simulator"
    }
  }
}

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
  @Published public var selectedSource: HubInputSource = .simulator

  @Published public var networkBindHost = "0.0.0.0"
  @Published public var networkPortText = "41320"

  @Published public var trackerCount = 3
  @Published public var rate: SimulatorRate = .hz90
  @Published public var motion: HubAppMotionPreset = .circle
  @Published public var seedText = "42"
  @Published public var frameLossPercent = 0.0
  @Published public var trackingLostPercent = 0.0

  @Published public private(set) var activeSource: HubInputSource?
  @Published public private(set) var isRunning = false
  @Published public private(set) var observedRateHz = 0.0
  @Published public private(set) var trackers: [TrackerDisplayState] = []
  @Published public private(set) var errorMessage: String?

  @Published public private(set) var attemptedFrames: UInt64 = 0
  @Published public private(set) var emittedFrames: UInt64 = 0
  @Published public private(set) var droppedFrames: UInt64 = 0
  @Published public private(set) var missedDeadlines: UInt64 = 0

  @Published public private(set) var receivedDatagrams: UInt64 = 0
  @Published public private(set) var validPackets: UInt64 = 0
  @Published public private(set) var invalidPackets: UInt64 = 0
  @Published public private(set) var missingFrames: UInt64 = 0
  @Published public private(set) var duplicatePackets: UInt64 = 0
  @Published public private(set) var outOfOrderPackets: UInt64 = 0
  @Published public private(set) var inconsistentBatchPackets: UInt64 = 0
  @Published public private(set) var lastProcessingMicroseconds: UInt64 = 0
  @Published public private(set) var boundEndpoint: String?
  @Published public private(set) var lastRemoteAddress: String?

  private let simulatorRuntime: SimulatorRuntime
  private let networkRuntime: NetworkRuntime
  private var previousSample: (source: HubInputSource, monotonicNS: UInt64, generation: UInt64)?

  public init(
    simulatorRuntime: SimulatorRuntime = SimulatorRuntime(),
    networkRuntime: NetworkRuntime = NetworkRuntime()
  ) {
    self.simulatorRuntime = simulatorRuntime
    self.networkRuntime = networkRuntime
  }

  public var displayedSource: HubInputSource {
    activeSource ?? selectedSource
  }

  public var statusTitle: String {
    guard let activeSource else { return "停止中" }
    return switch (activeSource, isRunning) {
    case (.network, true): "UDP受信中"
    case (.network, false): "受信停止中"
    case (.simulator, true): "Simulator実行中"
    case (.simulator, false): "Simulator停止中"
    }
  }

  public var startButtonTitle: String {
    if isRunning, activeSource == selectedSource {
      return "設定を反映して再起動"
    }
    if isRunning {
      return "\(selectedSource.displayName)へ切替"
    }
    return selectedSource == .network ? "受信開始" : "開始"
  }

  public var dashboardSubtitle: String {
    switch displayedSource {
    case .simulator:
      "SimulatorからHubへ入った正規化済みlatest state"
    case .network:
      if let lastRemoteAddress {
        "UDP \(lastRemoteAddress) から受信したlatest state"
      } else {
        "Windows Bridgeまたはtest senderからのUDP受信待ち"
      }
    }
  }

  public var summaryText: String {
    switch displayedSource {
    case .simulator:
      "attempted \(attemptedFrames) / emitted \(emittedFrames)"
    case .network:
      "datagrams \(receivedDatagrams) / valid \(validPackets)"
    }
  }

  public var droppedPercent: Double {
    guard attemptedFrames > 0 else { return 0 }
    return Double(droppedFrames) / Double(attemptedFrames) * 100
  }

  public var networkAnomalyCount: UInt64 {
    invalidPackets + duplicatePackets + outOfOrderPackets
      + inconsistentBatchPackets
  }

  public func startSelectedSource() async {
    do {
      switch selectedSource {
      case .simulator:
        let configuration = try simulatorConfiguration()
        try await networkRuntime.stop()
        try await simulatorRuntime.start(configuration: configuration)
      case .network:
        let configuration = try networkConfiguration()
        await simulatorRuntime.stop()
        _ = try await networkRuntime.start(configuration: configuration)
      }
      activeSource = selectedSource
      previousSample = nil
      errorMessage = nil
      await refresh()
    } catch {
      errorMessage =
        "\(selectedSource.displayName)を開始できませんでした: \(error)"
      await refresh()
    }
  }

  public func stopActiveSource() async {
    do {
      switch activeSource {
      case .network:
        try await networkRuntime.stop()
      case .simulator:
        await simulatorRuntime.stop()
      case nil:
        return
      }
      errorMessage = nil
      await refresh()
    } catch {
      errorMessage = "Sourceを停止できませんでした: \(error)"
    }
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
    // Source未開始時に同じ初期値を再publishしてSwiftUIを再layoutしない。
    guard let activeSource else { return }

    switch activeSource {
    case .simulator:
      update(from: await simulatorRuntime.snapshot())
    case .network:
      update(from: await networkRuntime.snapshot())
    }
  }

  private func simulatorConfiguration() throws -> HubAppConfiguration {
    guard let seed = UInt64(seedText) else {
      throw HubAppInputError.invalidSeed
    }
    return HubAppConfiguration(
      trackerCount: trackerCount,
      rate: rate,
      motion: motion,
      seed: seed,
      frameLossProbability: frameLossPercent / 100,
      trackingLostProbability: trackingLostPercent / 100
    )
  }

  private func networkConfiguration() throws -> NetworkRuntimeConfiguration {
    guard let port = Int(networkPortText), (1...65_535).contains(port) else {
      throw HubAppInputError.invalidPort
    }
    guard !networkBindHost.isEmpty else {
      throw HubAppInputError.emptyBindHost
    }
    return NetworkRuntimeConfiguration(host: networkBindHost, port: port)
  }

  private func update(from snapshot: SimulatorRuntimeSnapshot) {
    updateObservedRate(
      source: .simulator,
      monotonicNS: snapshot.monotonicNS,
      generation: snapshot.hubState.generation
    )
    publish(snapshot.metrics.isRunning, to: \.isRunning)
    publish(snapshot.metrics.attemptedFrames, to: \.attemptedFrames)
    publish(snapshot.metrics.emittedFrames, to: \.emittedFrames)
    publish(snapshot.metrics.droppedFrames, to: \.droppedFrames)
    publish(snapshot.metrics.missedDeadlines, to: \.missedDeadlines)
    publish(
      snapshot.hubState.trackers.map(TrackerDisplayState.init),
      to: \.trackers
    )
    if let runtimeError = snapshot.metrics.lastError {
      errorMessage = "Simulatorが停止しました: \(runtimeError)"
    }
  }

  private func update(from snapshot: NetworkRuntimeSnapshot) {
    updateObservedRate(
      source: .network,
      monotonicNS: snapshot.monotonicNS,
      generation: snapshot.hubState.generation
    )
    let receiver = snapshot.metrics.receiver
    publish(snapshot.metrics.isRunning, to: \.isRunning)
    publish(snapshot.metrics.boundEndpoint, to: \.boundEndpoint)
    publish(snapshot.metrics.lastRemoteAddress, to: \.lastRemoteAddress)
    publish(receiver.datagrams, to: \.receivedDatagrams)
    publish(receiver.validPackets, to: \.validPackets)
    publish(receiver.invalidPackets, to: \.invalidPackets)
    publish(receiver.missingFrames, to: \.missingFrames)
    publish(receiver.duplicatePackets, to: \.duplicatePackets)
    publish(receiver.outOfOrderPackets, to: \.outOfOrderPackets)
    publish(
      receiver.inconsistentBatchPackets,
      to: \.inconsistentBatchPackets
    )
    publish(
      receiver.lastProcessingTimeNS / 1_000,
      to: \.lastProcessingMicroseconds
    )
    publish(
      snapshot.hubState.trackers.map(TrackerDisplayState.init),
      to: \.trackers
    )
  }

  private func updateObservedRate(
    source: HubInputSource,
    monotonicNS: UInt64,
    generation: UInt64
  ) {
    defer {
      previousSample = (
        source: source,
        monotonicNS: monotonicNS,
        generation: generation
      )
    }
    guard let previousSample,
      previousSample.source == source,
      generation >= previousSample.generation,
      monotonicNS > previousSample.monotonicNS
    else {
      publish(0, to: \.observedRateHz)
      return
    }
    let elapsedSeconds =
      Double(monotonicNS - previousSample.monotonicNS) / 1_000_000_000
    publish(
      Double(generation - previousSample.generation) / elapsedSeconds,
      to: \.observedRateHz
    )
  }

  /// `@Published`は同値代入でも通知するため、idle sourceでは変更時だけpublishする。
  private func publish<Value: Equatable>(
    _ value: Value,
    to keyPath: ReferenceWritableKeyPath<HubAppModel, Value>
  ) {
    guard self[keyPath: keyPath] != value else { return }
    self[keyPath: keyPath] = value
  }
}

public enum HubAppInputError: Error, Equatable, Sendable,
  CustomStringConvertible
{
  case invalidSeed
  case invalidPort
  case emptyBindHost

  public var description: String {
    switch self {
    case .invalidSeed: "Seedは0以上の整数で入力してください"
    case .invalidPort: "UDP portは1〜65535の整数で入力してください"
    case .emptyBindHost: "Bind addressを入力してください"
    }
  }
}
