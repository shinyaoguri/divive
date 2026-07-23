#include "divive/bridge/sender_options.hpp"

#include <charconv>
#include <cmath>
#include <limits>
#include <sstream>
#include <system_error>
#include <utility>

namespace divive::bridge {
namespace {

template <typename T>
[[nodiscard]] std::optional<T> parse_integer(const std::string_view value) {
    T result{};
    const auto parsed =
        std::from_chars(value.data(), value.data() + value.size(), result);
    if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size()) {
        return std::nullopt;
    }
    return result;
}

[[nodiscard]] std::optional<double> parse_number(const std::string_view value) {
    double result = 0.0;
    const auto parsed =
        std::from_chars(value.data(), value.data() + value.size(), result);
    if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size() ||
        !std::isfinite(result)) {
        return std::nullopt;
    }
    return result;
}

[[nodiscard]] SenderOptionsResult error_result(std::string message) {
    SenderOptionsResult result;
    result.error = std::move(message);
    return result;
}

} // namespace

SenderOptionsResult
parse_sender_options(const std::vector<std::string_view>& arguments) {
    SenderOptions options;

    for (std::size_t index = 0; index < arguments.size(); ++index) {
        const auto argument = arguments[index];
        if (argument == "--help" || argument == "-h") {
            SenderOptionsResult result;
            result.show_help = true;
            return result;
        }
        if (index + 1U >= arguments.size()) {
            return error_result("optionに値が必要です: " + std::string(argument));
        }
        const auto value = arguments[++index];

        if (argument == "--host") {
            if (value.empty()) {
                return error_result("--hostに空文字列は指定できません");
            }
            options.publisher.destination_host = value;
        } else if (argument == "--port") {
            const auto parsed = parse_integer<std::uint32_t>(value);
            if (!parsed || *parsed == 0U ||
                *parsed > std::numeric_limits<std::uint16_t>::max()) {
                return error_result("--portは1〜65535の範囲で指定してください");
            }
            options.publisher.destination_port = static_cast<std::uint16_t>(*parsed);
        } else if (argument == "--rate") {
            const auto parsed = parse_number(value);
            if (!parsed || *parsed < 1.0 || *parsed > 1'000.0) {
                return error_result("--rateは1〜1000の範囲で指定してください");
            }
            options.rate_hz = *parsed;
        } else if (argument == "--frames") {
            const auto parsed = parse_integer<std::uint64_t>(value);
            if (!parsed) {
                return error_result("--framesは0以上の整数で指定してください");
            }
            options.frame_count = *parsed;
        } else if (argument == "--trackers") {
            const auto parsed = parse_integer<std::uint32_t>(value);
            if (!parsed || *parsed == 0U || *parsed > 256U) {
                return error_result("--trackersは1〜256の範囲で指定してください");
            }
            options.tracker_count = static_cast<std::size_t>(*parsed);
        } else if (argument == "--send-buffer") {
            const auto parsed = parse_integer<std::uint32_t>(value);
            if (!parsed || *parsed < 1'200U ||
                *parsed > static_cast<std::uint32_t>(std::numeric_limits<int>::max())) {
                return error_result(
                    "--send-bufferは1200以上のbyte数で指定してください");
            }
            options.publisher.send_buffer_bytes = static_cast<int>(*parsed);
        } else {
            return error_result("不明なoptionです: " + std::string(argument));
        }
    }

    SenderOptionsResult result;
    result.options = std::move(options);
    return result;
}

std::string sender_usage() {
    std::ostringstream output;
    output << "divive-bridge-send-test [options]\n\n"
           << "simulated Tracker姿勢をFlatBuffers/UDPでMac Hubへ送ります。\n\n"
           << "Options:\n"
           << "  --host <address>       Hub address。既定: 127.0.0.1\n"
           << "  --port <port>          Hub UDP port。既定: 41320\n"
           << "  --rate <hz>            送信頻度。既定: 90\n"
           << "  --frames <count>       frame数。0はCtrl+Cまで。既定: 900\n"
           << "  --trackers <count>     Tracker数。既定: 5\n"
           << "  --send-buffer <bytes>  socket送信buffer。既定: 262144\n"
           << "  --help, -h             このhelpを表示\n";
    return output.str();
}

} // namespace divive::bridge
