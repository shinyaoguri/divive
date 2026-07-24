#include "divive/probe/json.hpp"
#include "divive/probe/metrics.hpp"
#include "divive/probe/options.hpp"
#include "divive/probe/pose_math.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
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

bool near(const double actual, const double expected, const double epsilon = 1.0e-9) {
    return std::abs(actual - expected) <= epsilon;
}

void test_default_options() {
    constexpr std::string_view name = "default options";
    const auto parsed = divive::probe::parse_options(std::vector<std::string_view>{});

    CHECK(name, parsed.options.has_value());
    CHECK(name, !parsed.show_help);
    CHECK(name, parsed.error.empty());
    CHECK(name, near(parsed.options->rate_hz, 120.0));
    CHECK(name, near(parsed.options->duration_seconds, 30.0));
    CHECK(name, parsed.options->origin == divive::probe::Origin::standing);
    CHECK(name, !parsed.options->trackers_only);
    CHECK(name, parsed.options->output == "-");
}

void test_custom_options() {
    constexpr std::string_view name = "custom options";
    const std::vector<std::string_view> arguments{
        "--rate",
        "90",
        "--duration",
        "0",
        "--prediction-seconds",
        "0.011",
        "--inventory-interval",
        "5",
        "--origin",
        "raw",
        "--trackers-only",
        "--output",
        "probe.jsonl",
    };
    const auto parsed = divive::probe::parse_options(arguments);

    CHECK(name, parsed.options.has_value());
    CHECK(name, near(parsed.options->rate_hz, 90.0));
    CHECK(name, near(parsed.options->duration_seconds, 0.0));
    CHECK(name, near(parsed.options->prediction_seconds, 0.011));
    CHECK(name, near(parsed.options->inventory_interval_seconds, 5.0));
    CHECK(name, parsed.options->origin == divive::probe::Origin::raw);
    CHECK(name, parsed.options->trackers_only);
    CHECK(name, parsed.options->output == "probe.jsonl");
}

void test_invalid_options() {
    constexpr std::string_view name = "invalid options";
    const auto invalid_rate =
        divive::probe::parse_options(std::vector<std::string_view>{"--rate", "0"});
    CHECK(name, !invalid_rate.options.has_value());
    CHECK(name, !invalid_rate.error.empty());

    const auto unknown = divive::probe::parse_options(
        std::vector<std::string_view>{"--unknown", "value"});
    CHECK(name, !unknown.options.has_value());
    CHECK(name, !unknown.error.empty());
}

void test_pose_math() {
    constexpr std::string_view name = "pose math";
    divive::probe::Matrix34 matrix{
        .values =
            {
                0.0,
                -1.0,
                0.0,
                1.25,
                1.0,
                0.0,
                0.0,
                2.5,
                0.0,
                0.0,
                1.0,
                -3.75,
            },
    };

    const auto position = divive::probe::position_from_matrix(matrix);
    CHECK(name, near(position.x, 1.25));
    CHECK(name, near(position.y, 2.5));
    CHECK(name, near(position.z, -3.75));

    const auto orientation = divive::probe::quaternion_from_matrix(matrix);
    const double half_sqrt_two = std::sqrt(0.5);
    CHECK(name, near(orientation.x, 0.0));
    CHECK(name, near(orientation.y, 0.0));
    CHECK(name, near(std::abs(orientation.z), half_sqrt_two));
    CHECK(name, near(std::abs(orientation.w), half_sqrt_two));
}

void test_metrics() {
    constexpr std::string_view name = "metrics";
    divive::probe::ProbeMetrics metrics;

    divive::probe::PoseSample sample;
    sample.device_index = 3;
    sample.connected = true;
    sample.pose_valid = true;
    sample.tracking_result = divive::probe::TrackingResult::running_ok;
    sample.matrix.values[0] = 1.0;

    divive::probe::PoseFrame first{
        .sequence = 0,
        .elapsed_ns = 0,
        .devices = {sample},
    };
    metrics.observe(first);
    metrics.observe_wake_lateness(1'000'000);

    sample.tracking_result =
        divive::probe::TrackingResult::calibrating_out_of_range;
    divive::probe::PoseFrame second{
        .sequence = 1,
        .elapsed_ns = 10'000'000,
        .devices = {sample},
    };
    metrics.observe(second);
    metrics.observe_wake_lateness(2'000'000);

    sample.tracking_result = divive::probe::TrackingResult::running_ok;
    divive::probe::PoseFrame third{
        .sequence = 2,
        .elapsed_ns = 20'000'000,
        .devices = {sample},
    };
    metrics.observe(third);
    metrics.observe_wake_lateness(3'000'000);

    sample.position.x = 0.2;
    sample.matrix.values[3] = 0.2;
    divive::probe::PoseFrame fourth{
        .sequence = 3,
        .elapsed_ns = 30'000'000,
        .devices = {sample},
    };
    metrics.observe(fourth);
    metrics.observe_wake_lateness(4'000'000);
    metrics.add_missed_deadlines(2);

    const auto summary = metrics.summary(30'000'000);
    CHECK(name, summary.frames == 4);
    CHECK(name, summary.missed_deadlines == 2);
    CHECK(name, near(summary.effective_rate_hz, 100.0));
    CHECK(name, summary.interval_samples == 3);
    CHECK(name, near(summary.mean_interval_ms, 10.0));
    CHECK(name, near(summary.min_interval_ms, 10.0));
    CHECK(name, near(summary.p50_interval_ms, 10.0));
    CHECK(name, near(summary.p95_interval_ms, 10.0));
    CHECK(name, near(summary.p99_interval_ms, 10.0));
    CHECK(name, near(summary.max_interval_ms, 10.0));
    CHECK(name, summary.wake_lateness_samples == 4);
    CHECK(name, near(summary.mean_wake_lateness_ms, 2.5));
    CHECK(name, near(summary.min_wake_lateness_ms, 1.0));
    CHECK(name, near(summary.p50_wake_lateness_ms, 2.0));
    CHECK(name, near(summary.p95_wake_lateness_ms, 4.0));
    CHECK(name, near(summary.p99_wake_lateness_ms, 4.0));
    CHECK(name, near(summary.max_wake_lateness_ms, 4.0));

    const auto& device = summary.devices.at(3);
    CHECK(name, device.samples == 4);
    CHECK(name, device.connected_samples == 4);
    CHECK(name, device.valid_pose_samples == 4);
    CHECK(name, device.running_ok_pose_samples == 3);
    CHECK(name, device.degraded_valid_pose_samples == 1);
    CHECK(name, device.unique_pose_samples == 2);
    CHECK(name, device.identical_pose_samples == 2);
    CHECK(name, device.tracking_result_samples.at(
                    divive::probe::TrackingResult::running_ok) == 3);
    CHECK(name, device.tracking_result_samples.at(
                    divive::probe::TrackingResult::calibrating_out_of_range) == 1);
    CHECK(name, near(device.max_position_step_m, 0.2));
    CHECK(name, near(device.max_derived_speed_mps, 20.0));
    CHECK(name, near(device.max_speed_mismatch_mps, 20.0));
    CHECK(name, device.kinematic_discontinuity_samples == 1);
    CHECK(name, device.kinematic_discontinuity_running_ok_samples == 1);
}

void test_json() {
    constexpr std::string_view name = "json";
    CHECK(name, divive::probe::json_escape("a\"b\\c\n") == "a\\\"b\\\\c\\n");

    const auto error =
        divive::probe::serialize_error("openvr_init", "runtime \"not ready\"", 42);
    CHECK(name, error == "{\"schema\":\"divive.openvr_probe/1\","
                         "\"type\":\"error\",\"elapsed_ns\":42,"
                         "\"code\":\"openvr_init\","
                         "\"message\":\"runtime \\\"not ready\\\"\"}");

    const auto start = divive::probe::serialize_probe_start(
        "2026-07-24T00:00:00Z", "2.15.6", "C:\\SteamVR",
        divive::probe::Options{},
        divive::probe::SchedulerInfo{
            .backend = "windows_high_resolution_waitable_timer",
            .high_resolution = true,
        });
    CHECK(name, start.find("\"scheduler\":{"
                           "\"backend\":\"windows_high_resolution_waitable_timer\","
                           "\"high_resolution\":true}") != std::string::npos);

    divive::probe::ProbeMetrics metrics;
    divive::probe::PoseSample sample;
    sample.device_index = 1;
    sample.connected = true;
    sample.pose_valid = true;
    sample.tracking_result = divive::probe::TrackingResult::running_ok;
    metrics.observe(divive::probe::PoseFrame{
        .sequence = 0,
        .elapsed_ns = 1,
        .devices = {sample},
    });
    const auto summary = divive::probe::serialize_summary(metrics.summary(1));
    CHECK(name, summary.find("\"effective_rate_hz\":0") != std::string::npos);
    CHECK(name, summary.find("\"tracking_result_samples\":{\"running_ok\":1}") !=
                    std::string::npos);
    CHECK(name, summary.find("\"diagnostic_thresholds\":{") != std::string::npos);
    CHECK(name, summary.find("\"position_step_m\":0.10000000000000001") !=
                    std::string::npos);
    CHECK(name, summary.find("\"derived_speed_mps\":10") != std::string::npos);
    CHECK(name, summary.find("\"speed_mismatch_mps\":5") != std::string::npos);
}

} // namespace

int main() {
    test_default_options();
    test_custom_options();
    test_invalid_options();
    test_pose_math();
    test_metrics();
    test_json();

    if (failures == 0) {
        std::cout << "すべてのprobe core testが成功しました。\n";
        return EXIT_SUCCESS;
    }

    std::cerr << failures << "件のtestが失敗しました。\n";
    return EXIT_FAILURE;
}
