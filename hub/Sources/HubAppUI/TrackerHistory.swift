import HubProtocol

public struct TrackerHistorySample: Equatable, Identifiable, Sendable {
  public let sampledAtNS: UInt64
  public let position: Vector3
  public let trackingState: TrackingState
  public let frameSequence: UInt64

  public var id: UInt64 { sampledAtNS }
}

struct TrackerHistoryBuffer {
  private let capacity: Int
  private(set) var samplesByTrackerID: [String: [TrackerHistorySample]] = [:]

  init(capacity: Int = 61) {
    precondition(capacity > 0)
    self.capacity = capacity
  }

  mutating func reset() {
    samplesByTrackerID.removeAll(keepingCapacity: true)
  }

  mutating func record(
    trackers: [TrackerDisplayState],
    sampledAtNS: UInt64
  ) {
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
        latest.trackingState == tracker.trackingState
      {
        continue
      }

      samples.append(
        TrackerHistorySample(
          sampledAtNS: sampledAtNS,
          position: tracker.position,
          trackingState: tracker.trackingState,
          frameSequence: tracker.frameSequence
        )
      )
      if samples.count > capacity {
        samples.removeFirst(samples.count - capacity)
      }
      samplesByTrackerID[tracker.id] = samples
    }
  }
}
