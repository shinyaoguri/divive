#pragma once

#include "divive/probe/model.hpp"

#include <cstdint>
#include <map>
#include <optional>

namespace divive::probe {

class ProbeMetrics {
  public:
    void observe(const PoseFrame& frame);
    void add_missed_deadlines(std::uint64_t count) noexcept;
    ProbeSummary summary(std::uint64_t elapsed_ns) const;

  private:
    struct DeviceState {
        DeviceStatistics statistics;
        std::optional<Matrix34> last_valid_pose;
    };

    std::uint64_t frames_ = 0;
    std::uint64_t missed_deadlines_ = 0;
    std::optional<std::uint64_t> last_frame_elapsed_ns_;
    std::uint64_t interval_count_ = 0;
    long double interval_sum_ns_ = 0.0L;
    std::uint64_t min_interval_ns_ = 0;
    std::uint64_t max_interval_ns_ = 0;
    std::map<std::uint32_t, DeviceState> devices_;
};

} // namespace divive::probe
