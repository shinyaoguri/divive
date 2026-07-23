#pragma once

#include "divive/protocol/envelope.hpp"

#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace divive::protocol {

enum class Backend : std::uint8_t {
    unknown = 0,
    openvr = 1,
    openxr = 2,
    simulator = 3,
    playback = 4,
};

enum class TrackerIdKind : std::uint8_t {
    unknown = 0,
    permanent = 1,
    session = 2,
};

enum class TrackingState : std::uint8_t {
    unknown = 0,
    tracking = 1,
    lost = 2,
    disconnected = 3,
    simulated = 4,
};

enum class TrackingReason : std::uint8_t {
    unknown = 0,
    none = 1,
    runtime_pose_invalid = 2,
    out_of_range = 3,
    device_unplugged = 4,
    bridge_timeout = 5,
    network_stale = 6,
    simulated_fault = 7,
};

struct Vector3 {
    float x{0.0F};
    float y{0.0F};
    float z{0.0F};
};

struct Quaternion {
    float x{0.0F};
    float y{0.0F};
    float z{0.0F};
    float w{1.0F};
};

struct BatteryStatus {
    float level{0.0F};
    bool charging{false};
};

struct TrackerPose {
    std::string tracker_id;
    TrackerIdKind id_kind{TrackerIdKind::unknown};
    std::string role;
    std::string runtime_role;
    Vector3 position;
    Quaternion orientation;
    std::optional<Vector3> linear_velocity;
    std::optional<Vector3> angular_velocity;
    TrackingState tracking_state{TrackingState::unknown};
    TrackingReason tracking_reason{TrackingReason::unknown};
    bool connected{false};
    std::optional<BatteryStatus> battery;
    std::uint32_t device_metadata_revision{0};
};

struct PoseBatch {
    UuidBytes tracking_space_id{};
    std::uint32_t space_epoch{0};
    std::uint64_t capture_monotonic_ns{0};
    std::uint64_t send_monotonic_ns{0};
    std::uint16_t requested_rate_hz{0};
    Backend backend{Backend::unknown};
    std::vector<TrackerPose> trackers;
};

enum class PoseCodecError {
    none,
    nil_tracking_space_id,
    empty_tracker_id,
    non_finite_value,
    non_normalized_quaternion,
    invalid_battery_level,
    invalid_time_order,
    invalid_rate,
    flatbuffer_invalid,
    required_field_missing,
};

struct EncodePoseResult {
    PoseCodecError error{PoseCodecError::none};
    std::vector<std::byte> payload;

    [[nodiscard]] explicit operator bool() const noexcept {
        return error == PoseCodecError::none;
    }
};

struct DecodePoseResult {
    PoseCodecError error{PoseCodecError::none};
    std::optional<PoseBatch> batch;

    [[nodiscard]] explicit operator bool() const noexcept {
        return error == PoseCodecError::none && batch.has_value();
    }
};

[[nodiscard]] EncodePoseResult encode_pose_batch(const PoseBatch& batch);
[[nodiscard]] DecodePoseResult decode_pose_batch(std::span<const std::byte> payload);
[[nodiscard]] bool verify_pose_payload(std::span<const std::byte> payload) noexcept;
[[nodiscard]] std::string_view to_string(PoseCodecError error) noexcept;

} // namespace divive::protocol
