@testable import HubAppUI
import XCTest

final class HubMenuBarStatusTests: XCTestCase {
  func test停止中は過去の異常より停止を優先する() {
    let status = HubMenuBarStatus(
      source: .network,
      isRunning: false,
      trackerCount: 3,
      attentionTrackerCount: 1,
      anomalyCount: 4,
      errorMessage: nil
    )

    XCTAssertEqual(status.severity, .stopped)
    XCTAssertEqual(status.menuTitle, "停止")
  }

  func test受信開始後にTrackerがなければ待機を表示する() {
    let status = HubMenuBarStatus(
      source: .network,
      isRunning: true,
      trackerCount: 0,
      attentionTrackerCount: 0,
      anomalyCount: 0,
      errorMessage: nil
    )

    XCTAssertEqual(status.severity, .waiting)
    XCTAssertEqual(status.menuTitle, "待機")
    XCTAssertEqual(status.title, "UDPデータを待っています")
  }

  func test正常時はTracker台数をメニューバーへ表示する() {
    let status = HubMenuBarStatus(
      source: .simulator,
      isRunning: true,
      trackerCount: 5,
      attentionTrackerCount: 0,
      anomalyCount: 0,
      errorMessage: nil
    )

    XCTAssertEqual(status.severity, .healthy)
    XCTAssertEqual(status.menuTitle, "5台")
  }

  func test追跡異常と入力品質異常を要確認にする() {
    let trackingProblem = HubMenuBarStatus(
      source: .network,
      isRunning: true,
      trackerCount: 3,
      attentionTrackerCount: 1,
      anomalyCount: 0,
      errorMessage: nil
    )
    let inputProblem = HubMenuBarStatus(
      source: .simulator,
      isRunning: true,
      trackerCount: 3,
      attentionTrackerCount: 0,
      anomalyCount: 1,
      errorMessage: nil
    )

    XCTAssertEqual(trackingProblem.severity, .warning)
    XCTAssertEqual(trackingProblem.menuTitle, "要確認")
    XCTAssertEqual(inputProblem.severity, .warning)
    XCTAssertEqual(inputProblem.menuTitle, "要確認")
  }

  func test起動エラーを最優先で表示する() {
    let status = HubMenuBarStatus(
      source: .network,
      isRunning: false,
      trackerCount: 0,
      attentionTrackerCount: 0,
      anomalyCount: 0,
      errorMessage: "portを使用できません"
    )

    XCTAssertEqual(status.severity, .error)
    XCTAssertEqual(status.menuTitle, "エラー")
    XCTAssertEqual(status.detail, "portを使用できません")
  }
}
