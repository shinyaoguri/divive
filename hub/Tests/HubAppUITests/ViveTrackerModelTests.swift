import RealityKit
import XCTest
import simd

@testable import HubAppUI

final class ViveTrackerModelTests: XCTestCase {
  func test実機modelとNOTICEをbundleへ同梱する() throws {
    let url = try XCTUnwrap(ViveTrackerModelAsset.url)
    XCTAssertEqual(url.pathExtension, ViveTrackerModelAsset.resourceExtension)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

    // CC BY-SA 4.0の帰属表示を配布物から落とさない。
    let notice = try XCTUnwrap(
      Bundle.module.url(forResource: "NOTICE", withExtension: "md")
    )
    let text = try String(contentsOf: notice, encoding: .utf8)
    XCTAssertTrue(text.contains("CC BY-SA 4.0"))
    XCTAssertTrue(text.contains("qtit"))
    XCTAssertTrue(text.contains("sketchfab.com"))
  }

  func test表示幅へ等方に拡大しboundingBox中心を原点へ合わせる() {
    let placement = ViveTrackerModelPlacement(
      rotatedMinimum: SIMD3(-2, -1, 1),
      rotatedMaximum: SIMD3(2, 1, 4),
      targetWidthMeters: 0.033
    )
    XCTAssertEqual(placement.scale, 0.033 / 4, accuracy: 1e-9)
    // offsetは拡大前の座標系で与えるため、拡大率を掛けない。
    XCTAssertEqual(placement.centeringOffset.x, 0, accuracy: 1e-9)
    XCTAssertEqual(placement.centeringOffset.y, 0, accuracy: 1e-9)
    XCTAssertEqual(placement.centeringOffset.z, -2.5, accuracy: 1e-9)
    XCTAssertEqual(placement.extents.x, 0.033, accuracy: 1e-9)
    XCTAssertEqual(placement.extents.y, 2 * placement.scale, accuracy: 1e-9)
    XCTAssertEqual(placement.extents.z, 3 * placement.scale, accuracy: 1e-9)
  }

  func test退化したboundingBoxでも拡大率を有限に保つ() {
    for (minimum, maximum) in [
      (SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 0)),
      (SIMD3<Float>(.nan, 0, 0), SIMD3<Float>(.nan, 1, 1)),
    ] {
      let placement = ViveTrackerModelPlacement(
        rotatedMinimum: minimum,
        rotatedMaximum: maximum,
        targetWidthMeters: 0.033
      )
      XCTAssertEqual(placement.scale, 1)
    }

    let infiniteTarget = ViveTrackerModelPlacement(
      rotatedMinimum: SIMD3(-1, -1, -1),
      rotatedMaximum: SIMD3(1, 1, 1),
      targetWidthMeters: .infinity
    )
    XCTAssertEqual(infiniteTarget.scale, 1)
  }

  func test補正回転がassetの軸を共通pose規約へ写す() {
    let orientation = ViveTrackerModelPlacement.orientation
    // assetは+Xが上、+Yが後方、+Zが右。
    assertAxis(orientation.act(SIMD3(1, 0, 0)), equals: SIMD3(0, 1, 0))
    assertAxis(orientation.act(SIMD3(0, 1, 0)), equals: SIMD3(0, 0, 1))
    assertAxis(orientation.act(SIMD3(0, 0, 1)), equals: SIMD3(1, 0, 0))
  }

  @MainActor
  func test読み込んだmodelが指定した表示幅どおりに収まる() throws {
    guard #available(macOS 15.0, *) else {
      throw XCTSkip("3D表示はmacOS 15以降のみ")
    }
    guard
      let template = ViveTrackerModelAsset.loadTemplate(widthMeters: 0.033)
    else {
      throw XCTSkip("RealityKitがmodelを読み込めない環境")
    }

    // assetが持つscaleを潰すと100倍前後の大きさになるため、実測で押さえる。
    XCTAssertEqual(template.extents.x, 0.033, accuracy: 0.033 * 0.01)
    let bounds = template.entity.visualBounds(relativeTo: nil)
    XCTAssertEqual(bounds.extents.x, 0.033, accuracy: 0.033 * 0.01)
    XCTAssertEqual(bounds.extents.y, template.extents.y, accuracy: 1e-5)
    XCTAssertEqual(bounds.extents.z, template.extents.z, accuracy: 1e-5)
    XCTAssertLessThan(bounds.extents.y, bounds.extents.x)
    // pose原点がbounding boxの中心へ来る。
    XCTAssertLessThan(simd_length(bounds.center), 0.033 * 0.02)
  }

  @MainActor
  func test補正後のmodelが上下と前後を実機どおりに向く() throws {
    guard #available(macOS 15.0, *) else {
      throw XCTSkip("3D表示はmacOS 15以降のみ")
    }
    let url = try XCTUnwrap(ViveTrackerModelAsset.url)
    guard let source = try? Entity.load(contentsOf: url) else {
      throw XCTSkip("RealityKitがmodelを読み込めない環境")
    }
    source.orientation = ViveTrackerModelPlacement.orientation

    var points: [SIMD3<Float>] = []
    collect(source, transform: source.transform.matrix, into: &points)
    XCTAssertGreaterThan(points.count, 1_000)

    let minimum = points.reduce(points[0], simd_min)
    let maximum = points.reduce(points[0], simd_max)
    let size = maximum - minimum
    // 高さが最も薄い軸になる。
    XCTAssertLessThan(size.y, size.x)
    XCTAssertLessThan(size.y, size.z)

    let center = (minimum + maximum) / 2
    let centered = points.map { $0 - center }
    let halfWidth = size.x / 2

    // 左右へ最も張り出すのは前方(−Z)側の2つのlobe。
    let widest = try XCTUnwrap(centered.max(by: { abs($0.x) < abs($1.x) }))
    XCTAssertLessThan(widest.z, 0, "最大幅は前方の2 lobeが作る")

    // 後方(+Z)側は対称軸上の1つのlobeなので、最後端は中央にある。
    let rearmost = try XCTUnwrap(centered.max(by: { $0.z < $1.z }))
    XCTAssertLessThan(
      abs(rearmost.x),
      halfWidth * 0.15,
      "後端は対称軸上の単一lobe"
    )

    // lobeは上側で開くため、最も太い断面は上半分にある。
    let widestUpper =
      centered.filter { $0.y > 0 }
      .map { simd_length(SIMD2($0.x, $0.z)) }
      .max() ?? 0
    let widestLower =
      centered.filter { $0.y < 0 }
      .map { simd_length(SIMD2($0.x, $0.z)) }
      .max() ?? 0
    XCTAssertGreaterThan(widestUpper, widestLower, "lobeは上側で開く")
  }

  @available(macOS 15.0, *)
  @MainActor
  private func collect(
    _ entity: Entity,
    transform: float4x4,
    into points: inout [SIMD3<Float>]
  ) {
    if let model = entity.components[ModelComponent.self] {
      for part in model.mesh.contents.models.flatMap(\.parts) {
        for position in part.positions {
          let transformed = transform * SIMD4(position, 1)
          points.append(SIMD3(transformed.x, transformed.y, transformed.z))
        }
      }
    }
    for child in entity.children {
      collect(
        child,
        transform: transform * child.transform.matrix,
        into: &points
      )
    }
  }

  private func assertAxis(
    _ actual: SIMD3<Float>,
    equals expected: SIMD3<Float>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual.x, expected.x, accuracy: 1e-5, file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: 1e-5, file: file, line: line)
    XCTAssertEqual(actual.z, expected.z, accuracy: 1e-5, file: file, line: line)
  }
}
