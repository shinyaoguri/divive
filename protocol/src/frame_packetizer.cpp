#include "divive/protocol/frame_packetizer.hpp"

#include <array>
#include <cstdint>
#include <limits>
#include <utility>

namespace divive::protocol {
namespace {

[[nodiscard]] PoseBatch metadata_only(const PoseBatch& frame) {
    PoseBatch batch;
    batch.tracking_space_id = frame.tracking_space_id;
    batch.space_epoch = frame.space_epoch;
    batch.capture_monotonic_ns = frame.capture_monotonic_ns;
    batch.send_monotonic_ns = frame.send_monotonic_ns;
    batch.requested_rate_hz = frame.requested_rate_hz;
    batch.backend = frame.backend;
    return batch;
}

[[nodiscard]] FramePacketizerResult pose_error_result(const PoseCodecError error) {
    return {
        .error = FramePacketizerError::pose_codec_error,
        .pose_error = error,
    };
}

} // namespace

FramePacketizerResult packetize_pose_frame(const Envelope& base_envelope,
                                           const PoseBatch& frame) {
    std::vector<PoseBatch> batches;
    auto current = metadata_only(frame);

    if (frame.trackers.empty()) {
        const auto encoded = encode_pose_batch(current);
        if (!encoded) {
            return pose_error_result(encoded.error);
        }
        if (encoded.payload.size() > kMaxPayloadSize) {
            return {.error = FramePacketizerError::tracker_too_large};
        }
        batches.push_back(std::move(current));
    } else {
        for (const auto& tracker : frame.trackers) {
            current.trackers.push_back(tracker);
            const auto encoded = encode_pose_batch(current);
            if (!encoded) {
                return pose_error_result(encoded.error);
            }
            if (encoded.payload.size() <= kMaxPayloadSize) {
                continue;
            }

            current.trackers.pop_back();
            if (current.trackers.empty()) {
                return {.error = FramePacketizerError::tracker_too_large};
            }
            batches.push_back(std::move(current));

            current = metadata_only(frame);
            current.trackers.push_back(tracker);
            const auto single = encode_pose_batch(current);
            if (!single) {
                return pose_error_result(single.error);
            }
            if (single.payload.size() > kMaxPayloadSize) {
                return {.error = FramePacketizerError::tracker_too_large};
            }
        }
        batches.push_back(std::move(current));
    }

    if (batches.size() > std::numeric_limits<std::uint16_t>::max()) {
        return {.error = FramePacketizerError::too_many_batches};
    }

    FramePacketizerResult result;
    result.datagrams.reserve(batches.size());
    const auto batch_count = static_cast<std::uint16_t>(batches.size());

    for (std::size_t index = 0; index < batches.size(); ++index) {
        const auto encoded = encode_pose_batch(batches[index]);
        if (!encoded) {
            return pose_error_result(encoded.error);
        }

        auto envelope = base_envelope;
        envelope.batch_index = static_cast<std::uint16_t>(index);
        envelope.batch_count = batch_count;

        std::array<std::byte, kMaxDatagramSize> storage{};
        std::size_t written = 0;
        const auto packet_error =
            encode_packet(envelope, encoded.payload, storage, written);
        if (packet_error != PacketError::none) {
            return {
                .error = FramePacketizerError::packet_error,
                .packet_error = packet_error,
            };
        }

        result.datagrams.emplace_back(storage.begin(), storage.begin() + written);
    }

    return result;
}

std::string_view to_string(const FramePacketizerError error) noexcept {
    switch (error) {
    case FramePacketizerError::none:
        return "none";
    case FramePacketizerError::pose_codec_error:
        return "pose_codec_error";
    case FramePacketizerError::tracker_too_large:
        return "tracker_too_large";
    case FramePacketizerError::too_many_batches:
        return "too_many_batches";
    case FramePacketizerError::packet_error:
        return "packet_error";
    }
    return "unknown";
}

} // namespace divive::protocol
