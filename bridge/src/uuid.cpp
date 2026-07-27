#include "divive/bridge/uuid.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <random>

namespace divive::bridge {
namespace {

[[nodiscard]] std::optional<std::uint8_t> hex_value(const char value) noexcept {
    if (value >= '0' && value <= '9') {
        return static_cast<std::uint8_t>(value - '0');
    }
    if (value >= 'a' && value <= 'f') {
        return static_cast<std::uint8_t>(value - 'a' + 10);
    }
    if (value >= 'A' && value <= 'F') {
        return static_cast<std::uint8_t>(value - 'A' + 10);
    }
    return std::nullopt;
}

} // namespace

std::optional<protocol::UuidBytes> parse_uuid(const std::string_view value) noexcept {
    if (value.size() != 36U || value[8] != '-' || value[13] != '-' ||
        value[18] != '-' || value[23] != '-') {
        return std::nullopt;
    }

    protocol::UuidBytes result{};
    std::size_t input_index = 0;
    std::size_t output_index = 0;
    while (input_index < value.size()) {
        if (value[input_index] == '-') {
            ++input_index;
            continue;
        }
        if (input_index + 1U >= value.size() || output_index >= result.size()) {
            return std::nullopt;
        }
        const auto high = hex_value(value[input_index]);
        const auto low = hex_value(value[input_index + 1U]);
        if (!high || !low) {
            return std::nullopt;
        }
        result[output_index++] =
            static_cast<std::byte>((static_cast<std::uint16_t>(*high) << 4U) | *low);
        input_index += 2U;
    }

    if (output_index != result.size() || protocol::is_nil_uuid(result)) {
        return std::nullopt;
    }
    return result;
}

protocol::UuidBytes generate_random_uuid() {
    std::random_device source;
    protocol::UuidBytes result{};
    for (auto& value : result) {
        value = static_cast<std::byte>(source() & 0xFFU);
    }
    // RFC 4122 version 4、variant 1。
    result[6] = (result[6] & std::byte{0x0F}) | std::byte{0x40};
    result[8] = (result[8] & std::byte{0x3F}) | std::byte{0x80};
    return result;
}

std::string format_uuid(const protocol::UuidBytes& value) {
    constexpr std::array<char, 16> digits{
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
    };

    std::string result;
    result.reserve(36);
    for (std::size_t index = 0; index < value.size(); ++index) {
        if (index == 4U || index == 6U || index == 8U || index == 10U) {
            result.push_back('-');
        }
        const auto byte = std::to_integer<std::uint8_t>(value[index]);
        result.push_back(digits[(byte >> 4U) & 0x0FU]);
        result.push_back(digits[byte & 0x0FU]);
    }
    return result;
}

} // namespace divive::bridge
