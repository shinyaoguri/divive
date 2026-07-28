# Claude向け開発引き継ぎ

## この文書の目的

この文書は、別の開発端末やAI agentがGitHub上の情報だけを使ってdiviveの開発を
再開するための入口です。2026-07-28時点の基準は、calibration
core（[Issue #21](https://github.com/shinyaoguri/divive/issues/21)）と、
Hubからcontentへのstage plane配信・Unity SDKまでを取り込んだ`main`です。

進捗がこの文書より新しい場合は、次の順で判断してください。

1. open Issueの最新コメントと受け入れ条件
2. `main`のコードとtest
3. merge済みPRの本文とreview
4. この文書と[実装計画](implementation-plan.md)
5. Accepted ADR

設計判断を変更する場合は、既存ADRを書き換えて履歴を消さず、新しいADRで
supersedeします。

## 最初にClaudeへ渡すprompt

```text
shinyaoguri/divive のmainを更新し、docs/handoff.mdを最初から最後まで読んでください。
次にGitHub Issue #12と#17の最新コメント、docs/implementation-plan.md、
関連ADRを確認してください。実装前に、今回進めるIssue、受け入れ条件、実機が必要か、
protocol/calibration/recordingへの影響を日本語で整理してください。
mainへ直接commitせず、署名付きcommitとPRで進めてください。
```

## プロジェクトの目的と境界

VIVE Trackerの6DoF姿勢を、HMDなしのWindows x86-64実機で取得し、Mac Hubへ
低遅延で送信します。Unity、Unreal Engine、p5.js、独自contentはSteamVR/VIVE固有
処理を持たず、共通Tracker APIを利用します。

現在採用している基本構成は次のとおりです。

- Windows Bridge: C++20、MSVC、CMake
- Tracker 3.0取得候補: OpenVR
- Mac Hub: Swift、SwiftUI、RealityKit、SwiftNIO
- pose通信: FlatBuffers over UDP、既定1,200 byte以下
- control候補: WebSocket + JSON
- recording: MCAP + canonical FlatBuffers
- Unity: C#、Unreal: C++、Web: TypeScript

Node.js/Electronへ統一する案は、hardware APIとのnative addon境界を減らさないため
不採用です。根拠は[ADR 0001](adr/0001-platform-native-stack.md)にあります。

## 実装済みのvertical slice

### Protocol

- 72-byte envelopeとFlatBuffers schema
- 64-bit sequence、batch分割、1,200-byte datagram budget
- C++ codecとSwift decoder
- C++/Swiftで共有するgolden packet
- loss、duplicate、out-of-order、invalid packetの判定

主要な入口:

- [protocol/schema/pose.fbs](../protocol/schema/pose.fbs)
- [Protocol文書](protocol.md)
- [Protocol README](../protocol/README.md)
- [ADR 0003](adr/0003-flatbuffers-over-udp.md)

### Windows Bridge

- OpenVR device inventory / pose Probe
- Windows高分解能waitable timerとtiming metrics
- pose validityとtracking resultの分離
- kinematic discontinuity診断
- OpenVR Tracker poseからcanonical frameへの変換
- dedicated send threadとcapacity 1のlatest-value handoff
- UDP publisherと60 / 90 / 120Hz test sender
- Windows x86-64 GitHub Actions artifact

主要な入口:

- [OpenVR Probe](../bridge/probes/openvr/README.md)
- [OpenVR → UDP Bridge](../bridge/tools/openvr-bridge/README.md)
- [UDP test sender](../bridge/tools/send-test/README.md)
- [ADR 0002](adr/0002-openvr-first-backend.md)

### Mac Hub core

- SwiftNIO UDP receiver
- packet decodeとsequence/loss accounting
- 複数batchのframe再構成
- latest Tracker state
- receive ageによる`lost` / `disconnected`
- NetworkとSimulatorが共有するHub入力境界

pose frameの履歴queueは作らず、常にlatest valueを優先します。UDPで古いframeを
再送しません。WindowsとMacのmonotonic clockを直接比較してone-way latencyと
呼ばないでください。clock mappingは未実装です。

主要な入口:

- [Hub README](../hub/README.md)
- [HubCore](../hub/Sources/HubCore)
- [HubNetworking](../hub/Sources/HubNetworking)
- [HubProtocol](../hub/Sources/HubProtocol)

### Calibration core

- scaleを持たないSE(3) `RigidTransform`と合成・逆変換
- positionはrotationとtranslation、velocityはrotationだけを受ける
- `tracking_space_id`ごとのprofile entryとformat version / revision / space epoch
- 未較正は`uncalibrated`、epoch不一致は`epochMismatch`として区別
- production modeは未較正spaceを配信せず、preview modeは生Tracker Spaceを明示
- profileのJSON atomic保存と、読み込み失敗時のidentity fallback禁止
- SDK横断で共有するgolden fixture
- origin and forward手順の推定、退化検出、known pointによるresidual評価
- 評価済みHub snapshotへの較正適用と、Tracker単位の`stage` / `rawTrackerSpace` /
  `blocked`区分
- 3点以上の対応点からのpoint-set registration（Horn法、退化検出、residual）
- Mac GUIの較正popover、配信mode切替、Stage位置表示、profile永続化

GUIからの較正はorigin and forwardのみで、point-set registrationの対応点取得、
presentation scale、外れ値の採否提示は未実装です。

主要な入口:

- [HubCalibration](../hub/Sources/HubCalibration)
- [Calibration](calibration.md)
- [Calibration golden fixture](../calibration/README.md)
- [Issue #21](https://github.com/shinyaoguri/divive/issues/21)
- [Issue #23](https://github.com/shinyaoguri/divive/issues/23)
- [Issue #27](https://github.com/shinyaoguri/divive/issues/27)
- [Issue #29](https://github.com/shinyaoguri/divive/issues/29)
- [Issue #31](https://github.com/shinyaoguri/divive/issues/31)

### Stage plane配信とUnity SDK

Hubからcontentへの配信経路を「stage plane」として確定しました。判断は
[ADR 0006](adr/0006-stage-plane-content-transport.md)にあります。

- 既存の72-byte envelopeへmessage type `2`（stage frame）と`3`（購読）を追加
- `stage.fbs`は`pose.fbs`をincludeし、canonical semanticsとenumを共有する
- stage planeの上限は8,192 byte。loopback限定なのでv1では分割しない
- Swift（Hub）とC#（Unity）のbindingを生成してcommitし、乖離をbuildで検出する
- 較正済みsnapshotをTTL付き購読者へ配信する`HubDistribution`
- `blocked`のTrackerは姿勢を落とし、区分・role・状態だけを配信する
- `divive-simulator --publish`で実機なしにcontentまでの経路を確認できる
- Unity Package `com.divive.tracking`と、Play押下で動くサンプルプロジェクト
- 受信threadとmain threadを3つのsnapshotで受け渡し、定常状態のallocationを0にする
- canonical → Unity座標の変換。角速度は軸性vectorとして別式で変換する

検証はUnity 6000.5.5f1のEditorで実施済みです。EditModeでpackageのunit test 11件、
PlayModeでsampleがHubへ接続してTrackerを表示するところまで通っています。

```bash
python3 scripts/run_unity_editor_tests.py
```

CIへは入れていません。GitHubのrunnerにUnityがなく、jobを置いても常にskipされる
ためです。Editor licenseがない環境向けに、Unity同梱のRoslynと.NET runtimeで
SDKのcoreだけを検証する経路も残しています。

```bash
python3 scripts/run_unity_package_tests.py
python3 scripts/check_stage_end_to_end.py
```

主要な入口:

- [Unity SDK](../unity/README.md)
- [stage plane wire contract](../protocol/README.md)
- [HubDistribution](../hub/Sources/HubDistribution)
- [ADR 0006](adr/0006-stage-plane-content-transport.md)

### SimulatorとMac GUI

- 1〜16台、30 / 60 / 90 / 120Hz
- static、circle、walk、jump、random
- loss、tracking lost、delay、jitter、reordering、disconnect
- UDP / Simulator source切替
- Tracker一覧、状態、Network/Simulator診断
- 直近6秒のframe欠落率と追跡喪失時間率
- 上面・正面・側面の直交表示とXYZ直接編集
- 0.25〜1,000mの作業空間、自動fit、clamp、単一Undo
- macOS 15以降のRealityKit 3D表示
- local `-Z`前方とQuaternion方向軸
- Trackerを掴んだoffsetを維持する3D直接移動
- Unity / Blender型のorbit、pan、zoom、方向cube
- 仮想Base Station 2台の3D・直交表示
- メニューバーで停止、待機、正常、注意、エラーを継続監視

主要な入口:

- [Mac Hub GUI](../hub/GUI.md)
- [Simulator](../hub/SIMULATOR.md)
- [HubAppUI](../hub/Sources/HubAppUI)
- [HubSimulator](../hub/Sources/HubSimulator)
- [Issue #17](https://github.com/shinyaoguri/divive/issues/17)
- [PR #18](https://github.com/shinyaoguri/divive/pull/18)

## 実機検証の現在地

実機検証の正本は
[Issue #12](https://github.com/shinyaoguri/divive/issues/12)です。必ず最新コメントを
読んでからWindows側の操作を行ってください。

### 確認済み

限定構成:

- VIVE Tracker 3.0: 1台
- Base Station 2.0: 2台
- SteamVR: 2.16.7 default channel
- HMD / Link Box: 未接続
- `steamvr.requireHmd=false`
- Null Driver、非公式patch: 未使用

stock設定ではOpenVR初期化が`Hmd Not Found (108)`で失敗しました。
`steamvr.requireHmd=false`を明示すると、Trackerを`generic_tracker`、Base Stationを
`tracking_reference`として列挙できました。この設定は暫定的な必要条件です。
Bridgeがユーザーに無断で`steamvr.vrsettings`を変更してはいけません。

H0.5ではWindows高分解能waitable timerを使い、固定5分、緩速移動2分、遮蔽60秒を
実行しました。

- 実効rate: 3試験とも約120Hz
- deadline miss: 0
- sequence gap / timestamp reversal / JSON parse error: 0
- 固定・緩速移動の`kinematic_discontinuity_samples`: 0
- 遮蔽中はconnectionを維持し、pose/tracking stateがdegradedへ遷移
- 遮蔽解除後、`pose_valid=true / running_ok`へ機械可読に回復

この限定構成に対しては`H0.5 PASS / H1 GO`です。Ultimate、複数Tracker、
production全体の承認ではありません。

### 証跡の所在

H0.5 Evidence ZIPはWindows側ローカルにあり、Git repositoryへcommitされて
いません。

- ZIP: `dist/hardware-evidence/2026-07-27-windows-h05-evidence.zip`
- size: `13,330,040 bytes`
- SHA-256:
  `2c72e89ffd5f5941d87cf1ab8851ce52f5b80eac1e8eedf77ba9450179e57888`
- Probe SHA-256:
  `21e82fcf2f600bd9928f4202c6e4238a70845c7b8a4572621485b496d95d485f`

Mac側はこのZIP自体を保持していません。H1 GOはIssue #12へ報告された全行再parse、
manifest照合、hashを根拠にしたpreflight判定です。raw log、screenshots、Evidence
ZIPをGitへcommitしないでください。

### 次の実機タスク

H1はまだ実施していません。Issue #12最新コメントの条件で、Trackerを固定した
30分試験を次の3回実施します。

1. SteamVR clean start後
2. Tracker OFF/ONとSteamVR完全再起動後
3. Windows再起動後

1回でも初期化失敗、Probe error、serial不一致、非物理的不連続が出た場合は、
残りを惰性で続けず証跡を保存して中間報告します。

Ultimate TrackerのH2、3〜5台同時試験、Windows BridgeからMacへの有線LAN実機送信、
60分/8時間soakは未実施です。

## 現在の未完了機能

### 実機とBridge

- H1の30分×3回
- Ultimate TrackerのH2とOpenVR/OpenXR backend判断
- Windows Bridge → Mac CLI/GUIの有線LAN結合
- runtime切断時の指数backoffと再接続
- capture hot pathのframe buffer再利用
- 実機Base Station poseのBridge配信

### Hubとcontent

- GUIからのpoint-set registration対応点取得と外れ値の採否提示
- role mappingの永続化
- Mac GUIからのstage plane配信の開始・停止と状態表示（現状はCLIのみ）
- Unity SDKのmDNS discoveryと、clock mappingに基づく補間
- MCAP Recorder / Playback
- JSON WebSocket、p5.js client
- Unreal Engine Plugin
- contentごとの購読、配信頻度、座標変換profile

### Networkと運用

- control channel、clock mapping、RTT/offset推定
- mDNS、sender allowlist、token認証、UDP HMAC
- stage planeの認証。入るまで既定のloopback bindを外さない
- `.app` bundle、署名、notarization
- Windows自動起動、crash recovery、log rotation
- 複数Bridge結合と16台相当負荷試験

### Simulator Issue #17の残り

PR #18で3D直接移動と視点操作まで入りましたが、Issue #17は完了していません。

- 1軸・2軸を拘束する3軸gizmo
- 数値入力とキーボード微調整
- 初期位置へのreset
- 複数段階Undo/Redo
- scene保存・読み込み
- Canvas/3D Trackerのキーボード・VoiceOver代替操作の仕上げ

仮想Base StationはSimulator GUIだけの静的参照設備です。Tracker pose、品質統計、
録画対象へ混ぜません。実機Base Station poseは別のprotocol/Bridgeタスクです。

## 推奨する次の進め方

### Windows実機を使える場合

Issue #12のH1だけを先に実行します。H1結果のreviewが終わるまで、Tracker 3.0
backendを無条件に確定したり、Ultimate対応済みと表現したりしません。

### calibrationは実機で必要になるまで中断する

2026-07-28に、calibrationの追加実装をいったん止める判断をしました。core、2つの
推定器、Stage projection、Mac GUIの較正操作（#21、#23、#27、#29、#31）まで入って
います。

止める理由は、較正が本来は実機のための機能だからです。Simulatorが生成する
Tracker Spaceは最初からStageと一致し、実空間の設置誤差も床の傾きもありません。
Simulatorを較正する運用上の意味はなく、GUIの較正操作もWindows実機なしで経路を
確認するためのテストベッドとして作ったものです。

したがって残りのcalibration作業は、実際に使う段階が来るまで着手しません。

- GUIからのpoint-set registration対応点取得
- 外れ値の採否提示UI
- Content Profile Spaceのpresentation scale

`CalibrationPanel`はSourceに依存せず`model.trackers`の現在位置を読むだけなので、
UDP受信中の実機Trackerでも同じ手順で較正できます。ただしUDP経路での較正はまだ
testしておらず、実機Bridgeが来たときに実地で確認する必要があります。

物理calibrationのscaleは1.0を維持し、演出用presentation scaleと分離します。
複数Bridgeのspaceをcalibrationなしに混合してはいけません。詳細は
[Calibration](calibration.md)と[ADR 0004](adr/0004-multi-bridge-architecture.md)を
参照してください。

### Macだけで進める場合

Unity SDKまで通ったので、次の候補は3つです。

1. Mac GUIからstage plane配信を操作できるようにする。現状はCLIからしか配信できず、
   GUIでSimulatorを動かしながらUnityへ配信できない
2. 同じstage schemaでp5.jsまたはUnrealへ展開する。Unityで使い勝手を確定してから
   広げる順序は変えない
3. Unity SDKのmDNS discoveryを入れて、portの手入力をなくす

Recorderを先に進める場合も、記録対象はTracker Spaceのままにします。stage planeは
較正結果に依存するため、記録の正本にしません。

Simulatorを優先する場合は、Issue #17の残りを一度に実装せず、3軸gizmoと
キーボード/数値入力を別の検証可能なIssueへ分割します。

## 変更してはいけない設計上の不変条件

- canonical座標は右手系、m、`+X`右、`+Y`上、`-Z`前方
- Quaternionは正規化し、SDK境界でengine座標へ変換する
- UDPは再送せず、latest poseを優先する
- network/UI/recordingの遅さでcapture pathをblockしない
- Bridgeごとに`bridge_id`、`session_id`、`tracking_space_id`を保持する
- 異なるtracking spaceを未較正のまま混合しない
- Windows/Macのmonotonic clockをそのまま差し引かない
- OpenVR固有型やfieldをpublic canonical modelへ漏らさない
- 未較正spaceの姿勢を、Stage Spaceの値としてcontentへ渡さない
- 生成bindingを手編集せず、schemaから生成してcommitする
- `requireHmd=false`をBridgeが無断設定しない
- raw実機証跡、secret、token、個人情報をcommitしない

## GUIで維持する判断

GUIはAppleの標準controlとdesign guidelineを基準にしています。独自装飾を追加する
前に[Mac Hub GUI](../hub/GUI.md)の設計方針を確認してください。

- ウィンドウ内をスクロールしない
- app titleを画面内へ表示しない
- `UDP受信 / Simulator`は左上の滑らかな単一toggle
- 設定buttonはtoolbarの完全な右端
- 診断情報はpopoverへ隠さず主画面内へ表示
- メニューバーは状態を色、形、文字でリアルタイム表示
- Reduce Motionと色以外の識別を維持
- 3D視点はUnity/Blender型のorbit、pan、zoom
- Tracker移動と視点操作を明確に分離
- 「Trackerを回転中心にする」buttonは復活させない
- 作業空間の全体表示は斜め上の俯瞰角へ戻す
- 方向cubeは3面が同じ頂点を共有する立方体として描く

macOS 15以降ではRealityKit 3D、最小対応のmacOS 14では直交表示を使います。
macOS 26以降のLiquid Glassは標準controlへ追従し、古いSDKではmaterial fallbackを
保ちます。

## Buildとtest

### Mac

```bash
python3 scripts/check_docs.py

cmake --preset macos-debug
cmake --build --preset macos-debug
ctest --preset macos-debug
cmake --build --preset macos-debug \
  --target divive_protocol_swift_codegen_check divive_protocol_csharp_codegen_check

swift test --package-path hub
swift run --package-path hub divive-hub-app

python3 scripts/run_unity_editor_tests.py
python3 scripts/run_unity_package_tests.py
python3 scripts/check_stage_end_to_end.py
```

stage plane追加時点のHub testは203件です。test数だけでなく失敗0件を確認して
ください。Unity Package testはEditMode 11件、PlayMode 1件です。

`check_stage_end_to_end.py`は`divive-simulator --publish`を起動し、Unity SDKと同じ
C#実装でUDP受信します。Unity Editorのlicenseがなくても、SwiftのencoderとC#の
decoderが実際のsocket越しに噛み合うことを確認できます。

### Windows

```powershell
cmake --preset windows-release
cmake --build --preset windows-release
ctest --preset windows-release
cmake --install build/windows-release --config Release --prefix dist/windows-tools
```

Windows release artifactはGitHub Actionsの`divive-windows-tools-x64`です。
hardware testは通常CIではなく、Issue #12と
[Hardware Validation](hardware-validation.md)に従うmanual testです。

## GitHub運用

- 文書、Issue、PR本文、コードコメントは日本語を基本とする
- source識別子、wire field、machine-readable log keyは英語を維持する
- `main`へ直接commitしない
- feature branch、署名付きcommit、PRで進める
- ユーザーは1Passwordによる署名を要求している。署名を無効化しない
- main rulesetはPR必須、review thread解決必須、削除とnon-fast-forward禁止
- protocol、architecture、calibration、recordingの判断変更はADRを先に確認する
- 実機依存の結論は機材、runtime、firmware、手順、証跡hashを残す
- 未完了項目を文書だけのTODOにせず、検証可能なIssueへ切り出す

## 主要な実装履歴

| PR | 内容 |
| --- | --- |
| [#1](https://github.com/shinyaoguri/divive/pull/1) | 要求、architecture、ADR、roadmap |
| [#2](https://github.com/shinyaoguri/divive/pull/2) | OpenVR Probe |
| [#3](https://github.com/shinyaoguri/divive/pull/3) | wire protocol v1 |
| [#4](https://github.com/shinyaoguri/divive/pull/4) | Swift UDP receiver |
| [#5](https://github.com/shinyaoguri/divive/pull/5) | C++ UDP publisher |
| [#6](https://github.com/shinyaoguri/divive/pull/6) | latest-value handoff |
| [#7](https://github.com/shinyaoguri/divive/pull/7) | Hub state pipeline |
| [#8](https://github.com/shinyaoguri/divive/pull/8) | Hub liveness |
| [#9](https://github.com/shinyaoguri/divive/pull/9) | Headless Simulator |
| [#10](https://github.com/shinyaoguri/divive/pull/10) | SwiftUI GUI |
| [#11](https://github.com/shinyaoguri/divive/pull/11) | GUI UDP source |
| [#13](https://github.com/shinyaoguri/divive/pull/13) | Probe timing / pose品質 |
| [#14](https://github.com/shinyaoguri/divive/pull/14) | Simulator拡張とGUI再構成 |
| [#15](https://github.com/shinyaoguri/divive/pull/15) | OpenVR pose → UDP Bridge |
| [#16](https://github.com/shinyaoguri/divive/pull/16) | Simulator transport障害注入 |
| [#18](https://github.com/shinyaoguri/divive/pull/18) | 3D viewportと直接操作 |
| [#22](https://github.com/shinyaoguri/divive/pull/22)〜[#32](https://github.com/shinyaoguri/divive/pull/32) | calibration coreとMac GUIの較正 |

PR本文には実装理由、検証結果、手動確認項目が残っています。特定機能の設計意図を
調べる場合は、`git blame`だけでなく対応PRも読んでください。
