# ADR 0001: Platform nativeな実装技術スタック

- Status: Accepted
- Date: 2026-07-23

## 背景

主な開発環境はMacですが、Windows x86-64実機も使用できます。Windows BridgeはOpenVR/OpenXR/VIVE runtimeへ接続し、Mac HubはネイティブGUI、network server、Simulator、Recorderを提供します。

単一言語に統一すると、Windowsのhardware APIかMacのGUIのどちらかで追加のFFI、wrapper、非ネイティブUIが必要になります。

## 決定

platform-nativeなpolyglot構成を採用します。

- Windows Bridge: C++20、MSVC、CMake
- Mac Hub: Swift、SwiftUI、SwiftNIO
- Unity SDK: C#
- Unreal SDK: C++
- Web SDK: TypeScript
- 共通契約: FlatBuffers schema、protocol specification、golden vectors

ソースコードの共有より、wire contractとconformance testsを共有します。

## 検討した選択肢

### C#/.NET for Bridge and Hub

OpenVRの生成済みC# bindingがあり、性能も十分です。MacからWindows向けpublishもできます。一方、将来のOpenXR/VIVE固有APIではinterop更新が増え、SwiftUIよりMac GUIの選択肢が限定されます。

Bridge開発速度が主要な制約になった場合のfallbackとします。

### Node.js/Electron

GUIとWeb技術には適しますが、OpenVR取得にはnative addonまたは別processが必要です。hardware boundaryを単純化しないため不採用です。

### Rust shared core

memory safetyとcross-platform性は魅力的ですが、OpenVR/OpenXR FFI、Swift UI FFI、Unreal連携が追加されます。現在のteam/規模では言語を減らさず、統合境界を増やすため不採用です。

### C++ everywhere

hardware APIとUnrealには適しますが、SwiftUI/RealityKitを使うMac appよりGUI開発と配布の負担が増えます。

## 影響

### 利点

- vendor APIと直接接続できる
- macOSネイティブUIを構築できる
- Bridgeを小さなheadless processに保てる
- SDKが各engineの標準言語に合う

### 欠点

- 複数言語のtoolchainが必要
- protocolと座標変換のconformance testが必須
- generated codeのversion管理が必要

### リスクと対策

- Risk: 言語ごとの実装差
  - Mitigation: schema code generation、golden packets、coordinate golden tests
- Risk: C++のmemory/ownership bug
  - Mitigation: RAII、sanitizer、fuzzing、Bridgeの責務限定

## 検証

- C++/Swift間のgolden packet round-trip
- 全SDKのcoordinate conformance
- Windows BridgeとMac Hubの60分vertical slice

## 見直す条件

- C# bindingがUltimateを含めて明確に安定し、C++保守が支配的コストになった
- HubをmacOS以外へ展開する必要が生じた
- teamのtoolchain制約が変わった
