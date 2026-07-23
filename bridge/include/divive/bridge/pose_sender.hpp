#pragma once

#include "divive/bridge/latest_value_mailbox.hpp"
#include "divive/bridge/udp_publisher.hpp"
#include "divive/protocol/frame_packetizer.hpp"
#include "divive/protocol/pose_codec.hpp"

#include <cstdint>
#include <memory>
#include <string_view>

namespace divive::bridge {

struct PoseSenderConfig {
    UdpPublisherConfig publisher;
    protocol::Envelope envelope;
};

enum class PoseSenderStartError {
    none,
    invalid_identity,
    publisher_open_failed,
    thread_start_failed,
};

struct PoseSenderStartResult {
    PoseSenderStartError error{PoseSenderStartError::none};
    UdpPublisherResult publisher_result;
    int system_error{0};

    [[nodiscard]] explicit operator bool() const noexcept {
        return error == PoseSenderStartError::none;
    }
};

enum class PoseSenderSubmitResult {
    accepted,
    overwritten,
    not_running,
    closed,
};

enum class PoseSenderRuntimeError {
    none,
    packetize_failed,
    send_failed,
};

struct PoseSenderStats {
    std::uint64_t submitted_frames{0};
    std::uint64_t overwritten_frames{0};
    std::uint64_t rejected_frames{0};
    std::uint64_t sent_frames{0};
    std::uint64_t sent_datagrams{0};
    std::uint64_t sent_bytes{0};
    PoseSenderRuntimeError last_error{PoseSenderRuntimeError::none};
    protocol::FramePacketizerError packetizer_error{
        protocol::FramePacketizerError::none};
    protocol::PoseCodecError pose_codec_error{protocol::PoseCodecError::none};
    protocol::PacketError packet_error{protocol::PacketError::none};
    UdpPublisherError publisher_error{UdpPublisherError::none};
    int system_error{0};
    bool running{false};
};

/// capacity 1のlatest-value mailboxから姿勢を取得し、専用threadでUDP送信する。
///
/// `submit()`はsocket I/Oを行わず、未送信frameがあれば上書きする。wire sequenceと
/// send timestampは送信threadが付与するため、送信前に上書きしたframeはHub側の
/// packet lossとして数えられない。
class PoseSender {
  public:
    PoseSender();
    ~PoseSender();

    PoseSender(const PoseSender&) = delete;
    PoseSender& operator=(const PoseSender&) = delete;
    PoseSender(PoseSender&&) = delete;
    PoseSender& operator=(PoseSender&&) = delete;

    /// lifecycle操作は1本のcontrol threadから直列に呼ぶ。
    [[nodiscard]] PoseSenderStartResult start(const PoseSenderConfig& config);
    void stop();

    /// capture threadからmoveして渡す。`start()`と`stop()`との並行呼出しは許容する。
    [[nodiscard]] PoseSenderSubmitResult submit(protocol::PoseBatch frame);

    [[nodiscard]] bool is_running() const noexcept;
    [[nodiscard]] PoseSenderStats stats() const;

  private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

/// 同一process内のcapture/send durationに利用するsteady clock値。
[[nodiscard]] std::uint64_t monotonic_now_ns() noexcept;

[[nodiscard]] std::string_view to_string(PoseSenderStartError error) noexcept;
[[nodiscard]] std::string_view to_string(PoseSenderSubmitResult result) noexcept;
[[nodiscard]] std::string_view to_string(PoseSenderRuntimeError error) noexcept;

} // namespace divive::bridge
