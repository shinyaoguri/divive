# Mac Hub GUI

Headless Simulatorを操作し、VIVE実機やWindowsがない状態でもMacだけで
Tracker姿勢とHubの状態評価を確認するSwiftUI開発用GUIです。

## 起動

必要環境はmacOS 14以上、Swift 6.1以上です。初回だけSwiftPMの依存取得に
network accessが必要です。

```bash
cd hub
swift run divive-hub-app
```

ビルド後に`Divive Hub`ウィンドウが開きます。左側で設定し、「開始」を押します。
停止後も画面のsnapshot更新は続くため、既定では約250ms後に`Lost`、約2秒後に
`Disconnected`へ変化することを確認できます。

## 操作できる項目

- Tracker数: 1〜16台
- motion: 静止、円運動
- 更新頻度: 30 / 60 / 90 / 120Hz
- 再現用seed
- frame loss: 0〜50%
- Tracker単位のtracking lost: 0〜50%
- Simulatorの開始、設定を反映した再起動、停止

設定は「開始」または「設定を反映して再起動」を押した時点で反映します。seedを含む
設定が同一なら、Headless Simulatorのmotionとfault列も同一です。

## 表示

- 実測出力レート
- Hubへ入力したTracker数
- 累積frame loss率とdeadline miss数
- X / -Z上面図。表示範囲は原点から±2m
- Trackerごとのrole、恒久ID、実効tracking state
- X / Y / Z位置、receive age

上面図は内部共通座標のXを画面右、-Zを画面上として表示します。これはコンテンツ用の
2D座標変換ではなく、Tracker Spaceの簡易診断表示です。

## 実時間処理の境界

```text
SimulatorEngine 30〜120Hz
  → SimulatorRuntime actor
  → HubStateStore latest state
  → 10Hz snapshot
  → SwiftUI MainActor
```

SimulatorはMainActor外で動きます。UI更新が遅れてもpose eventを蓄積せず、
`HubStateStore`のlatest snapshotだけを読みます。schedulerが1周期以上遅れた場合も、
遅延frameをburstで生成せず現在時刻から再開します。

## 現在の制約

このGUIはSimulator source専用です。次の機能は後続タスクです。

- Windows BridgeからのUDP受信とSimulatorのsource切替
- RealityKitによる3D pose表示
- TrackerごとのID、role、位置、回転編集
- scene保存・読み込み
- delay、jitter、reordering、disconnectの障害注入
- calibration、Recorder / Playback、content配信
- `.app` bundle、署名、notarization、配布

`swift run`で起動する開発用実行形式であり、現時点では配布用macOSアプリでは
ありません。
