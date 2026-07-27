#pragma once

#include "divive/bridge/udp_publisher.hpp"
#include "divive/probe/model.hpp"
#include "divive/protocol/envelope.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace divive::bridge {

struct OpenVrBridgeOptions {
    UdpPublisherConfig publisher;
    double rate_hz{90.0};
    double duration_seconds{0.0};
    double prediction_seconds{0.0};
    double inventory_interval_seconds{1.0};
    probe::Origin origin{probe::Origin::standing};
    protocol::UuidBytes bridge_id{};
    protocol::UuidBytes tracking_space_id{};
    std::uint32_t space_epoch{1};
};

struct OpenVrBridgeOptionsResult {
    std::optional<OpenVrBridgeOptions> options;
    bool show_help{false};
    std::string error;
};

[[nodiscard]] OpenVrBridgeOptionsResult
parse_openvr_bridge_options(const std::vector<std::string_view>& arguments);

[[nodiscard]] std::string openvr_bridge_usage();

} // namespace divive::bridge
