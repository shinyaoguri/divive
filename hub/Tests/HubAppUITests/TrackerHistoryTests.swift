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
      trackingState: state,
      trackingReason: .none,
      liveness: .fresh,
      ageMilliseconds: 0,
      frameSequence: sequence
    )
  }
}
