import HubProtocol

public struct TrackerHistorySample: Equatable, Identifiable, Sendable {
  public let sampledAtNS: UInt64
  public let trackingState: TrackingState
  public let frameSequence: UInt64
  /// 前回のGUI sample以降にSource全体で検出した欠落frame数。
  public let frameLossCount: UInt64
  /// 前回のGUI sample以降にHubへ適用したframe数。
  public let deliveredFrameCount: UInt64

  public var id: UInt64 { sampledAtNS }
}

struct TrackerQualitySummary: Equatable, Sendable {
  let frameLossCount: UInt64
  let deliveredFrameCount: UInt64
  let trackingLossDurationNS: UInt64
  let observedDurationNS: UInt64

  var totalFrameCount: UInt64 {
    frameLossCount + deliveredFrameCount
  }

  var frameLossPercent: Double {
    guard totalFrameCount > 0 else { return 0 }
    return Double(frameLossCount) / Double(totalFrameCount) * 100
  }

  var trackingLossPercent: Double {
    guard observedDurationNS > 0 else { return 0 }
    return
      Double(trackingLossDurationNS) / Double(observedDurationNS) * 100
  }

  init(samples: [TrackerHistorySample]) {
    // 先頭sampleのcounter差分は表示窓より前の区間を含み得るため、
    // timestamp間を観測できる2点目以降だけを割合の分子・分母に使う。
    frameLossCount = samples.dropFirst().reduce(0) {
      $0 + $1.frameLossCount
    }
    deliveredFrameCount = samples.dropFirst().reduce(0) {
      $0 + $1.deliveredFrameCount
    }

    var observedDurationNS: UInt64 = 0
    var trackingLossDurationNS: UInt64 = 0
    for index in 0..<max(0, samples.count - 1) {
      let sample = samples[index]
      let nextSample = samples[index + 1]
      guard nextSample.sampledAtNS >= sample.sampledAtNS else {
        continue
      }
      let durationNS = nextSample.sampledAtNS - sample.sampledAtNS
      observedDurationNS += durationNS
      if !sample.trackingState.hasUsablePoseForHistory {
        trackingLossDurationNS += durationNS
      }
    }
    self.observedDurationNS = observedDurationNS
    self.trackingLossDurationNS = trackingLossDurationNS
  }
}

struct TrackerHistoryBuffer {
  private let capacity: Int
  private(set) var samplesByTrackerID: [String: [TrackerHistorySample]] = [:]
  private var previousCumulativeFrameLoss: UInt64?
  private var previousCumulativeDeliveredFrames: UInt64?

  init(capacity: Int = 61) {
    precondition(capacity > 0)
    self.capacity = capacity
  }

  mutating func reset() {
    samplesByTrackerID.removeAll(keepingCapacity: true)
    previousCumulativeFrameLoss = nil
    previousCumulativeDeliveredFrames = nil
  }

  mutating func record(
    trackers: [TrackerDisplayState],
    sampledAtNS: UInt64,
    cumulativeFrameLoss: UInt64 = 0,
    cumulativeDeliveredFrames: UInt64 = 0
  ) {
    let frameLossCount = counterDelta(
      current: cumulativeFrameLoss,
      previous: previousCumulativeFrameLoss
    )
    let deliveredFrameCount = counterDelta(
      current: cumulativeDeliveredFrames,
      previous: previousCumulativeDeliveredFrames
    )
    previousCumulativeFrameLoss = cumulativeFrameLoss
    previousCumulativeDeliveredFrames = cumulativeDeliveredFrames

    let activeIDs = Set(trackers.map(\.id))
    samplesByTrackerID = samplesByTrackerID.filter {
      activeIDs.contains($0.key)
    }

    for tracker in trackers {
      var samples = samplesByTrackerID[tracker.id, default: []]
      if let latest = samples.last,
        tracker.frameSequence < latest.frameSequence
      {
        samples.removeAll(keepingCapacity: true)
      }
      if let latest = samples.last,
        latest.frameSequence == tracker.frameSequence,
        latest.trackingState == tracker.trackingState,
        frameLossCount == 0,
        deliveredFrameCount == 0,
        tracker.trackingState.hasUsablePoseForHistory
      {
        continue
      }

      samples.append(
        TrackerHistorySample(
          sampledAtNS: sampledAtNS,
          trackingState: tracker.trackingState,
          frameSequence: tracker.frameSequence,
          frameLossCount: frameLossCount,
          deliveredFrameCount: deliveredFrameCount
        )
      )
      if samples.count > capacity {
        samples.removeFirst(samples.count - capacity)
      }
      samplesByTrackerID[tracker.id] = samples
    }
  }

  private func counterDelta(
    current: UInt64,
    previous: UInt64?
  ) -> UInt64 {
    guard let previous, current >= previous else {
      // Source開始直後、またはcounter reset後の値も取りこぼさない。
      return current
    }
    return current - previous
  }
}

extension TrackingState {
  fileprivate var hasUsablePoseForHistory: Bool {
    self == .tracking || self == .simulated
  }
}
