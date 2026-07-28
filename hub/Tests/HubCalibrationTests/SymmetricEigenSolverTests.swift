import Foundation
import XCTest

@testable import HubCalibration

final class SymmetricEigenSolverTests: XCTestCase {
  private func assertUnitLength(
    _ vector: [Double],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
    XCTAssertEqual(length, 1, accuracy: 1.0e-9, file: file, line: line)
  }

  func test対角行列の固有値を降順で返す() {
    let decomposition = SymmetricEigenSolver.decompose(
      [
        3, 0, 0,
        0, 1, 0,
        0, 0, 2,
      ],
      size: 3
    )

    XCTAssertEqual(decomposition.values[0], 3, accuracy: 1.0e-12)
    XCTAssertEqual(decomposition.values[1], 2, accuracy: 1.0e-12)
    XCTAssertEqual(decomposition.values[2], 1, accuracy: 1.0e-12)
    XCTAssertEqual(abs(decomposition.vectors[0][0]), 1, accuracy: 1.0e-12)
    XCTAssertEqual(abs(decomposition.vectors[1][2]), 1, accuracy: 1.0e-12)
    XCTAssertEqual(abs(decomposition.vectors[2][1]), 1, accuracy: 1.0e-12)
  }

  func test既知の非対角行列を分解する() {
    // 固有値は5、3、1。
    let decomposition = SymmetricEigenSolver.decompose(
      [
        2, 1, 0,
        1, 2, 0,
        0, 0, 5,
      ],
      size: 3
    )

    XCTAssertEqual(decomposition.values[0], 5, accuracy: 1.0e-10)
    XCTAssertEqual(decomposition.values[1], 3, accuracy: 1.0e-10)
    XCTAssertEqual(decomposition.values[2], 1, accuracy: 1.0e-10)

    // 固有値3の固有ベクトルは(1,1,0)/√2。
    let second = decomposition.vectors[1]
    XCTAssertEqual(abs(second[0]), 1 / 2.0.squareRoot(), accuracy: 1.0e-9)
    XCTAssertEqual(abs(second[1]), 1 / 2.0.squareRoot(), accuracy: 1.0e-9)
    XCTAssertEqual(second[2], 0, accuracy: 1.0e-9)
    XCTAssertEqual(second[0] * second[1], 0.5, accuracy: 1.0e-9, "符号が揃っていません")
  }

  func test固有ベクトルが単位長で固有方程式を満たす() {
    let matrix: [Double] = [
      4, 1, -2, 0,
      1, 3, 0, 1,
      -2, 0, 5, 2,
      0, 1, 2, 6,
    ]
    let decomposition = SymmetricEigenSolver.decompose(matrix, size: 4)

    XCTAssertEqual(decomposition.values.count, 4)
    for (value, vector) in zip(decomposition.values, decomposition.vectors) {
      assertUnitLength(vector)

      // A v = λ v を確認する。
      for row in 0..<4 {
        var product = 0.0
        for column in 0..<4 {
          product += matrix[row * 4 + column] * vector[column]
        }
        XCTAssertEqual(product, value * vector[row], accuracy: 1.0e-8)
      }
    }

    // 対称行列の固有値の和はtraceに一致する。
    XCTAssertEqual(
      decomposition.values.reduce(0, +),
      4 + 3 + 5 + 6,
      accuracy: 1.0e-9
    )
  }

  func test固有値は降順に整列する() {
    let decomposition = SymmetricEigenSolver.decompose(
      [
        1, 2, 3,
        2, 4, 5,
        3, 5, 6,
      ],
      size: 3
    )

    XCTAssertGreaterThanOrEqual(decomposition.values[0], decomposition.values[1])
    XCTAssertGreaterThanOrEqual(decomposition.values[1], decomposition.values[2])
  }
}
