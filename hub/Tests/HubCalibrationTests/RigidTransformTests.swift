import Foundation
import HubCalibration
import HubProtocol
import XCTest

final class RigidTransformTests: XCTestCase {
  private let yaw90 = Quaternion(x: 0, y: 0.7071068, z: 0, w: 0.7071068)

  func testGolden適合性caseを全て満たす() throws {
    let document = try GoldenTransformFixture.load()
    XCTAssertEqual(document.formatVersion, 1)
    XCTAssertFalse(document.cases.isEmpty)

    for goldenCase in document.cases {
      let transform = try goldenCase.composedTransform()

      assertVector(
        transform.apply(toPosition: try goldenCase.input.vector(goldenCase.input.position)),
        try goldenCase.expected.vector(goldenCase.expected.position),
        "\(goldenCase.name) position"
      )
      assertSameRotation(
        transform.apply(toOrientation: try goldenCase.input.quaternion()),
        try goldenCase.expected.quaternion(),
        "\(goldenCase.name) orientation"
      )
      assertVector(
        transform.apply(
          toDirection: try goldenCase.input.vector(goldenCase.input.linearVelocity)
        ),
        try goldenCase.expected.vector(goldenCase.expected.linearVelocity),
        "\(goldenCase.name) linearVelocity"
      )
      assertVector(
        transform.apply(
          toDirection: try goldenCase.input.vector(goldenCase.input.angularVelocity)
        ),
        try goldenCase.expected.vector(goldenCase.expected.angularVelocity),
        "\(goldenCase.name) angularVelocity"
      )
    }
  }

  func testGoldenFixtureがdocsの必須caseを含む() throws {
    let names = Set(try GoldenTransformFixture.load().cases.map(\.name))
    for required in [
      "identity",
      "translation_only",
      "yaw_90_about_up",
      "pitch_90_about_right",
      "roll_90_about_forward_axis",
      "yaw_90_then_translation",
      "velocity_ignores_large_translation",
      "quaternion_sign_equivalence",
      "two_space_composition",
    ] {
      XCTAssertTrue(names.contains(required), "\(required) caseが不足しています")
    }
  }

  func testIdentityはposeを変更しない() throws {
    let position = Vector3(x: 1, y: -2, z: 3)
    assertVector(RigidTransform.identity.apply(toPosition: position), position)
    assertVector(RigidTransform.identity.apply(toDirection: position), position)
    assertSameRotation(
      RigidTransform.identity.apply(toOrientation: yaw90),
      yaw90
    )
  }

  func test非正規化quaternionを拒否する() throws {
    XCTAssertThrowsError(
      try RigidTransform(
        translation: Vector3(x: 0, y: 0, z: 0),
        rotation: Quaternion(x: 0, y: 0, z: 0, w: 0.5)
      )
    ) { error in
      guard case let .quaternionNotNormalized(magnitude) = error as? RigidTransformError else {
        return XCTFail("quaternionNotNormalizedを期待しました: \(error)")
      }
      XCTAssertEqual(magnitude, 0.5, accuracy: 1.0e-6)
    }

    XCTAssertThrowsError(
      try RigidTransform(
        translation: Vector3(x: 0, y: 0, z: 0),
        rotation: Quaternion(x: 0, y: 0, z: 0, w: 0)
      )
    )
  }

  func test非有限成分を拒否する() throws {
    XCTAssertThrowsError(
      try RigidTransform(
        translation: Vector3(x: .nan, y: 0, z: 0),
        rotation: Quaternion(x: 0, y: 0, z: 0, w: 1)
      )
    ) { error in
      XCTAssertEqual(error as? RigidTransformError, .nonFiniteComponent)
    }

    XCTAssertThrowsError(
      try RigidTransform(
        translation: Vector3(x: 0, y: 0, z: 0),
        rotation: Quaternion(x: .infinity, y: 0, z: 0, w: 1)
      )
    ) { error in
      XCTAssertEqual(error as? RigidTransformError, .nonFiniteComponent)
    }
  }

  func test許容範囲内の量子化誤差は正規化して受け入れる() throws {
    let transform = try RigidTransform(
      translation: Vector3(x: 0, y: 0, z: 0),
      rotation: Quaternion(x: 0, y: 0.70712, z: 0, w: 0.70712)
    )
    let magnitude =
      Double(transform.rotation.x * transform.rotation.x)
      + Double(transform.rotation.y * transform.rotation.y)
      + Double(transform.rotation.z * transform.rotation.z)
      + Double(transform.rotation.w * transform.rotation.w)
    XCTAssertEqual(magnitude.squareRoot(), 1.0, accuracy: 1.0e-6)
  }

  func testInverseは元のposeへ戻す() throws {
    let transform = try RigidTransform(
      translation: Vector3(x: 1.5, y: -2.25, z: 3),
      rotation: yaw90
    )
    let position = Vector3(x: 0.5, y: 1, z: -2)
    let roundTrip = transform.inverse.apply(toPosition: transform.apply(toPosition: position))
    assertVector(roundTrip, position)

    let identity = transform.composed(with: transform.inverse)
    XCTAssertTrue(
      identity.representsSameTransform(as: .identity),
      "合成結果がidentityになりません: \(identity)"
    )
  }

  func testComposedは結合的で適用順を保つ() throws {
    let first = try RigidTransform(
      translation: Vector3(x: 1, y: 0, z: 0),
      rotation: yaw90
    )
    let second = try RigidTransform(
      translation: Vector3(x: 0, y: 2, z: 0),
      rotation: Quaternion(x: 0.7071068, y: 0, z: 0, w: 0.7071068)
    )
    let third = try RigidTransform(
      translation: Vector3(x: 0, y: 0, z: -3),
      rotation: Quaternion(x: 0, y: 0, z: 0.7071068, w: 0.7071068)
    )

    let leftAssociated = third.composed(with: second).composed(with: first)
    let rightAssociated = third.composed(with: second.composed(with: first))
    XCTAssertTrue(
      leftAssociated.representsSameTransform(as: rightAssociated),
      "合成が結合的ではありません"
    )

    let position = Vector3(x: 0.25, y: -1, z: 2)
    let stepwise = third.apply(
      toPosition: second.apply(toPosition: first.apply(toPosition: position))
    )
    assertVector(leftAssociated.apply(toPosition: position), stepwise)
  }

  func test符号反転したquaternionは同じ変換を表す() throws {
    let positive = try RigidTransform(
      translation: Vector3(x: 1, y: 2, z: 3),
      rotation: yaw90
    )
    let negated = try RigidTransform(
      translation: Vector3(x: 1, y: 2, z: 3),
      rotation: Quaternion(x: -yaw90.x, y: -yaw90.y, z: -yaw90.z, w: -yaw90.w)
    )

    XCTAssertNotEqual(positive.rotation, negated.rotation)
    XCTAssertTrue(positive.representsSameTransform(as: negated))

    let position = Vector3(x: -1, y: 0.5, z: 4)
    assertVector(positive.apply(toPosition: position), negated.apply(toPosition: position))
  }

  func testRigidTransformはJSONへ往復できる() throws {
    let transform = try RigidTransform(
      translation: Vector3(x: 0.125, y: -4, z: 16),
      rotation: yaw90
    )
    let data = try JSONEncoder().encode(transform)
    let decoded = try JSONDecoder().decode(RigidTransform.self, from: data)
    XCTAssertEqual(decoded, transform)
  }

  func test成分数が不正なJSONを拒否する() throws {
    let shortTranslation = Data(
      #"{"translation":[0,0],"rotation":[0,0,0,1]}"#.utf8
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(RigidTransform.self, from: shortTranslation)
    ) { error in
      XCTAssertEqual(
        error as? CalibrationCodingError,
        .invalidTranslationLength(actual: 2)
      )
    }

    let shortRotation = Data(
      #"{"translation":[0,0,0],"rotation":[0,0,1]}"#.utf8
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(RigidTransform.self, from: shortRotation)
    ) { error in
      XCTAssertEqual(
        error as? CalibrationCodingError,
        .invalidRotationLength(actual: 3)
      )
    }
  }
}
