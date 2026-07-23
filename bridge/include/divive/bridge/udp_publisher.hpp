#pragma once

#include "divive/protocol/envelope.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <string>
#include <string_view>

namespace divive::bridge {

struct UdpPublisherConfig {
    std::string destination_host{"127.0.0.1"};
    std::uint16_t destination_port{41'320};
    int send_buffer_bytes{262'144};
};

enum class UdpPublisherError {
    none,
    invalid_config,
    socket_runtime_failed,
    address_resolution_failed,
    socket_create_failed,
    socket_option_failed,
    not_open,
    empty_datagram,
    datagram_too_large,
    send_failed,
    partial_send,
};

struct UdpPublisherResult {
    UdpPublisherError error{UdpPublisherError::none};
    int system_error{0};
    std::size_t bytes_sent{0};

    [[nodiscard]] explicit operator bool() const noexcept {
        return error == UdpPublisherError::none;
    }
};

/// 1 destinationへUDP unicastする小さなRAII wrapper。
///
/// `send()`は呼出thread上で同期的に1 datagramを送る。Bridgeではcapture threadから
/// 直接呼ばず、bounded latest-value handoffの送信側で使用する。
class UdpPublisher {
  public:
    UdpPublisher();
    ~UdpPublisher();

    UdpPublisher(const UdpPublisher&) = delete;
    UdpPublisher& operator=(const UdpPublisher&) = delete;
    UdpPublisher(UdpPublisher&&) noexcept;
    UdpPublisher& operator=(UdpPublisher&&) noexcept;

    [[nodiscard]] UdpPublisherResult open(const UdpPublisherConfig& config);
    void close() noexcept;
    [[nodiscard]] bool is_open() const noexcept;
    [[nodiscard]] UdpPublisherResult send(std::span<const std::byte> datagram);

  private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

[[nodiscard]] std::string_view to_string(UdpPublisherError error) noexcept;

} // namespace divive::bridge
