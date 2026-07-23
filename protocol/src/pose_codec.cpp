#include "divive/protocol/pose_codec.hpp"

#include "pose_generated.h"

#include <cmath>
#include <cstring>
#include <utility>

#include <flatbuffers/flatbuffers.h>
#include <flatbuffers/verifier.h>

namespace divive::protocol {
namespace {

[[nodiscard]] std::uint32_t read_word(const UuidBytes& bytes,
                                      const std::size_t offset) noexcept {
    return (std::to_integer<std::uint32_t>(bytes[offset]) << 24U) |
           (std::to_integer<std::uint32_t>(bytes[offset + 1]) << 16U) |
           (std::to_integer<std::uint32_t>(bytes[offset + 2]) << 8U) |
           std::to_integer<std::uint32_t>(bytes[offset + 3]);
}

void write_word(UuidBytes& bytes, const std::size_t offset,
                const std::uint32_t value) noexcept {
    bytes[offset] = static_cast<std::byte>((value >> 24U) & 0xFFU);
    bytes[offset + 1] = static_cast<std::byte>((value >> 16U) & 0xFFU);
    bytes[offset + 2] = static_cast<std::byte>((value >> 8U) & 0xFFU);
    bytes[offset + 3] = static_cast<std::byte>(value & 0xFFU);
}

[[nodiscard]] Divive::Protocol::Uuid to_generated(const UuidBytes& value) {
    return {
        read_word(value, 0),
        read_word(value, 4),
        read_word(value, 8),
        read_word(value, 12),
    };
}

[[nodiscard]] UuidBytes from_generated(const Divive::Protocol::Uuid& value) {
    UuidBytes bytes{};
    write_word(bytes, 0, value.word0());
    write_word(bytes, 4, value.word1());
    write_word(bytes, 8, value.word2());
    write_word(bytes, 12, value.word3());
    return bytes;
}

[[nodiscard]] Divive::Protocol::Vec3 to_generated(const Vector3& value) {
    return {value.x, value.y, value.z};
}

[[nodiscard]] Vector3 from_generated(const Divive::Protocol::Vec3& value) {
    return {.x = value.x(), .y = value.y(), .z = value.z()};
}

[[nodiscard]] Divive::Protocol::Quaternion to_generated(const Quaternion& value) {
    return {value.x, value.y, value.z, value.w};
}

[[nodiscard]] Quaternion from_generated(const Divive::Protocol::Quaternion& value) {
    return {
        .x = value.x(),
        .y = value.y(),
        .z = value.z(),
        .w = value.w(),
    };
}

[[nodiscard]] bool finite(const Vector3& value) noexcept {
    return std::isfinite(value.x) && std::isfinite(value.y) && std::isfinite(value.z);
}

[[nodiscard]] bool finite(const Quaternion& value) noexcept {
    return std::isfinite(value.x) && std::isfinite(value.y) && std::isfinite(value.z) &&
           std::isfinite(value.w);
}

[[nodiscard]] bool normalized(const Quaternion& value) noexcept {
    const auto norm_squared =
        static_cast<double>(value.x) * static_cast<double>(value.x) +
        static_cast<double>(value.y) * static_cast<double>(value.y) +
        static_cast<double>(value.z) * static_cast<double>(value.z) +
        static_cast<double>(value.w) * static_cast<double>(value.w);
    return std::abs(norm_squared - 1.0) <= 1.0e-3;
}

[[nodiscard]] PoseCodecError validate(const PoseBatch& batch) noexcept {
    if (is_nil_uuid(batch.tracking_space_id)) {
        return PoseCodecError::nil_tracking_space_id;
    }
    if (batch.send_monotonic_ns < batch.capture_monotonic_ns) {
        return PoseCodecError::invalid_time_order;
    }
    if (batch.requested_rate_hz == 0U) {
        return PoseCodecError::invalid_rate;
    }
    for (const auto& tracker : batch.trackers) {
        if (tracker.tracker_id.empty()) {
            return PoseCodecError::empty_tracker_id;
        }
        if (!finite(tracker.position) || !finite(tracker.orientation) ||
            (tracker.linear_velocity.has_value() &&
             !finite(*tracker.linear_velocity)) ||
            (tracker.angular_velocity.has_value() &&
             !finite(*tracker.angular_velocity))) {
            return PoseCodecError::non_finite_value;
        }
        if (!normalized(tracker.orientation)) {
            return PoseCodecError::non_normalized_quaternion;
        }
        if (tracker.battery.has_value() &&
            (!std::isfinite(tracker.battery->level) || tracker.battery->level < 0.0F ||
             tracker.battery->level > 1.0F)) {
            return PoseCodecError::invalid_battery_level;
        }
    }
    return PoseCodecError::none;
}

[[nodiscard]] Divive::Protocol::Backend to_generated(const Backend value) {
    return static_cast<Divive::Protocol::Backend>(static_cast<std::uint8_t>(value));
}

[[nodiscard]] Divive::Protocol::TrackerIdKind to_generated(const TrackerIdKind value) {
    return static_cast<Divive::Protocol::TrackerIdKind>(
        static_cast<std::uint8_t>(value));
}

[[nodiscard]] Divive::Protocol::TrackingState to_generated(const TrackingState value) {
    return static_cast<Divive::Protocol::TrackingState>(
        static_cast<std::uint8_t>(value));
}

[[nodiscard]] Divive::Protocol::TrackingReason
to_generated(const TrackingReason value) {
    return static_cast<Divive::Protocol::TrackingReason>(
        static_cast<std::uint8_t>(value));
}

[[nodiscard]] Backend from_generated(const Divive::Protocol::Backend value) {
    switch (value) {
    case Divive::Protocol::Backend::OpenVR:
        return Backend::openvr;
    case Divive::Protocol::Backend::OpenXR:
        return Backend::openxr;
    case Divive::Protocol::Backend::Simulator:
        return Backend::simulator;
    case Divive::Protocol::Backend::Playback:
        return Backend::playback;
    case Divive::Protocol::Backend::Unknown:
        return Backend::unknown;
    }
    return Backend::unknown;
}

[[nodiscard]] TrackerIdKind
from_generated(const Divive::Protocol::TrackerIdKind value) {
    switch (value) {
    case Divive::Protocol::TrackerIdKind::Permanent:
        return TrackerIdKind::permanent;
    case Divive::Protocol::TrackerIdKind::Session:
        return TrackerIdKind::session;
    case Divive::Protocol::TrackerIdKind::Unknown:
        return TrackerIdKind::unknown;
    }
    return TrackerIdKind::unknown;
}

[[nodiscard]] TrackingState
from_generated(const Divive::Protocol::TrackingState value) {
    switch (value) {
    case Divive::Protocol::TrackingState::Tracking:
        return TrackingState::tracking;
    case Divive::Protocol::TrackingState::Lost:
        return TrackingState::lost;
    case Divive::Protocol::TrackingState::Disconnected:
        return TrackingState::disconnected;
    case Divive::Protocol::TrackingState::Simulated:
        return TrackingState::simulated;
    case Divive::Protocol::TrackingState::Unknown:
        return TrackingState::unknown;
    }
    return TrackingState::unknown;
}

[[nodiscard]] TrackingReason
from_generated(const Divive::Protocol::TrackingReason value) {
    switch (value) {
    case Divive::Protocol::TrackingReason::None:
        return TrackingReason::none;
    case Divive::Protocol::TrackingReason::RuntimePoseInvalid:
        return TrackingReason::runtime_pose_invalid;
    case Divive::Protocol::TrackingReason::OutOfRange:
        return TrackingReason::out_of_range;
    case Divive::Protocol::TrackingReason::DeviceUnplugged:
        return TrackingReason::device_unplugged;
    case Divive::Protocol::TrackingReason::BridgeTimeout:
        return TrackingReason::bridge_timeout;
    case Divive::Protocol::TrackingReason::NetworkStale:
        return TrackingReason::network_stale;
    case Divive::Protocol::TrackingReason::SimulatedFault:
        return TrackingReason::simulated_fault;
    case Divive::Protocol::TrackingReason::Unknown:
        return TrackingReason::unknown;
    }
    return TrackingReason::unknown;
}

[[nodiscard]] flatbuffers::Offset<flatbuffers::String>
optional_string(flatbuffers::FlatBufferBuilder& builder, const std::string& value) {
    if (value.empty()) {
        return {};
    }
    return builder.CreateString(value);
}

} // namespace

EncodePoseResult encode_pose_batch(const PoseBatch& batch) {
    const auto error = validate(batch);
    if (error != PoseCodecError::none) {
        return {.error = error};
    }

    flatbuffers::FlatBufferBuilder builder(1'024);
    std::vector<flatbuffers::Offset<Divive::Protocol::TrackerPose>> tracker_offsets;
    tracker_offsets.reserve(batch.trackers.size());

    for (const auto& tracker : batch.trackers) {
        const auto tracker_id = builder.CreateString(tracker.tracker_id);
        const auto role = optional_string(builder, tracker.role);
        const auto runtime_role = optional_string(builder, tracker.runtime_role);
        const auto position = to_generated(tracker.position);
        const auto orientation = to_generated(tracker.orientation);
        const auto linear_velocity =
            tracker.linear_velocity.has_value()
                ? std::optional{to_generated(*tracker.linear_velocity)}
                : std::nullopt;
        const auto angular_velocity =
            tracker.angular_velocity.has_value()
                ? std::optional{to_generated(*tracker.angular_velocity)}
                : std::nullopt;
        const auto battery = tracker.battery.has_value()
                                 ? std::optional{Divive::Protocol::BatteryStatus{
                                       tracker.battery->level,
                                       tracker.battery->charging,
                                   }}
                                 : std::nullopt;

        tracker_offsets.push_back(Divive::Protocol::CreateTrackerPose(
            builder, tracker_id, to_generated(tracker.id_kind), role, runtime_role,
            &position, &orientation,
            linear_velocity.has_value() ? &*linear_velocity : nullptr,
            angular_velocity.has_value() ? &*angular_velocity : nullptr,
            to_generated(tracker.tracking_state), to_generated(tracker.tracking_reason),
            tracker.connected, battery.has_value() ? &*battery : nullptr,
            tracker.device_metadata_revision));
    }

    const auto trackers = builder.CreateVector(tracker_offsets);
    const auto tracking_space_id = to_generated(batch.tracking_space_id);
    const auto pose_batch = Divive::Protocol::CreatePoseBatch(
        builder, &tracking_space_id, batch.space_epoch, batch.capture_monotonic_ns,
        batch.send_monotonic_ns, batch.requested_rate_hz, to_generated(batch.backend),
        trackers);
    Divive::Protocol::FinishPoseBatchBuffer(builder, pose_batch);

    std::vector<std::byte> payload(builder.GetSize());
    std::memcpy(payload.data(), builder.GetBufferPointer(), builder.GetSize());
    return {
        .error = PoseCodecError::none,
        .payload = std::move(payload),
    };
}

DecodePoseResult decode_pose_batch(const std::span<const std::byte> payload) {
    if (!verify_pose_payload(payload)) {
        return {.error = PoseCodecError::flatbuffer_invalid};
    }

    const auto* root = Divive::Protocol::GetPoseBatch(
        reinterpret_cast<const std::uint8_t*>(payload.data()));
    if (root == nullptr || root->tracking_space_id() == nullptr) {
        return {.error = PoseCodecError::required_field_missing};
    }

    PoseBatch batch;
    batch.tracking_space_id = from_generated(*root->tracking_space_id());
    batch.space_epoch = root->space_epoch();
    batch.capture_monotonic_ns = root->capture_monotonic_ns();
    batch.send_monotonic_ns = root->send_monotonic_ns();
    batch.requested_rate_hz = root->requested_rate_hz();
    batch.backend = from_generated(root->backend());

    if (const auto* trackers = root->trackers(); trackers != nullptr) {
        batch.trackers.reserve(trackers->size());
        for (const auto* source : *trackers) {
            if (source == nullptr || source->tracker_id() == nullptr ||
                source->position() == nullptr || source->orientation() == nullptr) {
                return {.error = PoseCodecError::required_field_missing};
            }

            TrackerPose tracker;
            tracker.tracker_id = source->tracker_id()->str();
            tracker.id_kind = from_generated(source->id_kind());
            if (source->role() != nullptr) {
                tracker.role = source->role()->str();
            }
            if (source->runtime_role() != nullptr) {
                tracker.runtime_role = source->runtime_role()->str();
            }
            tracker.position = from_generated(*source->position());
            tracker.orientation = from_generated(*source->orientation());
            if (source->linear_velocity() != nullptr) {
                tracker.linear_velocity = from_generated(*source->linear_velocity());
            }
            if (source->angular_velocity() != nullptr) {
                tracker.angular_velocity = from_generated(*source->angular_velocity());
            }
            tracker.tracking_state = from_generated(source->tracking_state());
            tracker.tracking_reason = from_generated(source->tracking_reason());
            tracker.connected = source->connected();
            if (source->battery() != nullptr) {
                tracker.battery = BatteryStatus{
                    .level = source->battery()->level(),
                    .charging = source->battery()->charging(),
                };
            }
            tracker.device_metadata_revision = source->device_metadata_revision();
            batch.trackers.push_back(std::move(tracker));
        }
    }

    const auto error = validate(batch);
    if (error != PoseCodecError::none) {
        return {.error = error};
    }
    return {
        .error = PoseCodecError::none,
        .batch = std::move(batch),
    };
}

bool verify_pose_payload(const std::span<const std::byte> payload) noexcept {
    if (payload.empty()) {
        return false;
    }
    flatbuffers::Verifier verifier(
        reinterpret_cast<const std::uint8_t*>(payload.data()), payload.size());
    return Divive::Protocol::VerifyPoseBatchBuffer(verifier);
}

std::string_view to_string(const PoseCodecError error) noexcept {
    switch (error) {
    case PoseCodecError::none:
        return "none";
    case PoseCodecError::nil_tracking_space_id:
        return "nil_tracking_space_id";
    case PoseCodecError::empty_tracker_id:
        return "empty_tracker_id";
    case PoseCodecError::non_finite_value:
        return "non_finite_value";
    case PoseCodecError::non_normalized_quaternion:
        return "non_normalized_quaternion";
    case PoseCodecError::invalid_battery_level:
        return "invalid_battery_level";
    case PoseCodecError::invalid_time_order:
        return "invalid_time_order";
    case PoseCodecError::invalid_rate:
        return "invalid_rate";
    case PoseCodecError::flatbuffer_invalid:
        return "flatbuffer_invalid";
    case PoseCodecError::required_field_missing:
        return "required_field_missing";
    }
    return "unknown";
}

} // namespace divive::protocol
