import CoreGraphics
import HubProtocol
import XCTest

@testable import HubAppUI

final class SimulatorWorkspaceTests: XCTestCase {
  func test3Dを既定候補にして直交投影を位置編集用に残す() {
    XCTAssertEqual(
      SimulatorStageViewMode.allCases.map(\.displayName),
      ["3D", "上面", "正面", "側面"]
    )
    XCTAssertNil(SimulatorStageViewMode.spatial.projection)
    XCTAssertEqual(SimulatorStageViewMode.top.projection, .top)
    XCTAssertEqual(SimulatorStageViewMode.front.projection, .front)
    XCTAssertEqual(SimulatorStageViewMode.side.projection, .side)
  }

  func test作業空間の範囲と有限値を検証する() throws {
    let workspace = try SimulatorWorkspaceDimensions(
      widthMeters: 20,
      heightMeters: 8,
      depthMeters: 12
    )
    XCTAssertEqual(workspace.widthMeters, 20)
    XCTAssertEqual(workspace.heightMeters, 8)
    XCTAssertEqual(workspace.depthMeters, 12)

    XCTAssertThrowsError(
      try SimulatorWorkspaceDimensions(
        widthMeters: 0.1,
        heightMeters: 3,
        depthMeters: 4
      )
    ) { error in
      XCTAssertEqual(
        error as? SimulatorWorkspaceDimensionsError,
        .invalidWidth
      )
    }
    XCTAssertThrowsError(
      try SimulatorWorkspaceDimensions(
        widthMeters: 4,
        heightMeters: .infinity,
        depthMeters: 4
      )
    ) { error in
      XCTAssertEqual(
        error as? SimulatorWorkspaceDimensionsError,
        .invalidHeight
      )
    }
    XCTAssertThrowsError(
      try SimulatorWorkspaceDimensions(
        widthMeters: 4,
        heightMeters: 3,
        depthMeters: 1_001
      )
    ) { error in
      XCTAssertEqual(
        error as? SimulatorWorkspaceDimensionsError,
        .invalidDepth
      )
    }
  }

  func test作業空間はXZを中央にYを床面から制限する() throws {
    let workspace = try SimulatorWorkspaceDimensions(
      widthMeters: 20,
      heightMeters: 8,
      depthMeters: 12
    )

    XCTAssertTrue(
      workspace.contains(Vector3(x: -10, y: 0, z: 6))
    )
    XCTAssertFalse(
      workspace.contains(Vector3(x: 0, y: -0.01, z: 0))
    )
    XCTAssertEqual(
      workspace.clamped(Vector3(x: 14, y: -2, z: -20)),
      Vector3(x: 10, y: 0, z: -6)
    )
  }

  func test各投影で画面座標とcanonical座標を往復する() throws {
    let workspace = try SimulatorWorkspaceDimensions(
      widthMeters: 20,
      heightMeters: 8,
      depthMeters: 12
    )
    let original = Vector3(x: 4, y: 3, z: -5)

    for projection in SimulatorStageProjection.allCases {
      let transform = SimulatorStageTransform(
        projection: projection,
        workspace: workspace,
        size: CGSize(width: 800, height: 600),
        padding: 40
      )
      let restored = transform.position(
        at: transform.point(for: original),
        preserving: original,
        clampsToWorkspace: false
      )

      XCTAssertEqual(
        restored.x,
        original.x,
        accuracy: 0.000_1,
        "\(projection)"
      )
      XCTAssertEqual(
        restored.y,
        original.y,
        accuracy: 0.000_1,
        "\(projection)"
      )
      XCTAssertEqual(
        restored.z,
        original.z,
        accuracy: 0.000_1,
        "\(projection)"
      )
    }
  }

  func test上面正面側面の操作でXYZ全軸を変更できる() throws {
    let workspace = try SimulatorWorkspaceDimensions(
      widthMeters: 20,
      heightMeters: 8,
      depthMeters: 12
    )
    let original = Vector3(x: 1, y: 2, z: -3)
    let size = CGSize(width: 800, height: 600)

    let top = SimulatorStageTransform(
      projection: .top,
      workspace: workspace,
      size: size
    ).position(
      at: CGPoint(x: 500, y: 200),
      preserving: original,
      clampsToWorkspace: false
    )
    XCTAssertNotEqual(top.x, original.x)
    XCTAssertEqual(top.y, original.y)
    XCTAssertNotEqual(top.z, original.z)

    let front = SimulatorStageTransform(
      projection: .front,
      workspace: workspace,
      size: size
    ).position(
      at: CGPoint(x: 500, y: 200),
      preserving: original,
      clampsToWorkspace: false
    )
    XCTAssertNotEqual(front.x, original.x)
    XCTAssertNotEqual(front.y, original.y)
    XCTAssertEqual(front.z, original.z)

    let side = SimulatorStageTransform(
      projection: .side,
      workspace: workspace,
      size: size
    ).position(
      at: CGPoint(x: 500, y: 200),
      preserving: original,
      clampsToWorkspace: false
    )
    XCTAssertEqual(side.x, original.x)
    XCTAssertNotEqual(side.y, original.y)
    XCTAssertNotEqual(side.z, original.z)
  }

  func test任意の縦横比を余白内へ自動fitする() throws {
    let workspace = try SimulatorWorkspaceDimensions(
      widthMeters: 100,
      heightMeters: 2.5,
      depthMeters: 7
    )
    let transform = SimulatorStageTransform(
      projection: .front,
      workspace: workspace,
      size: CGSize(width: 800, height: 600),
      padding: 40
    )

    XCTAssertEqual(transform.plotRect.minX, 40, accuracy: 0.000_1)
    XCTAssertEqual(transform.plotRect.maxX, 760, accuracy: 0.000_1)
    XCTAssertGreaterThanOrEqual(transform.plotRect.minY, 40)
    XCTAssertLessThanOrEqual(transform.plotRect.maxY, 560)
    XCTAssertTrue(
      [1.0, 2.0, 5.0].contains {
        let magnitude = pow(10, floor(log10(transform.gridStepMeters)))
        return abs(transform.gridStepMeters / magnitude - $0) < 0.000_1
      })
  }

  func test3D表示は最大辺を一定にして床と天井を中央へ写す() throws {
    let workspace = try SimulatorWorkspaceDimensions(
      widthMeters: 100,
      heightMeters: 2.5,
      depthMeters: 7
    )
    let transform = SimulatorSceneTransform(workspace: workspace)

    XCTAssertEqual(transform.scale, 0.007, accuracy: 0.000_1)
    XCTAssertEqual(transform.workspaceSize.x, 0.7, accuracy: 0.000_1)
    XCTAssertEqual(transform.workspaceSize.y, 0.0175, accuracy: 0.000_1)
    XCTAssertEqual(transform.workspaceSize.z, 0.049, accuracy: 0.000_1)

    let floor = transform.point(
      for: Vector3(x: 0, y: 0, z: 0)
    )
    let ceiling = transform.point(
      for: Vector3(x: 0, y: 2.5, z: 0)
    )
    XCTAssertEqual(floor.y, -0.00875, accuracy: 0.000_1)
    XCTAssertEqual(ceiling.y, 0.00875, accuracy: 0.000_1)
  }

  func test単位Quaternionの前方はcanonicalのマイナスZ() {
    let axes = TrackerOrientationAxes(
      orientation: Quaternion(x: 0, y: 0, z: 0, w: 1)
    )

    XCTAssertEqual(axes.right, Vector3(x: 1, y: 0, z: 0))
    XCTAssertEqual(axes.up, Vector3(x: 0, y: 1, z: 0))
    XCTAssertEqual(axes.forward, Vector3(x: 0, y: 0, z: -1))
  }

  func testY軸90度回転で前方と右方向を回転する() {
    let halfSqrt = Float(0.5.squareRoot())
    let axes = TrackerOrientationAxes(
      orientation: Quaternion(
        x: 0,
        y: halfSqrt,
        z: 0,
        w: halfSqrt
      )
    )

    XCTAssertEqual(axes.forward.x, -1, accuracy: 0.000_1)
    XCTAssertEqual(axes.forward.y, 0, accuracy: 0.000_1)
    XCTAssertEqual(axes.forward.z, 0, accuracy: 0.000_1)
    XCTAssertEqual(axes.right.x, 0, accuracy: 0.000_1)
    XCTAssertEqual(axes.right.z, -1, accuracy: 0.000_1)
  }
}
