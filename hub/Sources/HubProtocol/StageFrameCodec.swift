import FlatBuffers
import Foundation

/// stage frameをenvelope付きdatagramへencodeする。
///
/// 過去frameを再送しないため、encoderはbufferを持たず1 frameずつ完結させる。
public struct StageFrameEncoder: Sendable {
  private let envelopeEncoder = EnvelopeEncoder(
    maximumDatagramSize: StageWireProtocol.maximumDatagramSize
  )

  public init() {}

  public func encode(
    frame: StageFrameMessage,
    sessionID: UUIDBytes,
    sourceID: UUIDBytes,
    frameSequence: UInt64
  ) throws -> [UInt8] {
    try validate(frame)

    var builder = FlatBufferBuilder(initialSize: 1_024)
    let trackerOffsets = frame.trackers.map { tracker -> Offset in
      let trackerIDOffset = builder.create(string: tracker.trackerID)
      let roleOffset = builder.create(string: tracker.role)
      return Divive_Stage_StageTracker.createStageTracker(
        &builder,
        trackerIdOffset: trackerIDOffset,
        roleOffset: roleOffset,
        idKind: map(tracker.idKind),
        bridgeId: uuid(tracker.bridgeID),
        trackingSpaceId: uuid(tracker.trackingSpaceID),
        spaceEpoch: tracker.spaceEpoch,
        delivery: map(tracker.delivery),
        position: tracker.pose.map { vector($0.position) },
        orientation: tracker.pose.map { quaternion($0.orientation) },
        linearVelocity: tracker.pose?.linearVelocity.map(vector),
        angularVelocity: tracker.pose?.angularVelocity.map(vector),
        trackingState: map(tracker.trackingState),
        trackingReason: map(tracker.trackingReason),
        liveness: map(tracker.liveness),
        connected: tracker.connected,
        battery: tracker.battery.map {
          Divive_Protocol__BatteryStatus(level: $0.level, charging: $0.charging)
        },
        receiveAgeNs: tracker.receiveAgeNS,
        sourceFrameSequence: tracker.sourceFrameSequence,
        captureMonotonicNs: tracker.captureMonotonicNS
      )
    }
    let trackersOffset = builder.createVector(ofOffsets: trackerOffsets)
    let profileOffset = builder.create(string: frame.profileID)
    let root = Divive_Stage_StageFrame.createStageFrame(
      &builder,
      hubMonotonicNs: frame.hubMonotonicNS,
      generation: frame.generation,
      profileIdOffset: profileOffset,
      profileRevision: frame.profileRevision,
      deliveryMode: map(frame.deliveryMode),
      publishRateHz: frame.publishRateHz,
      trackersVectorOffset: trackersOffset
    )
    Divive_Stage_StageFrame.finish(&builder, end: root)

    return try envelopeEncoder.encode(
      envelope: PacketEnvelope(
        protocolMinor: WireProtocol.protocolMinor,
        messageType: .stageFrame,
        flags: 0,
        sessionID: sessionID,
        bridgeID: sourceID,
        frameSequence: frameSequence,
        batchIndex: 0,
        batchCount: 1
      ),
      payload: [UInt8](builder.sizedByteArray)
    )
  }

  /// contentへ壊れた姿勢を渡さないよう、送信前に値域を確認する。
  private func validate(_ frame: StageFrameMessage) throws {
    for tracker in frame.trackers {
      guard !tracker.trackerID.isEmpty else {
        throw PacketEncodeError.payloadEmpty
      }
      guard let pose = tracker.pose else {
        guard tracker.delivery == .blocked else {
          throw StageEncodeError.missingPose(trackerID: tracker.trackerID)
        }
        continue
      }
      guard tracker.delivery != .blocked else {
        throw StageEncodeError.blockedTrackerCarriesPose(
          trackerID: tracker.trackerID
        )
      }
      guard pose.position.isFinite,
        pose.orientation.isFinite,
        pose.linearVelocity?.isFinite ?? true,
        pose.angularVelocity?.isFinite ?? true
      else {
        throw StageEncodeError.nonFiniteValue(trackerID: tracker.trackerID)
      }
      guard pose.orientation.isNormalized else {
        throw StageEncodeError.nonNormalizedQuaternion(
          trackerID: tracker.trackerID
        )
      }
    }
  }

  private func uuid(_ value: UUIDBytes) -> Divive_Protocol__Uuid {
    let words = value.words
    return Divive_Protocol__Uuid(
      word0: words.0,
      word1: words.1,
      word2: words.2,
      word3: words.3
    )
  }

  private func vector(_ value: Vector3) -> Divive_Protocol__Vec3 {
    Divive_Protocol__Vec3(x: value.x, y: value.y, z: value.z)
  }

  private func quaternion(_ value: Quaternion) -> Divive_Protocol__Quaternion {
    Divive_Protocol__Quaternion(x: value.x, y: value.y, z: value.z, w: value.w)
  }

  private func map(_ value: StageDelivery) -> Divive_Stage_Delivery {
    switch value {
    case .unknown: .unknown
    case .stage: .stage
    case .rawTrackerSpace: .rawtrackerspace
    case .blocked: .blocked
    }
  }

  private func map(_ value: StageDeliveryMode) -> Divive_Stage_DeliveryMode {
    switch value {
    case .unknown: .unknown
    case .production: .production
    case .preview: .preview
    }
  }

  private func map(_ value: StageLiveness) -> Divive_Stage_Liveness {
    switch value {
    case .unknown: .unknown
    case .fresh: .fresh
    case .stale: .stale
    case .disconnected: .disconnected
    }
  }

  private func map(_ value: TrackerIDKind) -> Divive_Protocol__TrackerIdKind {
    switch value {
    case .unknown: .unknown
    case .permanent: .permanent
    case .session: .session
    }
  }

  private func map(_ value: TrackingState) -> Divive_Protocol__TrackingState {
    switch value {
    case .unknown: .unknown
    case .tracking: .tracking
    case .lost: .lost
    case .disconnected: .disconnected
    case .simulated: .simulated
    }
  }

  private func map(_ value: TrackingReason) -> Divive_Protocol__TrackingReason {
    switch value {
    case .unknown: .unknown
    case .none: .none_
    case .runtimePoseInvalid: .runtimeposeinvalid
    case .outOfRange: .outofrange
    case .deviceUnplugged: .deviceunplugged
    case .bridgeTimeout: .bridgetimeout
    case .networkStale: .networkstale
    case .simulatedFault: .simulatedfault
    }
  }
}

public enum StageEncodeError: Error, Equatable, Sendable, CustomStringConvertible {
  case missingPose(trackerID: String)
  case blockedTrackerCarriesPose(trackerID: String)
  case nonFiniteValue(trackerID: String)
  case nonNormalizedQuaternion(trackerID: String)

  public var description: String {
    switch self {
    case let .missingPose(trackerID):
      "missing_pose(\(trackerID))"
    case let .blockedTrackerCarriesPose(trackerID):
      "blocked_tracker_carries_pose(\(trackerID))"
    case let .nonFiniteValue(trackerID):
      "non_finite_value(\(trackerID))"
    case let .nonNormalizedQuaternion(trackerID):
      "non_normalized_quaternion(\(trackerID))"
    }
  }
}

/// stage frame datagramをdecodeする。
///
/// Hub自身は自分が送ったframeを読まないが、golden vectorとround trip testで
/// C# SDKと同じ解釈になっていることを確認するために実装する。
public struct StageFrameDecoder: Sendable {
  private let envelopeDecoder = EnvelopeDecoder(
    maximumDatagramSize: StageWireProtocol.maximumDatagramSize
  )

  public init() {}

  public func decode(_ datagram: [UInt8]) throws -> DecodedStageFramePacket {
    let parsed = try envelopeDecoder.decode(datagram)
    guard parsed.envelope.messageType == .stageFrame else {
      throw PacketDecodeError.unexpectedMessageType
    }
    // v1はbatch分割しない。将来LANへ広げるときのためにfieldだけ予約する。
    guard parsed.envelope.batchCount == 1, parsed.envelope.batchIndex == 0 else {
      throw PacketDecodeError.invalidBatch
    }

    var buffer = FlatBuffers.ByteBuffer(bytes: parsed.payload)
    let root: Divive_Stage_StageFrame
    do {
      root = try getCheckedRoot(byteBuffer: &buffer, fileId: "DVST")
    } catch {
      throw PacketDecodeError.flatbufferInvalid
    }

    let trackers = try root.trackers.map(decodeTracker)

    return DecodedStageFramePacket(
      envelope: parsed.envelope,
      frame: StageFrameMessage(
        hubMonotonicNS: root.hubMonotonicNs,
        generation: root.generation,
        profileID: root.profileId ?? "",
        profileRevision: root.profileRevision,
        deliveryMode: map(root.deliveryMode),
        publishRateHz: root.publishRateHz,
        trackers: trackers
      )
    )
  }

  private func decodeTracker(
    _ source: Divive_Stage_StageTracker
  ) throws -> StageTrackerRecord {
    guard let trackerID = source.trackerId, !trackerID.isEmpty else {
      throw PacketDecodeError.emptyTrackerID
    }
    guard let bridgeID = source.bridgeId, let trackingSpaceID = source.trackingSpaceId
    else {
      throw PacketDecodeError.requiredFieldMissing
    }

    let delivery = map(source.delivery)
    let pose: StagePose?
    if delivery == .blocked {
      pose = nil
    } else {
      guard let position = source.position, let orientation = source.orientation else {
        throw PacketDecodeError.requiredFieldMissing
      }
      let decoded = StagePose(
        position: Vector3(x: position.x, y: position.y, z: position.z),
        orientation: Quaternion(
          x: orientation.x,
          y: orientation.y,
          z: orientation.z,
          w: orientation.w
        ),
        linearVelocity: source.linearVelocity.map {
          Vector3(x: $0.x, y: $0.y, z: $0.z)
        },
        angularVelocity: source.angularVelocity.map {
          Vector3(x: $0.x, y: $0.y, z: $0.z)
        }
      )
      guard decoded.position.isFinite,
        decoded.orientation.isFinite,
        decoded.linearVelocity?.isFinite ?? true,
        decoded.angularVelocity?.isFinite ?? true
      else {
        throw PacketDecodeError.nonFiniteValue
      }
      guard decoded.orientation.isNormalized else {
        throw PacketDecodeError.nonNormalizedQuaternion
      }
      pose = decoded
    }

    if let battery = source.battery {
      guard battery.level.isFinite, (0...1).contains(battery.level) else {
        throw PacketDecodeError.invalidBatteryLevel
      }
    }

    return StageTrackerRecord(
      trackerID: trackerID,
      role: source.role ?? "",
      idKind: map(source.idKind),
      bridgeID: UUIDBytes(
        words: (
          bridgeID.word0, bridgeID.word1, bridgeID.word2, bridgeID.word3
        )
      ),
      trackingSpaceID: UUIDBytes(
        words: (
          trackingSpaceID.word0,
          trackingSpaceID.word1,
          trackingSpaceID.word2,
          trackingSpaceID.word3
        )
      ),
      spaceEpoch: source.spaceEpoch,
      delivery: delivery,
      pose: pose,
      trackingState: map(source.trackingState),
      trackingReason: map(source.trackingReason),
      liveness: map(source.liveness),
      connected: source.connected,
      battery: source.battery.map {
        BatteryStatus(level: $0.level, charging: $0.charging)
      },
      receiveAgeNS: source.receiveAgeNs,
      sourceFrameSequence: source.sourceFrameSequence,
      captureMonotonicNS: source.captureMonotonicNs
    )
  }

  private func map(_ value: Divive_Stage_Delivery) -> StageDelivery {
    switch value {
    case .unknown: .unknown
    case .stage: .stage
    case .rawtrackerspace: .rawTrackerSpace
    case .blocked: .blocked
    }
  }

  private func map(_ value: Divive_Stage_DeliveryMode) -> StageDeliveryMode {
    switch value {
    case .unknown: .unknown
    case .production: .production
    case .preview: .preview
    }
  }

  private func map(_ value: Divive_Stage_Liveness) -> StageLiveness {
    switch value {
    case .unknown: .unknown
    case .fresh: .fresh
    case .stale: .stale
    case .disconnected: .disconnected
    }
  }

  private func map(_ value: Divive_Protocol__TrackerIdKind) -> TrackerIDKind {
    switch value {
    case .unknown: .unknown
    case .permanent: .permanent
    case .session: .session
    }
  }

  private func map(_ value: Divive_Protocol__TrackingState) -> TrackingState {
    switch value {
    case .unknown: .unknown
    case .tracking: .tracking
    case .lost: .lost
    case .disconnected: .disconnected
    case .simulated: .simulated
    }
  }

  private func map(_ value: Divive_Protocol__TrackingReason) -> TrackingReason {
    switch value {
    case .unknown: .unknown
    case .none_: .none
    case .runtimeposeinvalid: .runtimePoseInvalid
    case .outofrange: .outOfRange
    case .deviceunplugged: .deviceUnplugged
    case .bridgetimeout: .bridgeTimeout
    case .networkstale: .networkStale
    case .simulatedfault: .simulatedFault
    }
  }
}

/// contentからの購読messageをencode / decodeする。
public struct StageSubscriptionCodec: Sendable {
  private let envelopeEncoder = EnvelopeEncoder(
    maximumDatagramSize: StageWireProtocol.maximumDatagramSize
  )
  private let envelopeDecoder = EnvelopeDecoder(
    maximumDatagramSize: StageWireProtocol.maximumDatagramSize
  )

  public init() {}

  public func encode(
    subscription: StageSubscriptionMessage,
    sessionID: UUIDBytes,
    clientID: UUIDBytes,
    sequence: UInt64
  ) throws -> [UInt8] {
    var builder = FlatBufferBuilder(initialSize: 128)
    let nameOffset = builder.create(
      string: String(subscription.clientName.prefix(
        StageWireProtocol.maximumClientNameLength
      ))
    )
    let root = Divive_Stage_StageSubscription.createStageSubscription(
      &builder,
      clientNameOffset: nameOffset,
      requestedRateHz: subscription.requestedRateHz,
      ttlMs: subscription.ttlMS,
      unsubscribe: subscription.unsubscribe
    )
    Divive_Stage_StageSubscription.finish(&builder, end: root)

    return try envelopeEncoder.encode(
      envelope: PacketEnvelope(
        protocolMinor: WireProtocol.protocolMinor,
        messageType: .stageSubscription,
        flags: 0,
        sessionID: sessionID,
        bridgeID: clientID,
        frameSequence: sequence,
        batchIndex: 0,
        batchCount: 1
      ),
      payload: [UInt8](builder.sizedByteArray)
    )
  }

  public func decode(
    _ datagram: [UInt8]
  ) throws -> DecodedStageSubscriptionPacket {
    let parsed = try envelopeDecoder.decode(datagram)
    guard parsed.envelope.messageType == .stageSubscription else {
      throw PacketDecodeError.unexpectedMessageType
    }
    guard parsed.envelope.batchCount == 1, parsed.envelope.batchIndex == 0 else {
      throw PacketDecodeError.invalidBatch
    }

    var buffer = FlatBuffers.ByteBuffer(bytes: parsed.payload)
    let root: Divive_Stage_StageSubscription
    do {
      root = try getCheckedRoot(byteBuffer: &buffer, fileId: "DVSC")
    } catch {
      throw PacketDecodeError.flatbufferInvalid
    }

    return DecodedStageSubscriptionPacket(
      envelope: parsed.envelope,
      subscription: StageSubscriptionMessage(
        clientName: String(
          (root.clientName ?? "").prefix(
            StageWireProtocol.maximumClientNameLength
          )
        ),
        requestedRateHz: root.requestedRateHz,
        ttlMS: root.ttlMs,
        unsubscribe: root.unsubscribe
      )
    )
  }
}

extension Vector3 {
  fileprivate var isFinite: Bool {
    x.isFinite && y.isFinite && z.isFinite
  }
}

extension Quaternion {
  fileprivate var isFinite: Bool {
    x.isFinite && y.isFinite && z.isFinite && w.isFinite
  }

  fileprivate var isNormalized: Bool {
    let normSquared =
      Double(x) * Double(x)
      + Double(y) * Double(y)
      + Double(z) * Double(z)
      + Double(w) * Double(w)
    return abs(normSquared - 1) <= 1e-3
  }
}
