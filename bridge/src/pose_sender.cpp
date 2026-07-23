#include "divive/bridge/pose_sender.hpp"

#include <atomic>
#include <chrono>
#include <mutex>
#include <system_error>
#include <thread>
#include <utility>

namespace divive::bridge {
namespace {

using PoseMailbox = LatestValueMailbox<protocol::PoseBatch>;

} // namespace

struct PoseSender::Impl {
    mutable std::mutex lifecycle_mutex;
    std::shared_ptr<PoseMailbox> mailbox;
    std::thread worker;
    UdpPublisher publisher;

    std::atomic<bool> running{false};
    std::atomic<std::uint64_t> submitted_frames{0};
    std::atomic<std::uint64_t> overwritten_frames{0};
    std::atomic<std::uint64_t> rejected_frames{0};
    std::atomic<std::uint64_t> sent_frames{0};
    std::atomic<std::uint64_t> sent_datagrams{0};
    std::atomic<std::uint64_t> sent_bytes{0};

    mutable std::mutex error_mutex;
    PoseSenderRuntimeError last_error{PoseSenderRuntimeError::none};
    protocol::FramePacketizerError packetizer_error{
        protocol::FramePacketizerError::none};
    protocol::PoseCodecError pose_codec_error{protocol::PoseCodecError::none};
    protocol::PacketError packet_error{protocol::PacketError::none};
    UdpPublisherError publisher_error{UdpPublisherError::none};
    int system_error{0};

    void reset_stats() {
        submitted_frames = 0;
        overwritten_frames = 0;
        rejected_frames = 0;
        sent_frames = 0;
        sent_datagrams = 0;
        sent_bytes = 0;
        std::lock_guard lock(error_mutex);
        last_error = PoseSenderRuntimeError::none;
        packetizer_error = protocol::FramePacketizerError::none;
        pose_codec_error = protocol::PoseCodecError::none;
        packet_error = protocol::PacketError::none;
        publisher_error = UdpPublisherError::none;
        system_error = 0;
    }

    void record_packetize_error(const protocol::FramePacketizerResult& packetized) {
        std::lock_guard lock(error_mutex);
        last_error = PoseSenderRuntimeError::packetize_failed;
        packetizer_error = packetized.error;
        pose_codec_error = packetized.pose_error;
        packet_error = packetized.packet_error;
    }

    void record_send_error(const UdpPublisherResult& sent) {
        std::lock_guard lock(error_mutex);
        last_error = PoseSenderRuntimeError::send_failed;
        publisher_error = sent.error;
        system_error = sent.system_error;
    }

    void send_loop(const std::shared_ptr<PoseMailbox>& channel,
                   const PoseSenderConfig config) {
        auto envelope = config.envelope;
        auto next_sequence = envelope.frame_sequence;

        while (auto frame = channel->wait_take()) {
            frame->send_monotonic_ns = monotonic_now_ns();
            envelope.frame_sequence = next_sequence;

            const auto packetized = protocol::packetize_pose_frame(envelope, *frame);
            if (!packetized) {
                record_packetize_error(packetized);
                break;
            }

            bool frame_sent = true;
            for (const auto& datagram : packetized.datagrams) {
                const auto sent = publisher.send(datagram);
                if (!sent) {
                    record_send_error(sent);
                    frame_sent = false;
                    break;
                }
                ++sent_datagrams;
                sent_bytes += sent.bytes_sent;
            }
            if (!frame_sent) {
                break;
            }

            ++sent_frames;
            ++next_sequence;
        }

        channel->close();
        publisher.close();
        running = false;
    }
};

PoseSender::PoseSender() : impl_(std::make_unique<Impl>()) {}

PoseSender::~PoseSender() {
    stop();
}

PoseSenderStartResult PoseSender::start(const PoseSenderConfig& config) {
    stop();
    impl_->reset_stats();

    if (protocol::is_nil_uuid(config.envelope.session_id) ||
        protocol::is_nil_uuid(config.envelope.bridge_id)) {
        return {.error = PoseSenderStartError::invalid_identity};
    }

    const auto opened = impl_->publisher.open(config.publisher);
    if (!opened) {
        return {
            .error = PoseSenderStartError::publisher_open_failed,
            .publisher_result = opened,
            .system_error = opened.system_error,
        };
    }

    auto channel = std::make_shared<PoseMailbox>();
    {
        std::lock_guard lock(impl_->lifecycle_mutex);
        impl_->mailbox = channel;
        impl_->running = true;
        try {
            impl_->worker = std::thread(
                [this, channel, config] { impl_->send_loop(channel, config); });
        } catch (const std::system_error& error) {
            impl_->running = false;
            impl_->mailbox.reset();
            impl_->publisher.close();
            return {
                .error = PoseSenderStartError::thread_start_failed,
                .system_error = error.code().value(),
            };
        }
    }

    return {};
}

void PoseSender::stop() {
    std::shared_ptr<PoseMailbox> channel;
    std::thread worker;
    {
        std::lock_guard lock(impl_->lifecycle_mutex);
        impl_->running = false;
        channel = impl_->mailbox;
        if (impl_->worker.joinable()) {
            worker = std::move(impl_->worker);
        }
    }

    if (channel) {
        channel->close();
    }
    if (worker.joinable()) {
        worker.join();
    }

    {
        std::lock_guard lock(impl_->lifecycle_mutex);
        if (impl_->mailbox == channel) {
            impl_->mailbox.reset();
        }
    }
    impl_->publisher.close();
}

PoseSenderSubmitResult PoseSender::submit(protocol::PoseBatch frame) {
    std::shared_ptr<PoseMailbox> channel;
    {
        std::lock_guard lock(impl_->lifecycle_mutex);
        if (!impl_->running || !impl_->mailbox) {
            ++impl_->rejected_frames;
            return PoseSenderSubmitResult::not_running;
        }
        channel = impl_->mailbox;
    }

    const auto published = channel->publish(std::move(frame));
    switch (published) {
    case LatestValuePublishResult::accepted:
        ++impl_->submitted_frames;
        return PoseSenderSubmitResult::accepted;
    case LatestValuePublishResult::overwritten:
        ++impl_->submitted_frames;
        ++impl_->overwritten_frames;
        return PoseSenderSubmitResult::overwritten;
    case LatestValuePublishResult::closed:
        ++impl_->rejected_frames;
        return PoseSenderSubmitResult::closed;
    }
    ++impl_->rejected_frames;
    return PoseSenderSubmitResult::closed;
}

bool PoseSender::is_running() const noexcept {
    return impl_->running;
}

PoseSenderStats PoseSender::stats() const {
    PoseSenderStats result{
        .submitted_frames = impl_->submitted_frames.load(),
        .overwritten_frames = impl_->overwritten_frames.load(),
        .rejected_frames = impl_->rejected_frames.load(),
        .sent_frames = impl_->sent_frames.load(),
        .sent_datagrams = impl_->sent_datagrams.load(),
        .sent_bytes = impl_->sent_bytes.load(),
        .running = impl_->running.load(),
    };
    std::lock_guard lock(impl_->error_mutex);
    result.last_error = impl_->last_error;
    result.packetizer_error = impl_->packetizer_error;
    result.pose_codec_error = impl_->pose_codec_error;
    result.packet_error = impl_->packet_error;
    result.publisher_error = impl_->publisher_error;
    result.system_error = impl_->system_error;
    return result;
}

std::uint64_t monotonic_now_ns() noexcept {
    const auto elapsed = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(elapsed).count());
}

std::string_view to_string(const PoseSenderStartError error) noexcept {
    switch (error) {
    case PoseSenderStartError::none:
        return "none";
    case PoseSenderStartError::invalid_identity:
        return "invalid_identity";
    case PoseSenderStartError::publisher_open_failed:
        return "publisher_open_failed";
    case PoseSenderStartError::thread_start_failed:
        return "thread_start_failed";
    }
    return "unknown";
}

std::string_view to_string(const PoseSenderSubmitResult result) noexcept {
    switch (result) {
    case PoseSenderSubmitResult::accepted:
        return "accepted";
    case PoseSenderSubmitResult::overwritten:
        return "overwritten";
    case PoseSenderSubmitResult::not_running:
        return "not_running";
    case PoseSenderSubmitResult::closed:
        return "closed";
    }
    return "unknown";
}

std::string_view to_string(const PoseSenderRuntimeError error) noexcept {
    switch (error) {
    case PoseSenderRuntimeError::none:
        return "none";
    case PoseSenderRuntimeError::packetize_failed:
        return "packetize_failed";
    case PoseSenderRuntimeError::send_failed:
        return "send_failed";
    }
    return "unknown";
}

} // namespace divive::bridge
