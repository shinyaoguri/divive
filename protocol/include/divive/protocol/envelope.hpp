#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string_view>

namespace divive::protocol {

using UuidBytes = std::array<std::byte, 16>;
using AuthTag = std::array<std::byte, 16>;

inline constexpr std::array<std::byte, 4> kPacketMagic{
    std::byte{'D'},
    std::byte{'V'},
    std::byte{'I'},
    std::byte{'V'},
};
inline constexpr std::uint8_t kProtocolMajor = 1;
inline constexpr std::uint8_t kProtocolMinor = 0;
inline constexpr std::size_t kEnvelopeSize = 72;
inline constexpr std::size_t kMaxDatagramSize = 1'200;
inline constexpr std::size_t kMaxPayloadSize = kMaxDatagramSize - kEnvelopeSize;

enum class MessageType : std::uint8_t {
    unknown = 0,
    pose_batch = 1,
};

enum class PacketFlag : std::uint8_t {
    authenticated = 1U << 0U,
};

struct Envelope {
    std::uint8_t protocol_minor{kProtocolMinor};
    MessageType message_type{MessageType::pose_batch};
    std::uint8_t flags{0};
    UuidBytes session_id{};
    UuidBytes bridge_id{};
    std::uint64_t frame_sequence{0};
    std::uint16_t batch_index{0};
    std::uint16_t batch_count{1};
    AuthTag auth_tag{};
};

enum class PacketError {
    none,
    output_too_small,
    datagram_too_short,
    datagram_too_large,
    bad_magic,
    unsupported_protocol_major,
    unsupported_flags,
    invalid_header_length,
    invalid_payload_length,
    invalid_batch,
    unknown_message_type,
    nil_session_id,
    nil_bridge_id,
    unexpected_auth_tag,
};

struct ParsedPacket {
    Envelope envelope;
    std::span<const std::byte> payload;
};

struct ParsePacketResult {
    PacketError error{PacketError::none};
    std::optional<ParsedPacket> packet;

    [[nodiscard]] explicit operator bool() const noexcept {
        return error == PacketError::none && packet.has_value();
    }
};

[[nodiscard]] PacketError encode_packet(const Envelope& envelope,
                                        std::span<const std::byte> payload,
                                        std::span<std::byte> output,
                                        std::size_t& written) noexcept;

[[nodiscard]] ParsePacketResult
parse_packet(std::span<const std::byte> datagram) noexcept;

[[nodiscard]] bool is_nil_uuid(const UuidBytes& uuid) noexcept;
[[nodiscard]] std::string_view to_string(PacketError error) noexcept;

} // namespace divive::protocol
