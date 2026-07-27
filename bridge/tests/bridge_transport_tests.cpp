#include "divive/bridge/latest_value_mailbox.hpp"
#include "divive/bridge/openvr_bridge_options.hpp"
#include "divive/bridge/openvr_pose_adapter.hpp"
#include "divive/bridge/pose_sender.hpp"
#include "divive/bridge/sender_options.hpp"
#include "divive/bridge/udp_publisher.hpp"
#include "divive/bridge/uuid.hpp"

#include "divive/protocol/envelope.hpp"
#include "divive/protocol/pose_codec.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <future>
#include <iostream>
#include <span>
#include <string_view>
#include <utility>
#include <vector>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#endif

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

#if defined(_WIN32)
using SocketHandle = SOCKET;
using SocketLength = int;
constexpr SocketHandle kInvalidSocket = INVALID_SOCKET;

void close_socket(const SocketHandle socket) {
    if (socket != kInvalidSocket) {
        closesocket(socket);
    }
}
#else
using SocketHandle = int;
using SocketLength = socklen_t;
constexpr SocketHandle kInvalidSocket = -1;

void close_socket(const SocketHandle socket) {
    if (socket != kInvalidSocket) {
        ::close(socket);
    }
}
#endif

class LoopbackReceiver {
  public:
    LoopbackReceiver() {
#if defined(_WIN32)
        WSADATA data{};
        runtime_started_ = WSAStartup(MAKEWORD(2, 2), &data) == 0;
        if (!runtime_started_) {
            return;
        }
#endif
        socket_ = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (socket_ == kInvalidSocket) {
            return;
        }

#if defined(_WIN32)
        DWORD timeout_ms = 2'000;
        if (setsockopt(socket_, SOL_SOCKET, SO_RCVTIMEO,
                       reinterpret_cast<const char*>(&timeout_ms),
                       static_cast<int>(sizeof(timeout_ms))) != 0) {
            close_socket(socket_);
            socket_ = kInvalidSocket;
            return;
        }
#else
        timeval timeout{.tv_sec = 2, .tv_usec = 0};
        if (setsockopt(socket_, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) !=
            0) {
            close_socket(socket_);
            socket_ = kInvalidSocket;
            return;
        }
#endif

        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        address.sin_port = 0;
        if (bind(socket_, reinterpret_cast<const sockaddr*>(&address),
                 static_cast<SocketLength>(sizeof(address))) != 0) {
            close_socket(socket_);
            socket_ = kInvalidSocket;
            return;
        }

        SocketLength address_length = static_cast<SocketLength>(sizeof(address));
        if (getsockname(socket_, reinterpret_cast<sockaddr*>(&address),
                        &address_length) != 0) {
            close_socket(socket_);
            socket_ = kInvalidSocket;
            return;
        }
        port_ = ntohs(address.sin_port);
    }

    ~LoopbackReceiver() {
        close_socket(socket_);
#if defined(_WIN32)
        if (runtime_started_) {
            WSACleanup();
        }
#endif
    }

    LoopbackReceiver(const LoopbackReceiver&) = delete;
    LoopbackReceiver& operator=(const LoopbackReceiver&) = delete;

    [[nodiscard]] bool is_open() const {
        return socket_ != kInvalidSocket && port_ != 0U;
    }

    [[nodiscard]] std::uint16_t port() const {
        return port_;
    }

    [[nodiscard]] std::vector<std::byte> receive() const {
        std::array<std::byte, 2'048> storage{};
#if defined(_WIN32)
        const auto received =
            recvfrom(socket_, reinterpret_cast<char*>(storage.data()),
                     static_cast<int>(storage.size()), 0, nullptr, nullptr);
        if (received == SOCKET_ERROR) {
            return {};
        }
#else
        const auto received =
            recvfrom(socket_, storage.data(), storage.size(), 0, nullptr, nullptr);
        if (received < 0) {
            return {};
        }
#endif
        return {storage.begin(),
                storage.begin() + static_cast<std::ptrdiff_t>(received)};
    }

  private:
    SocketHandle socket_{kInvalidSocket};
    std::uint16_t port_{0};
#if defined(_WIN32)
    bool runtime_started_{false};
#endif
};

[[nodiscard]] divive::protocol::UuidBytes uuid(const std::byte value) {
    divive::protocol::UuidBytes result{};
    result.fill(value);
    return result;
}

[[nodiscard]] divive::protocol::PoseBatch test_pose_batch() {
    divive::protocol::PoseBatch batch;
    batch.tracking_space_id = uuid(std::byte{3});
    batch.space_epoch = 1;
    batch.capture_monotonic_ns = divive::bridge::monotonic_now_ns();
    batch.requested_rate_hz = 90;
    batch.backend = divive::protocol::Backend::simulator;

    divive::protocol::TrackerPose tracker;
    tracker.tracker_id = "simulated/test";
    tracker.id_kind = divive::protocol::TrackerIdKind::session;
    tracker.role = "waist";
    tracker.position = {.x = 1.0F, .y = 2.0F, .z = -3.0F};
    tracker.orientation = {.x = 0.0F, .y = 0.0F, .z = 0.0F, .w = 1.0F};
    tracker.tracking_state = divive::protocol::TrackingState::simulated;
    tracker.tracking_reason = divive::protocol::TrackingReason::none;
    tracker.connected = true;
    batch.trackers.push_back(std::move(tracker));
    return batch;
}

void test_latest_value_mailbox() {
    constexpr std::string_view name = "latest value mailbox";
    divive::bridge::LatestValueMailbox<int> mailbox;

    CHECK(name,
          mailbox.publish(1) == divive::bridge::LatestValuePublishResult::accepted);
    CHECK(name,
          mailbox.publish(2) == divive::bridge::LatestValuePublishResult::overwritten);
    const auto before_take = mailbox.stats();
    CHECK(name, before_take.published == 2U);
    CHECK(name, before_take.consumed == 0U);
    CHECK(name, before_take.overwritten == 1U);
    CHECK(name, before_take.has_pending_value);

    mailbox.close();
    const auto latest = mailbox.wait_take();
    CHECK(name, latest.has_value());
    CHECK(name, latest == 2);
    CHECK(name, !mailbox.wait_take().has_value());
    CHECK(name, mailbox.publish(3) == divive::bridge::LatestValuePublishResult::closed);

    const auto final_stats = mailbox.stats();
    CHECK(name, final_stats.published == 2U);
    CHECK(name, final_stats.consumed == 1U);
    CHECK(name, final_stats.overwritten == 1U);
    CHECK(name, final_stats.closed);

    divive::bridge::LatestValueMailbox<int> blocking;
    auto waiting = std::async(std::launch::async,
                              [&blocking] { return blocking.wait_take().has_value(); });
    CHECK(name, waiting.wait_for(std::chrono::milliseconds(20)) ==
                    std::future_status::timeout);
    blocking.close();
    CHECK(name, waiting.wait_for(std::chrono::seconds(2)) == std::future_status::ready);
    CHECK(name, !waiting.get());
}

void test_sender_options() {
    constexpr std::string_view name = "sender options";
    const auto defaults =
        divive::bridge::parse_sender_options(std::vector<std::string_view>{});
    CHECK(name, defaults.options.has_value());
    CHECK(name, defaults.options->publisher.destination_host == "127.0.0.1");
    CHECK(name, defaults.options->publisher.destination_port == 41'320U);
    CHECK(name, defaults.options->rate_hz == 90.0);
    CHECK(name, defaults.options->frame_count == 900U);
    CHECK(name, defaults.options->tracker_count == 5U);

    const std::vector<std::string_view> custom{
        "--host",   "192.0.2.1", "--port",     "50000", "--rate",        "120",
        "--frames", "0",         "--trackers", "16",    "--send-buffer", "524288",
    };
    const auto parsed = divive::bridge::parse_sender_options(custom);
    CHECK(name, parsed.options.has_value());
    CHECK(name, parsed.options->publisher.destination_host == "192.0.2.1");
    CHECK(name, parsed.options->publisher.destination_port == 50'000U);
    CHECK(name, parsed.options->rate_hz == 120.0);
    CHECK(name, parsed.options->frame_count == 0U);
    CHECK(name, parsed.options->tracker_count == 16U);
    CHECK(name, parsed.options->publisher.send_buffer_bytes == 524'288);

    CHECK(name, !divive::bridge::parse_sender_options(
                     std::vector<std::string_view>{"--port", "0"})
                     .options.has_value());
    CHECK(name, !divive::bridge::parse_sender_options(
                     std::vector<std::string_view>{"--rate", "nan"})
                     .options.has_value());
    CHECK(name, !divive::bridge::parse_sender_options(
                     std::vector<std::string_view>{"--unknown", "1"})
                     .options.has_value());
}

void test_uuid() {
    constexpr std::string_view name = "uuid";
    constexpr std::string_view text = "00112233-4455-4677-8899-aabbccddeeff";
    const auto parsed = divive::bridge::parse_uuid(text);
    CHECK(name, parsed.has_value());
    if (parsed) {
        CHECK(name, divive::bridge::format_uuid(*parsed) == text);
        CHECK(name, (std::to_integer<std::uint8_t>((*parsed)[6]) >> 4U) == 4U);
    }
    CHECK(name, !divive::bridge::parse_uuid("00000000-0000-0000-0000-000000000000")
                     .has_value());
    CHECK(name, !divive::bridge::parse_uuid("not-a-uuid").has_value());

    const auto generated = divive::bridge::generate_random_uuid();
    CHECK(name, !divive::protocol::is_nil_uuid(generated));
    CHECK(name, (std::to_integer<std::uint8_t>(generated[6]) >> 4U) == 4U);
    CHECK(name, (std::to_integer<std::uint8_t>(generated[8]) & 0xC0U) == 0x80U);
    CHECK(
        name,
        divive::bridge::parse_uuid(divive::bridge::format_uuid(generated)).has_value());
}

void test_openvr_bridge_options() {
    constexpr std::string_view name = "openvr bridge options";
    CHECK(name, !divive::bridge::parse_openvr_bridge_options({}).options);

    const std::vector<std::string_view> arguments{
        "--host",
        "192.0.2.10",
        "--port",
        "50000",
        "--rate",
        "120",
        "--duration",
        "60",
        "--prediction-seconds",
        "0.01",
        "--inventory-interval",
        "2",
        "--origin",
        "raw",
        "--bridge-id",
        "00112233-4455-4677-8899-aabbccddeeff",
        "--tracking-space-id",
        "10213243-5465-4768-899a-abbccddeeff0",
        "--space-epoch",
        "3",
        "--send-buffer",
        "524288",
    };
    const auto parsed = divive::bridge::parse_openvr_bridge_options(arguments);
    CHECK(name, parsed.options.has_value());
    if (parsed.options) {
        CHECK(name, parsed.options->publisher.destination_host == "192.0.2.10");
        CHECK(name, parsed.options->publisher.destination_port == 50'000U);
        CHECK(name, parsed.options->publisher.send_buffer_bytes == 524'288);
        CHECK(name, parsed.options->rate_hz == 120.0);
        CHECK(name, parsed.options->duration_seconds == 60.0);
        CHECK(name, parsed.options->prediction_seconds == 0.01);
        CHECK(name, parsed.options->inventory_interval_seconds == 2.0);
        CHECK(name, parsed.options->origin == divive::probe::Origin::raw);
        CHECK(name, parsed.options->space_epoch == 3U);
    }

    CHECK(name, !divive::bridge::parse_openvr_bridge_options(
                     {"--host", "192.0.2.10", "--bridge-id",
                      "00112233-4455-4677-8899-aabbccddeeff", "--tracking-space-id",
                      "10213243-5465-4768-899a-abbccddeeff0", "--rate", "75"})
                     .options);
}

void test_openvr_pose_adapter() {
    constexpr std::string_view name = "openvr pose adapter";

    divive::probe::DeviceInventory tracked_inventory;
    tracked_inventory.device_index = 1;
    tracked_inventory.device_class = divive::probe::DeviceClass::generic_tracker;
    tracked_inventory.serial.value = "LHR-TRACKED";
    tracked_inventory.controller_type.value = "vive_tracker_waist";
    tracked_inventory.provides_battery.value = true;
    tracked_inventory.battery.value = 0.75;
    tracked_inventory.charging.value = true;

    divive::probe::PoseSample tracked;
    tracked.device_index = 1;
    tracked.serial = "LHR-TRACKED";
    tracked.device_class = divive::probe::DeviceClass::generic_tracker;
    tracked.connected = true;
    tracked.pose_valid = true;
    tracked.tracking_result = divive::probe::TrackingResult::running_ok;
    tracked.position = {.x = 1.0, .y = 2.0, .z = -3.0};
    tracked.orientation = {.x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0};
    tracked.linear_velocity = {.x = 0.1, .y = 0.2, .z = 0.3};
    tracked.angular_velocity = {.x = 0.4, .y = 0.5, .z = 0.6};

    auto lost = tracked;
    lost.device_index = 2;
    lost.serial = "LHR-LOST";
    lost.pose_valid = false;
    lost.tracking_result = divive::probe::TrackingResult::calibrating_out_of_range;

    auto disconnected = tracked;
    disconnected.device_index = 3;
    disconnected.serial.clear();
    disconnected.connected = false;
    disconnected.pose_valid = false;
    disconnected.tracking_result = divive::probe::TrackingResult::uninitialized;

    divive::probe::PoseSample reference;
    reference.device_index = 4;
    reference.device_class = divive::probe::DeviceClass::tracking_reference;

    const divive::probe::PoseFrame source{
        .sequence = 42,
        .elapsed_ns = 123'456,
        .devices = {tracked, lost, disconnected, reference},
    };
    const std::array inventory{tracked_inventory};
    const auto converted = divive::bridge::make_openvr_pose_batch(
        source, inventory,
        {
            .tracking_space_id = uuid(std::byte{7}),
            .space_epoch = 5,
            .requested_rate_hz = 120,
        });

    CHECK(name, converted.backend == divive::protocol::Backend::openvr);
    CHECK(name, converted.tracking_space_id == uuid(std::byte{7}));
    CHECK(name, converted.space_epoch == 5U);
    CHECK(name, converted.capture_monotonic_ns == 123'456U);
    CHECK(name, converted.send_monotonic_ns == 123'456U);
    CHECK(name, converted.requested_rate_hz == 120U);
    CHECK(name, converted.trackers.size() == 3U);
    if (converted.trackers.size() != 3U) {
        return;
    }

    const auto& first = converted.trackers[0];
    CHECK(name, first.tracker_id == "openvr/serial/LHR-TRACKED");
    CHECK(name, first.id_kind == divive::protocol::TrackerIdKind::permanent);
    CHECK(name, first.role.empty());
    CHECK(name, first.runtime_role.empty());
    CHECK(name, first.position.x == 1.0F);
    CHECK(name, first.position.z == -3.0F);
    CHECK(name, first.tracking_state == divive::protocol::TrackingState::tracking);
    CHECK(name, first.tracking_reason == divive::protocol::TrackingReason::none);
    CHECK(name, first.connected);
    CHECK(name, first.battery.has_value());
    if (first.battery) {
        CHECK(name, first.battery->level == 0.75F);
        CHECK(name, first.battery->charging);
    }

    CHECK(name, converted.trackers[1].tracking_state ==
                    divive::protocol::TrackingState::lost);
    CHECK(name, converted.trackers[1].tracking_reason ==
                    divive::protocol::TrackingReason::out_of_range);
    CHECK(name, converted.trackers[2].tracker_id == "openvr/session/device-3");
    CHECK(name,
          converted.trackers[2].id_kind == divive::protocol::TrackerIdKind::session);
    CHECK(name, converted.trackers[2].tracking_state ==
                    divive::protocol::TrackingState::disconnected);
    CHECK(name, converted.trackers[2].tracking_reason ==
                    divive::protocol::TrackingReason::device_unplugged);

    const auto encoded = divive::protocol::encode_pose_batch(converted);
    CHECK(name, static_cast<bool>(encoded));
}

void test_pose_sender_loopback() {
    constexpr std::string_view name = "pose sender loopback";
    LoopbackReceiver receiver;
    CHECK(name, receiver.is_open());
    if (!receiver.is_open()) {
        return;
    }

    divive::bridge::PoseSender sender;
    CHECK(name, sender.submit(test_pose_batch()) ==
                    divive::bridge::PoseSenderSubmitResult::not_running);

    divive::bridge::PoseSenderConfig config;
    config.publisher.destination_host = "127.0.0.1";
    config.publisher.destination_port = receiver.port();
    config.envelope.session_id = uuid(std::byte{1});
    config.envelope.bridge_id = uuid(std::byte{2});
    config.envelope.frame_sequence = 42;

    const auto started = sender.start(config);
    CHECK(name, static_cast<bool>(started));
    CHECK(name, sender.is_running());
    if (!started) {
        return;
    }

    const auto submitted = sender.submit(test_pose_batch());
    CHECK(name, submitted == divive::bridge::PoseSenderSubmitResult::accepted ||
                    submitted == divive::bridge::PoseSenderSubmitResult::overwritten);
    sender.stop();
    CHECK(name, !sender.is_running());

    const auto datagram = receiver.receive();
    CHECK(name, !datagram.empty());
    const auto parsed = divive::protocol::parse_packet(datagram);
    CHECK(name, static_cast<bool>(parsed));
    if (!parsed) {
        return;
    }
    CHECK(name, parsed.packet->envelope.frame_sequence == 42U);

    const auto decoded = divive::protocol::decode_pose_batch(parsed.packet->payload);
    CHECK(name, static_cast<bool>(decoded));
    if (decoded) {
        CHECK(name,
              decoded.batch->send_monotonic_ns >= decoded.batch->capture_monotonic_ns);
        CHECK(name, decoded.batch->trackers.size() == 1U);
        CHECK(name, decoded.batch->trackers[0].tracker_id == "simulated/test");
    }

    const auto stats = sender.stats();
    CHECK(name, stats.submitted_frames == 1U);
    CHECK(name, stats.sent_frames == 1U);
    CHECK(name, stats.sent_datagrams == 1U);
    CHECK(name, stats.last_error == divive::bridge::PoseSenderRuntimeError::none);

    divive::bridge::PoseSender invalid;
    CHECK(name, invalid.start({}).error ==
                    divive::bridge::PoseSenderStartError::invalid_identity);

    divive::bridge::PoseSender failing;
    CHECK(name, static_cast<bool>(failing.start(config)));
    auto invalid_batch = test_pose_batch();
    invalid_batch.tracking_space_id = {};
    CHECK(name, failing.submit(std::move(invalid_batch)) ==
                    divive::bridge::PoseSenderSubmitResult::accepted);
    failing.stop();
    const auto failure_stats = failing.stats();
    CHECK(name, failure_stats.sent_frames == 0U);
    CHECK(name, failure_stats.last_error ==
                    divive::bridge::PoseSenderRuntimeError::packetize_failed);
    CHECK(name, failure_stats.packetizer_error ==
                    divive::protocol::FramePacketizerError::pose_codec_error);
    CHECK(name, failure_stats.pose_codec_error ==
                    divive::protocol::PoseCodecError::nil_tracking_space_id);
}

void test_udp_loopback() {
    constexpr std::string_view name = "udp loopback";
    LoopbackReceiver receiver;
    CHECK(name, receiver.is_open());
    if (!receiver.is_open()) {
        return;
    }

    divive::bridge::UdpPublisher publisher;
    CHECK(name, publisher.send(std::span<const std::byte>{}).error ==
                    divive::bridge::UdpPublisherError::not_open);

    const auto opened = publisher.open({
        .destination_host = "127.0.0.1",
        .destination_port = receiver.port(),
    });
    CHECK(name, static_cast<bool>(opened));
    CHECK(name, publisher.is_open());
    if (!opened) {
        return;
    }

    constexpr std::array<std::byte, 8> expected{
        std::byte{'D'}, std::byte{'V'}, std::byte{'I'}, std::byte{'V'},
        std::byte{1},   std::byte{2},   std::byte{3},   std::byte{4},
    };
    const auto sent = publisher.send(expected);
    CHECK(name, static_cast<bool>(sent));
    CHECK(name, sent.bytes_sent == expected.size());
    const auto received = receiver.receive();
    CHECK(name, std::ranges::equal(received, expected));

    const std::vector<std::byte> oversized(divive::protocol::kMaxDatagramSize + 1U);
    CHECK(name, publisher.send(oversized).error ==
                    divive::bridge::UdpPublisherError::datagram_too_large);
    publisher.close();
    CHECK(name, !publisher.is_open());
}

} // namespace

int main() {
    test_latest_value_mailbox();
    test_sender_options();
    test_uuid();
    test_openvr_bridge_options();
    test_openvr_pose_adapter();
    test_pose_sender_loopback();
    test_udp_loopback();

    if (failures == 0) {
        std::cout << "すべてのBridge transport testが成功しました。\n";
        return EXIT_SUCCESS;
    }
    std::cerr << failures << "件のtestが失敗しました。\n";
    return EXIT_FAILURE;
}
