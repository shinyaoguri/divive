#include "divive/probe/metrics.hpp"

#include "divive/probe/pose_math.hpp"

#include <algorithm>
#include <limits>

namespace divive::probe {

void ProbeMetrics::observe(const PoseFrame& frame) {
    ++frames_;

    if (last_frame_elapsed_ns_ && frame.elapsed_ns >= *last_frame_elapsed_ns_) {
        const auto interval = frame.elapsed_ns - *last_frame_elapsed_ns_;
        interval_sum_ns_ += static_cast<long double>(interval);
        ++interval_count_;
        if (interval_count_ == 1) {
            min_interval_ns_ = interval;
            max_interval_ns_ = interval;
        } else {
            min_interval_ns_ = std::min(min_interval_ns_, interval);
            max_interval_ns_ = std::max(max_interval_ns_, interval);
        }
    }
    last_frame_elapsed_ns_ = frame.elapsed_ns;

    for (const auto& sample : frame.devices) {
        auto& state = devices_[sample.device_index];
        auto& statistics = state.statistics;
        ++statistics.samples;
        if (sample.connected) {
            ++statistics.connected_samples;
        }
        if (!sample.pose_valid) {
            continue;
        }

        ++statistics.valid_pose_samples;
        if (!state.last_valid_pose ||
            !same_pose(*state.last_valid_pose, sample.matrix)) {
            ++statistics.unique_pose_samples;
            state.last_valid_pose = sample.matrix;
        } else {
            ++statistics.identical_pose_samples;
        }
    }
}

void ProbeMetrics::add_missed_deadlines(const std::uint64_t count) noexcept {
    missed_deadlines_ += count;
}

ProbeSummary ProbeMetrics::summary(const std::uint64_t elapsed_ns) const {
    ProbeSummary result;
    result.elapsed_ns = elapsed_ns;
    result.frames = frames_;
    result.missed_deadlines = missed_deadlines_;

    if (interval_count_ > 0) {
        constexpr long double nanoseconds_per_millisecond = 1'000'000.0L;
        result.mean_interval_ms = static_cast<double>(
            interval_sum_ns_ / static_cast<long double>(interval_count_) /
            nanoseconds_per_millisecond);
        result.min_interval_ms = static_cast<double>(
            static_cast<long double>(min_interval_ns_) / nanoseconds_per_millisecond);
        result.max_interval_ms = static_cast<double>(
            static_cast<long double>(max_interval_ns_) / nanoseconds_per_millisecond);
    }

    for (const auto& [device_index, state] : devices_) {
        result.devices.emplace(device_index, state.statistics);
    }
    return result;
}

} // namespace divive::probe
