#include "divive/bridge/openvr_bridge_options.hpp"

#include "divive/bridge/uuid.hpp"

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

[[nodiscard]] OpenVrBridgeOptionsResult error_result(std::string message) {
    OpenVrBridgeOptionsResult result;
    result.error = std::move(message);
    return result;
}

[[nodiscard]] bool supported_rate(const double rate) noexcept {
    return rate == 60.0 || rate == 90.0 || rate == 120.0;
}

} // namespace

OpenVrBridgeOptionsResult
parse_openvr_bridge_options(const std::vector<std::string_view>& arguments) {
    OpenVrBridgeOptions options;
    bool host_provided = false;
    bool bridge_id_provided = false;
    bool tracking_space_id_provided = false;

    for (std::size_t index = 0; index < arguments.size(); ++index) {
        const auto argument = arguments[index];
        if (argument == "--help" || argument == "-h") {
            OpenVrBridgeOptionsResult result;
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
            host_provided = true;
        } else if (argument == "--port") {
            const auto parsed = parse_integer<std::uint32_t>(value);
            if (!parsed || *parsed == 0U ||
                *parsed > std::numeric_limits<std::uint16_t>::max()) {
                return error_result("--portは1〜65535の範囲で指定してください");
            }
            options.publisher.destination_port = static_cast<std::uint16_t>(*parsed);
        } else if (argument == "--rate") {
            const auto parsed = parse_number(value);
            if (!parsed || !supported_rate(*parsed)) {
                return error_result("--rateは60、90、120のいずれかです");
            }
            options.rate_hz = *parsed;
        } else if (argument == "--duration") {
            const auto parsed = parse_number(value);
            if (!parsed || *parsed < 0.0 || *parsed > 604'800.0) {
                return error_result("--durationは0〜604800秒の範囲で指定してください");
            }
            options.duration_seconds = *parsed;
        } else if (argument == "--prediction-seconds") {
            const auto parsed = parse_number(value);
            if (!parsed || *parsed < -1.0 || *parsed > 1.0) {
                return error_result(
                    "--prediction-secondsは-1〜1の範囲で指定してください");
            }
            options.prediction_seconds = *parsed;
        } else if (argument == "--inventory-interval") {
            const auto parsed = parse_number(value);
            if (!parsed || *parsed < 0.0 || *parsed > 3'600.0) {
                return error_result(
                    "--inventory-intervalは0〜3600秒の範囲で指定してください");
            }
            options.inventory_interval_seconds = *parsed;
        } else if (argument == "--origin") {
            if (value == "standing") {
                options.origin = probe::Origin::standing;
            } else if (value == "seated") {
                options.origin = probe::Origin::seated;
            } else if (value == "raw") {
                options.origin = probe::Origin::raw;
            } else {
                return error_result("--originはstanding、seated、rawのいずれかです");
            }
        } else if (argument == "--bridge-id") {
            const auto parsed = parse_uuid(value);
            if (!parsed) {
                return error_result(
                    "--bridge-idはnilでないRFC 4122 UUIDで指定してください");
            }
            options.bridge_id = *parsed;
            bridge_id_provided = true;
        } else if (argument == "--tracking-space-id") {
            const auto parsed = parse_uuid(value);
            if (!parsed) {
                return error_result(
                    "--tracking-space-idはnilでないRFC 4122 UUIDで指定してください");
            }
            options.tracking_space_id = *parsed;
            tracking_space_id_provided = true;
        } else if (argument == "--space-epoch") {
            const auto parsed = parse_integer<std::uint32_t>(value);
            if (!parsed || *parsed == 0U) {
                return error_result("--space-epochは1以上の整数で指定してください");
            }
            options.space_epoch = *parsed;
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

    if (!host_provided) {
        return error_result("--hostでMac Hubのaddressを指定してください");
    }
    if (!bridge_id_provided) {
        return error_result("--bridge-idを指定してください");
    }
    if (!tracking_space_id_provided) {
        return error_result("--tracking-space-idを指定してください");
    }

    OpenVrBridgeOptionsResult result;
    result.options = std::move(options);
    return result;
}

std::string openvr_bridge_usage() {
    std::ostringstream output;
    output << "divive-openvr-bridge [options]\n\n"
           << "Windows上のOpenVR Tracker姿勢をMac HubへUDP送信します。\n"
           << "SteamVRはBridge起動前に起動してください。\n\n"
           << "Required:\n"
           << "  --host <address>            Mac HubのIPv4/IPv6 address\n"
           << "  --bridge-id <uuid>          Bridge installationの固定UUID\n"
           << "  --tracking-space-id <uuid>  追跡空間の固定UUID\n\n"
           << "Options:\n"
           << "  --port <port>               Hub UDP port。既定: 41320\n"
           << "  --rate <hz>                 60 | 90 | 120。既定: 90\n"
           << "  --duration <seconds>        0はCtrl+Cまで。既定: 0\n"
           << "  --prediction-seconds <sec>  OpenVR pose予測時間。既定: 0\n"
           << "  --inventory-interval <sec>  property更新間隔。既定: 1\n"
           << "  --origin <value>            standing | seated | raw。"
              "既定: standing\n"
           << "  --space-epoch <number>      追跡空間の世代。既定: 1\n"
           << "  --send-buffer <bytes>       socket送信buffer。既定: 262144\n"
           << "  --help, -h                  このhelpを表示\n";
    return output.str();
}

} // namespace divive::bridge
