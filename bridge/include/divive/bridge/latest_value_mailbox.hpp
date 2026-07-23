#pragma once

#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <optional>
#include <type_traits>
#include <utility>

namespace divive::bridge {

enum class LatestValuePublishResult {
    accepted,
    overwritten,
    closed,
};

struct LatestValueMailboxStats {
    std::uint64_t published{0};
    std::uint64_t consumed{0};
    std::uint64_t overwritten{0};
    bool has_pending_value{false};
    bool closed{false};
};

/// producerとconsumerの間で未処理の最新値を1つだけ保持するmailbox。
///
/// consumerが遅い場合は古い未処理値を新しい値で上書きし、producerを待たせない。
/// `close()`後もclose時点の最新値はconsumerが1回取得できる。
template <typename T> class LatestValueMailbox {
    static_assert(std::is_move_constructible_v<T>,
                  "LatestValueMailboxの値はmove constructibleである必要があります");

  public:
    LatestValueMailbox() = default;

    LatestValueMailbox(const LatestValueMailbox&) = delete;
    LatestValueMailbox& operator=(const LatestValueMailbox&) = delete;

    [[nodiscard]] LatestValuePublishResult publish(T value) {
        std::unique_lock lock(mutex_);
        if (closed_) {
            return LatestValuePublishResult::closed;
        }

        const auto overwritten = pending_.has_value();
        pending_.reset();
        pending_.emplace(std::move(value));
        ++published_;
        if (overwritten) {
            ++overwritten_;
        }

        lock.unlock();
        available_.notify_one();
        return overwritten ? LatestValuePublishResult::overwritten
                           : LatestValuePublishResult::accepted;
    }

    /// 値が届くかmailboxがcloseされるまで待つ。
    ///
    /// close時に未処理値があればその値を返し、次の呼出しで`std::nullopt`を返す。
    [[nodiscard]] std::optional<T> wait_take() {
        std::unique_lock lock(mutex_);
        available_.wait(lock, [this] { return closed_ || pending_.has_value(); });
        if (!pending_) {
            return std::nullopt;
        }

        std::optional<T> value{std::move(*pending_)};
        pending_.reset();
        ++consumed_;
        return value;
    }

    void close() {
        std::unique_lock lock(mutex_);
        if (closed_) {
            return;
        }
        closed_ = true;
        lock.unlock();
        available_.notify_all();
    }

    [[nodiscard]] LatestValueMailboxStats stats() const {
        std::lock_guard lock(mutex_);
        return {
            .published = published_,
            .consumed = consumed_,
            .overwritten = overwritten_,
            .has_pending_value = pending_.has_value(),
            .closed = closed_,
        };
    }

  private:
    mutable std::mutex mutex_;
    std::condition_variable available_;
    std::optional<T> pending_;
    std::uint64_t published_{0};
    std::uint64_t consumed_{0};
    std::uint64_t overwritten_{0};
    bool closed_{false};
};

} // namespace divive::bridge
