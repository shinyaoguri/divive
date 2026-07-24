#pragma once

#include "divive/probe/model.hpp"

#include <chrono>
#include <memory>
#include <string>

namespace divive::probe {

class PeriodicWaiter {
  public:
    using Clock = std::chrono::steady_clock;

    static std::unique_ptr<PeriodicWaiter> create(std::string& error);

    ~PeriodicWaiter();

    PeriodicWaiter(const PeriodicWaiter&) = delete;
    PeriodicWaiter& operator=(const PeriodicWaiter&) = delete;

    bool wait_until(Clock::time_point deadline, std::string& error);
    SchedulerInfo info() const;

  private:
    PeriodicWaiter(void* timer, bool high_resolution);

    void* timer_ = nullptr;
    bool high_resolution_ = false;
};

} // namespace divive::probe
