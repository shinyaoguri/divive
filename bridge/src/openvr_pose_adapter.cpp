#include "divive/bridge/openvr_pose_adapter.hpp"

#include <cmath>
#include <cstdint>
#include <string>

namespace divive::bridge {
namespace {

[[nodiscard]] const probe::DeviceInventory*
find_inventory(const std::span<const probe::DeviceInventory> inventory,
               const std::uint32_t device_index) noexcept {
    for (const auto& device : inventory) {
        if (device.device_index == device_index) {
            return &device;
        }
    }
    return nullptr;
}

void set_identity(protocol::TrackerPose& destination, const probe::PoseSample& source) {
    if (!source.serial.empty()) {
        destination.tracker_id = "openvr/serial/" + source.serial;
        destination.id_kind = protocol::TrackerIdKind::permanent;
        return;
    }

    destination.tracker_id =
        "openvr/session/device-" + std::to_string(source.device_index);
    destination.id_kind = protocol::TrackerIdKind::session;
}

void set_tracking_state(protocol::TrackerPose& destination,
                        const probe::PoseSample& source) noexcept {
    destination.connected = source.connected;
    if (!source.connected) {
        destination.tracking_state = protocol::TrackingState::disconnected;
        destination.tracking_reason = protocol::TrackingReason::device_unplugged;
        return;
    }
    if (source.pose_valid &&
        source.tracking_result == probe::TrackingResult::running_ok) {
        destination.tracking_state = protocol::TrackingState::tracking;
        destination.tracking_reason = protocol::TrackingReason::none;
        return;
    }

    destination.tracking_state = protocol::TrackingState::lost;
    if (source.tracking_result == probe::TrackingResult::calibrating_out_of_range ||
        source.tracking_result == probe::TrackingResult::running_out_of_range) {
        destination.tracking_reason = protocol::TrackingReason::out_of_range;
    } else {
        destination.tracking_reason = protocol::TrackingReason::runtime_pose_invalid;
    }
}

void set_inventory_metadata(protocol::TrackerPose& destination,
                            const probe::DeviceInventory* const inventory) {
    if (inventory == nullptr) {
        return;
    }
    const auto battery = inventory->battery.value;
    if (!inventory->provides_battery.value.value_or(false) || !battery ||
        !std::isfinite(*battery) || *battery < 0.0 || *battery > 1.0) {
        return;
    }
    destination.battery = protocol::BatteryStatus{
        .level = static_cast<float>(*battery),
        .charging = inventory->charging.value.value_or(false),
    };
}

} // namespace

protocol::PoseBatch
make_openvr_pose_batch(const probe::PoseFrame& frame,
                       const std::span<const probe::DeviceInventory> inventory,
                       const OpenVrPoseAdapterConfig& config) {
    protocol::PoseBatch result;
    result.tracking_space_id = config.tracking_space_id;
    result.space_epoch = config.space_epoch;
    result.capture_monotonic_ns = frame.elapsed_ns;
    // PoseSenderが実送信時刻で上書きする。単体encode時にも時刻順を満たす初期値。
    result.send_monotonic_ns = frame.elapsed_ns;
    result.requested_rate_hz = config.requested_rate_hz;
    result.backend = protocol::Backend::openvr;
    result.trackers.reserve(frame.devices.size());

    for (const auto& source : frame.devices) {
        if (source.device_class != probe::DeviceClass::generic_tracker) {
            continue;
        }

        protocol::TrackerPose destination;
        set_identity(destination, source);
        destination.position = {
            .x = static_cast<float>(source.position.x),
            .y = static_cast<float>(source.position.y),
            .z = static_cast<float>(source.position.z),
        };
        destination.orientation = {
            .x = static_cast<float>(source.orientation.x),
            .y = static_cast<float>(source.orientation.y),
            .z = static_cast<float>(source.orientation.z),
            .w = static_cast<float>(source.orientation.w),
        };
        destination.linear_velocity = protocol::Vector3{
            .x = static_cast<float>(source.linear_velocity.x),
            .y = static_cast<float>(source.linear_velocity.y),
            .z = static_cast<float>(source.linear_velocity.z),
        };
        destination.angular_velocity = protocol::Vector3{
            .x = static_cast<float>(source.angular_velocity.x),
            .y = static_cast<float>(source.angular_velocity.y),
            .z = static_cast<float>(source.angular_velocity.z),
        };
        set_tracking_state(destination, source);
        set_inventory_metadata(destination,
                               find_inventory(inventory, source.device_index));
        result.trackers.push_back(std::move(destination));
    }
    return result;
}

} // namespace divive::bridge
