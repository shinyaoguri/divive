#include "openvr_session.hpp"

#include "divive/probe/json.hpp"
#include "divive/probe/metrics.hpp"
#include "divive/probe/options.hpp"

#include <chrono>
#include <csignal>
#include <cstdint>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <ostream>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;

volatile std::sig_atomic_t running = 1;

void stop_handler(int) {
    running = 0;
}

std::uint64_t elapsed_ns(const Clock::time_point start, const Clock::time_point now) {
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(now - start).count());
}

std::string wall_time_utc() {
    const auto now = std::chrono::system_clock::now();
    const std::time_t time = std::chrono::system_clock::to_time_t(now);
    std::tm utc{};
#if defined(_WIN32)
    gmtime_s(&utc, &time);
#else
    gmtime_r(&time, &utc);
#endif

    std::ostringstream output;
    output << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ");
    return output.str();
}

bool write_line(std::ostream& output, const std::string& line) {
    output << line << '\n';
    return output.good();
}

} // namespace

int main(int argc, char** argv) {
    std::vector<std::string_view> arguments;
    arguments.reserve(static_cast<std::size_t>(argc > 0 ? argc - 1 : 0));
    for (int index = 1; index < argc; ++index) {
        arguments.emplace_back(argv[index]);
    }

    const auto parsed = divive::probe::parse_options(arguments);
    if (parsed.show_help) {
        std::cout << divive::probe::usage();
        return 0;
    }
    if (!parsed.options) {
        std::cerr << parsed.error << "\n\n" << divive::probe::usage();
        return 64;
    }
    const auto& options = *parsed.options;

    std::ofstream file;
    std::ostream* output = &std::cout;
    if (options.output != "-") {
        file.open(options.output, std::ios::out | std::ios::trunc);
        if (!file.is_open()) {
            std::cerr << "出力fileを開けません: " << options.output << '\n';
            return 73;
        }
        output = &file;
    }

    std::signal(SIGINT, stop_handler);
    std::signal(SIGTERM, stop_handler);

    const auto start = Clock::now();
    std::string init_error;
    auto session = divive::probe::OpenVrSession::create(init_error);
    if (!session) {
        write_line(*output,
                   divive::probe::serialize_error("openvr_init_failed", init_error,
                                                  elapsed_ns(start, Clock::now())));
        output->flush();
        std::cerr << "OpenVR初期化失敗: " << init_error << '\n';
        return 2;
    }

    if (!write_line(*output, divive::probe::serialize_probe_start(
                                 wall_time_utc(), session->sdk_version(),
                                 session->runtime_path(), options))) {
        std::cerr << "probe_startを書き込めません\n";
        return 74;
    }

    const auto initial_inventory = session->inventory(options.trackers_only);
    if (!write_line(*output, divive::probe::serialize_inventory(
                                 elapsed_ns(start, Clock::now()), initial_inventory))) {
        std::cerr << "device inventoryを書き込めません\n";
        return 74;
    }
    output->flush();

    const auto period_ns = std::chrono::nanoseconds{
        static_cast<std::int64_t>(1'000'000'000.0 / options.rate_hz)};
    const auto duration_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(options.duration_seconds));
    const auto inventory_interval_ns =
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::duration<double>(options.inventory_interval_seconds));

    auto next_tick = Clock::now();
    auto next_inventory = options.inventory_interval_seconds > 0.0
                              ? start + inventory_interval_ns
                              : Clock::time_point::max();

    std::uint64_t sequence = 0;
    divive::probe::ProbeMetrics metrics;

    while (running != 0) {
        auto now = Clock::now();
        if (options.duration_seconds > 0.0 && now - start >= duration_ns) {
            break;
        }

        if (now < next_tick) {
            std::this_thread::sleep_until(next_tick);
        }
        now = Clock::now();

        if (now >= next_inventory) {
            const auto inventory = session->inventory(options.trackers_only);
            if (!write_line(*output, divive::probe::serialize_inventory(
                                         elapsed_ns(start, now), inventory))) {
                std::cerr << "device inventoryを書き込めません\n";
                return 74;
            }
            output->flush();
            next_inventory = now + inventory_interval_ns;
        }

        auto frame = session->sample(sequence++, elapsed_ns(start, now), options.origin,
                                     options.prediction_seconds, options.trackers_only);
        metrics.observe(frame);
        if (!write_line(*output, divive::probe::serialize_pose_frame(frame))) {
            std::cerr << "pose frameを書き込めません\n";
            return 74;
        }

        next_tick += period_ns;
        const auto after_sample = Clock::now();
        if (after_sample > next_tick) {
            const auto behind = after_sample - next_tick;
            const auto missed = static_cast<std::uint64_t>(behind / period_ns) + 1U;
            metrics.add_missed_deadlines(missed);
            next_tick += period_ns * static_cast<std::int64_t>(missed);
        }
    }

    const auto finished_elapsed_ns = elapsed_ns(start, Clock::now());
    write_line(*output,
               divive::probe::serialize_summary(metrics.summary(finished_elapsed_ns)));
    output->flush();

    return output->good() ? 0 : 74;
}
