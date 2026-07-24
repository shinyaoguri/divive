#include "periodic_waiter.hpp"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <string>

namespace divive::probe {
namespace {

// Windows 10 version 1803以降のCREATE_WAITABLE_TIMER_HIGH_RESOLUTION。
// 古いSDK headerでもruntime fallbackをbuildできるよう値を局所化する。
constexpr DWORD kCreateWaitableTimerHighResolution = 0x00000002;
constexpr DWORD kTimerAccess = TIMER_MODIFY_STATE | SYNCHRONIZE;

std::string windows_error(const std::string& operation, const DWORD error) {
    return operation + "に失敗しました (Win32 error " + std::to_string(error) + ")";
}

} // namespace

std::unique_ptr<PeriodicWaiter> PeriodicWaiter::create(std::string& error) {
    HANDLE timer =
        CreateWaitableTimerExW(nullptr, nullptr,
                               kCreateWaitableTimerHighResolution, kTimerAccess);
    bool high_resolution = true;

    if (timer == nullptr) {
        timer = CreateWaitableTimerExW(nullptr, nullptr, 0, kTimerAccess);
        high_resolution = false;
    }

    if (timer == nullptr) {
        error = windows_error("Waitable Timerの作成", GetLastError());
        return nullptr;
    }

    return std::unique_ptr<PeriodicWaiter>(
        new PeriodicWaiter(static_cast<void*>(timer), high_resolution));
}

PeriodicWaiter::PeriodicWaiter(void* timer, const bool high_resolution)
    : timer_(timer), high_resolution_(high_resolution) {}

PeriodicWaiter::~PeriodicWaiter() {
    if (timer_ != nullptr) {
        CloseHandle(static_cast<HANDLE>(timer_));
        timer_ = nullptr;
    }
}

bool PeriodicWaiter::wait_until(const Clock::time_point deadline,
                                std::string& error) {
    const auto now = Clock::now();
    if (now >= deadline) {
        return true;
    }

    const auto remaining =
        std::chrono::duration_cast<std::chrono::nanoseconds>(deadline - now);
    constexpr std::int64_t nanoseconds_per_timer_tick = 100;
    const auto ticks =
        std::max<std::int64_t>(
            1, (remaining.count() + nanoseconds_per_timer_tick - 1) /
                   nanoseconds_per_timer_tick);

    LARGE_INTEGER due_time{};
    due_time.QuadPart = -ticks;

    const auto timer = static_cast<HANDLE>(timer_);
    if (SetWaitableTimerEx(timer, &due_time, 0, nullptr, nullptr, nullptr, 0) == 0) {
        error = windows_error("Waitable Timerの設定", GetLastError());
        return false;
    }

    const DWORD wait_result = WaitForSingleObject(timer, INFINITE);
    if (wait_result == WAIT_OBJECT_0) {
        return true;
    }

    if (wait_result == WAIT_FAILED) {
        error = windows_error("Waitable Timerの待機", GetLastError());
    } else {
        error = "Waitable Timerが想定外の状態で終了しました (" +
                std::to_string(wait_result) + ")";
    }
    return false;
}

SchedulerInfo PeriodicWaiter::info() const {
    return SchedulerInfo{
        .backend = high_resolution_
                       ? "windows_high_resolution_waitable_timer"
                       : "windows_waitable_timer_fallback",
        .high_resolution = high_resolution_,
    };
}

} // namespace divive::probe
