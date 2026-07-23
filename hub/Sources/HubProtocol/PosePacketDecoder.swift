import FlatBuffers
import Foundation

public struct DecodedPosePacket: Equatable, Sendable {
  public let envelope: PacketEnvelope
  public let poseBatch: PoseBatch
}

public struct PosePacketDecoder: Sendable {
  private let envelopeDecoder = EnvelopeDecoder()

  public init() {}

  public func decode(_ datagram: [UInt8]) throws -> DecodedPosePacket {
    let parsed = try envelopeDecoder.decode(datagram)
    var buffer = FlatBuffers.ByteBuffer(bytes: parsed.payload)

    let root: Divive_Protocol__PoseBatch
    do {
      root = try getCheckedRoot(byteBuffer: &buffer, fileId: "DVPS")
    } catch {
      throw PacketDecodeError.flatbufferInvalid
    }

    guard let trackingSpace = root.trackingSpaceId else {
      throw PacketDecodeError.requiredFieldMissing
    }

    let trackingSpaceID = UUIDBytes(
      words: (
        trackingSpace.word0,
        trackingSpace.word1,
        trackingSpace.word2,
        trackingSpace.word3
      )
    )

    let trackers = try root.trackers.map(decodeTracker)
    let batch = PoseBatch(
      trackingSpaceID: trackingSpaceID,
      spaceEpoch: root.spaceEpoch,
      captureMonotonicNS: root.captureMonotonicNs,
      sendMonotonicNS: root.sendMonotonicNs,
      requestedRateHz: root.requestedRateHz,
      backend: map(root.backend),
      trackers: trackers
    )
    try validate(batch)

    return DecodedPosePacket(envelope: parsed.envelope, poseBatch: batch)
  }

  private func decodeTracker(_ source: Divive_Protocol__TrackerPose) throws -> TrackerPose {
    guard let trackerID = source.trackerId,
      let position = source.position,
      let orientation = source.orientation
    else {
      throw PacketDecodeError.requiredFieldMissing
    }

    return TrackerPose(
      trackerID: trackerID,
      idKind: map(source.idKind),
      role: source.role ?? "",
      runtimeRole: source.runtimeRole ?? "",
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
      },
      trackingState: map(source.trackingState),
      trackingReason: map(source.trackingReason),
      connected: source.connected,
      battery: source.battery.map {
        BatteryStatus(level: $0.level, charging: $0.charging)
      },
      deviceMetadataRevision: source.deviceMetadataRevision
    )
  }

  private func validate(_ batch: PoseBatch) throws {
    guard !batch.trackingSpaceID.isNil else {
      throw PacketDecodeError.nilTrackingSpaceID
    }
    guard batch.sendMonotonicNS >= batch.captureMonotonicNS else {
      throw PacketDecodeError.invalidTimeOrder
    }
    guard batch.requestedRateHz > 0 else {
      throw PacketDecodeError.invalidRate
    }

    for tracker in batch.trackers {
      guard !tracker.trackerID.isEmpty else {
        throw PacketDecodeError.emptyTrackerID
      }
      guard tracker.position.isFinite,
        tracker.orientation.isFinite,
        tracker.linearVelocity?.isFinite ?? true,
        tracker.angularVelocity?.isFinite ?? true
      else {
        throw PacketDecodeError.nonFiniteValue
      }
      guard tracker.orientation.isNormalized else {
        throw PacketDecodeError.nonNormalizedQuaternion
      }
      if let battery = tracker.battery {
        guard battery.level.isFinite, (0...1).contains(battery.level) else {
          throw PacketDecodeError.invalidBatteryLevel
        }
      }
    }
  }

  private func map(_ value: Divive_Protocol__Backend) -> Backend {
    switch value {
    case .openvr: .openvr
    case .openxr: .openxr
    case .simulator: .simulator
    case .playback: .playback
    case .unknown: .unknown
    }
  }

  private func map(_ value: Divive_Protocol__TrackerIdKind) -> TrackerIDKind {
    switch value {
    case .permanent: .permanent
    case .session: .session
    case .unknown: .unknown
    }
  }

  private func map(_ value: Divive_Protocol__TrackingState) -> TrackingState {
    switch value {
    case .tracking: .tracking
    case .lost: .lost
    case .disconnected: .disconnected
    case .simulated: .simulated
    case .unknown: .unknown
    }
  }

  private func map(_ value: Divive_Protocol__TrackingReason) -> TrackingReason {
    switch value {
    case .none_: .none
    case .runtimeposeinvalid: .runtimePoseInvalid
    case .outofrange: .outOfRange
    case .deviceunplugged: .deviceUnplugged
    case .bridgetimeout: .bridgeTimeout
    case .networkstale: .networkStale
    case .simulatedfault: .simulatedFault
    case .unknown: .unknown
    }
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
