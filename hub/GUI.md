# Mac Hub GUI

UDP Network sourceまたはHeadless Simulatorを選び、Tracker姿勢とHubの状態評価を
確認するSwiftUI開発用GUIです。VIVE実機やWindowsがない状態でもSimulatorと
Mac用test senderで開発できます。

## 起動

必要環境はmacOS 14以上、Swift 6.1以上です。初回だけSwiftPMの依存取得に
network accessが必要です。

```bash
cd hub
swift run divive-hub-app
```

ビルド後に`Divive Hub`ウィンドウが開きます。左側で入力Sourceを選び、設定後に
「開始」または「受信開始」を押します。停止後も画面のsnapshot更新は続くため、
既定では約250ms後に`Lost`、約2秒後に`Disconnected`へ変化することを確認できます。

## 画面構成

日常的な操作と診断情報を同じ強さで並べず、次の順で情報を表示します。

- サイドバー: Source選択、基本設定、開始・停止
- 詳細設定: seed、frame loss、tracking lost。通常は折りたたむ
- メイン画面: 空間プレビュー、Tracker一覧
- 上部ステータス: Hub更新レートとTracker数
- 診断情報: packetやSimulatorの詳細値。必要なときだけ展開する

空間とTracker状態を常に見える主情報とし、障害注入と通信診断は通常操作を妨げない
位置へ分離しています。

## Simulator

- Tracker数: 1〜16台
- motion: 静止、円運動、歩行、ジャンプ、ランダム移動
- 更新頻度: 30 / 60 / 90 / 120Hz
- 再現用seed
- frame loss: 0〜50%
- Tracker単位のtracking lost: 0〜50%
- Simulatorの開始、設定を反映した再起動、停止

設定は「開始」または「設定を反映して再起動」を押した時点で反映します。seedを含む
設定が同一なら、Headless Simulatorのmotionとfault列も同一です。

## UDP受信

`UDP受信`を選ぶと、次を設定できます。

- Bind address: Mac内だけなら`127.0.0.1`、同一LANから受ける場合は`0.0.0.0`
- UDP port: 既定値`41320`
- Listenerの開始、設定を反映した再起動、停止

MacだけでGUIまでの結合を確認する場合、先にGUIを`127.0.0.1:41320`で受信開始し、
別Terminalから既存のC++ test senderを実行します。

```bash
./build/macos-debug/bridge/tools/send-test/divive-bridge-send-test \
  --host 127.0.0.1 \
  --port 41320 \
  --rate 90 \
  --frames 900 \
  --trackers 5
```

senderのbuildと詳細は
[UDP send test](../bridge/tools/send-test/README.md)を参照してください。

`0.0.0.0`は同一LAN上の全interfaceから受信します。現段階ではHMAC、token、
sender allowlistがないため、信頼できるprivate LANでのみ使ってください。通常の
コンテンツ向けAPIをLAN公開する設定ではありません。

## 表示

- Hub latest stateの実測更新レート
- Hubへ入力したTracker数
- X / -Z上面図。表示範囲は原点から±2m
- Trackerごとのrole、恒久ID、実効tracking state
- X / Y / Z位置、receive age

Simulatorでは累積frame loss率とdeadline miss数を表示します。UDP受信では次を
表示します。

- 受信datagram数
- sequenceから検出した欠落frame数
- 順序逆転packet数
- 不正、重複、順序逆転、batch数不整合を合算した受信異常数
- 直近packetのdecodeとsequence判定に要した受信処理時間
- 直近senderのremote address

受信処理時間はWindowsからMacへのone-way latencyではありません。BridgeとHubの
monotonic clock mappingが未実装のため、captureから受信までの遅延はまだ断定しません。

上面図は内部共通座標のXを画面右、-Zを画面上として表示します。これはコンテンツ用の
2D座標変換ではなく、Tracker Spaceの簡易診断表示です。

## 実時間処理の境界

```text
UDPReceiver / SimulatorEngine
  → NetworkRuntime / SimulatorRuntime actor
  → HubStateStore latest state
  → 10Hz snapshot
  → SwiftUI MainActor
```

NIO callbackとSimulatorはMainActor外で動きます。UI更新が遅れてもpose eventを
蓄積せず、`HubStateStore`のlatest snapshotだけを読みます。Simulator schedulerが
1周期以上遅れた場合も、遅延frameをburstで生成せず現在時刻から再開します。
Source切替時は現在のSourceを停止し、選択した設定で新しいstateを開始します。

## 現在の制約

次の機能は後続タスクです。

- Windows実機Bridgeとの有線LAN結合検証
- mDNS discovery、sender allowlist、HMAC、control channel
- clock mapping、network jitter、one-way latency推定
- RealityKitによる3D pose表示
- TrackerごとのID、role、位置、回転編集
- scene保存・読み込み
- delay、jitter、reordering、disconnectの障害注入
- calibration、Recorder / Playback、content配信
- `.app` bundle、署名、notarization、配布

`swift run`で起動する開発用実行形式であり、現時点では配布用macOSアプリでは
ありません。
