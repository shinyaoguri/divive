#pragma once

#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace divive::probe {

enum class Origin {
    standing,
    seated,
    raw,
};

enum class DeviceClass {
    invalid,
    hmd,
    controller,
    generic_tracker,
    tracking_reference,
    display_redirect,
    unknown,
};

enum class TrackingResult {
    uninitialized,
    calibrating_in_progress,
    calibrating_out_of_range,
    running_ok,
    running_out_of_range,
    fallback_rotation_only,
    unknown,
};

std::string_view to_string(Origin value) noexcept;
std::string_view to_string(DeviceClass value) noexcept;
std::string_view to_string(TrackingResult value) noexcept;

struct Vector3 {
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
};

struct Quaternion {
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
    double w = 1.0;
};

struct Matrix34 {
    std::array<double, 12> values{};
};

template <typename T> struct PropertyValue {
    std::optional<T> value;
    std::string error;
};

struct DeviceInventory {
    std::uint32_t device_index = 0;
    DeviceClass device_class = DeviceClass::invalid;
    bool connected = false;
    PropertyValue<std::string> serial;
    PropertyValue<std::string> manufacturer;
    PropertyValue<std::string> model;
    PropertyValue<std::string> tracking_system;
    PropertyValue<std::string> firmware;
    PropertyValue<std::string> controller_type;
    PropertyValue<std::string> connected_dongle;
    PropertyValue<bool> wireless;
    PropertyValue<bool> provides_battery;
    PropertyValue<double> battery;
    PropertyValue<bool> charging;
};

struct PoseSample {
    std::uint32_t device_index = 0;
    std::string serial;
    DeviceClass device_class = DeviceClass::invalid;
    bool connected = false;
    bool pose_valid = false;
    TrackingResult tracking_result = TrackingResult::uninitialized;
    Matrix34 matrix;
    Vector3 position;
    Quaternion orientation;
    Vector3 linear_velocity;
    Vector3 angular_velocity;
};

struct PoseFrame {
    std::uint64_t sequence = 0;
    std::uint64_t elapsed_ns = 0;
    std::vector<PoseSample> devices;
};

struct SchedulerInfo {
    std::string backend;
    bool high_resolution = false;
};

struct DeviceStatistics {
    std::uint64_t samples = 0;
    std::uint64_t connected_samples = 0;
    std::uint64_t valid_pose_samples = 0;
    std::uint64_t running_ok_pose_samples = 0;
    std::uint64_t degraded_valid_pose_samples = 0;
    std::uint64_t unique_pose_samples = 0;
    std::uint64_t identical_pose_samples = 0;
    std::map<TrackingResult, std::uint64_t> tracking_result_samples;
    double max_position_step_m = 0.0;
    double max_derived_speed_mps = 0.0;
    double max_speed_mismatch_mps = 0.0;
    std::uint64_t kinematic_discontinuity_samples = 0;
    std::uint64_t kinematic_discontinuity_running_ok_samples = 0;
};

struct ProbeSummary {
    std::uint64_t elapsed_ns = 0;
    std::uint64_t frames = 0;
    std::uint64_t missed_deadlines = 0;
    double effective_rate_hz = 0.0;
    std::uint64_t interval_samples = 0;
    double mean_interval_ms = 0.0;
    double min_interval_ms = 0.0;
    double p50_interval_ms = 0.0;
    double p95_interval_ms = 0.0;
    double p99_interval_ms = 0.0;
    double max_interval_ms = 0.0;
    std::uint64_t wake_lateness_samples = 0;
    double mean_wake_lateness_ms = 0.0;
    double min_wake_lateness_ms = 0.0;
    double p50_wake_lateness_ms = 0.0;
    double p95_wake_lateness_ms = 0.0;
    double p99_wake_lateness_ms = 0.0;
    double max_wake_lateness_ms = 0.0;
    std::map<std::uint32_t, DeviceStatistics> devices;
};

} // namespace divive::probe
