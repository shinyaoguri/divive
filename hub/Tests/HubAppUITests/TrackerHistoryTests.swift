import HubCore
import HubProtocol
import XCTest

@testable import HubAppUI

final class TrackerHistoryTests: XCTestCase {
  func test新しいframeだけを上限件数まで記録する() {
    var buffer = TrackerHistoryBuffer(capacity: 3)

    for sequence in 1...4 {
      buffer.record(
        trackers: [tracker(sequence: UInt64(sequence))],
        sampledAtNS: UInt64(sequence) * 100
      )
    }
    buffer.record(
      trackers: [tracker(sequence: 4)],
      sampledAtNS: 500
    )

    let samples = buffer.samplesByTrackerID["tracker-1"]
    XCTAssertEqual(samples?.map(\.frameSequence), [2, 3, 4])
    XCTAssertEqual(samples?.map(\.sampledAtNS), [200, 300, 400])
  }

  func test追跡状態の変化は同じframeでも記録する() {
    var buffer = TrackerHistoryBuffer(capacity: 3)

    buffer.record(
      trackers: [tracker(sequence: 1, state: .tracking)],
      sampledAtNS: 100
    )
    buffer.record(
      trackers: [tracker(sequence: 1, state: .lost)],
      sampledAtNS: 200
    )

    XCTAssertEqual(
      buffer.samplesByTrackerID["tracker-1"]?.map(\.trackingState),
      [.tracking, .lost]
    )
  }

  func test追跡喪失中は同じframeでも時系列sampleを継続する() {
    var buffer = TrackerHistoryBuffer()

    buffer.record(
      trackers: [tracker(sequence: 1, state: .lost)],
      sampledAtNS: 100
    )
    buffer.record(
      trackers: [tracker(sequence: 1, state: .lost)],
      sampledAtNS: 200
    )

    XCTAssertEqual(
      buffer.samplesByTrackerID["tracker-1"]?.map(\.sampledAtNS),
      [100, 200]
    )
  }

  func test累積欠落数をGUI区間ごとの差分として記録する() {
    var buffer = TrackerHistoryBuffer()

    buffer.record(
      trackers: [tracker(sequence: 1)],
      sampledAtNS: 100,
      cumulativeFrameLoss: 2
    )
    buffer.record(
      trackers: [tracker(sequence: 2)],
      sampledAtNS: 200,
      cumulativeFrameLoss: 5
    )
    buffer.record(
      trackers: [tracker(sequence: 3)],
      sampledAtNS: 300,
      cumulativeFrameLoss: 1
    )

    XCTAssertEqual(
      buffer.samplesByTrackerID["tracker-1"]?.map(\.frameLossCount),
      [2, 3, 1]
    )
  }

  func test同じTrackerFrameでもSourceのFrame更新を記録する() {
    var buffer = TrackerHistoryBuffer()

    buffer.record(
      trackers: [tracker(sequence: 1)],
      sampledAtNS: 100,
      cumulativeDeliveredFrames: 1
    )
    buffer.record(
      trackers: [tracker(sequence: 1)],
      sampledAtNS: 200,
      cumulativeDeliveredFrames: 2
    )

    let samples = buffer.samplesByTrackerID["tracker-1"]
    XCTAssertEqual(samples?.map(\.sampledAtNS), [100, 200])
    XCTAssertEqual(samples?.map(\.deliveredFrameCount), [1, 1])
  }

  func test直近品質の欠落率と追跡喪失時間率を計算する() {
    let summary = TrackerQualitySummary(
      samples: [
        sample(
          at: 0,
          state: .tracking
        ),
        sample(
          at: 1_000_000_000,
          state: .lost,
          frameLossCount: 2,
          deliveredFrameCount: 8
        ),
        sample(
          at: 3_000_000_000,
          state: .lost,
          frameLossCount: 3,
          deliveredFrameCount: 7
        ),
        sample(
          at: 4_000_000_000,
          state: .tracking
        ),
      ]
    )

    XCTAssertEqual(summary.frameLossCount, 5)
    XCTAssertEqual(summary.deliveredFrameCount, 15)
    XCTAssertEqual(summary.totalFrameCount, 20)
    XCTAssertEqual(summary.frameLossPercent, 25, accuracy: 0.001)
    XCTAssertEqual(summary.trackingLossDurationNS, 3_000_000_000)
    XCTAssertEqual(summary.observedDurationNS, 4_000_000_000)
    XCTAssertEqual(summary.trackingLossPercent, 75, accuracy: 0.001)
  }

  func test分母がない品質Summaryは割合をゼロにする() {
    let summary = TrackerQualitySummary(
      samples: [
        sample(at: 100, state: .lost)
      ]
    )

    XCTAssertEqual(summary.frameLossPercent, 0)
    XCTAssertEqual(summary.trackingLossPercent, 0)
  }

  func test現在存在しないTrackerの履歴を破棄する() {
    var buffer = TrackerHistoryBuffer()
    buffer.record(
      trackers: [tracker(sequence: 1)],
      sampledAtNS: 100
    )

    buffer.record(trackers: [], sampledAtNS: 200)

    XCTAssertTrue(buffer.samplesByTrackerID.isEmpty)
  }

  func testSequence巻き戻り時にそのTrackerの履歴をresetする() {
    var buffer = TrackerHistoryBuffer()
    buffer.record(
      trackers: [tracker(sequence: 100)],
      sampledAtNS: 100
    )
    buffer.record(
      trackers: [tracker(sequence: 1)],
      sampledAtNS: 200
    )

    XCTAssertEqual(
      buffer.samplesByTrackerID["tracker-1"]?.map(\.frameSequence),
      [1]
    )
  }

  func testReset後は累積欠落数を新しいSourceの値として記録する() {
    var buffer = TrackerHistoryBuffer()
    buffer.record(
      trackers: [tracker(sequence: 1)],
      sampledAtNS: 100,
      cumulativeFrameLoss: 4
    )

    buffer.reset()
    buffer.record(
      trackers: [tracker(sequence: 1)],
      sampledAtNS: 200,
      cumulativeFrameLoss: 1
    )

    XCTAssertEqual(
      buffer.samplesByTrackerID["tracker-1"]?.map(\.frameLossCount),
      [1]
    )
  }

  private func tracker(
    sequence: UInt64,
    state: TrackingState = .tracking
  ) -> TrackerDisplayState {
    TrackerDisplayState(
      id: "tracker-1",
      role: "waist",
      position: Vector3(
        x: Float(sequence),
        y: 1,
        z: -1
      ),
      orientation: Quaternion(x: 0, y: 0, z: 0, w: 1),
      trackingState: state,
      trackingReason: .none,
      liveness: .fresh,
      ageMilliseconds: 0,
      frameSequence: sequence
    )
  }

  private func sample(
    at sampledAtNS: UInt64,
    state: TrackingState,
    frameLossCount: UInt64 = 0,
    deliveredFrameCount: UInt64 = 0
  ) -> TrackerHistorySample {
    TrackerHistorySample(
      sampledAtNS: sampledAtNS,
      trackingState: state,
      frameSequence: sampledAtNS,
      frameLossCount: frameLossCount,
      deliveredFrameCount: deliveredFrameCount
    )
  }
}
