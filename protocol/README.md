# divive wire protocol

Windows Bridge、Mac Hub ingest、Simulator、Playbackが共有するwire contractです。
取得backend固有の型を公開APIへ漏らさず、同じgolden packetを各言語で検証します。
Hubからcontent SDKへ配信するstage planeも、同じenvelopeとcanonical semanticsを
共有します。

## 2つのplane

同じenvelopeを、責務の違う2つの経路で使います。

| Plane | 経路 | Message type | Datagram上限 | Payload |
| --- | --- | ---: | ---: | --- |
| pose | Bridge → Hub | `1` | 1,200 | `DVPS` [pose.fbs](schema/pose.fbs) |
| stage | Hub → content | `2` | 8,192 | `DVST` [stage.fbs](schema/stage.fbs) |
| subscription | content → Hub | `3` | 8,192 | `DVSC` [stage_subscription.fbs](schema/stage_subscription.fbs) |

pose planeはLANを渡るためIP fragmentationを避ける必要があり、1,200 byteに収まるよう
batch分割します。stage planeは既定でloopbackに閉じるため分割せず、16台規模のTrackerを
1 datagramへ収めます。決定の背景は[ADR 0006](../docs/adr/0006-stage-plane-content-transport.md)に
あります。

decoderは自分のplaneのmessage typeだけを受理し、それ以外を
`unexpected_message_type`として拒否します。

## Protocol v1

pose planeのUDP datagram全体の上限は1,200 byteです。

```text
72-byte fixed envelope
  + FlatBuffers payload（最大1,128 byte）
```

Envelopeの整数はnetwork byte orderです。FlatBuffers payload内部のendiannessは
FlatBuffers runtimeへ任せ、手動変換しません。

| Offset | Size | Field | v1 rule |
| ---: | ---: | --- | --- |
| 0 | 4 | magic | ASCII `DVIV` |
| 4 | 1 | protocol major | `1` |
| 5 | 1 | protocol minor | `0` |
| 6 | 1 | message type | `1`: pose batch、`2`: stage frame、`3`: subscription |
| 7 | 1 | flags | M1では`0`のみ |
| 8 | 2 | header length | `72` |
| 10 | 2 | payload length | 1〜1,128 |
| 12 | 2 | batch index | 0-origin |
| 14 | 2 | batch count | 1以上 |
| 16 | 16 | session ID | RFC 4122 byte order |
| 32 | 16 | bridge ID | RFC 4122 byte order |
| 48 | 8 | frame sequence | unsigned 64-bit |
| 56 | 16 | auth tag | M1では全byte `0` |
| 72 | variable | payload | FlatBuffers `DVPS` |

`authenticated` flagと16-byte auth tagは、M4でtruncated HMAC-SHA-256を追加する
ための予約です。認証方式を実装するまではflag設定packetと非zero tagを拒否します。

同じmajor versionでは未知のminor versionを受理し、FlatBuffersの未知fieldを無視
します。majorが異なるpacketと、意味を安全に解釈できない未知flagは拒否します。

HMACなしpacketへ独自checksumは追加しません。UDP checksum、datagram length検査、
FlatBuffers verifierを使い、認証が必要な運用では将来のHMACを使います。

## Canonical pose

[schema/pose.fbs](schema/pose.fbs)がfield IDの正です。

- right-handed
- metre
- +X right、+Y up、-Z forward
- quaternion `(x, y, z, w)`
- `frame_sequence`は64-bitで、Bridge session内で単調増加
- velocityやbatteryは、対応するstructの有無でavailabilityを表現
- 未知enum値はdecoder側で`unknown`へ写像
- `role`はHubを正とし、Bridgeは通常空で送る
- runtime由来のroleは`runtime_role`へ分離

UUIDはschema内ではbig-endianの32-bit word 4個として定義します。言語runtimeが
FlatBuffers scalarのbyte orderを処理した後、RFC 4122の16-byte列へ復元します。

## Frame packetizer

C++の`packetize_pose_frame`は入力Tracker順を保つgreedy分割を行います。各候補batchを
実際にFlatBuffers encodeして1,128-byte payload budgetへ収まるか判定するため、
文字列長やoptional fieldを固定長と仮定しません。

- Tracker 0件でもframe metadataを伝える1 batchを生成
- 全batchで同じsession、bridge、frame sequence、capture/send timeを維持
- `batch_index`と`batch_count`はpacketizerが上書き
- Tracker 1件だけで上限を超える場合はframe全体を拒否
- 分割後の各datagramを再度envelope encoderで検証

MVPの最大16台ではgreedy encodeの計算量より、実際のwire sizeと上限が一致することを
優先します。profile結果で必要になった場合にbuilder再利用を最適化します。

## FlatBuffers pin

- Release: `v25.12.19-2026-02-06-03fffb2`
- Source commit: `03fffb25e2d777462b719cb4964249c30b19d58f`
- License: Apache-2.0

CMake configure時に公式`google/flatbuffers`から取得し、同じsourceから`flatc`と
C++ runtime headerを使います。

## Stage plane

Hubは較正とliveness評価を済ませた最新値だけを配信します。取得backend、Bridgeの
batch分割、未較正spaceの生の姿勢はcontentへ渡しません。

- `delivery`はTrackerごとの配信区分。`Stage` / `RawTrackerSpace` / `Blocked`
- `Blocked`のTrackerは姿勢fieldを持たない。IDとroleと状態は残す
- `liveness`は受信ageの評価で、`tracking_state`とは独立
- `batch_index` / `batch_count`は予約。v1では`0` / `1`以外を拒否する
- 購読はTTL付き。contentがTTL内に更新し続ける間だけ配信する
- Hubは既定でloopbackからの購読しか受け付けない

`requested_rate_hz`は診断表示にだけ使い、v1のHubは自身の設定rateで配信します。

## Golden vector

| Plane | Packet | 期待値 |
| --- | --- | --- |
| pose | [pose_v1.packet.hex](golden/pose_v1.packet.hex) | [pose_v1.expected.json](golden/pose_v1.expected.json) |
| stage | [stage_v1.packet.hex](golden/stage_v1.packet.hex) | [stage_v1.expected.json](golden/stage_v1.expected.json) |

`divive_protocol_tests`は、その場で生成したpose packetがhexとbyte単位で一致すること
を検査します。stage packetはSwiftの`StageFrameCodecTests`がdecodeと再encodeのbyte
一致を検査し、同じfileをUnity SDKの`DiviveStageFrameDecoderTests`が読みます。
将来のTypeScript実装もこのvectorを読みます。

Golden vectorを意図的に更新する場合:

```bash
cmake --preset macos-debug
cmake --build --preset macos-debug
./build/macos-debug/protocol/tests/divive_protocol_golden_tool
swift run --package-path hub divive-stage-golden > protocol/golden/stage_v1.packet.hex
cp protocol/golden/stage_v1.packet.hex \
  unity/com.divive.tracking/Tests/Editor/Fixtures/stage_v1.packet.hex.txt
```

出力を置き換えるだけでなく、schema compatibilityとprotocol version変更の要否を
レビューしてください。Unity Packageの写しを更新し忘れると、Hubの
`StageFrameCodecTests`が失敗します。

## Binding生成

Swift（Hub）とC#（Unity）のbindingはrepositoryへcommitしています。SwiftとC#のbuildに
flatcを要求しないためです。schemaを変えたら生成し直してcommitします。

```bash
python3 scripts/generate_bindings.py
```

`divive_protocol_swift_codegen_check`と`divive_protocol_csharp_codegen_check`が、
commit済みbindingとschemaの乖離をbuild時に検出します。
