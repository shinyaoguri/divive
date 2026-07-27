# Headless Simulator

VIVE実機、Windows、SteamVR / VIVE Hubがない状態で、MacだけからHubへcanonical
Tracker frameを供給する開発用sourceです。GUIから独立した`HubSimulator` libraryと
`divive-simulator` CLIで構成します。

## 現在の範囲

- virtual Trackerの追加、更新、ID変更、削除
- ID、role、base pose、source tracking stateの設定
- 30 / 60 / 90 / 120Hz
- `static`、`circle`、`walk`、`jump`、`random` motion
- seed付きframe loss
- seed付きTracker単位のtracking lost
- 固定delay、±jitter、隣接frameのreordering
- 継続時間付きdisconnect
- 最大1,024 frameの有界な配信障害pipeline
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

`random`はframeごとのwhite noiseではなく、seedから生成した2つの正弦波を軸ごとに
合成する滑らかな有界軌道です。fault用の乱数列からも独立しているため、
tracking lost率を変えても同じseedとframe sequenceなら位置と速度は一致します。

frame loss時もsequenceは進みますが、Hubへframeを渡しません。tracking lost時は
frameを渡し、対象Trackerを次の状態にします。

```text
tracking_state  = lost
tracking_reason = simulated_fault
connected       = true
```

確率はframeごと、tracking lostはTrackerごとに独立して評価します。

source設定が`connected = false`または`disconnected`の場合、tracking lost注入で
上書きしません。

### 配信経路の障害

姿勢生成器とHub入力境界の間に`SimulatorTransportFaultPipeline`を置きます。
motion、frame loss、tracking lostは`SimulatorEngine`、delay、jitter、reordering、
disconnectは配信pipelineの責務です。

```text
SimulatorEngine
  → frame loss / tracking lost
  → SimulatorTransportFaultPipeline
      → delay / jitter / reordering / disconnect
  → HubStateStore.apply()
```

delayは固定値、jitterは`delay ± jitter`の範囲でseedから決定し、負の配信遅延は0へ
丸めます。reordering対象frameは2周期余分に保留し、次のframeを先に配信します。
連続する2 frameを同時にreordering対象にしないため、確率1でも隣接frameの逆転を
確実に再現できます。逆転して遅れて届いた古いframeは、実運用と同じ
`HubStateStore`のstale判定で拒否されます。

disconnectは指定確率で開始し、`disconnect-ms`の間は新規frameを破棄します。
開始前から保留していたframeも破棄し、切断復帰後に古い姿勢をburst配信しません。
既存のHub latest stateは保持されるため、既定では受信停止から250msで`lost`、
2秒で`disconnected`へ遷移します。

配信待ちqueueは最大1,024 frameです。上限到達時は最も古いsequenceを捨てて最新値を
優先し、`overflow`として計数します。これは障害試験用の意図的な有界queueであり、
通常のHub配信経路に姿勢履歴queueを追加するものではありません。pipeline用乱数は
motion/tracking faultとは別のseed系列を使います。

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

`--motion`には`static`、`circle`、`walk`、`jump`、`random`を指定できます。

| preset | 既定動作 |
| --- | --- |
| `static` | base poseで静止 |
| `circle` | X/-Z平面を円運動 |
| `walk` | 腰を小さく、左右footを逆位相で前後・上下に歩行 |
| `jump` | 全Trackerを同位相で滑らかに上下 |
| `random` | seed付きの滑らかな3軸疑似random軌道 |

これらのpresetは位置と線形速度を生成し、orientationはTrackerのbase poseを維持します。

Control-Cまで継続する場合は`--frames 0`を指定するか、省略します。

障害注入:

```bash
swift run divive-simulator \
  --frames 1200 \
  --trackers 5 \
  --rate 120 \
  --frame-loss 0.05 \
  --tracking-lost 0.10 \
  --delay-ms 25 \
  --jitter-ms 8 \
  --reordering 0.03 \
  --disconnect 0.002 \
  --disconnect-ms 2500 \
  --seed 42
```

確率は0〜1、時間は0以上の整数ミリ秒です。`--disconnect`が0より大きい場合、
`--disconnect-ms`は1以上にします。1秒ごとと終了時にattempted / emitted /
dropped / stale、disconnect回数と破棄数、pending / overflow、deadline miss、
simulated / lost / disconnected Tracker数を表示します。有限frameを指定した場合は、
最後の配信待ちframeを排出してから終了します。
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
  for delivered in transport.advance(
    toMonotonicNS: now,
    offering: frame
  ) {
    hubStateStore.apply(delivered)
  }
case .dropped:
  for delivered in transport.advance(toMonotonicNS: now) {
    hubStateStore.apply(delivered)
  }
}
```

`addTracker`、`updateTracker`、`removeTracker`でsceneを編集できます。更新時に新しい
Tracker IDを指定するとrenameになります。空ID、重複ID、非有限pose、非正規化
Quaternion、各motionの負値・非有限値・0以下の周波数は拒否します。

## 今回含まないもの

- GUIからの数値編集とscene永続化
- fault scriptの保存・読み込み
- WebSocket、Unityなど外部contentへの配信

SwiftUIの開発用GUIは[GUI.md](GUI.md)でHeadless APIへ接続し、UDP Network sourceと
切り替えられます。現在の空間表示は上面図であり、3D表示と個別Tracker編集は後続範囲
です。次段階ではRecorder / Playbackまたはcontent向け配信を同じHub入力境界へ
接続します。
