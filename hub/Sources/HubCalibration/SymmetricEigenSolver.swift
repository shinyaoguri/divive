import Foundation

/// 実対称行列のJacobi固有値分解。
///
/// 3x3の共分散行列と4x4のquaternion行列しか扱わないため、外部のlinear algebra
/// 依存を足さず、決定的に解ける古典的Jacobi法を使う。
enum SymmetricEigenSolver {
  struct Decomposition {
    /// 固有値。降順。
    let values: [Double]
    /// 固有ベクトル。`vectors[i]`が`values[i]`に対応する単位ベクトル。
    let vectors: [[Double]]
  }

  /// row-majorの対称行列を分解する。
  ///
  /// - Parameters:
  ///   - matrix: `size * size`のrow-major要素。対称性は呼び出し側の責任。
  ///   - size: 行列の次数。
  static func decompose(
    _ matrix: [Double],
    size: Int,
    sweepLimit: Int = 64,
    tolerance: Double = 1.0e-14
  ) -> Decomposition {
    precondition(matrix.count == size * size, "行列の要素数が次数と一致しません")

    var a = matrix
    var v = identity(size: size)

    for _ in 0..<sweepLimit {
      if offDiagonalNorm(a, size: size) <= tolerance {
        break
      }

      for p in 0..<(size - 1) {
        for q in (p + 1)..<size {
          let apq = a[p * size + q]
          if abs(apq) <= tolerance {
            continue
          }

          // a[p][q]を0にするGivens回転を求める。
          let theta = (a[q * size + q] - a[p * size + p]) / (2 * apq)
          let signedUnit: Double = theta >= 0 ? 1 : -1
          let t = signedUnit / (abs(theta) + (theta * theta + 1).squareRoot())
          let c = 1 / (t * t + 1).squareRoot()
          let s = t * c

          rotate(&a, &v, size: size, p: p, q: q, c: c, s: s)
        }
      }
    }

    let pairs = (0..<size)
      .map { index -> (value: Double, vector: [Double]) in
        (
          value: a[index * size + index],
          vector: (0..<size).map { v[$0 * size + index] }
        )
      }
      .sorted { $0.value > $1.value }

    return Decomposition(
      values: pairs.map(\.value),
      vectors: pairs.map(\.vector)
    )
  }

  private static func rotate(
    _ a: inout [Double],
    _ v: inout [Double],
    size: Int,
    p: Int,
    q: Int,
    c: Double,
    s: Double
  ) {
    let app = a[p * size + p]
    let aqq = a[q * size + q]
    let apq = a[p * size + q]

    a[p * size + p] = c * c * app - 2 * s * c * apq + s * s * aqq
    a[q * size + q] = s * s * app + 2 * s * c * apq + c * c * aqq
    a[p * size + q] = 0
    a[q * size + p] = 0

    for k in 0..<size where k != p && k != q {
      let akp = a[k * size + p]
      let akq = a[k * size + q]
      let newAkp = c * akp - s * akq
      let newAkq = s * akp + c * akq
      a[k * size + p] = newAkp
      a[p * size + k] = newAkp
      a[k * size + q] = newAkq
      a[q * size + k] = newAkq
    }

    for k in 0..<size {
      let vkp = v[k * size + p]
      let vkq = v[k * size + q]
      v[k * size + p] = c * vkp - s * vkq
      v[k * size + q] = s * vkp + c * vkq
    }
  }

  private static func identity(size: Int) -> [Double] {
    var result = [Double](repeating: 0, count: size * size)
    for index in 0..<size {
      result[index * size + index] = 1
    }
    return result
  }

  private static func offDiagonalNorm(_ a: [Double], size: Int) -> Double {
    var sum = 0.0
    for row in 0..<size {
      for column in 0..<size where row != column {
        sum += a[row * size + column] * a[row * size + column]
      }
    }
    return sum.squareRoot()
  }
}
