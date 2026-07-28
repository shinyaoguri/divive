import XCTest
import simd

@testable import HubAppUI

final class ViveTrackerShapeTests: XCTestCase {
  private let shape = ViveTrackerShape(widthMeters: 0.033)

  func test実機VIVETrackerの外寸比を保つ() {
    let widthRatio =
      ViveTrackerShape.referenceDepthMeters
      / ViveTrackerShape.referenceWidthMeters
    let heightRatio =
      ViveTrackerShape.referenceHeightMeters
      / ViveTrackerShape.referenceWidthMeters
    XCTAssertEqual(shape.depthMeters, 0.033 * widthRatio, accuracy: 1e-6)
    XCTAssertEqual(shape.heightMeters, 0.033 * heightRatio, accuracy: 1e-6)

    let bounds = combinedBounds()
    XCTAssertEqual(
      bounds.maximum.x - bounds.minimum.x,
      shape.widthMeters,
      accuracy: shape.widthMeters * 0.01
    )
    XCTAssertEqual(
      bounds.maximum.z - bounds.minimum.z,
      shape.depthMeters,
      accuracy: shape.depthMeters * 0.01
    )
    XCTAssertEqual(
      bounds.maximum.y - bounds.minimum.y,
      shape.heightMeters,
      accuracy: 1e-6
    )
    XCTAssertEqual(bounds.maximum.y, shape.heightMeters / 2, accuracy: 1e-6)
  }

  func test上面視は前方へ細まり左右対称になる() {
    let front = shape.outlineOffset(angle: ViveTrackerShape.frontAngle)
    let rear = shape.outlineOffset(angle: ViveTrackerShape.rearAngle)
    XCTAssertEqual(front.y, -shape.depthMeters / 2, accuracy: 1e-6)
    XCTAssertEqual(rear.y, shape.depthMeters / 2, accuracy: 1e-6)
    XCTAssertEqual(front.x, 0, accuracy: 1e-6)
    XCTAssertEqual(rear.x, 0, accuracy: 1e-6)

    for index in 1..<180 {
      let angle = .pi * Float(index) / 360
      let frontOffset = shape.outlineOffset(angle: angle)
      let rearOffset = shape.outlineOffset(angle: .pi - angle)

      // 同じ深さで比べると前方の幅が狭い。
      XCTAssertEqual(rearOffset.y, -frontOffset.y, accuracy: 1e-6)
      XCTAssertLessThan(abs(frontOffset.x), abs(rearOffset.x))

      // X = 0平面に対する左右対称。
      let mirrored = shape.outlineOffset(angle: -angle)
      XCTAssertEqual(mirrored.x, -frontOffset.x, accuracy: 1e-6)
      XCTAssertEqual(mirrored.y, frontOffset.y, accuracy: 1e-6)
    }

    // 最大幅はwidthMetersちょうどで、後ろ寄りに現れる。
    var widestAngle: Float = 0
    var widestHalfWidth: Float = 0
    for index in 0..<720 {
      let angle = 2 * .pi * Float(index) / 720
      let offset = shape.outlineOffset(angle: angle)
      if abs(offset.x) > widestHalfWidth {
        widestHalfWidth = abs(offset.x)
        widestAngle = angle
      }
    }
    XCTAssertEqual(
      widestHalfWidth,
      shape.widthMeters / 2,
      accuracy: shape.widthMeters * 0.001
    )
    XCTAssertGreaterThan(
      shape.outlineOffset(angle: widestAngle).y,
      0
    )
  }

  func test側面視は下端が最も太い円錐台になる() {
    XCTAssertEqual(shape.radiusRatio(atHeightRatio: 0.05), 1, accuracy: 1e-6)
    XCTAssertLessThan(shape.radiusRatio(atHeightRatio: 0), 1)
    XCTAssertEqual(
      shape.radiusRatio(atHeightRatio: 1),
      shape.topRadiusRatio,
      accuracy: 1e-6
    )
    XCTAssertLessThan(shape.topRadiusRatio, 0.7)

    var previous = shape.radiusRatio(atHeightRatio: 0.05)
    for step in 1...19 {
      let heightRatio = 0.05 + 0.95 * Float(step) / 19
      let radiusRatio = shape.radiusRatio(atHeightRatio: heightRatio)
      XCTAssertLessThanOrEqual(radiusRatio, previous)
      previous = radiusRatio
    }
  }

  func test範囲外の高さ比と幅を境界へ丸める() {
    XCTAssertEqual(
      shape.radiusRatio(atHeightRatio: -3),
      shape.radiusRatio(atHeightRatio: 0),
      accuracy: 1e-6
    )
    XCTAssertEqual(
      shape.radiusRatio(atHeightRatio: 4),
      shape.topRadiusRatio,
      accuracy: 1e-6
    )
    XCTAssertEqual(
      shape.surfacePoint(heightRatio: .nan, angle: 0).y,
      -shape.heightMeters / 2,
      accuracy: 1e-6
    )
    XCTAssertEqual(
      shape.surfacePoint(heightRatio: -2, angle: 0).y,
      -shape.heightMeters / 2,
      accuracy: 1e-6
    )
    XCTAssertEqual(
      shape.surfacePoint(heightRatio: 4, angle: 0).y,
      shape.heightMeters / 2,
      accuracy: 1e-6
    )

    for width in [Float(0), -1, .nan] {
      let degenerate = ViveTrackerShape(widthMeters: width)
      XCTAssertEqual(degenerate.widthMeters, 0.001, accuracy: 1e-9)
      XCTAssertTrue(degenerate.depthMeters.isFinite)
      for position in degenerate.shellMesh().positions {
        XCTAssertTrue(position.x.isFinite)
        XCTAssertTrue(position.y.isFinite)
        XCTAssertTrue(position.z.isFinite)
      }
    }
  }

  func testShellMeshの三角形と法線が外を向く() {
    let mesh = shape.shellMesh()
    XCTAssertFalse(mesh.positions.isEmpty)
    XCTAssertEqual(mesh.positions.count, mesh.normals.count)
    XCTAssertEqual(mesh.indices.count % 3, 0)
    XCTAssertGreaterThan(mesh.triangleCount, 0)

    for normal in mesh.normals {
      XCTAssertEqual(simd_length(normal), 1, accuracy: 1e-4)
    }
    for (index, position) in mesh.positions.enumerated() {
      // 上下に凸な立体なので、中心から見た向きで表裏を判定できる。
      XCTAssertGreaterThan(
        simd_dot(mesh.normals[index], position),
        -1e-6,
        "頂点\(index)の法線が内側を向いている"
      )
    }

    var bottomTriangles = 0
    for triangle in triangles(of: mesh) {
      XCTAssertGreaterThan(simd_length(triangle.geometricNormal), 0)
      let normal = simd_normalize(triangle.geometricNormal)
      XCTAssertGreaterThan(
        simd_dot(normal, simd_normalize(triangle.centroid)),
        0,
        "三角形の巻き方向が内向きになっている"
      )
      if normal.y < -0.99 {
        bottomTriangles += 1
      }
    }
    XCTAssertEqual(bottomTriangles, ViveTrackerShape.radialSegments)
  }

  func test上面plateは上を向いた閉じた面になる() {
    let mesh = shape.topPlateMesh()
    XCTAssertEqual(mesh.triangleCount, ViveTrackerShape.radialSegments)
    for position in mesh.positions {
      XCTAssertEqual(position.y, shape.heightMeters / 2, accuracy: 1e-6)
    }
    for triangle in triangles(of: mesh) {
      XCTAssertGreaterThan(
        simd_normalize(triangle.geometricNormal).y,
        0.99,
        "上面plateが下を向いている"
      )
    }
  }

  func test状態LEDとsensor窪みが表面へ沿う() {
    let statusLight = shape.statusLightAnchor
    XCTAssertLessThan(statusLight.position.z, 0)
    XCTAssertLessThan(statusLight.normal.z, -0.5)
    XCTAssertEqual(simd_length(statusLight.normal), 1, accuracy: 1e-4)

    let connector = shape.connectorAnchor
    XCTAssertGreaterThan(connector.position.z, 0)
    XCTAssertGreaterThan(connector.normal.z, 0.5)

    let wells = shape.sensorWellAnchors()
    XCTAssertEqual(wells.count, 8)
    for well in wells {
      XCTAssertEqual(simd_length(well.normal), 1, accuracy: 1e-4)
      // 上側の斜面にあるため、外向きかつ上向き成分を持つ。
      XCTAssertGreaterThan(well.normal.y, 0)
      XCTAssertGreaterThan(
        simd_dot(
          simd_normalize(SIMD3(well.normal.x, 0, well.normal.z)),
          simd_normalize(SIMD3(well.position.x, 0, well.position.z))
        ),
        0
      )
      XCTAssertEqual(
        well.position.y,
        (0.79 - 0.5) * shape.heightMeters,
        accuracy: 1e-6
      )
      // 前面のLEDと重ならない。
      XCTAssertGreaterThan(
        simd_distance(well.position, statusLight.position),
        shape.statusLightRadius + shape.sensorWellRadius
      )
    }
    XCTAssertTrue(shape.sensorWellAnchors(count: 0).isEmpty)
  }

  func testマウント台座が底面より下へ出る() {
    XCTAssertGreaterThan(shape.mountRadius, 0)
    XCTAssertLessThan(shape.mountRadius, shape.widthMeters / 2)
    XCTAssertLessThan(shape.mountCenterY, -shape.heightMeters / 2)
    XCTAssertEqual(
      shape.bottomY,
      -shape.heightMeters / 2 - shape.mountHeight,
      accuracy: 1e-6
    )
  }

  private func combinedBounds() -> (
    minimum: SIMD3<Float>, maximum: SIMD3<Float>
  ) {
    let shell = shape.shellMesh().bounds
    let plate = shape.topPlateMesh().bounds
    return (
      simd_min(shell.minimum, plate.minimum),
      simd_max(shell.maximum, plate.maximum)
    )
  }

  private struct Triangle {
    let a: SIMD3<Float>
    let b: SIMD3<Float>
    let c: SIMD3<Float>

    var centroid: SIMD3<Float> {
      (a + b + c) / 3
    }

    /// 反時計回りを表とみなした面法線。
    var geometricNormal: SIMD3<Float> {
      simd_cross(b - a, c - a)
    }
  }

  private func triangles(of mesh: ViveTrackerMesh) -> [Triangle] {
    var result: [Triangle] = []
    var offset = 0
    while offset + 2 < mesh.indices.count {
      result.append(
        Triangle(
          a: mesh.positions[Int(mesh.indices[offset])],
          b: mesh.positions[Int(mesh.indices[offset + 1])],
          c: mesh.positions[Int(mesh.indices[offset + 2])]
        )
      )
      offset += 3
    }
    return result
  }
}
