# ADR 0006: Hubからcontentへのstage plane配信

- Status: Accepted
- Date: 2026-07-28
- Owners: divive
- Related issues: Unity SDK（作業領域E0）

## 背景

[ADR 0003](0003-flatbuffers-over-udp.md)はBridgeからHubへのpose planeを決めましたが、
Hubからcontent SDKへ何を、どの形式で渡すかは[protocol/README.md](../../protocol/README.md)で
「別途確定」としたまま保留していました。[docs/protocol.md](../protocol.md)の表には
`localhost UDP` + `envelope + FlatBuffers`と書かれていたものの、schemaもhandshakeも
決まっておらず、Unity SDKを書き始められない状態でした。

content planeはpose planeと責務が違います。

- Trackerの姿勢は較正済み（Stage Space）で渡す
- 未較正spaceのTrackerは姿勢を渡さず、渡せない理由を渡す
- 受信ageによるlivenessの評価結果を渡す
- 取得backendやBridgeのbatch分割を、contentへ見せない

Hub → contentはloopbackに閉じるため、LANを渡るpose planeとは制約も違います。

## 決定

Hubからcontentへの配信を「stage plane」と呼び、次のとおり確定します。

1. transportはUDP unicast。Hubは既定で`127.0.0.1:41321`へbindする
2. wire formatは既存の72-byte envelope + FlatBuffers payloadを再利用する
3. envelopeのmessage typeを追加する。`2`がstage frame、`3`が購読
4. schemaは[protocol/schema/stage.fbs](../../protocol/schema/stage.fbs)と
   [stage_subscription.fbs](../../protocol/schema/stage_subscription.fbs)。canonical
   semanticsとenumは`pose.fbs`をincludeして共有し、再定義しない
5. datagram上限は8,192 byteとし、v1ではbatch分割しない。envelopeの
   `batch_index` / `batch_count`は予約として残し、`1` / `0`以外を拒否する
6. contentが購読messageをTTL付きで送り、TTL内に更新し続ける間だけHubが配信する。
   Hubは既定でloopback以外からの購読を拒否する
7. 最新値優先を保つ。Hubは配信tickごとにsnapshotを取り直し、送れなかったframeを
   貯めない。SDKも受信threadでlatest valueだけを保持する
8. Stage Spaceへ変換できないTrackerは`delivery = Blocked`として姿勢を省き、
   ID、role、状態は残す

envelopeの`session_id`と`bridge_id`欄は、stage planeではHub sessionとHub instanceを
指します。購読messageでは、client sessionとclient instanceを指します。

## 検討した選択肢

### 固定長binary（content plane専用）

利点: Unity packageが第三者コード0依存になり、毎frameのallocationを0にしやすい。

欠点: schema evolutionの規則（optional field追加、未知enumのunknownへの写像、
field IDの非再利用）を自作することになる。Unreal（C++）とp5.js（TypeScript）でも
同じdecoderを書き直す必要があり、3実装の乖離をgolden vectorだけで抑えることになる。

不採用: pose planeで既にFlatBuffersのtoolchainとpinを持っており、追加費用は
C# runtimeのvendorだけ。schema 1つでSDK 3つを賄えるほうが総量が小さい。

### JSON over WebSocket

利点: 実装が最短。p5.js向けに予定しているchannelをそのまま使える。

欠点: Unityで毎frameのparseとGC負荷が出る。latest-value binaryという設計方針から
外れる。数値の精度と型を文字列表現に委ねることになる。

不採用: 人間が読むための診断channelとしては引き続き有用なので、
[docs/protocol.md](../protocol.md)のdebug用JSONとp5.js向けchannelとして残す。

### pose.fbsをそのまま再利用する

利点: schemaを増やさない。

欠点: 較正状態、liveness、blockedの区分を運べない。contentがStage Spaceの値と
Tracker Spaceの値を区別できず、未較正の姿勢を較正済みとして扱う危険がある。

不採用: content planeで最も重要な情報がwireへ乗らないため。

### 1,200 byte制限を content plane にも適用する

利点: pose planeと同じ制約で揃う。

欠点: 16台規模でbatch分割が必要になり、全SDKにframe再構成器を持たせることになる。
loopbackにIP fragmentationの問題はない。

不採用: 分割はLANへ広げる時点で必要になるため、envelopeのfieldだけ予約しておく。

## 影響

### 利点

- Unity、Unreal、Web SDKが1つのschemaを共有できる
- 未較正spaceの姿勢がcontentへ漏れない
- 購読TTLにより、contentが落ちてもHubが配信し続けない
- 既存のenvelope decoderとgolden vectorの規律をそのまま流用できる

### 欠点

- Unity packageにFlatBuffers C# runtimeをvendorする（Apache-2.0、10 file）
- Swift binding、C# bindingの生成物をrepositoryへcommitする
- message typeが増え、pose plane側のdecoderにも「想定外のmessage type」の
  判定が必要になる

### リスクと対策

- Risk: 生成物とschemaが乖離する
  - Mitigation: `divive_protocol_swift_codegen_check`と
    `divive_protocol_csharp_codegen_check`がbuild時に差分を検出する
- Risk: Unity packageに同梱したgolden fixtureが`protocol/golden`とずれる
  - Mitigation: Hubのtestが両者のbyte一致を検査する
- Risk: 認証がないまま配信先がLANへ広がる
  - Mitigation: 既定でloopback bind、かつloopback以外の購読を拒否する。
    `allowNonLoopbackClients`を明示的に有効にしない限り広がらない
- Risk: Tracker数が増えてdatagram上限を超える
  - Mitigation: encoderが`payload_too_large`で失敗し、統計へ計上する。
    silent truncateしない

## 検証

- `HubProtocolTests`: golden packetのdecode、再encodeのbyte一致、失敗系
- `HubDistributionTests`: 較正済み / 未較正 / preview modeのprojection、購読TTL、
  loopback以外の拒否、上限超過、購読者なし時の非送信
- `DiviveStageFrameDecoderTests`: 同じgolden packetをC#が同じ値へdecode
- `DiviveCoordinatesTests`: canonicalとUnityの座標変換、角速度と姿勢の整合
- `scripts/check_stage_end_to_end.py`: `divive-simulator --publish`からSDKの実装まで
  UDP越しに疎通し、frame数、decode error、位置の変化を検査

## 見直す条件

- 配信先をLANへ広げる必要が出たとき。認証（HMAC、token）とbatch分割を同時に決める
- clock mappingが入り、描画時刻に対する補間をSDKで提供するとき
- Tracker数が8,192 byteに収まらなくなったとき
- Unreal / p5.js SDKで、このschemaでは表せない要求が出たとき
