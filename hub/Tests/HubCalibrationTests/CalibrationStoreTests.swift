import Foundation
import HubCalibration
import HubProtocol
import XCTest

final class CalibrationStoreTests: XCTestCase {
  private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

  override func setUpWithError() throws {
    directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("divive-calibration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeStore(_ name: String = "profile.json") -> CalibrationStore {
    CalibrationStore(url: directory.appendingPathComponent(name))
  }

  func test保存したprofileを読み戻せる() throws {
    let store = makeStore()
    XCTAssertFalse(store.exists())

    let profile = try makeProfile(
      spaces: [
        try makeSpaceCalibration(
          trackingSpaceID: try calibrationTestUUID(0x11),
          spaceEpoch: 4,
          transform: try makeTransform(
            translation: Vector3(x: 0.5, y: -1.25, z: 2),
            rotation: Quaternion(x: 0, y: 0.7071068, z: 0, w: 0.7071068)
          ),
          method: .originAndForward
        )
      ]
    )

    try store.save(profile)
    XCTAssertTrue(store.exists())
    XCTAssertEqual(try store.load(), profile)
  }

  func test親ディレクトリが無くても保存できる() throws {
    let store = CalibrationStore(
      url: directory
        .appendingPathComponent("nested")
        .appendingPathComponent("deeper")
        .appendingPathComponent("profile.json")
    )
    let profile = try makeProfile()

    try store.save(profile)
    XCTAssertEqual(try store.load(), profile)
  }

  func test上書き保存で最新のrevisionが残る() throws {
    let store = makeStore()
    let spaceID = try calibrationTestUUID(0x12)
    let first = try makeProfile()
    try store.save(first)

    let second = first.upserting(
      try makeSpaceCalibration(trackingSpaceID: spaceID, spaceEpoch: 2),
      at: calibrationTestDate.addingTimeInterval(120)
    )
    try store.save(second)

    let loaded = try store.load()
    XCTAssertEqual(loaded.revision, first.revision + 1)
    XCTAssertEqual(loaded.calibration(forTrackingSpaceID: spaceID)?.spaceEpoch, 2)
  }

  func test存在しないprofileはprofileNotFoundになる() throws {
    let store = makeStore("missing.json")
    XCTAssertThrowsError(try store.load()) { error in
      XCTAssertEqual(
        error as? CalibrationStoreError,
        .profileNotFound(path: store.url.path)
      )
    }
  }

  func test壊れたJSONでidentityへfallbackしない() throws {
    let store = makeStore()
    try Data("{ not json".utf8).write(to: store.url)

    XCTAssertThrowsError(try store.load()) { error in
      guard case .malformedProfile = error as? CalibrationStoreError else {
        return XCTFail("malformedProfileを期待しました: \(error)")
      }
    }
  }

  func test未知のformatVersionを拒否する() throws {
    let store = makeStore()
    let json = """
      {
        "formatVersion": 2,
        "profileId": "studio-a",
        "name": "Studio A",
        "revision": 1,
        "createdAt": "2027-01-15T00:00:00Z",
        "updatedAt": "2027-01-15T00:00:00Z",
        "applicationVersion": "0.1.0-test",
        "spaces": {}
      }
      """
    try Data(json.utf8).write(to: store.url)

    XCTAssertThrowsError(try store.load()) { error in
      XCTAssertEqual(
        error as? CalibrationStoreError,
        .unsupportedFormatVersion(2)
      )
    }
  }

  func test非正規化quaternionを含むprofileを拒否する() throws {
    let store = makeStore()
    let json = """
      {
        "formatVersion": 1,
        "profileId": "studio-a",
        "name": "Studio A",
        "revision": 1,
        "createdAt": "2027-01-15T00:00:00Z",
        "updatedAt": "2027-01-15T00:00:00Z",
        "applicationVersion": "0.1.0-test",
        "spaces": {
          "00010203-0405-0607-0809-0a0b0c0d0e0f": {
            "spaceEpoch": 1,
            "translation": [0, 0, 0],
            "rotation": [0, 0, 0, 0.5],
            "method": "manual",
            "sampleCount": 0,
            "updatedAt": "2027-01-15T00:00:00Z"
          }
        }
      }
      """
    try Data(json.utf8).write(to: store.url)

    XCTAssertThrowsError(try store.load()) { error in
      guard case let .malformedProfile(_, reason) = error as? CalibrationStoreError else {
        return XCTFail("malformedProfileを期待しました: \(error)")
      }
      XCTAssertTrue(reason.contains("quaternionNotNormalized"), reason)
    }
  }

  func test不正なtrackingSpaceIDのkeyを拒否する() throws {
    let store = makeStore()
    let json = """
      {
        "formatVersion": 1,
        "profileId": "studio-a",
        "name": "Studio A",
        "revision": 1,
        "createdAt": "2027-01-15T00:00:00Z",
        "updatedAt": "2027-01-15T00:00:00Z",
        "applicationVersion": "0.1.0-test",
        "spaces": {
          "not-a-uuid": {
            "spaceEpoch": 1,
            "translation": [0, 0, 0],
            "rotation": [0, 0, 0, 1],
            "method": "manual",
            "sampleCount": 0,
            "updatedAt": "2027-01-15T00:00:00Z"
          }
        }
      }
      """
    try Data(json.utf8).write(to: store.url)

    XCTAssertThrowsError(try store.load()) { error in
      guard case let .malformedProfile(_, reason) = error as? CalibrationStoreError else {
        return XCTFail("malformedProfileを期待しました: \(error)")
      }
      XCTAssertTrue(reason.contains("invalidTrackingSpaceID"), reason)
    }
  }
}
