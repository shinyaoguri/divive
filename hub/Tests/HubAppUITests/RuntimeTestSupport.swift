import Foundation
import XCTest

/// 実時間runtimeの反映を、固定sleepではなく条件が成立するまで待つ。
///
/// CI runnerの負荷でschedulerが遅れると、固定sleepでは次のframeがHub stateへ届く
/// 前にassertionへ進み、testが不定期に失敗する。待ち時間ではなく条件で待つ。
///
/// 「一定時間が経っても変化しない」ことを確かめる否定的な検証には使えない。その場合は
/// 意図した経過時間を明示してsleepする。
func waitUntil(
  _ description: String,
  timeout: Duration = .seconds(5),
  pollInterval: Duration = .milliseconds(5),
  file: StaticString = #filePath,
  line: UInt = #line,
  condition: () async throws -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)

  while clock.now < deadline {
    if try await condition() {
      return
    }
    try await Task.sleep(for: pollInterval)
  }

  guard try await condition() else {
    XCTFail("\(description)がtimeoutしました", file: file, line: line)
    return
  }
}
