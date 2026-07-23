#include "golden_fixture.hpp"

#include "divive/protocol/envelope.hpp"
#include "divive/protocol/pose_codec.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace {

int failures = 0;

void check(const bool condition, const std::string_view expression,
           const std::string_view test_name) {
    if (condition) {
        return;
    }
    ++failures;
    std::cerr << "FAIL [" << test_name << "]: " << expression << '\n';
}

#define CHECK(test_name, expression)                                                   \
    check(static_cast<bool>(expression), #expression, test_name)

[[nodiscard]] bool near(const float actual, const float expected,
                        const float epsilon = 1.0e-6F) {
    return std::abs(actual - expected) <= epsilon;
}

[[nodiscard]] std::string to_hex(const std::span<const std::byte> bytes) {
    constexpr std::array<char, 16> digits{
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
    };
    std::string result;
    result.reserve(bytes.size() * 2U);
    for (const auto value : bytes) {
        const auto number = std::to_integer<unsigned>(value);
        result.push_back(digits[(number >> 4U) & 0x0FU]);
        result.push_back(digits[number & 0x0FU]);
    }
    return result;
}

[[nodiscard]] std::string read_golden_hex() {
    std::ifstream input(DIVIVE_PROTOCOL_GOLDEN_HEX_PATH);
    if (!input) {
        return {};
    }
    std::string result{
        std::istreambuf_iterator<char>{input},
        std::istreambuf_iterator<char>{},
    };
    result.erase(std::remove_if(result.begin(), result.end(),
                                [](const unsigned char value) {
                                    return std::isspace(value) != 0;
                                }),
                 result.end());
    return result;
}

void test_envelope_round_trip() {
    constexpr std::string_view name = "envelope round trip";
    const auto built = divive::protocol::test::golden_packet();
    CHECK(name, built.pose_error == divive::protocol::PoseCodecError::none);
    CHECK(name, built.packet_error == divive::protocol::PacketError::none);
    CHECK(name, built.packet.size() <= divive::protocol::kMaxDatagramSize);
    if (built.packet.size() < divive::protocol::kEnvelopeSize) {
        return;
    }

    CHECK(name, built.packet[0] == std::byte{'D'});
    CHECK(name, built.packet[1] == std::byte{'V'});
    CHECK(name, built.packet[2] == std::byte{'I'});
    CHECK(name, built.packet[3] == std::byte{'V'});
    CHECK(name, built.packet[4] == std::byte{1});
    CHECK(name, built.packet[5] == std::byte{0});
    CHECK(name, built.packet[6] == std::byte{1});
    CHECK(name, built.packet[7] == std::byte{0});
    CHECK(name, built.packet[8] == std::byte{0});
    CHECK(name, built.packet[9] == std::byte{72});
    CHECK(name, built.packet[14] == std::byte{0});
    CHECK(name, built.packet[15] == std::byte{1});

    constexpr std::array<std::byte, 8> expected_sequence{
        std::byte{1}, std::byte{2}, std::byte{3}, std::byte{4},
        std::byte{5}, std::byte{6}, std::byte{7}, std::byte{8},
    };
    CHECK(name, std::equal(expected_sequence.begin(), expected_sequence.end(),
                           built.packet.begin() + 48));

    const auto parsed = divive::protocol::parse_packet(built.packet);
    CHECK(name, static_cast<bool>(parsed));
    if (!parsed) {
        return;
    }
    CHECK(name, parsed.packet->envelope.frame_sequence == 0x0102030405060708ULL);
    CHECK(name, parsed.packet->envelope.session_id ==
                    divive::protocol::test::incremental_uuid(0x00U));
    CHECK(name, parsed.packet->envelope.bridge_id ==
                    divive::protocol::test::incremental_uuid(0x10U));
    CHECK(name, divive::protocol::verify_pose_payload(parsed.packet->payload));
}

void test_pose_round_trip() {
    constexpr std::string_view name = "pose round trip";
    const auto original = divive::protocol::test::golden_pose_batch();
    const auto encoded = divive::protocol::encode_pose_batch(original);
    CHECK(name, static_cast<bool>(encoded));
    CHECK(name, divive::protocol::verify_pose_payload(encoded.payload));
    if (!encoded) {
        return;
    }

    const auto decoded = divive::protocol::decode_pose_batch(encoded.payload);
    CHECK(name, static_cast<bool>(decoded));
    if (!decoded) {
        return;
    }

    CHECK(name, decoded.batch->tracking_space_id == original.tracking_space_id);
    CHECK(name, decoded.batch->space_epoch == 7U);
    CHECK(name, decoded.batch->capture_monotonic_ns == 123'456'789'000ULL);
    CHECK(name, decoded.batch->send_monotonic_ns == 123'456'789'500ULL);
    CHECK(name, decoded.batch->requested_rate_hz == 120U);
    CHECK(name, decoded.batch->backend == divive::protocol::Backend::openvr);
    CHECK(name, decoded.batch->trackers.size() == 2U);
    if (decoded.batch->trackers.size() != 2U) {
        return;
    }

    const auto& tracking = decoded.batch->trackers[0];
    CHECK(name, tracking.tracker_id == "htc/vive-tracker-3/LHR-ABC12345");
    CHECK(name, tracking.role == "left_foot");
    CHECK(name, tracking.runtime_role == "TrackerRole_LeftFoot");
    CHECK(name, near(tracking.position.x, 1.25F));
    CHECK(name, near(tracking.position.z, -3.75F));
    CHECK(name, tracking.linear_velocity.has_value());
    CHECK(name, tracking.angular_velocity.has_value());
    CHECK(name, tracking.battery.has_value());
    CHECK(name, tracking.battery->charging);
    CHECK(name, near(tracking.battery->level, 0.75F));
    CHECK(name, tracking.tracking_state == divive::protocol::TrackingState::tracking);

    const auto& lost = decoded.batch->trackers[1];
    CHECK(name, !lost.linear_velocity.has_value());
    CHECK(name, !lost.angular_velocity.has_value());
    CHECK(name, !lost.battery.has_value());
    CHECK(name, lost.tracking_state == divive::protocol::TrackingState::lost);
    CHECK(name, lost.tracking_reason ==
                    divive::protocol::TrackingReason::runtime_pose_invalid);
}

void test_envelope_rejection() {
    constexpr std::string_view name = "envelope rejection";
    const auto built = divive::protocol::test::golden_packet();
    CHECK(name, !built.packet.empty());
    if (built.packet.empty()) {
        return;
    }

    CHECK(name, divive::protocol::parse_packet(
                    std::span{built.packet}.first(divive::protocol::kEnvelopeSize - 1U))
                        .error == divive::protocol::PacketError::datagram_too_short);

    auto mutated = built.packet;
    mutated[0] = std::byte{'X'};
    CHECK(name, divive::protocol::parse_packet(mutated).error ==
                    divive::protocol::PacketError::bad_magic);

    mutated = built.packet;
    mutated[4] = std::byte{2};
    CHECK(name, divive::protocol::parse_packet(mutated).error ==
                    divive::protocol::PacketError::unsupported_protocol_major);

    mutated = built.packet;
    mutated[5] = std::byte{99};
    CHECK(name, static_cast<bool>(divive::protocol::parse_packet(mutated)));

    mutated = built.packet;
    mutated[7] = std::byte{2};
    CHECK(name, divive::protocol::parse_packet(mutated).error ==
                    divive::protocol::PacketError::unsupported_flags);

    mutated = built.packet;
    mutated[9] = std::byte{71};
    CHECK(name, divive::protocol::parse_packet(mutated).error ==
                    divive::protocol::PacketError::invalid_header_length);

    mutated = built.packet;
    mutated[10] = std::byte{0};
    mutated[11] = std::byte{1};
    CHECK(name, divive::protocol::parse_packet(mutated).error ==
                    divive::protocol::PacketError::invalid_payload_length);

    mutated = built.packet;
    mutated[13] = std::byte{1};
    CHECK(name, divive::protocol::parse_packet(mutated).error ==
                    divive::protocol::PacketError::invalid_batch);

    mutated = built.packet;
    mutated[6] = std::byte{99};
    CHECK(name, divive::protocol::parse_packet(mutated).error ==
                    divive::protocol::PacketError::unknown_message_type);

    mutated = built.packet;
    std::fill(mutated.begin() + 16, mutated.begin() + 32, std::byte{0});
    CHECK(name, divive::protocol::parse_packet(mutated).error ==
                    divive::protocol::PacketError::nil_session_id);

    mutated = built.packet;
    mutated[56] = std::byte{1};
    CHECK(name, divive::protocol::parse_packet(mutated).error ==
                    divive::protocol::PacketError::unexpected_auth_tag);

    std::vector<std::byte> oversized(divive::protocol::kMaxDatagramSize + 1U);
    CHECK(name, divive::protocol::parse_packet(oversized).error ==
                    divive::protocol::PacketError::datagram_too_large);
}

void test_semantic_rejection() {
    constexpr std::string_view name = "semantic rejection";
    auto batch = divive::protocol::test::golden_pose_batch();
    batch.trackers[0].tracker_id.clear();
    CHECK(name, divive::protocol::encode_pose_batch(batch).error ==
                    divive::protocol::PoseCodecError::empty_tracker_id);

    batch = divive::protocol::test::golden_pose_batch();
    batch.trackers[0].orientation.w = 2.0F;
    CHECK(name, divive::protocol::encode_pose_batch(batch).error ==
                    divive::protocol::PoseCodecError::non_normalized_quaternion);

    batch = divive::protocol::test::golden_pose_batch();
    batch.trackers[0].position.x = std::numeric_limits<float>::quiet_NaN();
    CHECK(name, divive::protocol::encode_pose_batch(batch).error ==
                    divive::protocol::PoseCodecError::non_finite_value);

    batch = divive::protocol::test::golden_pose_batch();
    batch.trackers[0].battery->level = 1.1F;
    CHECK(name, divive::protocol::encode_pose_batch(batch).error ==
                    divive::protocol::PoseCodecError::invalid_battery_level);

    batch = divive::protocol::test::golden_pose_batch();
    batch.send_monotonic_ns = batch.capture_monotonic_ns - 1U;
    CHECK(name, divive::protocol::encode_pose_batch(batch).error ==
                    divive::protocol::PoseCodecError::invalid_time_order);

    const auto encoded = divive::protocol::encode_pose_batch(
        divive::protocol::test::golden_pose_batch());
    CHECK(name, static_cast<bool>(encoded));
    if (encoded.payload.size() > 7U) {
        auto corrupt = encoded.payload;
        corrupt[4] ^= std::byte{1};
        CHECK(name, !divive::protocol::verify_pose_payload(corrupt));
        CHECK(name, divive::protocol::decode_pose_batch(corrupt).error ==
                        divive::protocol::PoseCodecError::flatbuffer_invalid);
    }

    batch = divive::protocol::test::golden_pose_batch();
    batch.backend = static_cast<divive::protocol::Backend>(99);
    batch.trackers[0].tracking_state = static_cast<divive::protocol::TrackingState>(99);
    const auto unknown_encoded = divive::protocol::encode_pose_batch(batch);
    CHECK(name, static_cast<bool>(unknown_encoded));
    const auto unknown_decoded =
        divive::protocol::decode_pose_batch(unknown_encoded.payload);
    CHECK(name, static_cast<bool>(unknown_decoded));
    CHECK(name, unknown_decoded.batch->backend == divive::protocol::Backend::unknown);
    CHECK(name, unknown_decoded.batch->trackers[0].tracking_state ==
                    divive::protocol::TrackingState::unknown);
}

void test_size_budget() {
    constexpr std::string_view name = "size budget";
    const auto envelope = divive::protocol::test::golden_envelope();
    std::vector<std::byte> payload(divive::protocol::kMaxPayloadSize, std::byte{0x5A});
    std::array<std::byte, divive::protocol::kMaxDatagramSize> output{};
    std::size_t written = 0;
    CHECK(name, divive::protocol::encode_packet(envelope, payload, output, written) ==
                    divive::protocol::PacketError::none);
    CHECK(name, written == divive::protocol::kMaxDatagramSize);

    payload.push_back(std::byte{0});
    CHECK(name, divive::protocol::encode_packet(envelope, payload, output, written) ==
                    divive::protocol::PacketError::invalid_payload_length);
}

void test_golden_packet() {
    constexpr std::string_view name = "golden packet";
    const auto built = divive::protocol::test::golden_packet();
    const auto expected = read_golden_hex();
    CHECK(name, !expected.empty());
    CHECK(name, to_hex(built.packet) == expected);
}

} // namespace

int main() {
    test_envelope_round_trip();
    test_pose_round_trip();
    test_envelope_rejection();
    test_semantic_rejection();
    test_size_budget();
    test_golden_packet();

    if (failures == 0) {
        std::cout << "すべてのprotocol testが成功しました。\n";
        return EXIT_SUCCESS;
    }

    std::cerr << failures << "件のtestが失敗しました。\n";
    return EXIT_FAILURE;
}
