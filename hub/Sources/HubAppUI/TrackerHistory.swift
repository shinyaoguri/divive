import HubProtocol

public struct TrackerHistorySample: Equatable, Identifiable, Sendable {
  public let sampledAtNS: UInt64
  public let trackingState: TrackingState
  public let frameSequence: UInt64
  /// 前回のGUI sample以降にSource全体で検出した欠落frame数。
  public let frameLossCount: UInt64

  public var id: UInt64 { sampledAtNS }
}

struct TrackerHistoryBuffer {
  private let capacity: Int
  private(set) var samplesByTrackerID: [String: [TrackerHistorySample]] = [:]
  private var previousCumulativeFrameLoss: UInt64?

  init(capacity: Int = 61) {
    precondition(capacity > 0)
    self.capacity = capacity
  }

  mutating func reset() {
    samplesByTrackerID.removeAll(keepingCapacity: true)
    previousCumulativeFrameLoss = nil
  }

  mutating func record(
    trackers: [TrackerDisplayState],
    sampledAtNS: UInt64,
    cumulativeFrameLoss: UInt64 = 0
  ) {
    let frameLossCount: UInt64
    if let previousCumulativeFrameLoss,
      cumulativeFrameLoss >= previousCumulativeFrameLoss
    {
      frameLossCount =
        cumulativeFrameLoss - previousCumulativeFrameLoss
    } else {
      // Source開始直後、またはcounter reset後の値も取りこぼさない。
      frameLossCount = cumulativeFrameLoss
    }
    previousCumulativeFrameLoss = cumulativeFrameLoss

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
        tracker.trackingState.hasUsablePoseForHistory
      {
        continue
      }

      samples.append(
        TrackerHistorySample(
          sampledAtNS: sampledAtNS,
          trackingState: tracker.trackingState,
          frameSequence: tracker.frameSequence,
          frameLossCount: frameLossCount
        )
      )
      if samples.count > capacity {
        samples.removeFirst(samples.count - capacity)
      }
      samplesByTrackerID[tracker.id] = samples
    }
  }
}

extension TrackingState {
  fileprivate var hasUsablePoseForHistory: Bool {
    self == .tracking || self == .simulated
  }
}
