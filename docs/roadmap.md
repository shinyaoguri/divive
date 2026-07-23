# Roadmap

## 方針

ロードマップは機能数ではなく、リスクを早く消す順序で構成します。最大のリスクはネットワーク性能ではなく、ヘッドセットなしでTracker 3.0とUltimate Trackerを安定取得できるかです。

日付は実機検証結果と担当人数で変わるため、この文書では固定しません。1人の実装者を想定した相対規模は、M0がS、M1がM、M2がL、M3がL、M4がXLです。

## M0: Hardware Feasibility

### 目的

Windows上の取得経路を実測し、OpenVRとOpenXRの採用範囲を確定します。

### 含むもの

- Tracker 3.0、1台および3〜5台
- Ultimate Tracker、1台および可能なら3〜5台
- ヘッドセットなし
- OpenVR列挙、姿勢、速度、状態、シリアル、電池
- OpenXR `XR_HTCX_vive_tracker_interaction`の利用可否
- SteamVR/VIVE Hub再起動、Tracker再接続
- 60 / 90 / 120Hzでの重複値、欠落、ジッター

### Exit Criteria

- [ ] Tracker 3.0の採用backendが決まっている
- [ ] Ultimateの採用backend、保留、または非対応理由が決まっている
- [ ] ヘッドセットなし運用の再現手順が記録されている
- [ ] 取得可能なメタデータ一覧が記録されている
- [ ] 実機ログと検証環境がリポジトリから参照できる
- [ ] M1を続行するか、前提を変更するか判断できる

## M1: End-to-End Vertical Slice

### 目的

実機1台の姿勢がWindowsからMacへ到達する最短経路を完成させます。

### 含むもの

- C++ Bridge skeleton
- M0で選んだ1つの取得backend
- draft FlatBuffers schema
- UDP unicast
- Mac command-line receiver
- sequence、capture time、receive time、tracking state
- packet loss、out-of-order、ageの基本メトリクス
- protocol golden vectors

### 含まないもの

- GUI
- 録画
- SDK
- 自動検出
- 複数Bridgeの空間統合

### Exit Criteria

- [ ] 1台の実機姿勢が60分連続でMacへ届く
- [ ] 欠落時に古いフレームを再送しない
- [ ] Bridge/receiver再起動後に同一Tracker IDへ復帰する
- [ ] WindowsとMacで同じgolden packetを解釈できる
- [ ] ローカル有線LANでHub受信処理p99が2ms未満

## M2: Developer MVP

### 目的

実機がない日もMacでUnityコンテンツを開発できる状態にします。

### 含むもの

- Swift/SwiftUI Hub app
- Tracker一覧、状態、通信メトリクス
- role mappingの永続化
- Simulator
- 障害注入の最小セット: loss、delay、tracking lost
- Unity Package
- MCAP recorder/playback
- キャリブレーションprofileの保存・適用
- 3〜5台の同時利用

### Exit Criteria

- [ ] 実機、Simulator、Playbackが同じHub入力interfaceを使う
- [ ] Unity側がTracker IDまたはroleで最新姿勢を取得できる
- [ ] 追跡喪失と再接続イベントがUnityへ届く
- [ ] 録画をMac単体で再生できる
- [ ] profile変更時にversionが更新され、記録にも残る
- [ ] 8時間の有線LAN soak testを通過する

## M3: Content SDKs and Diagnostics

### 目的

複数の制作環境から同時利用し、問題を再現・診断できる状態にします。

### 含むもの

- Unreal Engine Plugin
- p5.js TypeScript client
- JSON WebSocket
- binary WebSocketの性能評価
- コンテンツ単位の購読・配信頻度・変換profile
- Simulator 3D表示とmotion preset
- jitter、reordering、disconnectの障害注入
- OSC adapterの要否評価

### Exit Criteria

- [ ] Unity、Unreal、Webクライアントへ同時配信できる
- [ ] 各クライアントが遅い場合もHubの取得経路をブロックしない
- [ ] p5.jsが常に最新姿勢を読み、過去フレームを蓄積しない
- [ ] 障害注入のseedを保存し、同じ試験を再現できる
- [ ] 座標変換conformance testが全SDKで一致する

## M4: Production Readiness

### 目的

展示・長時間運用・複数Bridgeへ対応します。

### 含むもの

- 複数Bridgeとtracking space管理
- 16台相当の負荷試験
- Bridge-Hub control channel
- clock offset / RTT推定
- token認証とUDP HMAC
- mDNS discoveryと明示IPの両対応
- Windows自動起動、crash recovery、ログ収集
- macOS app packaging、Windows artifact packaging
- 24時間soak test
- 運用runbook

### Exit Criteria

- [ ] Bridge単位の障害が他Bridgeやコンテンツを停止させない
- [ ] 異なるtracking spaceを未較正のまま混合しない
- [ ] 16台相当、120Hzのsynthetic loadで目標を満たす
- [ ] 24時間試験後にメモリ増加、queue成長、時刻ドリフトが許容範囲内
- [ ] runtime再起動から自動復帰できる
- [ ] LAN公開時の認証と鍵更新手順がある

## Later

- OSC adapter
- shared memoryによるローカル配信
- MessagePackまたはFlatBuffers WebSocket
- 複数Mac Hubの冗長化
- 自動空間較正
- ヘルス監視の外部export
- Linux Hub

Later項目は、具体的な利用者と受入基準が定義されるまでMilestoneへ昇格させません。

## GitHubでの追跡

- Milestoneはこの文書のM0〜M4に対応させる
- Issueは1つの検証可能な成果物に分割する
- hardware validation Issueにはログまたは記録ファイルを添付する
- ADRが必要なIssueは実装前にADR PRをmergeする
- Milestone完了時にExit Criteriaを見直し、次のMilestoneの前提を更新する
