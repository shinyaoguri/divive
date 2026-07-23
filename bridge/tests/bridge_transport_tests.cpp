#include "divive/bridge/sender_options.hpp"
#include "divive/bridge/udp_publisher.hpp"

#include "divive/protocol/envelope.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <span>
#include <string_view>
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
    test_sender_options();
    test_udp_loopback();

    if (failures == 0) {
        std::cout << "すべてのBridge transport testが成功しました。\n";
        return EXIT_SUCCESS;
    }
    std::cerr << failures << "件のtestが失敗しました。\n";
    return EXIT_FAILURE;
}
