public enum WireProtocol {
  public static let protocolMajor: UInt8 = 1
  public static let protocolMinor: UInt8 = 0
  public static let envelopeSize = 72
  public static let maximumDatagramSize = 1_200
  public static let maximumPayloadSize = maximumDatagramSize - envelopeSize
}

public enum MessageType: UInt8, Sendable {
  case poseBatch = 1
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

public struct EnvelopeDecoder: Sendable {
  public init() {}

  public func decode(_ datagram: [UInt8]) throws -> ParsedDatagram {
    guard datagram.count >= WireProtocol.envelopeSize else {
      throw PacketDecodeError.datagramTooShort
    }
    guard datagram.count <= WireProtocol.maximumDatagramSize else {
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
      payloadLength <= WireProtocol.maximumPayloadSize,
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
