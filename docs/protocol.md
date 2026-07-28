# 通信プロトコル

Status: **Accepted (v1)**

この文書はwire contractの設計基準です。実装の正は
[`protocol/schema`](../protocol/schema)配下のschemaと
[`protocol/README.md`](../protocol/README.md)です。

wireは責務の違う2つのplaneに分かれます。BridgeからHubへ取得したままのTracker
Spaceを運ぶpose planeと、HubからcontentへStage Spaceの最新値を運ぶstage planeです。
stage planeの決定は[ADR 0006](adr/0006-stage-plane-content-transport.md)にあります。

## 通信レイヤー

| Path | Transport | Encoding | Reliability |
| --- | --- | --- | --- |
| Bridge → Hub pose | UDP unicast | fixed envelope + FlatBuffers | latest value |
| Bridge ↔ Hub control | WebSocket | JSON | reliable |
| Hub → Unity/Unreal stage | localhost UDP | envelope + FlatBuffers | latest value |
| Unity/Unreal → Hub subscription | localhost UDP | envelope + FlatBuffers | TTLで失効 |
| Hub → Web/p5.js | WebSocket | JSON、将来binary | reliable connection、latest value semantics |
| Hub control API | HTTP / WebSocket | JSON | reliable |

poseとcontrolを同じqueueへ入れません。

## 共通規約

- right-handed
- metres
- +X right
- +Y up
- -Z forward
- quaternion `(x, y, z, w)`
- quaternionは正規化する
- matrixをwire formatの正としない

## 識別子

bare serialだけでなくnamespaceを含めます。

```text
tracker_id = <vendor>/<product-family>/<serial>
```

例:

```text
htc/vive-tracker-3/LHR-XXXXXXXX
htc/vive-ultimate/XXXXXXXXXXXX
```

serialが取得できないdeviceにはsession-scoped IDを割り当てますが、permanent IDとは明確に区別し、role mappingを自動永続化しません。

## Envelope

UDP datagramは72-byte固定長envelopeとFlatBuffers payloadで構成します。

| Offset | Size | Field | Purpose |
| ---: | ---: | --- | --- |
| 0 | 4 | magic | ASCII `DVIV` |
| 4 | 1 | protocol major | compatibility |
| 5 | 1 | protocol minor | compatibility |
| 6 | 1 | message type | `1` pose batch、`2` stage frame、`3` subscription |
| 7 | 1 | flags | HMAC等 |
| 8 | 2 | header length | v1は72 |
| 10 | 2 | payload length | bounds check |
| 12 | 2 | batch index | 同一frameの分割 |
| 14 | 2 | batch count | 同一frameの分割 |
| 16 | 16 | session ID | Bridge process/session |
| 32 | 16 | bridge ID | Bridge identity |
| 48 | 8 | frame sequence | 実際に送信するframeの単調増加番号 |
| 56 | 16 | auth tag | 将来のtruncated HMAC |

数値はnetwork byte orderとし、C/C++ structのmemory layoutをそのまま送信しません。
FlatBuffers payload内部はFlatBuffers runtimeの規約に従います。

M1ではflagsは`0`、auth tagは全byte `0`だけを許可します。予約済み機能を暗黙に
受理せず、未対応flagはpacket単位で拒否します。

## Pose frame

Frame metadata（envelopeとFlatBuffers payloadの組み合わせ）:

- `bridge_id`（envelope）
- `session_id`（envelope）
- `tracking_space_id`
- `space_epoch`
- `frame_sequence`
- `capture_monotonic_ns`
- `send_monotonic_ns`
- `requested_rate_hz`
- `backend`

Tracker record:

- permanentまたはsession ID
- logical roleは任意
- position
- orientation quaternion
- linear velocity
- angular velocity
- velocity validity flags
- tracking state
- tracking reason/result
- connected
- battery valueとvalidity
- charging
- device metadata revision

roleはHubを正とします。Bridgeがruntime roleを報告する場合も、`runtime_role`として別fieldに入れます。

## Stage frame

Hubがcontentへ配信する最新値です。取得backend、Bridgeのbatch分割、未較正spaceの
生の姿勢はcontentへ渡しません。

Frame metadata:

- `hub_monotonic_ns`（評価に使ったHubのclock）
- `generation`（Hub stateの世代）
- `profile_id`と`profile_revision`（較正profileの識別）
- `delivery_mode`（production / preview）
- `publish_rate_hz`

Tracker record:

- permanentまたはsession ID、logical role
- `bridge_id`、`tracking_space_id`、`space_epoch`
- `delivery`（stage / raw_tracker_space / blocked）
- position、orientation、velocity（`blocked`では存在しない）
- tracking state、tracking reason
- `liveness`（fresh / stale / disconnected）
- connected、battery
- `receive_age_ns`、`source_frame_sequence`、`capture_monotonic_ns`

`delivery`と`liveness`と`tracking_state`は別物です。`delivery`はHubが較正できたか、
`liveness`は最近受信できているか、`tracking_state`はTrackerが追跡できているかを
表します。contentがこの3つを混同しないよう、それぞれ別のfieldで渡します。

envelopeの`session_id`欄はHub sessionを、`bridge_id`欄はHub instanceを指します。
Hubを再起動すると`session_id`が変わるため、contentは配信元の入れ替わりを検出できます。

### 購読

contentがHubへ購読messageを送り、TTL内に更新し続ける間だけHubが配信します。

- clientが`client_name`、`requested_rate_hz`、`ttl_ms`を送る
- HubはTTLを許容範囲へ丸め、期限を過ぎた配信先を落とす
- `unsubscribe`を立てると即座に配信先から外れる
- Hubは既定でloopback以外からの購読を拒否する
- 購読は配信先の登録であり、認証ではない

UDPは送信元を詐称できます。LANへ配信先を広げる前に、HMACとtokenを入れます。

## Datagram sizeとbatch分割

pose planeはIP fragmentationを避けるため、datagram全体を最大1,200 bytesにします。
72-byte envelopeを除いたFlatBuffers payload budgetは1,128 bytesです。

stage planeは既定でloopbackに閉じるため、この制限を共有しません。上限は8,192 bytes
とし、v1では分割しません。`batch_index`と`batch_count`はLANへ広げるときのために
予約し、`0` / `1`以外を拒否します。上限を超えるframeはsilent truncateせず、encode
errorとして統計へ計上します。

以下はpose planeのbatch規則です。

- 1 capture tickが複数datagramに分かれてよい
- batchは同じ`frame_sequence`とcapture timeを持つ
- Hubは欠けたbatchの到着を待たない
- 未着batchのTrackerは前回値を保持するがageが増える
- 次のframeを受信した時点で前frameの欠落を確定する

batch内のTracker順序に意味を持たせません。

C++ Bridge実装は、各Tracker追加後のFlatBuffers実payload長を使うgreedy分割を採用
します。Tracker数だけからpacket長を推測しません。単体Trackerがpayload budgetを
超える場合はsilent truncateせずframe生成errorとして可視化します。

Mac `HubCore`はbatch index順でTrackerを結合し、全batchが到着した時点でcomplete
frameを確定します。次sequenceまたはsession切替までに揃わなければpartial frameを
確定します。Bridgeごとの未完成frameは最大1つです。同一frame内でmetadata、
batch count、Tracker IDが矛盾するpacketはstateへ適用しません。

## 順序制御

Hubは`session_id + bridge_id`ごとにsequenceを管理します。

- sequenceが新しい: 採用
- 同一sequence、未受信batch: 採用
- 同一sequence、受信済みbatch: duplicate
- 古いsequence: metricsへ計上し、poseへ反映しない
- session ID変更: Bridge restartとしてsequence windowをリセット

sequenceは64-bit unsigned integerとします。session変更時に比較windowを
リセットするため、通常運用でのwrap-around処理は不要です。

Bridgeのcapture threadと送信threadの間はcapacity 1のlatest-value mailboxです。
送信がcaptureに追いつかない場合、まだ送信していない古いframeを上書きします。
`frame_sequence`は送信threadが選択したframeだけに連番を付けるため、送信前の
上書きをHubのpacket lossと誤認しません。上書き数はBridge側の
`overwritten_frames`として別に観測します。

## 時刻

### Clock domain

- `bridge_monotonic`
- `hub_monotonic`
- optional wall clock

monotonic timeは同一machine内での順序とdurationに使用します。異なるmachineの値を直接引いてone-way latencyとしません。

### Clock同期

control channelでNTP風の4 timestamp exchangeを繰り返し、最低RTT付近のsampleからoffsetを推定します。

- estimated offset
- RTT
- uncertainty
- last sync age

Hubがframe時刻を変換できない場合、receive timeとsequenceだけで動作し、latencyをunknownとして報告します。

wall clockは録画の検索やoperator表示にだけ使い、補間の基準にしません。

## 最新値優先のsemantics

WebSocket/TCPを使う場合も、application semanticsはlatest valueです。

- clientごとにpose backlogを無制限に持たない
- 未送信pose frameは新しいframeで置換できる
- capture threadは同期socket I/Oやpacketizeを行わない
- control response、state transition、recording commandは置換しない
- p5.js clientはmessage handlerでlatest stateを更新し、`draw()`で読む

## 状態遷移

wire上の主要状態:

- `tracking`
- `lost`
- `disconnected`
- `simulated`

補助reasonの例:

- `runtime_pose_invalid`
- `out_of_range`
- `device_unplugged`
- `bridge_timeout`
- `network_stale`
- `simulated_fault`

未知のreasonは主要状態を壊さず表示できるようにします。

### Hubのage評価

Hubはwireで受信した最新姿勢とsource報告状態を記録用の生データとして保持し、
receive ageによる状態を別のviewとして評価します。新鮮な間はsourceの
`tracking_state`と`tracking_reason`を変更しません。

既定policyは実機検証前の暫定値です。

| receive age | liveness | 実効状態 | reason |
| --- | --- | --- | --- |
| 250ms未満 | `fresh` | source報告を維持 | source報告を維持 |
| 250ms以上、2秒未満 | `stale` | `lost` | `network_stale` |
| 2秒以上 | `disconnected` | `disconnected` | `bridge_timeout` |

sourceが`connected = false`または`disconnected`を報告した場合は、ageに関係なく
直ちに`disconnected`として扱い、sourceのreasonを維持します。閾値はHub APIとCLIで
変更可能です。評価にはHubのmonotonic clockを使い、Bridgeのmonotonic timestampと
直接比較しません。

## Version管理

### Protocol version

- major: wire互換性を壊す
- minor: optional field/message追加

### Schema evolution

- field IDを再利用しない
- optional field追加を基本とする
- enumの未知値を拒否せずunknownへ写像する
- 削除fieldはdeprecatedとして予約する
- 全実装でgolden vectorsを読む

### Calibration version

protocol versionとは独立です。

- `calibration_profile_id`
- `calibration_revision`
- `space_epoch`

をframe/配信metadataに付与します。stage planeでは`profile_id`、`profile_revision`、
Trackerごとの`space_epoch`として運びます。

## 認証

MVPではprivate LANを前提にできますが、tokenをUDP payloadへ平文で付けません。

Production案:

1. WebSocketでtoken認証
2. session-scoped UDP keyを導出または配布
3. envelopeとpayloadにHMAC-SHA-256
4. tagを16 bytesへ切り詰め
5. session IDとsequenceでreplayを拒否

暗号化が必要な環境では、TLS controlとVPN/VLANを優先します。独自暗号化protocolは作りません。

## Debug用JSON形式

JSON APIは人間が読めることを優先し、binary wire layoutを模倣しません。

```json
{
  "type": "tracker_frame",
  "sequence": 42,
  "time": {
    "hubMonotonicNs": 1234567890,
    "ageMs": 3.2
  },
  "trackers": [
    {
      "id": "htc/vive-tracker-3/LHR-XXXXXXXX",
      "role": "left_foot",
      "state": "tracking",
      "position": [0.1, 1.2, -0.4],
      "orientation": [0.0, 0.0, 0.0, 1.0]
    }
  ]
}
```

## 未決定事項

- Bridge control connectionのdiscovery手順
- JSON WebSocketのrate limit
- stage planeをLANへ広げる場合の認証とbatch分割
- clock mappingが入ったあとの、描画時刻に対する補間APIの置き場

HMACなしpacketには独自checksumを追加しません。UDP checksum、length検査、
FlatBuffers verifierを使い、送信元認証が必要な段階でHMACを有効化します。
