# ADR 0002: 交換可能なbackendとOpenVR優先の取得

- Status: Accepted, conditional
- Date: 2026-07-23
- Condition: [Hardware Validation](../hardware-validation.md)のM0 Gate通過

## 背景

Tracker 3.0とUltimate TrackerをヘッドセットなしでWindowsから取得する必要があります。OpenVRはSteamVR deviceを直接列挙し、pose/propertyへアクセスできます。OpenXRにはVIVE Tracker extensionがありますが、session/action space中心で、headless用途とUltimateのruntime挙動に不確定要素があります。

UltimateはVIVE Hubから通常のVIVE Trackerとしてemulateされる可能性がありますが、実機で確認が必要です。

## 決定

- MVPの第一候補をOpenVRとする
- `ITrackingBackend`境界を設ける
- OpenXR probeをM0で実施する
- OpenVRでUltimateを取得できない場合だけOpenXR backendをproduction化する
- 非公開protocol、runtime patch、Bluetooth直結をproduction backendにしない

## 検討した選択肢

### OpenXR only

標準化と将来性は高い一方、headless session、tracker action binding、runtime拡張の可用性が未確認です。MVPの単独選択にはしません。

### VIVE-specific SDK only

Ultimate固有機能へ近い可能性がありますが、公開された汎用native APIの可用性とTracker 3.0共通化が不明です。

### Direct device protocol

runtimeを避けられる可能性がありますが、非公開仕様、firmware互換性、保守、法的/配布上のリスクが高いため不採用です。

## 影響

### 利点

- Tracker 3.0のSteamVR modelと合う
- device inventory/propertyを直接取得できる
- runtime interfaceの後方互換性を利用できる
- backend差をBridge内部に閉じ込められる

### 欠点

- SteamVRへ依存する
- headlessのnull/virtual HMD設定が運用リスクになり得る
- UltimateでOpenXR backendが追加される可能性がある

### リスクと対策

- Risk: SteamVR updateでheadless手順が壊れる
  - Mitigation: tested runtime matrix、startup diagnostics、release前hardware test
- Risk: UltimateがOpenVRへ公開されない
  - Mitigation: OpenXR probe、MVP scope decision
- Risk: backend固有fieldがpublic modelへ漏れる
  - Mitigation: canonical adapterとavailability flags

## 検証

- H1 Tracker 3.0 without HMD
- H2 Ultimate without HMD
- H3 available fields
- H4 rate/prediction
- H5 reconnect/identity

## 見直す条件

- M0でOpenVRがExit Criteriaを満たさない
- Khronos extensionとruntimeのheadless supportが安定する
- HTCがheadless向け公式native APIを提供する
