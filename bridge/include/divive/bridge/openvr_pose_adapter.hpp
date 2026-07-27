#pragma once

#include "divive/probe/model.hpp"
#include "divive/protocol/pose_codec.hpp"

#include <cstdint>
#include <span>

namespace divive::bridge {

struct OpenVrPoseAdapterConfig {
    protocol::UuidBytes tracking_space_id{};
    std::uint32_t space_epoch{1};
    std::uint16_t requested_rate_hz{90};
};

/// OpenVRのTracker poseをbackend非依存のcanonical frameへ変換する。
///
/// OpenVRのstanding spaceはcanonicalと同じ右手系、metre、+X右、+Y上、
/// -Z前なので、position/orientation/velocityの軸反転は行わない。
[[nodiscard]] protocol::PoseBatch
make_openvr_pose_batch(const probe::PoseFrame& frame,
                       std::span<const probe::DeviceInventory> inventory,
                       const OpenVrPoseAdapterConfig& config);

} // namespace divive::bridge
