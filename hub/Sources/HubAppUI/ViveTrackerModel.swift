import Foundation
import RealityKit
import simd

/// 同梱した実機Tracker modelのasset。
///
/// asset自体は改変せず、向きと大きさの補正は実行時のtransformだけで与える。
/// 出典とライセンスは`Resources/NOTICE.md`にまとめる。
public enum ViveTrackerModelAsset {
  public static let resourceName = "HTC_Vive_Tracker"
  public static let resourceExtension = "usdz"

  /// bundle内のasset URL。同梱されていなければnil。
  public static var url: URL? {
    Bundle.module.url(
      forResource: resourceName,
      withExtension: resourceExtension
    )
      ?? Bundle.module.url(
        forResource: resourceName,
        withExtension: resourceExtension,
        subdirectory: "Resources"
      )
  }
}

/// assetのlocal軸と大きさを、共通pose規約の表示空間へ合わせる配置。
///
/// assetは+Xが上、+Yが後方、+Zが右を向く。共通pose規約は+Yが上、−Zが前方、
/// +Xが右なので、軸をx→y→z→xと入れ替える(1, 1, 1)軸まわりの120度回転で揃う。
/// 拡大は等方に行い、bounding boxの中心をTrackerのpose原点へ合わせる。
public struct ViveTrackerModelPlacement: Equatable, Sendable {
  /// assetのlocal軸を共通pose規約へ写す回転。
  public static var orientation: simd_quatf {
    simd_quatf(
      angle: 2 * .pi / 3,
      axis: simd_normalize(SIMD3<Float>(1, 1, 1))
    )
  }

  /// 親へ与える拡大率。asset自身のscaleは保つため、親側で掛ける。
  public let scale: Float
  /// bounding box中心を原点へ寄せるoffset。拡大前の座標系で与える。
  public let centeringOffset: SIMD3<Float>
  /// 拡大後の表示寸法。
  public let extents: SIMD3<Float>

  /// 回転後のbounding boxから、拡大率と中心合わせのoffsetを求める。
  public init(
    rotatedMinimum: SIMD3<Float>,
    rotatedMaximum: SIMD3<Float>,
    targetWidthMeters: Float
  ) {
    let size = rotatedMaximum - rotatedMinimum
    let width = size.x
    let resolvedScale =
      width.isFinite && width > 1e-9 && targetWidthMeters.isFinite
      ? targetWidthMeters / width
      : 1
    scale = resolvedScale
    centeringOffset = -(rotatedMinimum + rotatedMaximum) / 2
    extents = size * resolvedScale
  }
}

@available(macOS 15.0, *)
extension ViveTrackerModelAsset {
  /// assetを読み込み、共通pose規約へ合わせたentityと表示寸法を返す。
  ///
  /// 読み込みに失敗した場合はnilを返し、呼び出し側の手続き的形状へ委ねる。
  @MainActor
  static func loadTemplate(
    widthMeters: Float
  ) -> (entity: Entity, extents: SIMD3<Float>)? {
    guard
      let url,
      let model = try? Entity.load(contentsOf: url)
    else {
      return nil
    }

    model.orientation = ViveTrackerModelPlacement.orientation
    let bounds = model.visualBounds(relativeTo: nil)
    let placement = ViveTrackerModelPlacement(
      rotatedMinimum: bounds.min,
      rotatedMaximum: bounds.max,
      targetWidthMeters: widthMeters
    )
    // assetが持つscale(USDのmetersPerUnit由来)を潰さないよう、拡大は親へ与える。
    model.position = placement.centeringOffset

    let container = Entity()
    container.name = "vive-tracker-model"
    container.scale = SIMD3(repeating: placement.scale)
    container.addChild(model)
    return (container, placement.extents)
  }
}
