#pragma once

#include "divive/protocol/envelope.hpp"
#include "divive/protocol/pose_codec.hpp"

#include <cstddef>
#include <string_view>
#include <vector>

namespace divive::protocol {

enum class FramePacketizerError {
    none,
    pose_codec_error,
    tracker_too_large,
    too_many_batches,
    packet_error,
};

struct FramePacketizerResult {
    FramePacketizerError error{FramePacketizerError::none};
    PoseCodecError pose_error{PoseCodecError::none};
    PacketError packet_error{PacketError::none};
    std::vector<std::vector<std::byte>> datagrams;

    [[nodiscard]] explicit operator bool() const noexcept {
        return error == FramePacketizerError::none;
    }
};

/// Tracker順を保ったgreedy分割で、1 capture frameを1,200-byte以下へpacketizeする。
///
/// `base_envelope`のbatch index/countは無視し、生成したdatagram数から設定する。
/// 入力Trackerが0件でも、frame metadataを伝える1 batchを生成する。
[[nodiscard]] FramePacketizerResult packetize_pose_frame(const Envelope& base_envelope,
                                                         const PoseBatch& frame);

[[nodiscard]] std::string_view to_string(FramePacketizerError error) noexcept;

} // namespace divive::protocol
