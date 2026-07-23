#pragma once

#include "divive/probe/model.hpp"

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace divive::probe {

struct Options {
    double rate_hz = 120.0;
    double duration_seconds = 30.0;
    double prediction_seconds = 0.0;
    double inventory_interval_seconds = 1.0;
    Origin origin = Origin::standing;
    bool trackers_only = false;
    std::string output = "-";
};

struct ParseResult {
    std::optional<Options> options;
    bool show_help = false;
    std::string error;
};

ParseResult parse_options(const std::vector<std::string_view>& arguments);
std::string usage();

} // namespace divive::probe
