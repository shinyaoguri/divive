#pragma once

#include "divive/probe/model.hpp"

#include <cstddef>
#include <cstdint>
#include <map>
#include <optional>
#include <vector>

namespace divive::probe {

class ProbeMetrics {
  public:
    static constexpr double kDiscontinuityMinimumStepM = 0.1;
    static constexpr double kDiscontinuityMinimumDerivedSpeedMps = 10.0;
    static constexpr double kDiscontinuityMinimumSpeedMismatchMps = 5.0;

    void observe(const PoseFrame& frame);
    void observe_wake_lateness(std::uint64_t lateness_ns);
    void add_missed_deadlines(std::uint64_t count) noexcept;
    ProbeSummary summary(std::uint64_t elapsed_ns) const;

  private:
    class BoundedSamples {
      public:
        void observe(std::uint64_t value);
        double quantile(double probability) const;

      private:
        static constexpr std::size_t kMaximumSamples = 262'144;

        std::vector<std::uint64_t> values_;
        std::uint64_t observations_ = 0;
        std::uint64_t stride_ = 1;
    };

    struct PreviousValidSample {
        Vector3 position;
        Vector3 linear_velocity;
        TrackingResult tracking_result = TrackingResult::uninitialized;
        std::uint64_t elapsed_ns = 0;
    };

    struct DeviceState {
        DeviceStatistics statistics;
        std::optional<Matrix34> last_valid_pose;
        std::optional<PreviousValidSample> previous_valid_sample;
    };

    std::uint64_t frames_ = 0;
    std::uint64_t missed_deadlines_ = 0;
    std::optional<std::uint64_t> first_frame_elapsed_ns_;
    std::optional<std::uint64_t> last_frame_elapsed_ns_;
    std::uint64_t interval_count_ = 0;
    long double interval_sum_ns_ = 0.0L;
    std::uint64_t min_interval_ns_ = 0;
    std::uint64_t max_interval_ns_ = 0;
    BoundedSamples interval_samples_;
    std::uint64_t wake_lateness_count_ = 0;
    long double wake_lateness_sum_ns_ = 0.0L;
    std::uint64_t min_wake_lateness_ns_ = 0;
    std::uint64_t max_wake_lateness_ns_ = 0;
    BoundedSamples wake_lateness_samples_;
    std::map<std::uint32_t, DeviceState> devices_;
};

} // namespace divive::probe
