# Changelog

このpackageの変更履歴です。[Keep a Changelog](https://keepachangelog.com/ja/1.1.0/)に
従い、versionは[Semantic Versioning](https://semver.org/lang/ja/)です。

## [0.1.0] - 2026-07-28

### Added

- Hubのstage plane（localhost UDP、message type 2）へ購読して最新姿勢を受け取る
  `DiviveHubClient`
- main threadへlatest valueを供給する`DiviveHubConnection` component
- 姿勢をTransformへ反映する`DiviveTrackerBinding` component
- canonical（右手系、`-Z`前方）からUnity座標への変換`DiviveCoordinates`
- 較正状態を表す`DiviveDelivery`と、受信ageによる`DiviveLiveness`
- `protocol/golden/stage_v1.packet.hex`を読むEditMode test
