import HubProtocol

/// 現在stage frameを受け取るcontent client。
public struct StageSubscriber<Key: Hashable & Sendable>: Equatable, Sendable {
  public let key: Key
  public let address: String
  public let clientName: String
  public let clientID: UUIDBytes
  public let sessionID: UUIDBytes
  public let requestedRateHz: UInt16
  public let registeredAtMonotonicNS: UInt64
  public let expiresAtMonotonicNS: UInt64
  public let renewals: UInt64
}

/// 購読登録の判定結果。
public enum StageSubscriptionOutcome: Equatable, Sendable {
  case registered
  case renewed
  case unsubscribed
  /// loopback以外からの購読を既定で拒否する。UDPは送信元を詐称できるため、
  /// 認証を実装するまでLANへ配信先を広げない。
  case rejectedNotLoopback
  case rejectedCapacity
  /// 未登録のclientからのunsubscribeなど、状態を変えなかった場合。
  case ignored
}

public struct StageSubscriptionStatistics: Equatable, Sendable {
  public var registrations: UInt64 = 0
  public var renewals: UInt64 = 0
  public var unsubscribes: UInt64 = 0
  public var expirations: UInt64 = 0
  public var rejectedNotLoopback: UInt64 = 0
  public var rejectedCapacity: UInt64 = 0

  public init() {}
}

/// TTL付きで配信先を保持する。
///
/// contentが落ちてもHubが配信し続けないよう、更新の来ない購読は期限で消す。
/// 期限判定はHubのmonotonic clockで行い、client側の時刻を信用しない。
public struct StageSubscriptionRegistry<Key: Hashable & Sendable>: Sendable {
  public let maximumSubscribers: Int
  public let allowNonLoopbackClients: Bool

  private var subscribers: [Key: StageSubscriber<Key>] = [:]
  public private(set) var statistics = StageSubscriptionStatistics()

  public init(
    maximumSubscribers: Int = 16,
    allowNonLoopbackClients: Bool = false
  ) {
    self.maximumSubscribers = max(1, maximumSubscribers)
    self.allowNonLoopbackClients = allowNonLoopbackClients
  }

  public var count: Int {
    subscribers.count
  }

  @discardableResult
  public mutating func register(
    _ packet: DecodedStageSubscriptionPacket,
    from key: Key,
    address: String,
    isLoopback: Bool,
    atMonotonicNS monotonicNS: UInt64
  ) -> StageSubscriptionOutcome {
    guard isLoopback || allowNonLoopbackClients else {
      statistics.rejectedNotLoopback += 1
      return .rejectedNotLoopback
    }

    if packet.subscription.unsubscribe {
      guard subscribers.removeValue(forKey: key) != nil else {
        return .ignored
      }
      statistics.unsubscribes += 1
      return .unsubscribed
    }

    let existing = subscribers[key]
    if existing == nil, subscribers.count >= maximumSubscribers {
      statistics.rejectedCapacity += 1
      return .rejectedCapacity
    }

    let ttlNS = UInt64(clampedTTLMS(packet.subscription.ttlMS)) * 1_000_000
    subscribers[key] = StageSubscriber(
      key: key,
      address: address,
      clientName: packet.subscription.clientName,
      clientID: packet.envelope.bridgeID,
      sessionID: packet.envelope.sessionID,
      requestedRateHz: packet.subscription.requestedRateHz,
      registeredAtMonotonicNS: existing?.registeredAtMonotonicNS ?? monotonicNS,
      expiresAtMonotonicNS: monotonicNS &+ ttlNS,
      renewals: (existing?.renewals ?? 0) &+ (existing == nil ? 0 : 1)
    )

    if existing == nil {
      statistics.registrations += 1
      return .registered
    }
    statistics.renewals += 1
    return .renewed
  }

  /// 期限切れの購読を取り除き、残った配信先を返す。
  @discardableResult
  public mutating func prune(
    atMonotonicNS monotonicNS: UInt64
  ) -> [StageSubscriber<Key>] {
    let expired = subscribers.filter { $0.value.expiresAtMonotonicNS <= monotonicNS }
    for key in expired.keys {
      subscribers.removeValue(forKey: key)
    }
    statistics.expirations += UInt64(expired.count)
    return sortedSubscribers()
  }

  public func activeSubscribers() -> [StageSubscriber<Key>] {
    sortedSubscribers()
  }

  private func sortedSubscribers() -> [StageSubscriber<Key>] {
    subscribers.values.sorted { left, right in
      if left.registeredAtMonotonicNS == right.registeredAtMonotonicNS {
        return left.address < right.address
      }
      return left.registeredAtMonotonicNS < right.registeredAtMonotonicNS
    }
  }

  private func clampedTTLMS(_ requested: UInt32) -> UInt32 {
    guard requested > 0 else {
      return StageWireProtocol.defaultSubscriptionTTLMS
    }
    return min(
      max(requested, StageWireProtocol.minimumSubscriptionTTLMS),
      StageWireProtocol.maximumSubscriptionTTLMS
    )
  }
}
