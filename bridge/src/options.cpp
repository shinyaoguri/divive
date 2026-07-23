#include "divive/probe/options.hpp"

#include <charconv>
#include <cmath>
#include <sstream>
#include <system_error>

namespace divive::probe {
namespace {

std::optional<double> parse_number(const std::string_view value) {
    double result = 0.0;
    const auto* begin = value.data();
    const auto* end = value.data() + value.size();
    const auto parsed = std::from_chars(begin, end, result);
    if (parsed.ec != std::errc{} || parsed.ptr != end || !std::isfinite(result)) {
        return std::nullopt;
    }
    return result;
}

ParseResult error_result(std::string message) {
    ParseResult result;
    result.error = std::move(message);
    return result;
}

} // namespace

ParseResult parse_options(const std::vector<std::string_view>& arguments) {
    Options options;

    for (std::size_t index = 0; index < arguments.size(); ++index) {
        const auto argument = arguments[index];

        if (argument == "--help" || argument == "-h") {
            ParseResult result;
            result.show_help = true;
            return result;
        }
        if (argument == "--trackers-only") {
            options.trackers_only = true;
            continue;
        }
        if (argument == "--all-devices") {
            options.trackers_only = false;
            continue;
        }

        if (index + 1 >= arguments.size()) {
            return error_result("optionに値が必要です: " + std::string(argument));
        }
        const auto value = arguments[++index];

        if (argument == "--rate") {
            const auto parsed = parse_number(value);
            if (!parsed || *parsed < 1.0 || *parsed > 1000.0) {
                return error_result("--rateは1〜1000の範囲で指定してください");
            }
            options.rate_hz = *parsed;
        } else if (argument == "--duration") {
            const auto parsed = parse_number(value);
            if (!parsed || *parsed < 0.0 || *parsed > 604800.0) {
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
            if (!parsed || *parsed < 0.0 || *parsed > 3600.0) {
                return error_result(
                    "--inventory-intervalは0〜3600秒の範囲で指定してください");
            }
            options.inventory_interval_seconds = *parsed;
        } else if (argument == "--origin") {
            if (value == "standing") {
                options.origin = Origin::standing;
            } else if (value == "seated") {
                options.origin = Origin::seated;
            } else if (value == "raw") {
                options.origin = Origin::raw;
            } else {
                return error_result("--originはstanding、seated、rawのいずれかです");
            }
        } else if (argument == "--output") {
            if (value.empty()) {
                return error_result("--outputに空文字列は指定できません");
            }
            options.output = value;
        } else {
            return error_result("不明なoptionです: " + std::string(argument));
        }
    }

    ParseResult result;
    result.options = std::move(options);
    return result;
}

std::string usage() {
    std::ostringstream output;
    output << "divive-openvr-probe [options]\n\n"
           << "Windows上のOpenVR deviceとposeをJSONLへ記録します。\n"
           << "SteamVRはprobe起動前に起動してください。\n\n"
           << "Options:\n"
           << "  --rate <hz>                 poll頻度。既定: 120\n"
           << "  --duration <seconds>        実行時間。0はCtrl+Cまで。既定: 30\n"
           << "  --prediction-seconds <sec>  OpenVR pose予測時間。既定: 0\n"
           << "  --inventory-interval <sec>  device情報の再出力間隔。"
              "0は開始時だけ。既定: 1\n"
           << "  --origin <value>            standing | seated | raw。"
              "既定: standing\n"
           << "  --trackers-only             GenericTrackerだけを記録\n"
           << "  --all-devices               全deviceを記録。既定値\n"
           << "  --output <path|->           JSONL出力先。-はstdout。既定: -\n"
           << "  --help, -h                  このhelpを表示\n";
    return output.str();
}

} // namespace divive::probe
