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

ビルド後に`Divive Hub`ウィンドウが開きます。ツールバー左上の
`UDP受信 / Simulator`トグルで入力Sourceを選び、「設定」で入力条件を指定してから
「開始」または「受信開始」を押します。停止後も画面のsnapshot更新は続くため、
既定では約250ms後に`Lost`、約2秒後に`Disconnected`へ変化することを確認できます。

## 画面構成

ウィンドウ内にスクロール領域を作らず、次の固定レイアウトで情報を表示します。

- ツールバー: `UDP受信 / Simulator`トグル、設定、開始・停止
- ステータス行: Source状態、Hub更新レート、Tracker数、診断値
- 左ペイン: Tracker空間の上面プレビュー
- 右ペイン: Trackerのrole、ID、状態、位置、receive age
- 設定popover: SimulatorまたはUDPの設定

Trackerが8台以下なら1列、9〜16台なら2列で表示し、最大16台でも一覧内の
スクロールを必要としません。ウィンドウを操作不能な大きさへ縮めないよう、
最小サイズを1120×700ptに設定しています。

診断値はpopoverに隠さず、ステータス行と空間プレビューのヘッダーへ常時表示します。
Simulatorではframe loss、deadline miss、attempted / emittedを、UDP受信では
datagram、欠落frame、順序逆転、受信異常、受信処理時間を確認できます。

## Liquid Glass

macOS 26以降では、設定・開始・停止の操作にSwiftUIの`glass`または
`glassProminent` button styleを使います。popover、toolbar、Sourceトグルなどの
標準controlもOSが提供するLiquid Glassの外観とアクセシビリティ設定へ自動的に
追従します。
Liquid Glassとしてビルドする場合はXcode 26以降のSDKが必要です。古いXcodeでは
コンパイル時にGlass APIを除外し、標準のbordered buttonを使います。

Appleの
[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)と
[Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
に従い、Liquid Glassは操作とnavigationの機能層だけに使います。空間プレビューと
Tracker一覧はGlassを重ねず、標準materialのコンテンツ層として表示します。
macOS 14〜25では同じ情報階層を維持し、標準のbordered buttonへfallbackします。

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
