# Headless Simulator

VIVE実機、Windows、SteamVR / VIVE Hubがない状態で、MacだけからHubへcanonical
Tracker frameを供給する開発用sourceです。GUIから独立した`HubSimulator` libraryと
`divive-simulator` CLIで構成します。

## 現在の範囲

- virtual Trackerの追加、更新、ID変更、削除
- ID、role、base pose、source tracking stateの設定
- 30 / 60 / 90 / 120Hz
- `static`、`circle` motion
- seed付きframe loss
- seed付きTracker単位のtracking lost
- `AssembledPoseFrame`を`HubFrameSink`へ直接入力
- 最大64台を指定できるCLI

Simulatorはwire protocolやUDPを試験するtoolではありません。motionとfaultを
決定論的に生成し、networkで正規化された後と同じHub入力境界を使います。
UDP/envelope/FlatBuffersの結合試験には
[Bridge UDP send test](../bridge/tools/send-test/README.md)を使います。

## 決定論

motion timeはwall clockではなく次の固定stepで求めます。

```text
simulation_time_seconds = frame_sequence / requested_rate_hz
```

同じsource設定、Tracker設定、rate、seedなら、Macの負荷や開始時刻に関係なく同じ
motionとfault列を生成します。TrackerはID順に評価し、dictionaryの走査順へ
依存させません。

frame loss時もsequenceは進みますが、Hubへframeを渡しません。tracking lost時は
frameを渡し、対象Trackerを次の状態にします。

```text
tracking_state  = lost
tracking_reason = simulated_fault
connected       = true
```

確率はframeごと、tracking lostはTrackerごとに独立して評価します。継続時間を
明示するfault scriptは後続範囲です。

source設定が`connected = false`または`disconnected`の場合、tracking lost注入で
上書きしません。

## CLI

有限frameで動作確認する例:

```bash
cd hub
swift run divive-simulator \
  --frames 900 \
  --trackers 5 \
  --rate 90 \
  --motion circle \
  --seed 42
```

Control-Cまで継続する場合は`--frames 0`を指定するか、省略します。

障害注入:

```bash
swift run divive-simulator \
  --frames 1200 \
  --trackers 5 \
  --rate 120 \
  --frame-loss 0.05 \
  --tracking-lost 0.10 \
  --seed 42
```

確率は0〜1です。1秒ごとと終了時にattempted / emitted / dropped、
deadline miss、simulated / lost / disconnected Tracker数を表示します。
`--print-pose`はframeごとの先頭Tracker姿勢を確認するときだけ使用します。

CLIが生成する既定role:

| index | role |
| --- | --- |
| 1 | `waist` |
| 2 | `left_foot` |
| 3 | `right_foot` |
| 4以降 | `prop_1`、`prop_2`、… |

## Library API

`SimulatorEngine`は実時間schedulerを持たない値型です。GUIやtestが任意の
Hub monotonic timestampで1 stepずつ進めます。

```swift
var simulator = try SimulatorEngine(
  source: sourceConfiguration,
  trackers: trackerConfigurations,
  faults: faultConfiguration
)

switch try simulator.step(receivedMonotonicNS: now) {
case .emitted(let frame):
  hubStateStore.apply(frame)
case .dropped:
  break
}
```

`addTracker`、`updateTracker`、`removeTracker`でsceneを編集できます。更新時に新しい
Tracker IDを指定するとrenameになります。空ID、重複ID、非有限pose、非正規化
Quaternion、不正なcircle値は拒否します。

## 今回含まないもの

- GUIからの数値編集とscene永続化
- walk、jump、random motion
- delay、jitter、reordering、disconnect fault
- fault scriptの保存・読み込み
- WebSocket、Unityなど外部contentへの配信

SwiftUIの開発用GUIは[GUI.md](GUI.md)でHeadless APIへ接続し、UDP Network sourceと
切り替えられます。現在の空間表示は上面図であり、3D表示と個別Tracker編集は後続範囲
です。次段階では障害注入を同じ固定seed modelへ追加します。
