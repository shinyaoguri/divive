#include "divive/probe/json.hpp"

#include "divive/probe/metrics.hpp"

#include <cmath>
#include <iomanip>
#include <locale>
#include <sstream>
#include <type_traits>

namespace divive::probe {
namespace {

std::ostringstream json_stream() {
    std::ostringstream output;
    output.imbue(std::locale::classic());
    output << std::setprecision(17);
    return output;
}

void append_string(std::ostringstream& output, const std::string_view value) {
    output << '"' << json_escape(value) << '"';
}

void append_bool(std::ostringstream& output, const bool value) {
    output << (value ? "true" : "false");
}

void append_number(std::ostringstream& output, const double value) {
    if (std::isfinite(value)) {
        output << value;
    } else {
        output << "null";
    }
}

void append_vector3(std::ostringstream& output, const Vector3& value) {
    output << '[';
    append_number(output, value.x);
    output << ',';
    append_number(output, value.y);
    output << ',';
    append_number(output, value.z);
    output << ']';
}

void append_quaternion(std::ostringstream& output, const Quaternion& value) {
    output << '[';
    append_number(output, value.x);
    output << ',';
    append_number(output, value.y);
    output << ',';
    append_number(output, value.z);
    output << ',';
    append_number(output, value.w);
    output << ']';
}

void append_matrix(std::ostringstream& output, const Matrix34& value) {
    output << '[';
    for (std::size_t index = 0; index < value.values.size(); ++index) {
        if (index > 0) {
            output << ',';
        }
        append_number(output, value.values[index]);
    }
    output << ']';
}

template <typename T>
void append_property(std::ostringstream& output, const PropertyValue<T>& property) {
    output << "{\"available\":";
    append_bool(output, property.value.has_value());
    output << ",\"value\":";
    if (!property.value) {
        output << "null";
    } else if constexpr (std::is_same_v<T, std::string>) {
        append_string(output, *property.value);
    } else if constexpr (std::is_same_v<T, bool>) {
        append_bool(output, *property.value);
    } else {
        append_number(output, static_cast<double>(*property.value));
    }
    output << ",\"error\":";
    append_string(output, property.error);
    output << '}';
}

void append_inventory_device(std::ostringstream& output,
                             const DeviceInventory& device) {
    output << "{\"device_index\":" << device.device_index;
    output << ",\"device_class\":";
    append_string(output, to_string(device.device_class));
    output << ",\"connected\":";
    append_bool(output, device.connected);
    output << ",\"properties\":{";

    output << "\"serial\":";
    append_property(output, device.serial);
    output << ",\"manufacturer\":";
    append_property(output, device.manufacturer);
    output << ",\"model\":";
    append_property(output, device.model);
    output << ",\"tracking_system\":";
    append_property(output, device.tracking_system);
    output << ",\"firmware\":";
    append_property(output, device.firmware);
    output << ",\"controller_type\":";
    append_property(output, device.controller_type);
    output << ",\"connected_dongle\":";
    append_property(output, device.connected_dongle);
    output << ",\"wireless\":";
    append_property(output, device.wireless);
    output << ",\"provides_battery\":";
    append_property(output, device.provides_battery);
    output << ",\"battery\":";
    append_property(output, device.battery);
    output << ",\"charging\":";
    append_property(output, device.charging);
    output << "}}";
}

void append_pose_sample(std::ostringstream& output, const PoseSample& sample) {
    output << "{\"device_index\":" << sample.device_index;
    output << ",\"serial\":";
    append_string(output, sample.serial);
    output << ",\"device_class\":";
    append_string(output, to_string(sample.device_class));
    output << ",\"connected\":";
    append_bool(output, sample.connected);
    output << ",\"pose_valid\":";
    append_bool(output, sample.pose_valid);
    output << ",\"tracking_result\":";
    append_string(output, to_string(sample.tracking_result));
    output << ",\"position\":";
    append_vector3(output, sample.position);
    output << ",\"orientation_xyzw\":";
    append_quaternion(output, sample.orientation);
    output << ",\"linear_velocity_mps\":";
    append_vector3(output, sample.linear_velocity);
    output << ",\"angular_velocity_radps\":";
    append_vector3(output, sample.angular_velocity);
    output << ",\"matrix_3x4_row_major\":";
    append_matrix(output, sample.matrix);
    output << '}';
}

} // namespace

std::string json_escape(const std::string_view value) {
    constexpr char hex[] = "0123456789abcdef";
    std::string result;
    result.reserve(value.size());

    for (const char character : value) {
        const auto byte = static_cast<unsigned char>(character);
        switch (character) {
        case '"':
            result += "\\\"";
            break;
        case '\\':
            result += "\\\\";
            break;
        case '\b':
            result += "\\b";
            break;
        case '\f':
            result += "\\f";
            break;
        case '\n':
            result += "\\n";
            break;
        case '\r':
            result += "\\r";
            break;
        case '\t':
            result += "\\t";
            break;
        default:
            if (byte < 0x20U) {
                result += "\\u00";
                result += hex[(byte >> 4U) & 0x0FU];
                result += hex[byte & 0x0FU];
            } else {
                result += character;
            }
            break;
        }
    }
    return result;
}

std::string serialize_probe_start(const std::string_view wall_time_utc,
                                  const std::string_view sdk_version,
                                  const std::string_view runtime_path,
                                  const Options& options,
                                  const SchedulerInfo& scheduler) {
    auto output = json_stream();
    output << "{\"schema\":\"divive.openvr_probe/1\","
              "\"type\":\"probe_start\",\"wall_time_utc\":";
    append_string(output, wall_time_utc);
    output << ",\"sdk_version\":";
    append_string(output, sdk_version);
    output << ",\"runtime_path\":";
    append_string(output, runtime_path);
    output << ",\"options\":{";
    output << "\"rate_hz\":";
    append_number(output, options.rate_hz);
    output << ",\"duration_seconds\":";
    append_number(output, options.duration_seconds);
    output << ",\"prediction_seconds\":";
    append_number(output, options.prediction_seconds);
    output << ",\"inventory_interval_seconds\":";
    append_number(output, options.inventory_interval_seconds);
    output << ",\"origin\":";
    append_string(output, to_string(options.origin));
    output << ",\"trackers_only\":";
    append_bool(output, options.trackers_only);
    output << "},\"scheduler\":{\"backend\":";
    append_string(output, scheduler.backend);
    output << ",\"high_resolution\":";
    append_bool(output, scheduler.high_resolution);
    output << "}}";
    return output.str();
}

std::string serialize_inventory(const std::uint64_t elapsed_ns,
                                const std::vector<DeviceInventory>& devices) {
    auto output = json_stream();
    output << "{\"schema\":\"divive.openvr_probe/1\","
              "\"type\":\"device_inventory\",\"elapsed_ns\":"
           << elapsed_ns << ",\"devices\":[";
    for (std::size_t index = 0; index < devices.size(); ++index) {
        if (index > 0) {
            output << ',';
        }
        append_inventory_device(output, devices[index]);
    }
    output << "]}";
    return output.str();
}

std::string serialize_pose_frame(const PoseFrame& frame) {
    auto output = json_stream();
    output << "{\"schema\":\"divive.openvr_probe/1\","
              "\"type\":\"pose_frame\",\"sequence\":"
           << frame.sequence << ",\"elapsed_ns\":" << frame.elapsed_ns
           << ",\"devices\":[";
    for (std::size_t index = 0; index < frame.devices.size(); ++index) {
        if (index > 0) {
            output << ',';
        }
        append_pose_sample(output, frame.devices[index]);
    }
    output << "]}";
    return output.str();
}

std::string serialize_summary(const ProbeSummary& summary) {
    auto output = json_stream();
    output << "{\"schema\":\"divive.openvr_probe/1\","
              "\"type\":\"probe_summary\",\"elapsed_ns\":"
           << summary.elapsed_ns << ",\"frames\":" << summary.frames
           << ",\"missed_deadlines\":" << summary.missed_deadlines
           << ",\"effective_rate_hz\":";
    append_number(output, summary.effective_rate_hz);
    output << ",\"interval_ms\":{\"samples\":" << summary.interval_samples
           << ",\"mean\":";
    append_number(output, summary.mean_interval_ms);
    output << ",\"min\":";
    append_number(output, summary.min_interval_ms);
    output << ",\"p50\":";
    append_number(output, summary.p50_interval_ms);
    output << ",\"p95\":";
    append_number(output, summary.p95_interval_ms);
    output << ",\"p99\":";
    append_number(output, summary.p99_interval_ms);
    output << ",\"max\":";
    append_number(output, summary.max_interval_ms);
    output << "},\"wake_lateness_ms\":{\"samples\":"
           << summary.wake_lateness_samples << ",\"mean\":";
    append_number(output, summary.mean_wake_lateness_ms);
    output << ",\"min\":";
    append_number(output, summary.min_wake_lateness_ms);
    output << ",\"p50\":";
    append_number(output, summary.p50_wake_lateness_ms);
    output << ",\"p95\":";
    append_number(output, summary.p95_wake_lateness_ms);
    output << ",\"p99\":";
    append_number(output, summary.p99_wake_lateness_ms);
    output << ",\"max\":";
    append_number(output, summary.max_wake_lateness_ms);
    output << "},\"diagnostic_thresholds\":{"
              "\"position_step_m\":";
    append_number(output, ProbeMetrics::kDiscontinuityMinimumStepM);
    output << ",\"derived_speed_mps\":";
    append_number(output, ProbeMetrics::kDiscontinuityMinimumDerivedSpeedMps);
    output << ",\"speed_mismatch_mps\":";
    append_number(output, ProbeMetrics::kDiscontinuityMinimumSpeedMismatchMps);
    output << "},\"devices\":[";

    std::size_t index = 0;
    for (const auto& [device_index, statistics] : summary.devices) {
        if (index++ > 0) {
            output << ',';
        }
        output << "{\"device_index\":" << device_index
               << ",\"samples\":" << statistics.samples
               << ",\"connected_samples\":" << statistics.connected_samples
               << ",\"valid_pose_samples\":" << statistics.valid_pose_samples
               << ",\"running_ok_pose_samples\":"
               << statistics.running_ok_pose_samples
               << ",\"degraded_valid_pose_samples\":"
               << statistics.degraded_valid_pose_samples
               << ",\"unique_pose_samples\":" << statistics.unique_pose_samples
               << ",\"identical_pose_samples\":" << statistics.identical_pose_samples
               << ",\"tracking_result_samples\":{";

        std::size_t tracking_result_index = 0;
        for (const auto& [tracking_result, samples] :
             statistics.tracking_result_samples) {
            if (tracking_result_index++ > 0) {
                output << ',';
            }
            append_string(output, to_string(tracking_result));
            output << ':' << samples;
        }

        output << "},\"max_position_step_m\":";
        append_number(output, statistics.max_position_step_m);
        output << ",\"max_derived_speed_mps\":";
        append_number(output, statistics.max_derived_speed_mps);
        output << ",\"max_speed_mismatch_mps\":";
        append_number(output, statistics.max_speed_mismatch_mps);
        output << ",\"kinematic_discontinuity_samples\":"
               << statistics.kinematic_discontinuity_samples
               << ",\"kinematic_discontinuity_running_ok_samples\":"
               << statistics.kinematic_discontinuity_running_ok_samples << '}';
    }
    output << "]}";
    return output.str();
}

std::string serialize_error(const std::string_view code, const std::string_view message,
                            const std::uint64_t elapsed_ns) {
    auto output = json_stream();
    output << "{\"schema\":\"divive.openvr_probe/1\","
              "\"type\":\"error\",\"elapsed_ns\":"
           << elapsed_ns << ",\"code\":";
    append_string(output, code);
    output << ",\"message\":";
    append_string(output, message);
    output << '}';
    return output.str();
}

} // namespace divive::probe
