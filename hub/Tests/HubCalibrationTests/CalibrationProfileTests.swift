import Foundation
import HubCalibration
import HubProtocol
import XCTest

final class CalibrationProfileTests: XCTestCase {
  func test較正の追加でrevisionとupdatedAtが進む() throws {
    let spaceID = try calibrationTestUUID(0x10)
    let profile = try makeProfile()
    XCTAssertEqual(profile.spaceCount, 0)
    XCTAssertNil(profile.calibration(forTrackingSpaceID: spaceID))

    let later = calibrationTestDate.addingTimeInterval(60)
    let updated = profile.upserting(
      try makeSpaceCalibration(trackingSpaceID: spaceID, spaceEpoch: 2),
      at: later
    )

    XCTAssertEqual(updated.revision, profile.revision + 1)
    XCTAssertEqual(updated.updatedAt, later)
    XCTAssertEqual(updated.createdAt, profile.createdAt)
    XCTAssertEqual(updated.spaceCount, 1)
    XCTAssertEqual(updated.calibration(forTrackingSpaceID: spaceID)?.spaceEpoch, 2)
    XCTAssertEqual(profile.spaceCount, 0, "元のprofileを変更してはいけません")
  }

  func test同じspaceの再較正は置換される() throws {
    let spaceID = try calibrationTestUUID(0x20)
    let profile = try makeProfile()
      .upserting(
        try makeSpaceCalibration(trackingSpaceID: spaceID, spaceEpoch: 1),
        at: calibrationTestDate
      )
      .upserting(
        try makeSpaceCalibration(
          trackingSpaceID: spaceID,
          spaceEpoch: 5,
          method: .originAndForward
        ),
        at: calibrationTestDate
      )

    XCTAssertEqual(profile.spaceCount, 1)
    XCTAssertEqual(profile.calibration(forTrackingSpaceID: spaceID)?.spaceEpoch, 5)
    XCTAssertEqual(profile.calibration(forTrackingSpaceID: spaceID)?.method, .originAndForward)
    XCTAssertEqual(profile.revision, 3)
  }

  func test較正の取り消しで未較正へ戻る() throws {
    let spaceID = try calibrationTestUUID(0x30)
    let calibrated = try makeProfile(
      spaces: [try makeSpaceCalibration(trackingSpaceID: spaceID)]
    )
    let removed = calibrated.removingCalibration(
      forTrackingSpaceID: spaceID,
      at: calibrationTestDate
    )

    XCTAssertNil(removed.calibration(forTrackingSpaceID: spaceID))
    XCTAssertEqual(removed.revision, calibrated.revision + 1)

    let missing = try calibrationTestUUID(0x31)
    let unchanged = removed.removingCalibration(
      forTrackingSpaceID: missing,
      at: calibrationTestDate
    )
    XCTAssertEqual(unchanged.revision, removed.revision, "無い較正の削除でrevisionを進めません")
  }

  func testSortedSpacesはtrackingSpaceID順に整列する() throws {
    let first = try calibrationTestUUID(0x01)
    let second = try calibrationTestUUID(0x02)
    let third = try calibrationTestUUID(0x03)
    let profile = try makeProfile(
      spaces: [
        try makeSpaceCalibration(trackingSpaceID: third),
        try makeSpaceCalibration(trackingSpaceID: first),
        try makeSpaceCalibration(trackingSpaceID: second),
      ]
    )

    XCTAssertEqual(
      profile.sortedSpaces.map(\.trackingSpaceID),
      [first, second, third]
    )
  }

  func test空のprofileIDを拒否する() throws {
    XCTAssertThrowsError(try makeProfile(profileID: "")) { error in
      XCTAssertEqual(error as? CalibrationProfileError, .emptyProfileID)
    }
  }

  func test未知のformatVersionを拒否する() throws {
    XCTAssertThrowsError(
      try CalibrationProfile(
        profileID: "studio-a",
        name: "Studio A",
        createdAt: calibrationTestDate,
        updatedAt: calibrationTestDate,
        applicationVersion: "0.1.0-test",
        formatVersion: 99
      )
    ) { error in
      XCTAssertEqual(error as? CalibrationProfileError, .unsupportedFormatVersion(99))
    }
  }

  func test負またはNaNのresidualを拒否する() throws {
    let spaceID = try calibrationTestUUID(0x40)
    XCTAssertThrowsError(
      try makeSpaceCalibration(trackingSpaceID: spaceID, rmsErrorM: -0.001)
    ) { error in
      XCTAssertEqual(error as? CalibrationProfileError, .negativeResidual)
    }
    XCTAssertThrowsError(
      try makeSpaceCalibration(trackingSpaceID: spaceID, maxResidualM: .nan)
    ) { error in
      XCTAssertEqual(error as? CalibrationProfileError, .negativeResidual)
    }
  }

  func testProfileはJSONへ往復できる() throws {
    let profile = try makeProfile(
      spaces: [
        try makeSpaceCalibration(
          trackingSpaceID: try calibrationTestUUID(0x50),
          spaceEpoch: 7,
          transform: try makeTransform(
            translation: Vector3(x: 1.5, y: -0.25, z: 3),
            rotation: Quaternion(x: 0, y: 0.7071068, z: 0, w: 0.7071068)
          ),
          method: .pointSetRegistration,
          operatorNote: "床面基準で較正"
        ),
        try makeSpaceCalibration(
          trackingSpaceID: try calibrationTestUUID(0x60),
          rmsErrorM: nil,
          maxResidualM: nil,
          operatorNote: nil
        ),
      ]
    )

    let data = try CalibrationStore.makeEncoder().encode(profile)
    let decoded = try CalibrationStore.makeDecoder().decode(
      CalibrationProfile.self,
      from: data
    )
    XCTAssertEqual(decoded, profile)
  }

  func testJSONはtrackingSpaceIDをkeyに持つ() throws {
    let spaceID = try calibrationTestUUID(0x70)
    let profile = try makeProfile(
      spaces: [try makeSpaceCalibration(trackingSpaceID: spaceID)]
    )
    let json = String(
      decoding: try CalibrationStore.makeEncoder().encode(profile),
      as: UTF8.self
    )

    XCTAssertTrue(json.contains("\"\(spaceID.description)\""), json)
    XCTAssertTrue(json.contains("\"formatVersion\" : 1"), json)
  }

  func testUUID文字列の復元と拒否() throws {
    let spaceID = try calibrationTestUUID(0x80)
    XCTAssertEqual(try UUIDBytes(calibrationString: spaceID.description), spaceID)

    XCTAssertThrowsError(try UUIDBytes(calibrationString: "not-a-uuid")) { error in
      XCTAssertEqual(
        error as? CalibrationCodingError,
        .invalidTrackingSpaceID("not-a-uuid")
      )
    }
    XCTAssertThrowsError(
      try UUIDBytes(calibrationString: "zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz")
    )
  }
}
