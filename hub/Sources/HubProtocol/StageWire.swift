import Foundation

/// Hub → contentのstage planeが従うwire定数。
///
/// Bridge → Hubのpose planeとはdatagram上限が異なる。pose planeはLANを越えるため
/// IP fragmentationを避ける1,200 byte制限を持つが、stage planeは既定でloopbackに
/// 閉じるため、16台規模のTrackerを1 datagramへ収められる上限にしている。
/// batch分割はenvelopeのfieldとして予約するが、v1では常に1 batchで送る。
public enum StageWireProtocol {
  public static let maximumDatagramSize = 8_192
  public static let maximumPayloadSize = maximumDatagramSize - WireProtocol.envelopeSize
  /// Hubがstage frameを配信し、購読を受け付ける既定のUDP port。
  public static let defaultPort = 41_321
  /// contentが購読を更新しない場合にHubが配信を止めるまでの既定時間。
  public static let defaultSubscriptionTTLMS: UInt32 = 3_000
  /// 購読TTLとして受理する範囲。過大なTTLで配信先が残り続けないようにする。
  public static let minimumSubscriptionTTLMS: UInt32 = 200
  public static let maximumSubscriptionTTLMS: UInt32 = 30_000
  /// 診断表示に使うclient名の上限。境界のないstringをそのまま保持しない。
  public static let maximumClientNameLength = 64
}

/// Trackerがcontentへどの空間で渡るか。HubCalibrationの区分と対応する。
public enum StageDelivery: UInt8, Sendable, CaseIterable {
  case unknown = 0
  case stage = 1
  case rawTrackerSpace = 2
  case blocked = 3
}

/// 未較正spaceの扱いを決めるHub側の配信mode。
public enum StageDeliveryMode: UInt8, Sendable, CaseIterable {
  case unknown = 0
  case production = 1
  case preview = 2
}

/// 受信ageに基づくHubの可用性評価。
public enum StageLiveness: UInt8, Sendable, CaseIterable {
  case unknown = 0
  case fresh = 1
  case stale = 2
  case disconnected = 3
}

/// Stage Space（またはpreview modeのTracker Space）における姿勢。
public struct StagePose: Equatable, Sendable {
  public let position: Vector3
  public let orientation: Quaternion
  public let linearVelocity: Vector3?
  public let angularVelocity: Vector3?

  public init(
    position: Vector3,
    orientation: Quaternion,
    linearVelocity: Vector3?,
    angularVelocity: Vector3?
  ) {
    self.position = position
    self.orientation = orientation
    self.linearVelocity = linearVelocity
    self.angularVelocity = angularVelocity
  }
}

/// contentへ配信するTracker 1台分の最新値。
///
/// `delivery`が`.blocked`のとき`pose`はnil。未較正の値をStage Spaceの姿勢として
/// contentへ渡さないため、poseを省いたうえで区分だけを伝える。
public struct StageTrackerRecord: Equatable, Sendable {
  public let trackerID: String
  public let role: String
  public let idKind: TrackerIDKind
  public let bridgeID: UUIDBytes
  public let trackingSpaceID: UUIDBytes
  public let spaceEpoch: UInt32
  public let delivery: StageDelivery
  public let pose: StagePose?
  public let trackingState: TrackingState
  public let trackingReason: TrackingReason
  public let liveness: StageLiveness
  public let connected: Bool
  public let battery: BatteryStatus?
  public let receiveAgeNS: UInt64
  public let sourceFrameSequence: UInt64
  public let captureMonotonicNS: UInt64

  public init(
    trackerID: String,
    role: String,
    idKind: TrackerIDKind,
    bridgeID: UUIDBytes,
    trackingSpaceID: UUIDBytes,
    spaceEpoch: UInt32,
    delivery: StageDelivery,
    pose: StagePose?,
    trackingState: TrackingState,
    trackingReason: TrackingReason,
    liveness: StageLiveness,
    connected: Bool,
    battery: BatteryStatus?,
    receiveAgeNS: UInt64,
    sourceFrameSequence: UInt64,
    captureMonotonicNS: UInt64
  ) {
    self.trackerID = trackerID
    self.role = role
    self.idKind = idKind
    self.bridgeID = bridgeID
    self.trackingSpaceID = trackingSpaceID
    self.spaceEpoch = spaceEpoch
    self.delivery = delivery
    self.pose = pose
    self.trackingState = trackingState
    self.trackingReason = trackingReason
    self.liveness = liveness
    self.connected = connected
    self.battery = battery
    self.receiveAgeNS = receiveAgeNS
    self.sourceFrameSequence = sourceFrameSequence
    self.captureMonotonicNS = captureMonotonicNS
  }
}

/// Hubが1回の配信で送るStage Spaceの最新値。
public struct StageFrameMessage: Equatable, Sendable {
  public let hubMonotonicNS: UInt64
  public let generation: UInt64
  public let profileID: String
  public let profileRevision: UInt32
  public let deliveryMode: StageDeliveryMode
  public let publishRateHz: UInt16
  public let trackers: [StageTrackerRecord]

  public init(
    hubMonotonicNS: UInt64,
    generation: UInt64,
    profileID: String,
    profileRevision: UInt32,
    deliveryMode: StageDeliveryMode,
    publishRateHz: UInt16,
    trackers: [StageTrackerRecord]
  ) {
    self.hubMonotonicNS = hubMonotonicNS
    self.generation = generation
    self.profileID = profileID
    self.profileRevision = profileRevision
    self.deliveryMode = deliveryMode
    self.publishRateHz = publishRateHz
    self.trackers = trackers
  }
}

/// contentがHubへ送る購読登録。認証ではなく配信先の登録である。
public struct StageSubscriptionMessage: Equatable, Sendable {
  public let clientName: String
  public let requestedRateHz: UInt16
  public let ttlMS: UInt32
  public let unsubscribe: Bool

  public init(
    clientName: String,
    requestedRateHz: UInt16 = 0,
    ttlMS: UInt32 = StageWireProtocol.defaultSubscriptionTTLMS,
    unsubscribe: Bool = false
  ) {
    self.clientName = clientName
    self.requestedRateHz = requestedRateHz
    self.ttlMS = ttlMS
    self.unsubscribe = unsubscribe
  }
}

/// envelopeとpayloadを合わせたstage planeのdecode結果。
public struct DecodedStageFramePacket: Equatable, Sendable {
  public let envelope: PacketEnvelope
  public let frame: StageFrameMessage

  public init(envelope: PacketEnvelope, frame: StageFrameMessage) {
    self.envelope = envelope
    self.frame = frame
  }
}

public struct DecodedStageSubscriptionPacket: Equatable, Sendable {
  public let envelope: PacketEnvelope
  public let subscription: StageSubscriptionMessage

  public init(envelope: PacketEnvelope, subscription: StageSubscriptionMessage) {
    self.envelope = envelope
    self.subscription = subscription
  }
}
