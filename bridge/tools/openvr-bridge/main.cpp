#include "openvr_session.hpp"
#include "periodic_waiter.hpp"

#include "divive/bridge/openvr_bridge_options.hpp"
#include "divive/bridge/openvr_pose_adapter.hpp"
#include "divive/bridge/pose_sender.hpp"
#include "divive/bridge/uuid.hpp"

#include <chrono>
#include <cmath>
#include <csignal>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;

volatile std::sig_atomic_t running = 1;

void stop_handler(int) {
    running = 0;
}

void print_inventory(const std::vector<divive::probe::DeviceInventory>& inventory) {
    std::cout << "Tracker inventory: " << inventory.size() << "台\n";
    for (const auto& device : inventory) {
        std::cout << "  index=" << device.device_index
                  << " serial=" << device.serial.value.value_or("(取得不可)")
                  << " model=" << device.model.value.value_or("(取得不可)")
                  << " connected=" << (device.connected ? "true" : "false") << '\n';
    }
}

int sender_error_exit(const divive::bridge::PoseSenderStats& stats) {
    if (stats.last_error == divive::bridge::PoseSenderRuntimeError::none) {
        return 0;
    }
    std::cerr << "送信threadでerrorが発生しました: "
              << divive::bridge::to_string(stats.last_error) << " packetizer_error="
              << divive::protocol::to_string(stats.packetizer_error)
              << " pose_error=" << divive::protocol::to_string(stats.pose_codec_error)
              << " packet_error=" << divive::protocol::to_string(stats.packet_error)
              << " publisher_error=" << divive::bridge::to_string(stats.publisher_error)
              << " system_error=" << stats.system_error << '\n';
    return 3;
}

} // namespace

int main(int argc, char** argv) {
    std::vector<std::string_view> arguments;
    arguments.reserve(static_cast<std::size_t>(argc > 0 ? argc - 1 : 0));
    for (int index = 1; index < argc; ++index) {
        arguments.emplace_back(argv[index]);
    }

    const auto parsed = divive::bridge::parse_openvr_bridge_options(arguments);
    if (parsed.show_help) {
        std::cout << divive::bridge::openvr_bridge_usage();
        return 0;
    }
    if (!parsed.options) {
        std::cerr << parsed.error << "\n\n" << divive::bridge::openvr_bridge_usage();
        return 64;
    }
    const auto& options = *parsed.options;

    std::signal(SIGINT, stop_handler);
    std::signal(SIGTERM, stop_handler);

    std::string init_error;
    auto session = divive::probe::OpenVrSession::create(init_error);
    if (!session) {
        std::cerr << "OpenVR初期化失敗: " << init_error << '\n';
        return 2;
    }

    std::string scheduler_error;
    auto scheduler = divive::probe::PeriodicWaiter::create(scheduler_error);
    if (!scheduler) {
        std::cerr << "scheduler初期化失敗: " << scheduler_error << '\n';
        return 75;
    }

    auto inventory = session->inventory(true);
    print_inventory(inventory);

    divive::protocol::Envelope envelope;
    envelope.session_id = divive::bridge::generate_random_uuid();
    envelope.bridge_id = options.bridge_id;

    divive::bridge::PoseSender sender;
    const auto started = sender.start({
        .publisher = options.publisher,
        .envelope = envelope,
    });
    if (!started) {
        std::cerr << "Pose senderを開始できません: "
                  << divive::bridge::to_string(started.error) << " publisher_error="
                  << divive::bridge::to_string(started.publisher_result.error)
                  << " system_error=" << started.system_error << '\n';
        return 2;
    }

    const auto scheduler_info = scheduler->info();
    std::cout << "OpenVR送信開始: destination=" << options.publisher.destination_host
              << ':' << options.publisher.destination_port
              << " rate=" << options.rate_hz
              << "Hz bridge_id=" << divive::bridge::format_uuid(options.bridge_id)
              << " session_id=" << divive::bridge::format_uuid(envelope.session_id)
              << " tracking_space_id="
              << divive::bridge::format_uuid(options.tracking_space_id)
              << " space_epoch=" << options.space_epoch
              << " scheduler=" << scheduler_info.backend << " high_resolution="
              << (scheduler_info.high_resolution ? "true" : "false") << '\n';

    const auto requested_rate_hz =
        static_cast<std::uint16_t>(std::lround(options.rate_hz));
    const divive::bridge::OpenVrPoseAdapterConfig adapter_config{
        .tracking_space_id = options.tracking_space_id,
        .space_epoch = options.space_epoch,
        .requested_rate_hz = requested_rate_hz,
    };
    const auto period = std::chrono::nanoseconds{
        static_cast<std::int64_t>(1'000'000'000.0 / options.rate_hz)};
    const auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(options.duration_seconds));
    const auto inventory_interval =
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::duration<double>(options.inventory_interval_seconds));

    const auto start = Clock::now();
    auto next_tick = start;
    auto next_inventory = options.inventory_interval_seconds > 0.0
                              ? start + inventory_interval
                              : Clock::time_point::max();
    std::uint64_t capture_sequence = 0;
    std::uint64_t missed_capture_deadlines = 0;

    while (running != 0 && sender.is_running()) {
        auto now = Clock::now();
        if (options.duration_seconds > 0.0 && now - start >= duration) {
            break;
        }
        if (now < next_tick && !scheduler->wait_until(next_tick, scheduler_error)) {
            std::cerr << "scheduler待機失敗: " << scheduler_error << '\n';
            sender.stop();
            return 75;
        }
        now = Clock::now();

        if (now >= next_inventory) {
            inventory = session->inventory(true);
            next_inventory = now + inventory_interval;
        }

        const auto capture_ns = divive::bridge::monotonic_now_ns();
        auto native_frame =
            session->sample(capture_sequence++, capture_ns, options.origin,
                            options.prediction_seconds, true);
        auto canonical_frame = divive::bridge::make_openvr_pose_batch(
            native_frame, inventory, adapter_config);
        const auto submitted = sender.submit(std::move(canonical_frame));
        if (submitted == divive::bridge::PoseSenderSubmitResult::not_running ||
            submitted == divive::bridge::PoseSenderSubmitResult::closed) {
            break;
        }

        next_tick += period;
        const auto after_submit = Clock::now();
        if (after_submit > next_tick) {
            const auto behind = after_submit - next_tick;
            const auto missed = static_cast<std::uint64_t>(behind / period) + 1U;
            missed_capture_deadlines += missed;
            next_tick += period * static_cast<std::int64_t>(missed);
        }
    }

    sender.stop();
    const auto stats = sender.stats();
    const auto elapsed_seconds =
        std::chrono::duration<double>(Clock::now() - start).count();
    std::cout << "OpenVR送信終了: captured_frames=" << capture_sequence
              << " submitted_frames=" << stats.submitted_frames
              << " overwritten_frames=" << stats.overwritten_frames
              << " sent_frames=" << stats.sent_frames
              << " datagrams=" << stats.sent_datagrams << " bytes=" << stats.sent_bytes
              << " missed_capture_deadlines=" << missed_capture_deadlines
              << " elapsed_s=" << elapsed_seconds << '\n';
    return sender_error_exit(stats);
}
