import Foundation
import HubCalibration
import HubProtocol
import XCTest

@testable import HubAppUI

@MainActor
final class HubAppCalibrationTests: XCTestCase {
  private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
  private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

  override func setUpWithError() throws {
    directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("divive-gui-calibration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private var storeURL: URL {
    directory.appendingPathComponent("calibration.json")
  }

  private func makeModel() -> HubAppModel {
    HubAppModel(
      calibrationStore: CalibrationStore(url: storeURL),
      now: fixedDate
    )
  }

  /// Simulatorを1台で開始し、Trackerが表示されるまで待つ。
  private func startSimulator(_ model: HubAppModel) async throws {
    model.selectedSource = .simulator
    model.trackerCount = 1
    model.motion = .stationary
    await model.startSelectedSource()

    try await waitUntil("SimulatorのTrackerが表示される") {
      await model.refresh()
      return !model.trackers.isEmpty
    }
  }

  /// Trackerを指定位置へ動かし、表示へ反映されるまで待つ。
  private func move(
    _ model: HubAppModel,
    trackerID: String,
    to position: Vector3
  ) async throws {
    model.moveSimulatorTracker(trackerID: trackerID, to: position)
    try await waitUntil("Tracker位置が\(position)へ反映される") {
      await model.refresh()
      guard let tracker = model.trackers.first(where: { $0.id == trackerID }) else {
        return false
      }
      return abs(tracker.position.x - position.x) < 1.0e-3
        && abs(tracker.position.y - position.y) < 1.0e-3
        && abs(tracker.position.z - position.z) < 1.0e-3
    }
  }

  func test較正前は未較正としてpreview配信される() async throws {
    let model = makeModel()
    try await startSimulator(model)
    defer { Task { await model.stopActiveSource() } }

    let tracker = try XCTUnwrap(model.trackers.first)
    XCTAssertEqual(model.calibrationMode, .preview, "GUIの既定はpreview")
    XCTAssertEqual(tracker.calibrationDelivery, .rawTrackerSpace)
    XCTAssertEqual(tracker.stagePosition, tracker.position)
    XCTAssertTrue(model.hasUncalibratedSpace)
    XCTAssertEqual(model.calibratedSpaceCount, 0)
    XCTAssertEqual(model.uncalibratedSpaceCount, 1)
  }

  func testProductionでは未較正Trackerが非配信になる() async throws {
    let model = makeModel()
    try await startSimulator(model)
    defer { Task { await model.stopActiveSource() } }

    model.calibrationMode = .production
    try await waitUntil("production modeが反映される") {
      await model.refresh()
      return model.trackers.first?.calibrationDelivery == .blocked
    }

    let tracker = try XCTUnwrap(model.trackers.first)
    XCTAssertNil(tracker.stagePosition)
    // 非配信でも一覧から消さない。
    XCTAssertEqual(model.trackers.count, 1)
  }

  func test原点と前方から較正してStage位置を得る() async throws {
    let model = makeModel()
    try await startSimulator(model)
    defer { Task { await model.stopActiveSource() } }

    let trackerID = try XCTUnwrap(model.trackers.first?.id)

    try await move(model, trackerID: trackerID, to: Vector3(x: 0, y: 0, z: 0))
    model.captureCalibrationOrigin(trackerID: trackerID)
    XCTAssertEqual(model.calibrationOriginSample?.captureCount, 1)

    try await move(model, trackerID: trackerID, to: Vector3(x: 2, y: 0, z: 0))
    model.captureCalibrationForward(trackerID: trackerID)
    XCTAssertEqual(model.calibrationForwardSample?.captureCount, 1)
    XCTAssertTrue(model.canApplyCalibration)

    model.applyOriginAndForwardCalibration(now: fixedDate)
    XCTAssertNil(model.calibrationErrorMessage, model.calibrationErrorMessage ?? "")
    XCTAssertEqual(model.calibrationProfileRevision, 2)

    try await waitUntil("較正が表示へ反映される") {
      await model.refresh()
      return model.trackers.first?.calibrationDelivery == .stage
    }

    let tracker = try XCTUnwrap(model.trackers.first)
    // Tracker Spaceの+Xを基準方向にしたので、Stageでは-Zを向く。
    let stagePosition = try XCTUnwrap(tracker.stagePosition)
    XCTAssertEqual(stagePosition.x, 0, accuracy: 1.0e-3)
    XCTAssertEqual(stagePosition.y, 0, accuracy: 1.0e-3)
    XCTAssertEqual(stagePosition.z, -2, accuracy: 1.0e-3)

    // プレビューが使う座標はTracker Spaceのまま。
    XCTAssertEqual(tracker.position.x, 2, accuracy: 1.0e-3)
    XCTAssertEqual(tracker.position.z, 0, accuracy: 1.0e-3)

    XCTAssertFalse(model.hasUncalibratedSpace)
    XCTAssertEqual(model.calibratedSpaceCount, 1)
  }

  func test床面offsetで原点の高さを指定できる() async throws {
    let model = makeModel()
    try await startSimulator(model)
    defer { Task { await model.stopActiveSource() } }

    let trackerID = try XCTUnwrap(model.trackers.first?.id)
    model.calibrationFloorHeightOffsetText = "0.9"

    try await move(model, trackerID: trackerID, to: Vector3(x: 0, y: 0, z: 0))
    model.captureCalibrationOrigin(trackerID: trackerID)
    try await move(model, trackerID: trackerID, to: Vector3(x: 0, y: 0, z: -2))
    model.captureCalibrationForward(trackerID: trackerID)
    model.applyOriginAndForwardCalibration(now: fixedDate)

    try await move(model, trackerID: trackerID, to: Vector3(x: 0, y: 0, z: 0))
    try await waitUntil("較正後のStage位置が得られる") {
      await model.refresh()
      return model.trackers.first?.stagePosition != nil
        && model.trackers.first?.calibrationDelivery == .stage
    }

    let stagePosition = try XCTUnwrap(model.trackers.first?.stagePosition)
    XCTAssertEqual(stagePosition.y, 0.9, accuracy: 1.0e-3)
  }

  func test較正結果がファイルへ保存され再読込で復元される() async throws {
    let model = makeModel()
    try await startSimulator(model)

    let trackerID = try XCTUnwrap(model.trackers.first?.id)
    try await move(model, trackerID: trackerID, to: Vector3(x: 0, y: 0, z: 0))
    model.captureCalibrationOrigin(trackerID: trackerID)
    try await move(model, trackerID: trackerID, to: Vector3(x: 2, y: 0, z: 0))
    model.captureCalibrationForward(trackerID: trackerID)
    model.applyOriginAndForwardCalibration(now: fixedDate)
    let trackingSpaceID = try XCTUnwrap(model.calibrationOriginSample?.trackingSpaceID)
    await model.stopActiveSource()

    XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

    let restored = makeModel()
    XCTAssertNil(restored.calibrationErrorMessage)
    XCTAssertEqual(restored.calibrationProfileRevision, model.calibrationProfileRevision)
    let calibration = try XCTUnwrap(
      restored.calibrationProfile?.calibration(forTrackingSpaceID: trackingSpaceID)
    )
    XCTAssertEqual(calibration.method, .originAndForward)
    XCTAssertEqual(calibration.sampleCount, 2)
  }

  func test較正を取り消すと未較正へ戻る() async throws {
    let model = makeModel()
    try await startSimulator(model)
    defer { Task { await model.stopActiveSource() } }

    let trackerID = try XCTUnwrap(model.trackers.first?.id)
    try await move(model, trackerID: trackerID, to: Vector3(x: 0, y: 0, z: 0))
    model.captureCalibrationOrigin(trackerID: trackerID)
    try await move(model, trackerID: trackerID, to: Vector3(x: 2, y: 0, z: 0))
    model.captureCalibrationForward(trackerID: trackerID)
    model.applyOriginAndForwardCalibration(now: fixedDate)

    let trackingSpaceID = try XCTUnwrap(model.calibrationOriginSample?.trackingSpaceID)
    let revisionBefore = model.calibrationProfileRevision

    model.clearCalibration(forTrackingSpaceID: trackingSpaceID, now: fixedDate)
    XCTAssertEqual(model.calibrationProfileRevision, revisionBefore + 1)
    XCTAssertNil(
      model.calibrationProfile?.calibration(forTrackingSpaceID: trackingSpaceID)
    )

    try await waitUntil("未較正へ戻る") {
      await model.refresh()
      return model.trackers.first?.calibrationDelivery == .rawTrackerSpace
    }
    XCTAssertTrue(model.hasUncalibratedSpace)
  }

  func test退化した較正はエラーになりprofileを変更しない() async throws {
    let model = makeModel()
    try await startSimulator(model)
    defer { Task { await model.stopActiveSource() } }

    let trackerID = try XCTUnwrap(model.trackers.first?.id)
    try await move(model, trackerID: trackerID, to: Vector3(x: 1, y: 0, z: 0))
    model.captureCalibrationOrigin(trackerID: trackerID)
    model.captureCalibrationForward(trackerID: trackerID)

    let revisionBefore = model.calibrationProfileRevision
    model.applyOriginAndForwardCalibration(now: fixedDate)

    let message = try XCTUnwrap(model.calibrationErrorMessage)
    XCTAssertTrue(message.contains("前方サンプルが近すぎます"), message)
    XCTAssertEqual(model.calibrationProfileRevision, revisionBefore)
    XCTAssertNil(model.lastCalibrationEstimate)
    XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
  }

  func testTracker未選択のサンプル取得はエラーになる() async throws {
    let model = makeModel()

    model.captureCalibrationOrigin(trackerID: nil)

    XCTAssertEqual(
      model.calibrationErrorMessage,
      CalibrationCommandError.noSelectedTracker.description
    )
    XCTAssertNil(model.calibrationOriginSample)
  }

  func testサンプルは繰り返し取得すると蓄積される() async throws {
    let model = makeModel()
    try await startSimulator(model)
    defer { Task { await model.stopActiveSource() } }

    let trackerID = try XCTUnwrap(model.trackers.first?.id)
    try await move(model, trackerID: trackerID, to: Vector3(x: 0, y: 0, z: 0))
    model.captureCalibrationOrigin(trackerID: trackerID)
    model.captureCalibrationOrigin(trackerID: trackerID)
    model.captureCalibrationOrigin(trackerID: trackerID)

    XCTAssertEqual(model.calibrationOriginSample?.captureCount, 3)
    XCTAssertEqual(model.calibrationMessage, "原点サンプルを3点取得しました")

    model.clearCalibrationSamples()
    XCTAssertNil(model.calibrationOriginSample)
    XCTAssertNil(model.calibrationMessage)
  }

  func test壊れたprofileはidentityへfallbackせずエラーを出す() async throws {
    try Data("{ broken".utf8).write(to: storeURL)

    let model = makeModel()

    let message = try XCTUnwrap(model.calibrationErrorMessage)
    XCTAssertTrue(message.contains("calibration profileを読み込めませんでした"), message)
    XCTAssertNil(model.calibrationProfile, "壊れたprofileを空profileで置き換えません")

    // 較正操作も受け付けない。
    try await startSimulator(model)
    defer { Task { await model.stopActiveSource() } }
    let trackerID = try XCTUnwrap(model.trackers.first?.id)
    model.captureCalibrationOrigin(trackerID: trackerID)
    model.captureCalibrationForward(trackerID: trackerID)
    model.applyOriginAndForwardCalibration(now: fixedDate)
    XCTAssertNil(model.lastCalibrationEstimate)
  }

  func test保存済みprofileが起動時に読み込まれる() async throws {
    let spaceID = try UUIDBytes(bytes: (0..<16).map { UInt8($0) })
    let profile = try CalibrationProfile(
      profileID: "divive-hub",
      name: "保存済み",
      revision: 7,
      createdAt: fixedDate,
      updatedAt: fixedDate,
      applicationVersion: "0.1.0-test",
      spaces: [
        try SpaceCalibration(
          trackingSpaceID: spaceID,
          spaceEpoch: 1,
          transform: .identity,
          method: .manual,
          updatedAt: fixedDate
        )
      ]
    )
    try CalibrationStore(url: storeURL).save(profile)

    let model = makeModel()

    XCTAssertNil(model.calibrationErrorMessage)
    XCTAssertEqual(model.calibrationProfileName, "保存済み")
    XCTAssertEqual(model.calibrationProfileRevision, 7)
    XCTAssertNotNil(
      model.calibrationProfile?.calibration(forTrackingSpaceID: spaceID)
    )
  }
}
