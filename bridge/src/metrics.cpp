#include "divive/probe/metrics.hpp"

#include "divive/probe/pose_math.hpp"

#include <algorithm>
#include <cmath>

namespace divive::probe {
namespace {

double vector_length(const Vector3& value) {
    return std::sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
}

double position_distance(const Vector3& first, const Vector3& second) {
    return vector_length(Vector3{
        .x = second.x - first.x,
        .y = second.y - first.y,
        .z = second.z - first.z,
    });
}

double nanoseconds_to_milliseconds(const long double value) {
    constexpr long double nanoseconds_per_millisecond = 1'000'000.0L;
    return static_cast<double>(value / nanoseconds_per_millisecond);
}

} // namespace

void ProbeMetrics::BoundedSamples::observe(const std::uint64_t value) {
    const std::uint64_t observation_index = observations_++;
    if (observation_index % stride_ != 0) {
        return;
    }

    if (values_.size() >= kMaximumSamples) {
        std::size_t destination = 0;
        for (std::size_t source = 0; source < values_.size(); source += 2) {
            values_[destination++] = values_[source];
        }
        values_.resize(destination);
        stride_ *= 2;

        if (observation_index % stride_ != 0) {
            return;
        }
    }

    values_.push_back(value);
}

double ProbeMetrics::BoundedSamples::quantile(const double probability) const {
    if (values_.empty()) {
        return 0.0;
    }

    auto sorted = values_;
    std::sort(sorted.begin(), sorted.end());

    const double bounded_probability = std::clamp(probability, 0.0, 1.0);
    const auto rank = static_cast<std::size_t>(
        std::ceil(bounded_probability * static_cast<double>(sorted.size())));
    const auto index = rank == 0 ? std::size_t{0} : rank - 1;
    return static_cast<double>(sorted[std::min(index, sorted.size() - 1)]);
}

void ProbeMetrics::observe(const PoseFrame& frame) {
    ++frames_;
    if (!first_frame_elapsed_ns_) {
        first_frame_elapsed_ns_ = frame.elapsed_ns;
    }

    if (last_frame_elapsed_ns_ && frame.elapsed_ns >= *last_frame_elapsed_ns_) {
        const auto interval = frame.elapsed_ns - *last_frame_elapsed_ns_;
        interval_sum_ns_ += static_cast<long double>(interval);
        ++interval_count_;
        interval_samples_.observe(interval);
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
        ++statistics.tracking_result_samples[sample.tracking_result];
        if (!sample.pose_valid) {
            continue;
        }

        ++statistics.valid_pose_samples;
        if (sample.tracking_result == TrackingResult::running_ok) {
            ++statistics.running_ok_pose_samples;
        } else {
            ++statistics.degraded_valid_pose_samples;
        }

        if (state.previous_valid_sample &&
            frame.elapsed_ns > state.previous_valid_sample->elapsed_ns) {
            const auto elapsed =
                frame.elapsed_ns - state.previous_valid_sample->elapsed_ns;
            const double elapsed_seconds =
                static_cast<double>(elapsed) / 1'000'000'000.0;
            const double distance =
                position_distance(state.previous_valid_sample->position,
                                  sample.position);
            const double derived_speed = distance / elapsed_seconds;
            const double reported_speed =
                std::max(vector_length(state.previous_valid_sample->linear_velocity),
                         vector_length(sample.linear_velocity));
            const double speed_mismatch =
                std::max(0.0, derived_speed - reported_speed);

            statistics.max_position_step_m =
                std::max(statistics.max_position_step_m, distance);
            statistics.max_derived_speed_mps =
                std::max(statistics.max_derived_speed_mps, derived_speed);
            statistics.max_speed_mismatch_mps =
                std::max(statistics.max_speed_mismatch_mps, speed_mismatch);

            if (distance >= kDiscontinuityMinimumStepM &&
                derived_speed >= kDiscontinuityMinimumDerivedSpeedMps &&
                speed_mismatch >= kDiscontinuityMinimumSpeedMismatchMps) {
                ++statistics.kinematic_discontinuity_samples;
                if (state.previous_valid_sample->tracking_result ==
                        TrackingResult::running_ok &&
                    sample.tracking_result == TrackingResult::running_ok) {
                    ++statistics.kinematic_discontinuity_running_ok_samples;
                }
            }
        }

        if (!state.last_valid_pose ||
            !same_pose(*state.last_valid_pose, sample.matrix)) {
            ++statistics.unique_pose_samples;
            state.last_valid_pose = sample.matrix;
        } else {
            ++statistics.identical_pose_samples;
        }

        state.previous_valid_sample = PreviousValidSample{
            .position = sample.position,
            .linear_velocity = sample.linear_velocity,
            .tracking_result = sample.tracking_result,
            .elapsed_ns = frame.elapsed_ns,
        };
    }
}

void ProbeMetrics::observe_wake_lateness(const std::uint64_t lateness_ns) {
    ++wake_lateness_count_;
    wake_lateness_sum_ns_ += static_cast<long double>(lateness_ns);
    wake_lateness_samples_.observe(lateness_ns);

    if (wake_lateness_count_ == 1) {
        min_wake_lateness_ns_ = lateness_ns;
        max_wake_lateness_ns_ = lateness_ns;
    } else {
        min_wake_lateness_ns_ = std::min(min_wake_lateness_ns_, lateness_ns);
        max_wake_lateness_ns_ = std::max(max_wake_lateness_ns_, lateness_ns);
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
    if (frames_ > 1 && first_frame_elapsed_ns_ && last_frame_elapsed_ns_ &&
        *last_frame_elapsed_ns_ > *first_frame_elapsed_ns_) {
        const auto sampled_span =
            *last_frame_elapsed_ns_ - *first_frame_elapsed_ns_;
        result.effective_rate_hz =
            static_cast<double>(frames_ - 1) * 1'000'000'000.0 /
            static_cast<double>(sampled_span);
    }

    if (interval_count_ > 0) {
        result.interval_samples = interval_count_;
        result.mean_interval_ms = nanoseconds_to_milliseconds(
            interval_sum_ns_ / static_cast<long double>(interval_count_));
        result.min_interval_ms = nanoseconds_to_milliseconds(
            static_cast<long double>(min_interval_ns_));
        result.p50_interval_ms =
            nanoseconds_to_milliseconds(interval_samples_.quantile(0.50));
        result.p95_interval_ms =
            nanoseconds_to_milliseconds(interval_samples_.quantile(0.95));
        result.p99_interval_ms =
            nanoseconds_to_milliseconds(interval_samples_.quantile(0.99));
        result.max_interval_ms = nanoseconds_to_milliseconds(
            static_cast<long double>(max_interval_ns_));
    }

    if (wake_lateness_count_ > 0) {
        result.wake_lateness_samples = wake_lateness_count_;
        result.mean_wake_lateness_ms = nanoseconds_to_milliseconds(
            wake_lateness_sum_ns_ /
            static_cast<long double>(wake_lateness_count_));
        result.min_wake_lateness_ms = nanoseconds_to_milliseconds(
            static_cast<long double>(min_wake_lateness_ns_));
        result.p50_wake_lateness_ms =
            nanoseconds_to_milliseconds(wake_lateness_samples_.quantile(0.50));
        result.p95_wake_lateness_ms =
            nanoseconds_to_milliseconds(wake_lateness_samples_.quantile(0.95));
        result.p99_wake_lateness_ms =
            nanoseconds_to_milliseconds(wake_lateness_samples_.quantile(0.99));
        result.max_wake_lateness_ms = nanoseconds_to_milliseconds(
            static_cast<long double>(max_wake_lateness_ns_));
    }

    for (const auto& [device_index, state] : devices_) {
        result.devices.emplace(device_index, state.statistics);
    }
    return result;
}

} // namespace divive::probe
