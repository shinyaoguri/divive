# Mac Hub

Mac Tracker Hubのheadless coreとSwiftUI開発用GUIです。Windows Bridgeがまだ
なくても、C++実装が生成したgolden packetをSwiftで検証し、UDP loopbackでingest経路を
試験できます。SwiftUI GUIではHeadless Simulatorを操作して、Macだけで姿勢と状態遷移を
確認できます。

## 現在の範囲

```text
UDP datagram
  → 72-byte envelope検証
  → FlatBuffers verifier
  → canonical Swift model
  → Bridge/session単位のsequence・batch判定
  → Bridgeごとに最大1つのframeを再構成
  → latest Bridge / Tracker state
  → receive ageからlivenessと実効tracking stateを評価
  → CLI snapshotと受信metrics
```

Packageは次の責務に分けています。

| Target | 責務 |
| --- | --- |
| `HubProtocol` | wire decode、canonical model、sequence/batch判定 |
| `HubNetworking` | SwiftNIO UDP socket、受信時刻、metrics |
| `HubCore` | 複数batch再構成、partial frame確定、latest state、liveness評価 |
| `HubCalibration` | rigid transform、calibration profile、space gate、profile永続化 |
| `HubSimulator` | 固定step motion、Tracker編集、seed付き生成・配信障害注入 |
| `HubAppUI` | UDP / Simulator runtime、source切替、10Hz latest snapshot、SwiftUI画面 |
| `divive-receiver` | CLI引数、診断表示、graceful shutdown |
| `divive-simulator` | Headless Simulatorの実時間CLI |
| `divive-hub-app` | macOS SwiftUI開発用GUI |

`HubProtocol`はSwiftNIOへ依存しません。今後のSimulatorとPlaybackも、decode後の
canonical modelから`HubStateStore.apply()`へ接続できます。

`HubCore`はBridgeごとに未完成frameを最大1つだけ保持します。全batchが到着すれば
直ちにcomplete frameを確定し、欠落時は次sequenceまたはsession切替時にpartial
frameとして確定します。partial frameに含まれないTrackerは前回値と更新時刻を保持
します。sessionまたはtracking spaceが変わった場合は、古いTracker stateを混在
させません。consumerはthread-safeなsnapshot、Bridge ID、または
`TrackerKey(bridgeID, trackerID)`から最新値を取得できます。

`HubStateStore.evaluatedSnapshot(atMonotonicNS:policy:)`は、latestの生データを
上書きせず、指定したHub monotonic timeにおける状態を返します。既定policyでは
receive ageが250ms以上で`stale / lost / network_stale`、2秒以上で
`disconnected / disconnected / bridge_timeout`になります。sourceが新鮮な間は、
実機が報告した`lost / runtime_pose_invalid`などをそのまま維持します。評価時刻を
引数にすることで、Simulator、Playback、unit testでも同じ境界を再現できます。

Simulatorの設計、CLI、fault semanticsは
[SIMULATOR.md](SIMULATOR.md)を参照してください。
Mac GUIの起動方法と現在の制約は[GUI.md](GUI.md)を参照してください。

## 必要環境

- macOS 14以上
- Swift 6.1以上
- network access（初回のSwiftPM依存取得時）

依存は`Package.resolved`で固定しています。

- FlatBuffers:
  `03fffb25e2d777462b719cb4964249c30b19d58f`
- SwiftNIO: `2.101.3`

## Buildとtest

```bash
cd hub
swift test
swift build -c release
```

testは次を含みます。

- C++と共通の`protocol/golden/pose_v1.packet.hex`のdecode
- envelopeおよびFlatBuffers破損packetの拒否
- loss、duplicate、out-of-order、session変更、batch欠落の分類
- batch到着順、partial確定、metadata矛盾、Tracker ID重複
- latest state、前回値保持、session / tracking space reset
- liveness policy検証、age境界、source状態保持、partialからの復帰
- SimulatorのTracker編集、fixed-step motion、seed再現性、生成・配信fault、
  有界queue、Hub sink結合
- SDK共通の`calibration/golden/transform_v1.cases.json`による変換適合性
- calibration profileのJSON往復、未較正・epoch不一致のgate、読み込み失敗の拒否
- GUI設定からのscene生成と実時間runtimeの開始・停止
- 実UDP socketを使うlocalhost loopback

## Mac GUI

```bash
cd hub
swift run divive-hub-app
```

左側でUDP受信またはSimulatorを選び、bind/portまたはSimulator sceneを設定して
開始します。詳細は[GUI.md](GUI.md)を参照してください。

## CLI

```bash
cd hub
swift run divive-receiver --bind 0.0.0.0 --port 41320
```

姿勢をpacketごとに確認するときだけ`--print-pose`を追加します。通常ログへ毎frameの
姿勢を出さず、1秒ごとに受信数、確定frame数、partial frame数、pending frame数、
latest Tracker数、fresh / stale数、実効tracking / lost / disconnected /
simulated数を表示します。

状態評価の閾値はミリ秒単位で変更できます。disconnect閾値はlost閾値より大きい値が
必要です。

```bash
swift run divive-receiver \
  --lost-after-ms 500 \
  --disconnected-after-ms 3000
```

250ms / 2秒という既定値は実機検証前の暫定値です。30Hz運用、Wi-Fi、展示環境の
計測結果からprofileごとに調整します。

`0.0.0.0` bindはWindows Bridgeから到達させるためのCLI既定値です。現段階ではHMACと
allowlistがないため、信頼できるprivate LANでのみ使い、macOS firewallでも受信元を
制限してください。将来のcontent APIをLANへ公開する指定ではありません。

## Schema code generation

生成済みSwift bindingは
`Sources/HubProtocol/Generated/pose_generated.swift`へcommitします。このファイルは
手編集しません。

```bash
cmake --preset macos-debug
cmake --build --preset macos-debug --target flatc
build/macos-debug/_deps/divive_flatbuffers-build/flatc \
  --swift \
  -o hub/Sources/HubProtocol/Generated \
  protocol/schema/pose.fbs
python3 scripts/normalize_generated_swift.py \
  hub/Sources/HubProtocol/Generated/pose_generated.swift
```

生成後は`swift test`とC++ protocol conformance testを両方実行します。CIでも生成結果と
commit済みbindingのbyte一致を検査します。

## M1で意図的に残す制約

- NIO `ByteBuffer`からFlatBuffers runtimeへ渡す際にpacketごとに1回copyする
- BridgeとHubのmonotonic clock offsetは未推定のため、one-way latencyを断定しない
- HMAC、sender allowlist、control channelは未実装
- liveness遷移eventの購読APIは未実装
- Windows実機BridgeとのGUI結合は未検証
- HMAC、allowlist、clock mapping、jitter推定は未実装
- calibrationはcore（変換、profile、gate、永続化）のみで、ingest pipelineとGUIへ
  未結線
- 較正手順の推定器、role永続化、content配信は未実装

16台×120Hzの規模では1回copyより、古いframeをqueueしないことと検証失敗を観測できる
ことを先に固定します。copy最適化は受信処理時間の計測結果を見て判断します。
