#pragma once

#include "divive/bridge/udp_publisher.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace divive::bridge {

struct SenderOptions {
    UdpPublisherConfig publisher;
    double rate_hz{90.0};
    std::uint64_t frame_count{900};
    std::size_t tracker_count{5};
};

struct SenderOptionsResult {
    std::optional<SenderOptions> options;
    bool show_help{false};
    std::string error;
};

[[nodiscard]] SenderOptionsResult
parse_sender_options(const std::vector<std::string_view>& arguments);
[[nodiscard]] std::string sender_usage();

} // namespace divive::bridge
