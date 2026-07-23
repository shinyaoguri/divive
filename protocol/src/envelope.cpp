#include "divive/protocol/envelope.hpp"

#include <algorithm>

namespace divive::protocol {
namespace {

constexpr std::size_t kMagicOffset = 0;
constexpr std::size_t kMajorOffset = 4;
constexpr std::size_t kMinorOffset = 5;
constexpr std::size_t kMessageTypeOffset = 6;
constexpr std::size_t kFlagsOffset = 7;
constexpr std::size_t kHeaderLengthOffset = 8;
constexpr std::size_t kPayloadLengthOffset = 10;
constexpr std::size_t kBatchIndexOffset = 12;
constexpr std::size_t kBatchCountOffset = 14;
constexpr std::size_t kSessionIdOffset = 16;
constexpr std::size_t kBridgeIdOffset = 32;
constexpr std::size_t kFrameSequenceOffset = 48;
constexpr std::size_t kAuthTagOffset = 56;
constexpr std::uint8_t kKnownFlags =
    static_cast<std::uint8_t>(PacketFlag::authenticated);

void write_u16(const std::span<std::byte> output, const std::size_t offset,
               const std::uint16_t value) noexcept {
    output[offset] = static_cast<std::byte>((value >> 8U) & 0xFFU);
    output[offset + 1] = static_cast<std::byte>(value & 0xFFU);
}

void write_u64(const std::span<std::byte> output, const std::size_t offset,
               const std::uint64_t value) noexcept {
    for (std::size_t index = 0; index < sizeof(value); ++index) {
        const auto shift = static_cast<unsigned>((sizeof(value) - index - 1U) * 8U);
        output[offset + index] = static_cast<std::byte>((value >> shift) & 0xFFU);
    }
}

[[nodiscard]] std::uint16_t read_u16(const std::span<const std::byte> input,
                                     const std::size_t offset) noexcept {
    return static_cast<std::uint16_t>(
        (std::to_integer<std::uint16_t>(input[offset]) << 8U) |
        std::to_integer<std::uint16_t>(input[offset + 1]));
}

[[nodiscard]] std::uint64_t read_u64(const std::span<const std::byte> input,
                                     const std::size_t offset) noexcept {
    std::uint64_t value = 0;
    for (std::size_t index = 0; index < sizeof(value); ++index) {
        value = (value << 8U) | std::to_integer<std::uint64_t>(input[offset + index]);
    }
    return value;
}

[[nodiscard]] bool is_zero(const std::span<const std::byte> bytes) noexcept {
    return std::all_of(bytes.begin(), bytes.end(),
                       [](const std::byte value) { return value == std::byte{0}; });
}

[[nodiscard]] PacketError validate_envelope(const Envelope& envelope) noexcept {
    if (envelope.message_type != MessageType::pose_batch) {
        return PacketError::unknown_message_type;
    }
    if ((envelope.flags & static_cast<std::uint8_t>(~kKnownFlags)) != 0U ||
        (envelope.flags & static_cast<std::uint8_t>(PacketFlag::authenticated)) != 0U) {
        return PacketError::unsupported_flags;
    }
    if (envelope.batch_count == 0U || envelope.batch_index >= envelope.batch_count) {
        return PacketError::invalid_batch;
    }
    if (is_nil_uuid(envelope.session_id)) {
        return PacketError::nil_session_id;
    }
    if (is_nil_uuid(envelope.bridge_id)) {
        return PacketError::nil_bridge_id;
    }
    if (!is_zero(envelope.auth_tag)) {
        return PacketError::unexpected_auth_tag;
    }
    return PacketError::none;
}

} // namespace

PacketError encode_packet(const Envelope& envelope,
                          const std::span<const std::byte> payload,
                          const std::span<std::byte> output,
                          std::size_t& written) noexcept {
    written = 0;
    const auto envelope_error = validate_envelope(envelope);
    if (envelope_error != PacketError::none) {
        return envelope_error;
    }
    if (payload.empty() || payload.size() > kMaxPayloadSize) {
        return PacketError::invalid_payload_length;
    }
    const auto packet_size = kEnvelopeSize + payload.size();
    if (packet_size > kMaxDatagramSize) {
        return PacketError::datagram_too_large;
    }
    if (output.size() < packet_size) {
        return PacketError::output_too_small;
    }

    std::fill_n(output.begin(), static_cast<std::ptrdiff_t>(packet_size), std::byte{0});
    std::copy(kPacketMagic.begin(), kPacketMagic.end(),
              output.begin() + static_cast<std::ptrdiff_t>(kMagicOffset));
    output[kMajorOffset] = static_cast<std::byte>(kProtocolMajor);
    output[kMinorOffset] = static_cast<std::byte>(envelope.protocol_minor);
    output[kMessageTypeOffset] = static_cast<std::byte>(envelope.message_type);
    output[kFlagsOffset] = static_cast<std::byte>(envelope.flags);
    write_u16(output, kHeaderLengthOffset, static_cast<std::uint16_t>(kEnvelopeSize));
    write_u16(output, kPayloadLengthOffset, static_cast<std::uint16_t>(payload.size()));
    write_u16(output, kBatchIndexOffset, envelope.batch_index);
    write_u16(output, kBatchCountOffset, envelope.batch_count);
    std::copy(envelope.session_id.begin(), envelope.session_id.end(),
              output.begin() + static_cast<std::ptrdiff_t>(kSessionIdOffset));
    std::copy(envelope.bridge_id.begin(), envelope.bridge_id.end(),
              output.begin() + static_cast<std::ptrdiff_t>(kBridgeIdOffset));
    write_u64(output, kFrameSequenceOffset, envelope.frame_sequence);
    std::copy(envelope.auth_tag.begin(), envelope.auth_tag.end(),
              output.begin() + static_cast<std::ptrdiff_t>(kAuthTagOffset));
    std::copy(payload.begin(), payload.end(),
              output.begin() + static_cast<std::ptrdiff_t>(kEnvelopeSize));
    written = packet_size;
    return PacketError::none;
}

ParsePacketResult parse_packet(const std::span<const std::byte> datagram) noexcept {
    if (datagram.size() < kEnvelopeSize) {
        return {.error = PacketError::datagram_too_short};
    }
    if (datagram.size() > kMaxDatagramSize) {
        return {.error = PacketError::datagram_too_large};
    }
    if (!std::equal(kPacketMagic.begin(), kPacketMagic.end(),
                    datagram.begin() + static_cast<std::ptrdiff_t>(kMagicOffset))) {
        return {.error = PacketError::bad_magic};
    }
    if (std::to_integer<std::uint8_t>(datagram[kMajorOffset]) != kProtocolMajor) {
        return {.error = PacketError::unsupported_protocol_major};
    }

    const auto header_length = read_u16(datagram, kHeaderLengthOffset);
    if (header_length != kEnvelopeSize) {
        return {.error = PacketError::invalid_header_length};
    }
    const auto payload_length = read_u16(datagram, kPayloadLengthOffset);
    if (payload_length == 0U ||
        static_cast<std::size_t>(payload_length) > kMaxPayloadSize ||
        datagram.size() != static_cast<std::size_t>(header_length) + payload_length) {
        return {.error = PacketError::invalid_payload_length};
    }

    Envelope envelope;
    envelope.protocol_minor = std::to_integer<std::uint8_t>(datagram[kMinorOffset]);
    envelope.message_type = static_cast<MessageType>(
        std::to_integer<std::uint8_t>(datagram[kMessageTypeOffset]));
    envelope.flags = std::to_integer<std::uint8_t>(datagram[kFlagsOffset]);
    envelope.batch_index = read_u16(datagram, kBatchIndexOffset);
    envelope.batch_count = read_u16(datagram, kBatchCountOffset);
    std::copy_n(datagram.begin() + static_cast<std::ptrdiff_t>(kSessionIdOffset),
                static_cast<std::ptrdiff_t>(envelope.session_id.size()),
                envelope.session_id.begin());
    std::copy_n(datagram.begin() + static_cast<std::ptrdiff_t>(kBridgeIdOffset),
                static_cast<std::ptrdiff_t>(envelope.bridge_id.size()),
                envelope.bridge_id.begin());
    envelope.frame_sequence = read_u64(datagram, kFrameSequenceOffset);
    std::copy_n(datagram.begin() + static_cast<std::ptrdiff_t>(kAuthTagOffset),
                static_cast<std::ptrdiff_t>(envelope.auth_tag.size()),
                envelope.auth_tag.begin());

    const auto envelope_error = validate_envelope(envelope);
    if (envelope_error != PacketError::none) {
        return {.error = envelope_error};
    }

    return {
        .error = PacketError::none,
        .packet =
            ParsedPacket{
                .envelope = envelope,
                .payload = datagram.subspan(kEnvelopeSize, payload_length),
            },
    };
}

bool is_nil_uuid(const UuidBytes& uuid) noexcept {
    return is_zero(uuid);
}

std::string_view to_string(const PacketError error) noexcept {
    switch (error) {
    case PacketError::none:
        return "none";
    case PacketError::output_too_small:
        return "output_too_small";
    case PacketError::datagram_too_short:
        return "datagram_too_short";
    case PacketError::datagram_too_large:
        return "datagram_too_large";
    case PacketError::bad_magic:
        return "bad_magic";
    case PacketError::unsupported_protocol_major:
        return "unsupported_protocol_major";
    case PacketError::unsupported_flags:
        return "unsupported_flags";
    case PacketError::invalid_header_length:
        return "invalid_header_length";
    case PacketError::invalid_payload_length:
        return "invalid_payload_length";
    case PacketError::invalid_batch:
        return "invalid_batch";
    case PacketError::unknown_message_type:
        return "unknown_message_type";
    case PacketError::nil_session_id:
        return "nil_session_id";
    case PacketError::nil_bridge_id:
        return "nil_bridge_id";
    case PacketError::unexpected_auth_tag:
        return "unexpected_auth_tag";
    }
    return "unknown";
}

} // namespace divive::protocol
