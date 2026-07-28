import Foundation
import HubCalibration
import HubProtocol

/// SDK横断で共有する適合性fixtureの1 case。
struct GoldenTransformCase: Decodable {
  let name: String
  let description: String
  let transforms: [RigidTransform]
  let input: GoldenPose
  let expected: GoldenPose

  /// 先頭のtransformが最初に適用されるよう合成する。
  func composedTransform() throws -> RigidTransform {
    guard var composed = transforms.first else {
      throw GoldenTransformFixtureError.emptyTransformList(caseName: name)
    }
    for outer in transforms.dropFirst() {
      composed = outer.composed(with: composed)
    }
    return composed
  }
}

struct GoldenPose: Decodable {
  let position: [Float]
  let orientation: [Float]
  let linearVelocity: [Float]
  let angularVelocity: [Float]

  func vector(_ components: [Float]) throws -> Vector3 {
    guard components.count == 3 else {
      throw GoldenTransformFixtureError.malformedComponents(count: components.count)
    }
    return Vector3(x: components[0], y: components[1], z: components[2])
  }

  func quaternion() throws -> Quaternion {
    guard orientation.count == 4 else {
      throw GoldenTransformFixtureError.malformedComponents(count: orientation.count)
    }
    return Quaternion(
      x: orientation[0],
      y: orientation[1],
      z: orientation[2],
      w: orientation[3]
    )
  }
}

struct GoldenTransformDocument: Decodable {
  let formatVersion: Int
  let cases: [GoldenTransformCase]
}

enum GoldenTransformFixtureError: Error, Equatable {
  case emptyTransformList(caseName: String)
  case malformedComponents(count: Int)
}

enum GoldenTransformFixture {
  static let url: URL = {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repositoryRoot =
      testDirectory
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return repositoryRoot.appendingPathComponent("calibration/golden/transform_v1.cases.json")
  }()

  static func load() throws -> GoldenTransformDocument {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(GoldenTransformDocument.self, from: data)
  }
}
