#include "divive/bridge/sender_options.hpp"
#include "divive/bridge/udp_publisher.hpp"
#include "divive/protocol/frame_packetizer.hpp"

#include <chrono>
#include <cmath>
#include <csignal>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <numbers>
#include <random>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;
using divive::protocol::PoseBatch;
using divive::protocol::TrackerPose;
using divive::protocol::UuidBytes;

volatile std::sig_atomic_t running = 1;

void stop_handler(int) {
    running = 0;
}

[[nodiscard]] std::uint64_t monotonic_ns(const Clock::time_point origin,
                                         const Clock::time_point now) {
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(now - origin).count());
}

[[nodiscard]] UuidBytes random_uuid() {
    std::random_device source;
    UuidBytes result{};
    for (auto& value : result) {
        value = static_cast<std::byte>(source() & 0xFFU);
    }
    // RFC 4122 version 4、variant 1。
    result[6] = (result[6] & std::byte{0x0F}) | std::byte{0x40};
    result[8] = (result[8] & std::byte{0x3F}) | std::byte{0x80};
    return result;
}

[[nodiscard]] PoseBatch
make_frame(const std::size_t tracker_count, const UuidBytes& tracking_space_id,
           const std::uint64_t sequence, const std::uint64_t capture_ns,
           const std::uint64_t send_ns, const std::uint16_t rate_hz) {
    PoseBatch frame;
    frame.tracking_space_id = tracking_space_id;
    frame.space_epoch = 1;
    frame.capture_monotonic_ns = capture_ns;
    frame.send_monotonic_ns = send_ns;
    frame.requested_rate_hz = rate_hz;
    frame.backend = divive::protocol::Backend::simulator;
    frame.trackers.reserve(tracker_count);

    const auto phase = static_cast<double>(sequence) * 0.025;
    for (std::size_t index = 0; index < tracker_count; ++index) {
        const auto angle =
            phase + (2.0 * std::numbers::pi * static_cast<double>(index) /
                     static_cast<double>(tracker_count));
        const auto half_angle = angle * 0.5;

        TrackerPose tracker;
        tracker.tracker_id = "simulated/bridge-send-test/" + std::to_string(index);
        tracker.id_kind = divive::protocol::TrackerIdKind::session;
        tracker.role = "sim_" + std::to_string(index);
        tracker.position = {
            .x = static_cast<float>(std::cos(angle)),
            .y = 1.0F + static_cast<float>(index) * 0.05F,
            .z = static_cast<float>(-std::sin(angle)),
        };
        tracker.orientation = {
            .x = 0.0F,
            .y = static_cast<float>(std::sin(half_angle)),
            .z = 0.0F,
            .w = static_cast<float>(std::cos(half_angle)),
        };
        tracker.linear_velocity = divive::protocol::Vector3{
            .x = static_cast<float>(-std::sin(angle) * 2.25),
            .y = 0.0F,
            .z = static_cast<float>(-std::cos(angle) * 2.25),
        };
        tracker.tracking_state = divive::protocol::TrackingState::simulated;
        tracker.tracking_reason = divive::protocol::TrackingReason::none;
        tracker.connected = true;
        frame.trackers.push_back(std::move(tracker));
    }
    return frame;
}

} // namespace

int main(int argc, char** argv) {
    std::vector<std::string_view> arguments;
    arguments.reserve(static_cast<std::size_t>(argc > 0 ? argc - 1 : 0));
    for (int index = 1; index < argc; ++index) {
        arguments.emplace_back(argv[index]);
    }

    const auto parsed = divive::bridge::parse_sender_options(arguments);
    if (parsed.show_help) {
        std::cout << divive::bridge::sender_usage();
        return 0;
    }
    if (!parsed.options) {
        std::cerr << parsed.error << "\n\n" << divive::bridge::sender_usage();
        return 64;
    }
    const auto& options = *parsed.options;

    divive::bridge::UdpPublisher publisher;
    const auto opened = publisher.open(options.publisher);
    if (!opened) {
        std::cerr << "UDP publisherを開始できません: "
                  << divive::bridge::to_string(opened.error)
                  << " system_error=" << opened.system_error << '\n';
        return 2;
    }

    std::signal(SIGINT, stop_handler);
    std::signal(SIGTERM, stop_handler);

    divive::protocol::Envelope envelope;
    envelope.session_id = random_uuid();
    envelope.bridge_id = random_uuid();
    const auto tracking_space_id = random_uuid();

    const auto requested_rate_hz =
        static_cast<std::uint16_t>(std::lround(options.rate_hz));
    const auto period = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / options.rate_hz));
    const auto start = Clock::now();
    auto next_tick = start;

    std::uint64_t sequence = 0;
    std::uint64_t datagrams = 0;
    std::uint64_t bytes = 0;
    std::uint64_t missed_deadlines = 0;

    std::cout << "送信開始: " << options.publisher.destination_host << ':'
              << options.publisher.destination_port << " rate=" << options.rate_hz
              << "Hz trackers=" << options.tracker_count << '\n';

    while (running != 0 &&
           (options.frame_count == 0U || sequence < options.frame_count)) {
        const auto before_capture = Clock::now();
        if (before_capture < next_tick) {
            std::this_thread::sleep_until(next_tick);
        }
        const auto captured_at = Clock::now();
        const auto capture_ns = monotonic_ns(start, captured_at);
        const auto send_ns = monotonic_ns(start, Clock::now());
        const auto frame = make_frame(options.tracker_count, tracking_space_id,
                                      sequence, capture_ns, send_ns, requested_rate_hz);
        envelope.frame_sequence = sequence;

        const auto packetized = divive::protocol::packetize_pose_frame(envelope, frame);
        if (!packetized) {
            std::cerr << "frameをpacketizeできません: "
                      << divive::protocol::to_string(packetized.error) << " pose_error="
                      << divive::protocol::to_string(packetized.pose_error)
                      << " packet_error="
                      << divive::protocol::to_string(packetized.packet_error) << '\n';
            return 3;
        }

        for (const auto& datagram : packetized.datagrams) {
            const auto sent = publisher.send(datagram);
            if (!sent) {
                std::cerr << "UDP送信失敗: " << divive::bridge::to_string(sent.error)
                          << " system_error=" << sent.system_error << '\n';
                return 4;
            }
            ++datagrams;
            bytes += sent.bytes_sent;
        }
        ++sequence;

        next_tick += period;
        const auto after_send = Clock::now();
        if (after_send > next_tick) {
            const auto behind = after_send - next_tick;
            const auto missed = static_cast<std::uint64_t>(behind / period) + 1U;
            missed_deadlines += missed;
            next_tick += period * static_cast<std::int64_t>(missed);
        }
    }

    const auto elapsed_seconds =
        std::chrono::duration<double>(Clock::now() - start).count();
    std::cout << "送信終了: frames=" << sequence << " datagrams=" << datagrams
              << " bytes=" << bytes << " missed_deadlines=" << missed_deadlines
              << " elapsed_s=" << elapsed_seconds << '\n';
    return 0;
}
