import HubCore

public enum SimulatorTransportFaultConfigurationError: Error, Equatable,
  Sendable
{
  case invalidReorderingProbability
  case invalidDisconnectProbability
  case disconnectDurationMustBePositive
  case maximumPendingFramesMustBePositive
  case frameIntervalMustBePositive
}

/// Simulatorが生成したcanonical frameとHub入力境界の間へ挿入する通信障害設定。
///
/// delayとjitterの単位はHub monotonic nanosecond。disconnect確率が0より大きい場合は、
/// 1回の障害がliveness閾値をまたげるよう継続時間を明示する。
public struct SimulatorTransportFaultConfiguration: Equatable, Sendable {
  public let seed: UInt64
  public let delayNS: UInt64
  public let jitterNS: UInt64
  public let reorderingProbability: Double
  public let disconnectProbability: Double
  public let disconnectDurationNS: UInt64
  public let maximumPendingFrames: Int

  public init() {
    seed = 1
    delayNS = 0
    jitterNS = 0
    reorderingProbability = 0
    disconnectProbability = 0
    disconnectDurationNS = 0
    maximumPendingFrames = 1_024
  }

  public init(
    seed: UInt64,
    delayNS: UInt64,
    jitterNS: UInt64,
    reorderingProbability: Double,
    disconnectProbability: Double,
    disconnectDurationNS: UInt64,
    maximumPendingFrames: Int = 1_024
  ) throws {
    guard reorderingProbability.isFinite,
      (0...1).contains(reorderingProbability)
    else {
      throw SimulatorTransportFaultConfigurationError
        .invalidReorderingProbability
    }
    guard disconnectProbability.isFinite,
      (0...1).contains(disconnectProbability)
    else {
      throw SimulatorTransportFaultConfigurationError
        .invalidDisconnectProbability
    }
    guard disconnectProbability == 0 || disconnectDurationNS > 0 else {
      throw SimulatorTransportFaultConfigurationError
        .disconnectDurationMustBePositive
    }
    guard maximumPendingFrames > 0 else {
      throw SimulatorTransportFaultConfigurationError
        .maximumPendingFramesMustBePositive
    }

    self.seed = seed
    self.delayNS = delayNS
    self.jitterNS = jitterNS
    self.reorderingProbability = reorderingProbability
    self.disconnectProbability = disconnectProbability
    self.disconnectDurationNS = disconnectDurationNS
    self.maximumPendingFrames = maximumPendingFrames
  }
}

public struct SimulatorTransportFaultStatistics: Equatable, Sendable {
  public fileprivate(set) var offeredFrames: UInt64 = 0
  public fileprivate(set) var deliveredFrames: UInt64 = 0
  public fileprivate(set) var disconnectEvents: UInt64 = 0
  public fileprivate(set) var disconnectedFrames: UInt64 = 0
  public fileprivate(set) var overflowFrames: UInt64 = 0
  public fileprivate(set) var reorderingCandidates: UInt64 = 0
  public fileprivate(set) var pendingFrames: UInt64 = 0

  public init() {}
}

/// 実時間schedulerから独立した、決定論的で有界な配信障害pipeline。
///
/// 同じ設定、seed、入力frame、時刻列なら同じ配信順になります。保留frame数には
/// 上限があり、超過時は最も古いsequenceを破棄してlatest frameを優先します。
public struct SimulatorTransportFaultPipeline: Sendable {
  private struct PendingFrame: Sendable {
    let deliveryMonotonicNS: UInt64
    let insertionOrder: UInt64
    let frame: AssembledPoseFrame
  }

  public let configuration: SimulatorTransportFaultConfiguration
  public let frameIntervalNS: UInt64

  private var random: TransportSplitMix64
  private var pending: [PendingFrame] = []
  private var nextInsertionOrder: UInt64 = 0
  private var disconnectUntilNS: UInt64?
  private var skipReorderingForNextFrame = false
  private var value = SimulatorTransportFaultStatistics()

  public init(
    configuration: SimulatorTransportFaultConfiguration,
    frameIntervalNS: UInt64
  ) throws {
    guard frameIntervalNS > 0 else {
      throw SimulatorTransportFaultConfigurationError
        .frameIntervalMustBePositive
    }
    self.configuration = configuration
    self.frameIntervalNS = frameIntervalNS
    random = TransportSplitMix64(seed: configuration.seed)
  }

  public var statistics: SimulatorTransportFaultStatistics {
    var snapshot = value
    snapshot.pendingFrames = UInt64(pending.count)
    return snapshot
  }

  public var nextDeliveryMonotonicNS: UInt64? {
    pending.map(\.deliveryMonotonicNS).min()
  }

  public func isDisconnected(atMonotonicNS monotonicNS: UInt64) -> Bool {
    guard let disconnectUntilNS else { return false }
    return monotonicNS < disconnectUntilNS
  }

  /// 指定時刻までclockを進め、任意の新規frameを障害経路へ投入する。
  ///
  /// 返すframeの受信時刻は実際の配信時刻へ更新するが、capture/send時刻は生成時の
  /// 値を維持する。`frame == nil`でも期限到達済みframeを排出できる。
  public mutating func advance(
    toMonotonicNS monotonicNS: UInt64,
    offering frame: AssembledPoseFrame? = nil
  ) -> [AssembledPoseFrame] {
    var delivered = drain(atMonotonicNS: monotonicNS)
    if let frame {
      offer(frame, atMonotonicNS: monotonicNS)
    }
    delivered.append(contentsOf: drain(atMonotonicNS: monotonicNS))
    return delivered
  }

  private mutating func offer(
    _ frame: AssembledPoseFrame,
    atMonotonicNS monotonicNS: UInt64
  ) {
    value.offeredFrames += 1

    if isDisconnected(atMonotonicNS: monotonicNS) {
      value.disconnectedFrames += 1
      return
    }
    disconnectUntilNS = nil

    let startsDisconnect =
      random.nextUnitInterval() < configuration.disconnectProbability
    if startsDisconnect {
      value.disconnectEvents += 1
      value.disconnectedFrames += UInt64(pending.count) + 1
      pending.removeAll(keepingCapacity: true)
      disconnectUntilNS = saturatingAdd(
        monotonicNS,
        configuration.disconnectDurationNS
      )
      skipReorderingForNextFrame = false
      return
    }

    let jitterUnit = random.nextUnitInterval()
    let jitterOffset =
      (jitterUnit * 2 - 1) * Double(configuration.jitterNS)
    let delay = max(
      0,
      Double(configuration.delayNS) + jitterOffset
    )

    let shouldReorder: Bool
    if skipReorderingForNextFrame {
      shouldReorder = false
      skipReorderingForNextFrame = false
    } else {
      shouldReorder =
        random.nextUnitInterval() < configuration.reorderingProbability
      if shouldReorder {
        skipReorderingForNextFrame = true
        value.reorderingCandidates += 1
      }
    }

    let reorderDelay =
      shouldReorder
      ? saturatingMultiply(frameIntervalNS, 2)
      : 0
    let boundedDelay =
      delay >= Double(UInt64.max) ? UInt64.max : UInt64(delay.rounded())
    let deliveryTime = saturatingAdd(
      monotonicNS,
      saturatingAdd(boundedDelay, reorderDelay)
    )

    if pending.count >= configuration.maximumPendingFrames {
      if let oldestIndex = pending.indices.min(by: {
        pending[$0].frame.frameSequence
          < pending[$1].frame.frameSequence
      }) {
        pending.remove(at: oldestIndex)
        value.overflowFrames += 1
      }
    }

    pending.append(
      PendingFrame(
        deliveryMonotonicNS: deliveryTime,
        insertionOrder: nextInsertionOrder,
        frame: frame
      )
    )
    nextInsertionOrder &+= 1
  }

  private mutating func drain(
    atMonotonicNS monotonicNS: UInt64
  ) -> [AssembledPoseFrame] {
    guard !isDisconnected(atMonotonicNS: monotonicNS) else {
      return []
    }

    let due = pending.filter {
      $0.deliveryMonotonicNS <= monotonicNS
    }.sorted {
      if $0.deliveryMonotonicNS == $1.deliveryMonotonicNS {
        return $0.insertionOrder < $1.insertionOrder
      }
      return $0.deliveryMonotonicNS < $1.deliveryMonotonicNS
    }
    guard !due.isEmpty else { return [] }

    let dueOrders = Set(due.map(\.insertionOrder))
    pending.removeAll { dueOrders.contains($0.insertionOrder) }
    value.deliveredFrames += UInt64(due.count)
    return due.map {
      frameByUpdatingReceiveTime(
        $0.frame,
        receivedMonotonicNS: monotonicNS
      )
    }
  }

  private func frameByUpdatingReceiveTime(
    _ frame: AssembledPoseFrame,
    receivedMonotonicNS: UInt64
  ) -> AssembledPoseFrame {
    AssembledPoseFrame(
      sessionID: frame.sessionID,
      bridgeID: frame.bridgeID,
      frameSequence: frame.frameSequence,
      expectedBatchCount: frame.expectedBatchCount,
      receivedBatchIndices: frame.receivedBatchIndices,
      firstReceivedMonotonicNS: receivedMonotonicNS,
      lastReceivedMonotonicNS: receivedMonotonicNS,
      completeness: frame.completeness,
      poseBatch: frame.poseBatch
    )
  }

  private func saturatingAdd(_ left: UInt64, _ right: UInt64) -> UInt64 {
    let (result, overflow) = left.addingReportingOverflow(right)
    return overflow ? UInt64.max : result
  }

  private func saturatingMultiply(
    _ left: UInt64,
    _ right: UInt64
  ) -> UInt64 {
    let (result, overflow) = left.multipliedReportingOverflow(by: right)
    return overflow ? UInt64.max : result
  }
}

private struct TransportSplitMix64: Sendable {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func nextUnitInterval() -> Double {
    let upper53Bits = next() >> 11
    return Double(upper53Bits) * (1.0 / 9_007_199_254_740_992.0)
  }

  private mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var value = state
    value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
    value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
    return value ^ (value >> 31)
  }
}
