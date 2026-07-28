import XCTest
import simd

@testable import HubAppUI

final class ViveTrackerShapeTests: XCTestCase {
  private let shape = ViveTrackerShape(widthMeters: 0.033)

  func test実機VIVETrackerの外寸比を保つ() {
    let depthRatio =
      ViveTrackerShape.referenceDepthMeters
      / ViveTrackerShape.referenceWidthMeters
    let heightRatio =
      ViveTrackerShape.referenceHeightMeters
      / ViveTrackerShape.referenceWidthMeters
    XCTAssertEqual(shape.depthMeters, 0.033 * depthRatio, accuracy: 1e-6)
    XCTAssertEqual(shape.heightMeters, 0.033 * heightRatio, accuracy: 1e-6)

    let bounds = shape.bodyMesh().bounds
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

  func test上面視が120度ごとの3つのlobeを持つ() {
    let samples = 360
    var points: [SIMD2<Float>] = []
    for index in 0..<samples {
      let angle = 2 * .pi * Float(index) / Float(samples)
      let point = shape.surfacePoint(heightRatio: 0.4, angle: angle)
      points.append(SIMD2(point.x, point.z))
    }
    let center =
      points.reduce(SIMD2<Float>.zero, +) / Float(samples)
    let radii = points.map { simd_length($0 - center) }

    var peakAngles: [Float] = []
    for index in 0..<samples {
      let previous = radii[(index + samples - 1) % samples]
      let next = radii[(index + 1) % samples]
      if radii[index] > previous, radii[index] >= next {
        peakAngles.append(2 * .pi * Float(index) / Float(samples))
      }
    }
    XCTAssertEqual(peakAngles.count, 3, "lobeは3つ")
    for peak in peakAngles {
      let nearest = ViveTrackerShape.lobeAngles.map {
        abs(angleDifference(peak, $0))
      }
      .min() ?? .greatestFiniteMagnitude
      XCTAssertLessThan(nearest, 0.1, "lobeは120度ごとに並ぶ")
    }

    // 前方はlobeではなくくぼみで、状態LEDを置く面になる。
    XCTAssertLessThan(radii[0], radii[samples / 6])
    XCTAssertLessThan(radii[0], radii[samples * 5 / 6])

    // X = 0平面に対する左右対称。
    for index in 1..<samples {
      let mirrored = points[samples - index]
      XCTAssertEqual(mirrored.x, -points[index].x, accuracy: 1e-6)
      XCTAssertEqual(mirrored.y, points[index].y, accuracy: 1e-6)
    }
  }

  func test上面はlobeが高くくぼみが低い鞍状になる() {
    for lobe in ViveTrackerShape.lobeAngles {
      XCTAssertEqual(shape.topHeightScale(angle: lobe), 1, accuracy: 1e-5)
    }
    XCTAssertEqual(
      shape.topHeightScale(angle: ViveTrackerShape.frontAngle),
      1 - ViveTrackerShape.saddleDepth,
      accuracy: 1e-5
    )

    let lobeTop = shape.surfacePoint(
      heightRatio: 1,
      angle: ViveTrackerShape.rearAngle
    )
    let notchTop = shape.surfacePoint(
      heightRatio: 1,
      angle: ViveTrackerShape.frontAngle
    )
    XCTAssertEqual(lobeTop.y, shape.heightMeters / 2, accuracy: 1e-6)
    XCTAssertLessThan(notchTop.y, lobeTop.y - shape.heightMeters * 0.25)
  }

  func test側面視は下端が最も太い() {
    XCTAssertEqual(shape.radiusRatio(atHeightRatio: 0.1), 1, accuracy: 1e-6)
    XCTAssertLessThan(shape.radiusRatio(atHeightRatio: 0), 1)
    XCTAssertLessThan(shape.radiusRatio(atHeightRatio: 1), 0.4)

    var previous = shape.radiusRatio(atHeightRatio: 0.1)
    for step in 1...18 {
      let heightRatio = 0.1 + 0.9 * Float(step) / 18
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
      shape.radiusRatio(atHeightRatio: 1),
      accuracy: 1e-6
    )
    for heightRatio in [Float(-2), 4, .nan] {
      let point = shape.surfacePoint(
        heightRatio: heightRatio,
        angle: ViveTrackerShape.rearAngle
      )
      XCTAssertGreaterThanOrEqual(point.y, -shape.heightMeters / 2 - 1e-6)
      XCTAssertLessThanOrEqual(point.y, shape.heightMeters / 2 + 1e-6)
    }

    for width in [Float(0), -1, .nan] {
      let degenerate = ViveTrackerShape(widthMeters: width)
      XCTAssertEqual(degenerate.widthMeters, 0.001, accuracy: 1e-9)
      XCTAssertTrue(degenerate.depthMeters.isFinite)
      for position in degenerate.bodyMesh().positions {
        XCTAssertTrue(position.x.isFinite)
        XCTAssertTrue(position.y.isFinite)
        XCTAssertTrue(position.z.isFinite)
      }
    }
  }

  func testBodyMeshの三角形と法線が外を向く() {
    let mesh = shape.bodyMesh()
    let segments = ViveTrackerShape.radialSegments
    XCTAssertEqual(mesh.positions.count, mesh.normals.count)
    XCTAssertEqual(mesh.indices.count % 3, 0)
    XCTAssertEqual(
      mesh.triangleCount,
      (ViveTrackerShape.profile.count - 1) * segments * 2 + segments * 2
    )

    for normal in mesh.normals {
      XCTAssertEqual(simd_length(normal), 1, accuracy: 1e-4)
    }

    var bottomTriangles = 0
    var topTriangles = 0
    for triangle in triangles(of: mesh) {
      let geometric = triangle.geometricNormal(of: mesh)
      XCTAssertGreaterThan(simd_length(geometric), 0)
      // 鞍状で凸ではないため、頂点法線と面法線の一致で巻き方向を判定する。
      XCTAssertGreaterThan(
        simd_dot(
          simd_normalize(geometric),
          simd_normalize(triangle.shadingNormal(of: mesh))
        ),
        0,
        "三角形の巻き方向が法線と食い違っている"
      )
      let normal = simd_normalize(geometric)
      if normal.y < -0.99 { bottomTriangles += 1 }
      if normal.y > 0.5 { topTriangles += 1 }
    }
    XCTAssertEqual(bottomTriangles, segments, "底面が閉じている")
    XCTAssertGreaterThanOrEqual(topTriangles, segments, "上面が閉じている")

    // 側面の頂点法線は本体軸から外を向く。
    for index in 0..<(ViveTrackerShape.profile.count * segments) {
      let position = mesh.positions[index]
      let radial = SIMD3<Float>(position.x, 0, position.z)
      guard simd_length(radial) > 1e-6 else { continue }
      XCTAssertGreaterThan(
        simd_dot(mesh.normals[index], simd_normalize(radial)),
        0
      )
    }
  }

  func test状態LEDとsensor窪みが表面へ沿う() {
    let statusLight = shape.statusLightAnchor
    XCTAssertLessThan(statusLight.position.z, 0, "LEDは前方のくぼみ")
    XCTAssertLessThan(statusLight.normal.z, -0.5)
    XCTAssertEqual(simd_length(statusLight.normal), 1, accuracy: 1e-4)

    let connector = shape.connectorAnchor
    XCTAssertGreaterThan(connector.position.z, 0, "USBは後方lobe")
    XCTAssertGreaterThan(connector.normal.z, 0.5)

    let wells = shape.sensorWellAnchors()
    XCTAssertEqual(wells.count, ViveTrackerShape.lobeAngles.count * 3)
    for well in wells {
      XCTAssertEqual(simd_length(well.normal), 1, accuracy: 1e-4)
      XCTAssertGreaterThan(well.normal.y, 0, "斜面なので上向き成分を持つ")
      XCTAssertGreaterThan(
        simd_dot(
          simd_normalize(SIMD3(well.normal.x, 0, well.normal.z)),
          simd_normalize(SIMD3(well.position.x, 0, well.position.z))
        ),
        0
      )
      XCTAssertGreaterThan(
        simd_distance(well.position, statusLight.position),
        shape.statusLightRadius + shape.sensorWellRadius
      )
    }
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

  /// −πからπの範囲へ畳んだ角度差。
  private func angleDifference(_ lhs: Float, _ rhs: Float) -> Float {
    var difference = lhs - rhs
    while difference > .pi { difference -= 2 * .pi }
    while difference < -.pi { difference += 2 * .pi }
    return difference
  }

  private struct Triangle {
    let a: UInt32
    let b: UInt32
    let c: UInt32

    /// 反時計回りを表とみなした面法線。
    func geometricNormal(of mesh: ViveTrackerMesh) -> SIMD3<Float> {
      let first = mesh.positions[Int(a)]
      return simd_cross(
        mesh.positions[Int(b)] - first,
        mesh.positions[Int(c)] - first
      )
    }

    /// 3頂点の法線の平均。
    func shadingNormal(of mesh: ViveTrackerMesh) -> SIMD3<Float> {
      mesh.normals[Int(a)] + mesh.normals[Int(b)] + mesh.normals[Int(c)]
    }
  }

  private func triangles(of mesh: ViveTrackerMesh) -> [Triangle] {
    var result: [Triangle] = []
    var offset = 0
    while offset + 2 < mesh.indices.count {
      result.append(
        Triangle(
          a: mesh.indices[offset],
          b: mesh.indices[offset + 1],
          c: mesh.indices[offset + 2]
        )
      )
      offset += 3
    }
    return result
  }
}
