import Dispatch
import Foundation
import HubCore
import HubNetworking

public struct NetworkRuntimeConfiguration: Equatable, Sendable {
  public let host: String
  public let port: Int

  public init(host: String, port: Int) {
    self.host = host
    self.port = port
  }
}

public enum NetworkRuntimeConfigurationError: Error, Equatable, Sendable {
  case emptyHost
  case invalidPort
}

public struct NetworkBoundEndpoint: Equatable, Sendable {
  public let description: String
  public let port: Int
}

public struct NetworkRuntimeMetrics: Equatable, Sendable {
  public let isRunning: Bool
  public let boundEndpoint: String?
  public let lastRemoteAddress: String?
  public let receiver: ReceiverStatistics
}

public struct NetworkRuntimeSnapshot: Sendable {
  public let monotonicNS: UInt64
  public let metrics: NetworkRuntimeMetrics
  public let hubState: EvaluatedHubStateSnapshot
}

/// SwiftNIO callbackをMainActorへ渡さず、Network sourceのlatest stateを保持する。
public actor NetworkRuntime {
  private var receiver: UDPReceiver?
  private var ingress = NetworkIngress()
  private var boundEndpoint: NetworkBoundEndpoint?
  private var lastStatistics = ReceiverStatistics()

  public init() {}

  @discardableResult
  public func start(
    configuration: NetworkRuntimeConfiguration
  ) throws -> NetworkBoundEndpoint {
    guard !configuration.host.isEmpty else {
      throw NetworkRuntimeConfigurationError.emptyHost
    }
    guard (0...65_535).contains(configuration.port) else {
      throw NetworkRuntimeConfigurationError.invalidPort
    }

    try stopReceiver()

    let nextIngress = NetworkIngress()
    let nextReceiver = UDPReceiver()
    do {
      let address = try nextReceiver.start(
        configuration: UDPReceiverConfiguration(
          host: configuration.host,
          port: configuration.port
        ),
        onPacket: nextIngress.receive
      )
      let endpoint = NetworkBoundEndpoint(
        description: String(describing: address),
        port: address.port ?? configuration.port
      )
      receiver = nextReceiver
      ingress = nextIngress
      boundEndpoint = endpoint
      lastStatistics = ReceiverStatistics()
      return endpoint
    } catch {
      try? nextReceiver.shutdown()
      throw error
    }
  }

  public func stop() throws {
    try stopReceiver()
  }

  public func snapshot() -> NetworkRuntimeSnapshot {
    let now = DispatchTime.now().uptimeNanoseconds
    let currentReceiver = receiver
    let statistics = currentReceiver?.statistics() ?? lastStatistics
    let ingressSnapshot = ingress.snapshot(atMonotonicNS: now)
    return NetworkRuntimeSnapshot(
      monotonicNS: now,
      metrics: NetworkRuntimeMetrics(
        isRunning: currentReceiver?.isActive() ?? false,
        boundEndpoint: boundEndpoint?.description,
        lastRemoteAddress: ingressSnapshot.remoteAddress,
        receiver: statistics
      ),
      hubState: ingressSnapshot.hubState
    )
  }

  private func stopReceiver() throws {
    guard let currentReceiver = receiver else { return }
    try currentReceiver.close()
    ingress.flushPendingFrames()
    lastStatistics = currentReceiver.statistics()
    try currentReceiver.shutdown()
    receiver = nil
  }
}

private struct NetworkIngressSnapshot {
  let remoteAddress: String?
  let hubState: EvaluatedHubStateSnapshot
}

/// NIO event loopとGUI snapshotから共有する最小のthread-safe ingress。
private final class NetworkIngress: @unchecked Sendable {
  private let lock = NSLock()
  private let store = HubStateStore()
  private var remoteAddress: String?

  func receive(_ received: ReceivedPosePacket) {
    // 送信元と姿勢を同じ受信時点として公開し、snapshotへ中間状態を見せない。
    lock.withLock {
      _ = store.ingest(
        received.packet,
        receivedMonotonicNS: received.receivedMonotonicNS
      )
      remoteAddress = received.remoteAddress
    }
  }

  func snapshot(
    atMonotonicNS monotonicNS: UInt64
  ) -> NetworkIngressSnapshot {
    lock.withLock {
      NetworkIngressSnapshot(
        remoteAddress: remoteAddress,
        hubState: store.evaluatedSnapshot(
          atMonotonicNS: monotonicNS
        )
      )
    }
  }

  func flushPendingFrames() {
    lock.withLock {
      _ = store.flushPendingFrames()
    }
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
