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

ビルド後にHubウィンドウが開きます。ウィンドウタイトルは表示せず、ツールバー左上の
`UDP受信 / Simulator`トグルで入力Sourceを選び、歯車ボタンで入力条件を指定してから
「開始」または「受信開始」を押します。稼働中にSourceを切り替えた場合は、選択した
Sourceへそのまま切り替わります。停止後も画面のsnapshot更新は続くため、
既定では約250ms後に`Lost`、約2秒後に`Disconnected`へ変化することを確認できます。

アプリの状態はメニューバーにも常時表示します。Hubウィンドウを閉じても監視は続き、
`停止`、`待機`、正常時のTracker台数、`要確認`、`エラー`をアイコン形状と文字で
区別します。メニューバー項目を開くと、問題の概要、入力元、実測更新レート、Tracker
台数を確認でき、Hubウィンドウの再表示と入力の開始・停止も行えます。

状態色は停止をグレー、受信待ちをブルー、正常をグリーン、注意をオレンジ、エラーを
レッドに統一します。色だけに依存せず、pause、ellipsis、checkmark、warning、
octagonの異なるsymbolと状態文字を併用します。エラー時だけsymbolを穏やかにpulse
させ、動きを減らすアクセシビリティ設定ではpulseと色遷移を停止します。

## 設計方針

macOSの運用コンソールとして、空間の動きと異常の発見を主目的にしています。常時見る
必要がない設定はツールバーのpopoverへ置き、入力状態、Tracker一覧、診断は一画面で
確認できるようにしています。

- プレビューを主役にし、装飾用のカードや見出しを重ねない
- 入力状態、更新レート、台数は一つの状態表示へまとめる
- Tracker一覧では全体を確認し、選択した1台だけ詳細を表示する
- 正常時の診断は静かに表示し、異常時だけ色と具体的な文言で注意を促す
- 同じ操作をツールバーと設定内へ重複させない
- 標準controlとsystem fontを使い、OSの外観とアクセシビリティ設定へ追従する

## 画面構成

ウィンドウ内にスクロール領域を作らず、次の固定レイアウトで情報を表示します。

- メニューバー: ウィンドウを閉じても継続する状態監視と最小限の復旧操作
- ツールバー: Liquid Glassの`UDP受信 / Simulator`トグル、開始または停止、
  右端の現在Source設定
- ライブ空間: X / -Z上面プレビューと、Source状態、更新レート、Tracker数
- 右インスペクタ上部: 最大16台のTracker一覧
- 右インスペクタ中央: 選択したTrackerのID、状態、位置、receive age
- 右インスペクタ中央: 選択したTrackerの直近6秒の位置推移
- 右インスペクタ下部: 現在のSourceに対応する診断値
- 設定popover: 選択中のSourceだけを設定し、稼働中は「設定を反映」で再起動

Trackerは常に2列の選択可能な一覧として表示し、最大16台でも一覧内のスクロールを
必要としません。選択Trackerは一覧とライブ空間の両方で強調します。8台を超える
場合は空間上のrole表示を選択Trackerだけに絞り、一覧の行高と間隔をわずかに詰めます。
ウィンドウを操作不能な大きさへ縮めないよう、最小サイズを1120×700ptに設定しています。

診断値はpopoverに隠さず、右インスペクタ下部へ常時表示します。Simulatorでは
生成、出力、frame loss、deadline missを、UDP受信ではdatagram、有効packet、
欠落frame、順序逆転、受信異常、受信処理時間を確認できます。

## Liquid Glass

macOS 26以降では、toolbar、popover、segmented picker、buttonなどの標準controlが
OSのLiquid Glassへ自動的に追従します。カスタムの`glassEffect`はライブ空間上の
状態表示とSourceトグルの選択面だけに使い、操作と状態の機能層をコンテンツから
分離します。
Liquid Glassとしてビルドする場合はXcode 26以降のSDKが必要です。古いXcodeでは
コンパイル時にGlass APIを除外し、同じ場所へ標準materialを表示します。

Sourceトグルは一つのGlassカプセルを保持したまま、選択先へ臨界減衰スプリング
（response 0.34、damping 1.0）で移動します。切替を連続して行っても、現在の
表示位置から新しい目標へ追従するため、不連続な飛びや固定duration待ちはありません。
文字はtoolbar上でも読める`callout`サイズとし、選択側だけweightを上げます。外側の
カプセルはtoolbarのGlassと重なって濁らないよう、ほぼ透明なsystem foregroundを
使い、選択面だけaccent tintを持たせます。クリック中は即座にわずかに縮小し、操作への
応答を示します。動きを減らす設定では移動animationを無効化し、透明度を下げる設定では
不透明な選択面へ切り替えます。macOS 14〜25では標準のsegmented pickerを使います。

開始・停止は入力切替の隣へ置き、設定は補助操作としてtoolbar右端へ分離します。
macOS 26ではsystemの可変`ToolbarSpacer`を間に置き、設定を画面右端へ固定します。
開始・停止ボタンのsymbolには横方向の余白を持たせ、円ではなく少し横長のsystem
buttonとして表示します。独自背景を重ねず、標準の押下feedbackとLiquid Glassへの
追従を維持します。

Appleの
[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)と
[Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
に従い、Liquid Glassは操作とnavigationの機能層だけに使います。空間プレビューと
Tracker一覧へ個別のGlassカードを重ねません。透明度を下げるアクセシビリティ設定が
有効な場合は、状態表示とSourceトグルを不透明なsystem surfaceへ切り替えます。
macOS 14〜25でも同じ情報階層を維持します。

### 個別Trackerの時系列表示

選択中Trackerについて、GUIの10Hz更新時に品質sampleを最大61点だけ保持し、直近6秒の
フレーム欠落と追跡状態を2段のタイムラインで表示します。BridgeやHubの姿勢処理とは別の
表示用履歴であり、過去フレームを実時間配信へ戻したり、90HzデータをGUIへ
キューイングしたりしません。X、Y、Zの現在位置はグラフ上部の数値で常に確認できます。

上段の「欠落」は、Simulatorでは累積drop数、UDP受信ではsequenceから検出した累積欠落数
の前回GUI sampleとの差分です。欠落を検出した約100msの区間をオレンジで表示します。
これはcaptureの厳密な発生時刻ではなく、Hubが欠落を検出したGUI sampling区間です。
下段の「追跡」は通常時に静かな緑の基準線を表示し、選択Trackerが追跡喪失または
切断状態になった区間だけを赤い帯と点で強調します。色だけでなくlane名、状態ラベル、
直近6秒の集計表示を併用します。

集計には欠落件数に加えて、次の割合を小数点以下1桁で表示します。

- 欠落率 = 欠落frame数 /（Hub適用frame数 + 欠落frame数）
- 追跡喪失率 = 選択Trackerが`lost`または`disconnected`だった時間 / 観測時間

起動後6秒未満は、その時点までに蓄積した観測窓を分母にします。UDPの分母にはdatagram数や
packet数ではなくHubへ適用したframe数を使うため、複数batchのframeでも割合が歪みません。

Sourceを開始または切り替えた時点で履歴と累積値の基準をresetし、異なるSourceやsessionの
品質を混在させません。9台以上ではタイムラインの高さを抑え、16台の一覧、選択詳細、診断を
1120×700pt内へ維持します。

## Simulator

- Tracker数: 1〜16台
- motion: 静止、円運動、歩行、ジャンプ、ランダム移動
- 更新頻度: 30 / 60 / 90 / 120Hz
- 再現用seed
- frame loss: 0〜50%
- Tracker単位のtracking lost: 0〜50%
- Simulatorの開始、設定を反映した再起動、停止
- Tracker数が増えても、初期位置を±2mプレビュー内へ収める自動間隔

設定は「開始」または「設定を反映」を押した時点で反映します。seedを含む
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
- Hubへ入力したTracker数と全体の追跡状態
- X / -Z上面図。表示範囲は原点から±2m
- 全Trackerのrole、実効tracking state、receive age
- 選択Trackerの恒久IDとX / Y / Z位置

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
