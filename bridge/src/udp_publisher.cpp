#include "divive/bridge/udp_publisher.hpp"

#include <cerrno>
#include <cstring>
#include <limits>
#include <string>
#include <utility>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace divive::bridge {
namespace {

#if defined(_WIN32)
using SocketHandle = SOCKET;
using SocketLength = int;
constexpr SocketHandle kInvalidSocket = INVALID_SOCKET;

[[nodiscard]] int last_socket_error() noexcept {
    return WSAGetLastError();
}

void close_socket(const SocketHandle socket) noexcept {
    if (socket != kInvalidSocket) {
        closesocket(socket);
    }
}
#else
using SocketHandle = int;
using SocketLength = socklen_t;
constexpr SocketHandle kInvalidSocket = -1;

[[nodiscard]] int last_socket_error() noexcept {
    return errno;
}

void close_socket(const SocketHandle socket) noexcept {
    if (socket != kInvalidSocket) {
        ::close(socket);
    }
}
#endif

} // namespace

struct UdpPublisher::Impl {
    SocketHandle socket{kInvalidSocket};
    sockaddr_storage destination{};
    SocketLength destination_length{0};
#if defined(_WIN32)
    bool socket_runtime_started{false};
#endif

    void close() noexcept {
        close_socket(socket);
        socket = kInvalidSocket;
        destination = {};
        destination_length = 0;
    }

    ~Impl() {
        close();
#if defined(_WIN32)
        if (socket_runtime_started) {
            WSACleanup();
        }
#endif
    }
};

UdpPublisher::UdpPublisher() : impl_(std::make_unique<Impl>()) {}

UdpPublisher::~UdpPublisher() = default;

UdpPublisher::UdpPublisher(UdpPublisher&&) noexcept = default;

UdpPublisher& UdpPublisher::operator=(UdpPublisher&&) noexcept = default;

UdpPublisherResult UdpPublisher::open(const UdpPublisherConfig& config) {
    impl_->close();
    if (config.destination_host.empty() || config.destination_port == 0U ||
        config.send_buffer_bytes <= 0) {
        return {.error = UdpPublisherError::invalid_config};
    }

#if defined(_WIN32)
    if (!impl_->socket_runtime_started) {
        WSADATA data{};
        const auto startup_error = WSAStartup(MAKEWORD(2, 2), &data);
        if (startup_error != 0) {
            return {
                .error = UdpPublisherError::socket_runtime_failed,
                .system_error = startup_error,
            };
        }
        impl_->socket_runtime_started = true;
    }
#endif

    addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_protocol = IPPROTO_UDP;

    addrinfo* addresses = nullptr;
    const auto port = std::to_string(config.destination_port);
    const auto resolve_error =
        getaddrinfo(config.destination_host.c_str(), port.c_str(), &hints, &addresses);
    if (resolve_error != 0 || addresses == nullptr) {
        return {
            .error = UdpPublisherError::address_resolution_failed,
            .system_error = resolve_error,
        };
    }

    UdpPublisherError last_error = UdpPublisherError::socket_create_failed;
    int system_error = 0;
    for (auto* address = addresses; address != nullptr; address = address->ai_next) {
        const auto socket =
            ::socket(address->ai_family, address->ai_socktype, address->ai_protocol);
        if (socket == kInvalidSocket) {
            system_error = last_socket_error();
            continue;
        }

#if defined(_WIN32)
        const auto option_result =
            setsockopt(socket, SOL_SOCKET, SO_SNDBUF,
                       reinterpret_cast<const char*>(&config.send_buffer_bytes),
                       static_cast<int>(sizeof(config.send_buffer_bytes)));
#else
        const auto option_result =
            setsockopt(socket, SOL_SOCKET, SO_SNDBUF, &config.send_buffer_bytes,
                       sizeof(config.send_buffer_bytes));
#endif
        if (option_result != 0) {
            system_error = last_socket_error();
            last_error = UdpPublisherError::socket_option_failed;
            close_socket(socket);
            continue;
        }

        if (address->ai_addrlen > sizeof(impl_->destination)) {
            last_error = UdpPublisherError::address_resolution_failed;
            close_socket(socket);
            continue;
        }

        impl_->socket = socket;
        std::memcpy(&impl_->destination, address->ai_addr, address->ai_addrlen);
        impl_->destination_length = static_cast<SocketLength>(address->ai_addrlen);
        last_error = UdpPublisherError::none;
        break;
    }
    freeaddrinfo(addresses);

    if (last_error != UdpPublisherError::none) {
        return {
            .error = last_error,
            .system_error = system_error,
        };
    }
    return {};
}

void UdpPublisher::close() noexcept {
    impl_->close();
}

bool UdpPublisher::is_open() const noexcept {
    return impl_->socket != kInvalidSocket;
}

UdpPublisherResult UdpPublisher::send(const std::span<const std::byte> datagram) {
    if (!is_open()) {
        return {.error = UdpPublisherError::not_open};
    }
    if (datagram.empty()) {
        return {.error = UdpPublisherError::empty_datagram};
    }
    if (datagram.size() > protocol::kMaxDatagramSize) {
        return {.error = UdpPublisherError::datagram_too_large};
    }

#if defined(_WIN32)
    const auto sent =
        sendto(impl_->socket, reinterpret_cast<const char*>(datagram.data()),
               static_cast<int>(datagram.size()), 0,
               reinterpret_cast<const sockaddr*>(&impl_->destination),
               static_cast<int>(impl_->destination_length));
    if (sent == SOCKET_ERROR) {
        return {
            .error = UdpPublisherError::send_failed,
            .system_error = last_socket_error(),
        };
    }
#else
    const auto sent = sendto(impl_->socket, datagram.data(), datagram.size(), 0,
                             reinterpret_cast<const sockaddr*>(&impl_->destination),
                             impl_->destination_length);
    if (sent < 0) {
        return {
            .error = UdpPublisherError::send_failed,
            .system_error = last_socket_error(),
        };
    }
#endif

    const auto bytes_sent = static_cast<std::size_t>(sent);
    if (bytes_sent != datagram.size()) {
        return {
            .error = UdpPublisherError::partial_send,
            .bytes_sent = bytes_sent,
        };
    }
    return {
        .bytes_sent = bytes_sent,
    };
}

std::string_view to_string(const UdpPublisherError error) noexcept {
    switch (error) {
    case UdpPublisherError::none:
        return "none";
    case UdpPublisherError::invalid_config:
        return "invalid_config";
    case UdpPublisherError::socket_runtime_failed:
        return "socket_runtime_failed";
    case UdpPublisherError::address_resolution_failed:
        return "address_resolution_failed";
    case UdpPublisherError::socket_create_failed:
        return "socket_create_failed";
    case UdpPublisherError::socket_option_failed:
        return "socket_option_failed";
    case UdpPublisherError::not_open:
        return "not_open";
    case UdpPublisherError::empty_datagram:
        return "empty_datagram";
    case UdpPublisherError::datagram_too_large:
        return "datagram_too_large";
    case UdpPublisherError::send_failed:
        return "send_failed";
    case UdpPublisherError::partial_send:
        return "partial_send";
    }
    return "unknown";
}

} // namespace divive::bridge
