public enum WireProtocol {
  public static let protocolMajor: UInt8 = 1
  public static let protocolMinor: UInt8 = 0
  public static let envelopeSize = 72
  public static let maximumDatagramSize = 1_200
  public static let maximumPayloadSize = maximumDatagramSize - envelopeSize
}

public enum MessageType: UInt8, Sendable {
  /// Bridge → Hub。Tracker Spaceのpose batch。
  case poseBatch = 1
  /// Hub → content。較正とliveness評価を適用したStage Spaceの最新値。
  case stageFrame = 2
  /// content → Hub。配信先を登録・更新する購読。
  case stageSubscription = 3
}

public struct PacketEnvelope: Equatable, Sendable {
  public let protocolMinor: UInt8
  public let messageType: MessageType
  public let flags: UInt8
  public let sessionID: UUIDBytes
  public let bridgeID: UUIDBytes
  public let frameSequence: UInt64
  public let batchIndex: UInt16
  public let batchCount: UInt16

  public init(
    protocolMinor: UInt8,
    messageType: MessageType,
    flags: UInt8,
    sessionID: UUIDBytes,
    bridgeID: UUIDBytes,
    frameSequence: UInt64,
    batchIndex: UInt16,
    batchCount: UInt16
  ) {
    self.protocolMinor = protocolMinor
    self.messageType = messageType
    self.flags = flags
    self.sessionID = sessionID
    self.bridgeID = bridgeID
    self.frameSequence = frameSequence
    self.batchIndex = batchIndex
    self.batchCount = batchCount
  }
}

public struct ParsedDatagram: Equatable, Sendable {
  public let envelope: PacketEnvelope
  public let payload: [UInt8]
}

public enum PacketDecodeError: Error, Equatable, Sendable, CustomStringConvertible {
  case datagramTooShort
  case datagramTooLarge
  case badMagic
  case unsupportedProtocolMajor
  case unsupportedFlags
  case invalidHeaderLength
  case invalidPayloadLength
  case invalidBatch
  case unknownMessageType
  case unexpectedMessageType
  case nilSessionID
  case nilBridgeID
  case unexpectedAuthTag
  case flatbufferInvalid
  case requiredFieldMissing
  case nilTrackingSpaceID
  case emptyTrackerID
  case nonFiniteValue
  case nonNormalizedQuaternion
  case invalidBatteryLevel
  case invalidTimeOrder
  case invalidRate

  public var description: String {
    switch self {
    case .datagramTooShort: "datagram_too_short"
    case .datagramTooLarge: "datagram_too_large"
    case .badMagic: "bad_magic"
    case .unsupportedProtocolMajor: "unsupported_protocol_major"
    case .unsupportedFlags: "unsupported_flags"
    case .invalidHeaderLength: "invalid_header_length"
    case .invalidPayloadLength: "invalid_payload_length"
    case .invalidBatch: "invalid_batch"
    case .unknownMessageType: "unknown_message_type"
    case .unexpectedMessageType: "unexpected_message_type"
    case .nilSessionID: "nil_session_id"
    case .nilBridgeID: "nil_bridge_id"
    case .unexpectedAuthTag: "unexpected_auth_tag"
    case .flatbufferInvalid: "flatbuffer_invalid"
    case .requiredFieldMissing: "required_field_missing"
    case .nilTrackingSpaceID: "nil_tracking_space_id"
    case .emptyTrackerID: "empty_tracker_id"
    case .nonFiniteValue: "non_finite_value"
    case .nonNormalizedQuaternion: "non_normalized_quaternion"
    case .invalidBatteryLevel: "invalid_battery_level"
    case .invalidTimeOrder: "invalid_time_order"
    case .invalidRate: "invalid_rate"
    }
  }
}

public enum PacketEncodeError: Error, Equatable, Sendable, CustomStringConvertible {
  case payloadEmpty
  case payloadTooLarge(actual: Int, limit: Int)
  case nilSessionID
  case nilSourceID
  case invalidBatch

  public var description: String {
    switch self {
    case .payloadEmpty: "payload_empty"
    case let .payloadTooLarge(actual, limit):
      "payload_too_large(actual: \(actual), limit: \(limit))"
    case .nilSessionID: "nil_session_id"
    case .nilSourceID: "nil_source_id"
    case .invalidBatch: "invalid_batch"
    }
  }
}

/// 72-byte envelopeを組み立てる。数値はnetwork byte orderで書く。
///
/// C++ Bridgeと同じlayoutを生成するが、structのmemory layoutは送信しない。
public struct EnvelopeEncoder: Sendable {
  public let maximumDatagramSize: Int

  public init(maximumDatagramSize: Int = WireProtocol.maximumDatagramSize) {
    self.maximumDatagramSize = maximumDatagramSize
  }

  public func encode(
    envelope: PacketEnvelope,
    payload: [UInt8]
  ) throws -> [UInt8] {
    guard !payload.isEmpty else {
      throw PacketEncodeError.payloadEmpty
    }
    let limit = maximumDatagramSize - WireProtocol.envelopeSize
    guard payload.count <= limit else {
      throw PacketEncodeError.payloadTooLarge(actual: payload.count, limit: limit)
    }
    guard !envelope.sessionID.isNil else {
      throw PacketEncodeError.nilSessionID
    }
    guard !envelope.bridgeID.isNil else {
      throw PacketEncodeError.nilSourceID
    }
    guard envelope.batchCount > 0, envelope.batchIndex < envelope.batchCount else {
      throw PacketEncodeError.invalidBatch
    }

    var datagram = [UInt8]()
    datagram.reserveCapacity(WireProtocol.envelopeSize + payload.count)
    datagram.append(contentsOf: [0x44, 0x56, 0x49, 0x56])
    datagram.append(WireProtocol.protocolMajor)
    datagram.append(envelope.protocolMinor)
    datagram.append(envelope.messageType.rawValue)
    datagram.append(envelope.flags)
    append(UInt16(WireProtocol.envelopeSize), to: &datagram)
    append(UInt16(payload.count), to: &datagram)
    append(envelope.batchIndex, to: &datagram)
    append(envelope.batchCount, to: &datagram)
    datagram.append(contentsOf: envelope.sessionID.bytes)
    datagram.append(contentsOf: envelope.bridgeID.bytes)
    append(envelope.frameSequence, to: &datagram)
    // auth tagはHMACを実装するまで全byte 0。decoderも非zeroを拒否する。
    datagram.append(contentsOf: [UInt8](repeating: 0, count: 16))
    datagram.append(contentsOf: payload)
    return datagram
  }

  private func append(_ value: UInt16, to datagram: inout [UInt8]) {
    datagram.append(UInt8((value >> 8) & 0xff))
    datagram.append(UInt8(value & 0xff))
  }

  private func append(_ value: UInt64, to datagram: inout [UInt8]) {
    for shift in stride(from: 56, through: 0, by: -8) {
      datagram.append(UInt8((value >> UInt64(shift)) & 0xff))
    }
  }
}

public struct EnvelopeDecoder: Sendable {
  /// datagram上限はpathごとに異なる。Bridge → HubはIP fragmentationを避けるため
  /// 1,200 byteだが、loopback限定のstage planeはより大きなdatagramを許す。
  public let maximumDatagramSize: Int

  public init(maximumDatagramSize: Int = WireProtocol.maximumDatagramSize) {
    self.maximumDatagramSize = maximumDatagramSize
  }

  public func decode(_ datagram: [UInt8]) throws -> ParsedDatagram {
    guard datagram.count >= WireProtocol.envelopeSize else {
      throw PacketDecodeError.datagramTooShort
    }
    guard datagram.count <= maximumDatagramSize else {
      throw PacketDecodeError.datagramTooLarge
    }
    guard Array(datagram[0..<4]) == [0x44, 0x56, 0x49, 0x56] else {
      throw PacketDecodeError.badMagic
    }
    guard datagram[4] == WireProtocol.protocolMajor else {
      throw PacketDecodeError.unsupportedProtocolMajor
    }

    let headerLength = readUInt16(datagram, at: 8)
    guard headerLength == WireProtocol.envelopeSize else {
      throw PacketDecodeError.invalidHeaderLength
    }
    let payloadLength = Int(readUInt16(datagram, at: 10))
    guard payloadLength > 0,
      payloadLength <= maximumDatagramSize - WireProtocol.envelopeSize,
      datagram.count == Int(headerLength) + payloadLength
    else {
      throw PacketDecodeError.invalidPayloadLength
    }

    guard let messageType = MessageType(rawValue: datagram[6]) else {
      throw PacketDecodeError.unknownMessageType
    }
    let flags = datagram[7]
    guard flags == 0 else {
      throw PacketDecodeError.unsupportedFlags
    }

    let batchIndex = readUInt16(datagram, at: 12)
    let batchCount = readUInt16(datagram, at: 14)
    guard batchCount > 0, batchIndex < batchCount else {
      throw PacketDecodeError.invalidBatch
    }

    let sessionID = try UUIDBytes(bytes: Array(datagram[16..<32]))
    guard !sessionID.isNil else {
      throw PacketDecodeError.nilSessionID
    }
    let bridgeID = try UUIDBytes(bytes: Array(datagram[32..<48]))
    guard !bridgeID.isNil else {
      throw PacketDecodeError.nilBridgeID
    }
    guard datagram[56..<72].allSatisfy({ $0 == 0 }) else {
      throw PacketDecodeError.unexpectedAuthTag
    }

    return ParsedDatagram(
      envelope: PacketEnvelope(
        protocolMinor: datagram[5],
        messageType: messageType,
        flags: flags,
        sessionID: sessionID,
        bridgeID: bridgeID,
        frameSequence: readUInt64(datagram, at: 48),
        batchIndex: batchIndex,
        batchCount: batchCount
      ),
      payload: Array(datagram[WireProtocol.envelopeSize...])
    )
  }

  private func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
    (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
  }

  private func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
    bytes[offset..<(offset + 8)].reduce(UInt64(0)) { value, byte in
      (value << 8) | UInt64(byte)
    }
  }
}
