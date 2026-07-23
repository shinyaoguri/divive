#pragma once

#include "divive/protocol/envelope.hpp"
#include "divive/protocol/pose_codec.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace divive::protocol::test {

struct GoldenPacketResult {
    PoseCodecError pose_error{PoseCodecError::none};
    PacketError packet_error{PacketError::none};
    std::vector<std::byte> packet;
};

[[nodiscard]] inline UuidBytes incremental_uuid(const std::uint8_t first) {
    UuidBytes result{};
    for (std::size_t index = 0; index < result.size(); ++index) {
        result[index] =
            static_cast<std::byte>(static_cast<std::uint8_t>(first + index));
    }
    return result;
}

[[nodiscard]] inline PoseBatch golden_pose_batch() {
    PoseBatch batch;
    batch.tracking_space_id = incremental_uuid(0x30U);
    batch.space_epoch = 7;
    batch.capture_monotonic_ns = 123'456'789'000ULL;
    batch.send_monotonic_ns = 123'456'789'500ULL;
    batch.requested_rate_hz = 120;
    batch.backend = Backend::openvr;

    TrackerPose tracking;
    tracking.tracker_id = "htc/vive-tracker-3/LHR-ABC12345";
    tracking.id_kind = TrackerIdKind::permanent;
    tracking.role = "left_foot";
    tracking.runtime_role = "TrackerRole_LeftFoot";
    tracking.position = {.x = 1.25F, .y = 2.5F, .z = -3.75F};
    tracking.orientation = {
        .x = 0.0F,
        .y = 0.70710677F,
        .z = 0.0F,
        .w = 0.70710677F,
    };
    tracking.linear_velocity = Vector3{.x = 0.1F, .y = 0.2F, .z = -0.3F};
    tracking.angular_velocity = Vector3{.x = -0.4F, .y = 0.5F, .z = 0.6F};
    tracking.tracking_state = TrackingState::tracking;
    tracking.tracking_reason = TrackingReason::none;
    tracking.connected = true;
    tracking.battery = BatteryStatus{.level = 0.75F, .charging = true};
    tracking.device_metadata_revision = 11;
    batch.trackers.push_back(tracking);

    TrackerPose lost;
    lost.tracker_id = "session/openvr/5";
    lost.id_kind = TrackerIdKind::session;
    lost.position = {.x = -0.5F, .y = 0.0F, .z = -1.0F};
    lost.orientation = {};
    lost.tracking_state = TrackingState::lost;
    lost.tracking_reason = TrackingReason::runtime_pose_invalid;
    lost.connected = true;
    lost.device_metadata_revision = 2;
    batch.trackers.push_back(lost);
    return batch;
}

[[nodiscard]] inline Envelope golden_envelope() {
    Envelope envelope;
    envelope.session_id = incremental_uuid(0x00U);
    envelope.bridge_id = incremental_uuid(0x10U);
    envelope.frame_sequence = 0x0102030405060708ULL;
    envelope.batch_index = 0;
    envelope.batch_count = 1;
    return envelope;
}

[[nodiscard]] inline GoldenPacketResult golden_packet() {
    const auto encoded_pose = encode_pose_batch(golden_pose_batch());
    if (!encoded_pose) {
        return {.pose_error = encoded_pose.error};
    }

    std::array<std::byte, kMaxDatagramSize> storage{};
    std::size_t written = 0;
    const auto packet_error =
        encode_packet(golden_envelope(), encoded_pose.payload, storage, written);
    if (packet_error != PacketError::none) {
        return {.packet_error = packet_error};
    }

    return {
        .packet = std::vector<std::byte>(
            storage.begin(), storage.begin() + static_cast<std::ptrdiff_t>(written)),
    };
}

} // namespace divive::protocol::test
