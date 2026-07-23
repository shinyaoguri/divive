# Mac Hub headless receiver

Mac Tracker Hubのうち、GUIから独立したM1受信vertical sliceです。Windows Bridgeがまだ
なくても、C++実装が生成したgolden packetをSwiftで検証し、UDP loopbackでingest経路を
試験できます。

## 現在の範囲

```text
UDP datagram
  → 72-byte envelope検証
  → FlatBuffers verifier
  → canonical Swift model
  → Bridge/session単位のsequence・batch判定
  → CLI callbackと受信metrics
```

Packageは次の責務に分けています。

| Target | 責務 |
| --- | --- |
| `HubProtocol` | wire decode、canonical model、sequence/batch判定 |
| `HubNetworking` | SwiftNIO UDP socket、受信時刻、metrics |
| `divive-receiver` | CLI引数、診断表示、graceful shutdown |

`HubProtocol`はSwiftNIOへ依存しません。今後のSimulatorとPlaybackも、decode後の
canonical modelから同じHubCore入力へ接続します。

## 必要環境

- macOS 14以上
- Swift 6.1以上
- network access（初回のSwiftPM依存取得時）

依存は`Package.resolved`で固定しています。

- FlatBuffers:
  `03fffb25e2d777462b719cb4964249c30b19d58f`
- SwiftNIO: `2.101.3`

## Buildとtest

```bash
cd hub
swift test
swift build -c release
```

testは次を含みます。

- C++と共通の`protocol/golden/pose_v1.packet.hex`のdecode
- envelopeおよびFlatBuffers破損packetの拒否
- loss、duplicate、out-of-order、session変更、batch欠落の分類
- 実UDP socketを使うlocalhost loopback

## CLI

```bash
cd hub
swift run divive-receiver --bind 0.0.0.0 --port 41320
```

姿勢をpacketごとに確認するときだけ`--print-pose`を追加します。通常ログへ毎frameの
姿勢を出さず、1秒ごとの集計値だけを表示します。

`0.0.0.0` bindはWindows Bridgeから到達させるためのCLI既定値です。現段階ではHMACと
allowlistがないため、信頼できるprivate LANでのみ使い、macOS firewallでも受信元を
制限してください。将来のcontent APIをLANへ公開する指定ではありません。

## Schema code generation

生成済みSwift bindingは
`Sources/HubProtocol/Generated/pose_generated.swift`へcommitします。このファイルは
手編集しません。

```bash
cmake --preset macos-debug
cmake --build --preset macos-debug --target flatc
build/macos-debug/_deps/divive_flatbuffers-build/flatc \
  --swift \
  -o hub/Sources/HubProtocol/Generated \
  protocol/schema/pose.fbs
python3 scripts/normalize_generated_swift.py \
  hub/Sources/HubProtocol/Generated/pose_generated.swift
```

生成後は`swift test`とC++ protocol conformance testを両方実行します。CIでも生成結果と
commit済みbindingのbyte一致を検査します。

## M1で意図的に残す制約

- NIO `ByteBuffer`からFlatBuffers runtimeへ渡す際にpacketごとに1回copyする
- 同一frameの複数batchは順序判定するが、完全なframeへの再構成はHubCoreで実装する
- BridgeとHubのmonotonic clock offsetは未推定のため、one-way latencyを断定しない
- HMAC、sender allowlist、control channelは未実装
- GUI、calibration、最新Tracker state、content配信は未実装

16台×120Hzの規模では1回copyより、古いframeをqueueしないことと検証失敗を観測できる
ことを先に固定します。copy最適化は受信処理時間の計測結果を見て判断します。
