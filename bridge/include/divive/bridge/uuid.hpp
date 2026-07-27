#pragma once

#include "divive/protocol/envelope.hpp"

#include <optional>
#include <string>
#include <string_view>

namespace divive::bridge {

/// RFC 4122のcanonical表記を16 byteへ変換する。
[[nodiscard]] std::optional<protocol::UuidBytes>
parse_uuid(std::string_view value) noexcept;

/// process/session識別用のversion 4 UUIDを生成する。
[[nodiscard]] protocol::UuidBytes generate_random_uuid();

[[nodiscard]] std::string format_uuid(const protocol::UuidBytes& value);

} // namespace divive::bridge
