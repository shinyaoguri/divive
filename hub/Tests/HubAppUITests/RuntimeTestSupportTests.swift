import Foundation
import XCTest

/// 遅れて成立する条件を再現するためのflag。
private actor DelayedFlag {
  private(set) var value = false

  func set() {
    value = true
  }
}

final class RuntimeTestSupportTests: XCTestCase {
  /// 固定sleepでは足りない遅延でも、条件が成立するまで待てることを固定する。
  ///
  /// 遅延は、以前の固定sleep（30ms）では取りこぼす長さにしている。
  func test条件が遅れて成立しても待ち続ける() async throws {
    let flag = DelayedFlag()
    let setter = Task {
      try? await Task.sleep(for: .milliseconds(150))
      await flag.set()
    }
    defer { setter.cancel() }

    try await waitUntil("遅れて成立する条件") {
      await flag.value
    }

    let value = await flag.value
    XCTAssertTrue(value, "条件成立前にwaitUntilが返っています")
  }

  func test成立済みの条件では待たずに返る() async throws {
    let clock = ContinuousClock()
    let start = clock.now

    try await waitUntil("成立済みの条件") { true }

    XCTAssertLessThan(
      start.duration(to: clock.now),
      .milliseconds(50),
      "成立済みでもpoll間隔を待っています"
    )
  }
}
