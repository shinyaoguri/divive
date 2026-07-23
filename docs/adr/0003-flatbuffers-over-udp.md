# ADR 0003: FlatBuffers over UDP for real-time pose

- Status: Accepted
- Date: 2026-07-23

## Context

Windows BridgeからMac Hubへ、最大16台相当、60〜120Hzの姿勢を送ります。過去frameの完全配送より、最新姿勢と低いjitterを優先します。C++、Swift、C#、TypeScriptで同じdata modelを扱います。

独自固定binaryは小さい一方、複数言語の手書きdecoderとschema evolutionが保守リスクになります。

## Decision

- pose dataはUDP unicast
- payloadはFlatBuffers
- 固定length envelopeでversion、sequence、batch、authを運ぶ
- datagramは既定1,200 bytes以下
- 大きなframeは複数batchへ分割
- Hubは全batchの到着を待たない
- control/status commandはWebSocket + JSON
- golden vectorsを全言語で共有

## Alternatives considered

### Hand-written fixed binary structs

最小overheadですが、alignment、endianness、optional field、version追加を全言語で手作業管理する必要があります。

### Protocol Buffers

成熟した選択ですが、hot pathでのdecode/model materializationとSwift/engine側の扱いを比較し、zero-copy accessを重視してFlatBuffersを選びます。

### MessagePack

JSONより小さく柔軟ですが、schema contractとcode generationが弱く、言語間の型差が増えます。

### TCP/WebSocket only

実装は単純ですが、packet loss時のhead-of-line blockingとslow consumerのbacklog管理がpose semanticsに合いません。controlとWeb browserには使用します。

### QUIC datagrams

securityとconnection管理を統合できますが、MVPの実装・debug・platform差が大きいため延期します。

## Consequences

### Positive

- 最新値優先がtransportと一致する
- schema evolutionと多言語codegenを利用できる
- packet captureとgolden testが可能
- control pathとpose pathの障害を分離できる

### Negative

- UDP loss、NAT/firewall、authをapplicationで扱う
- FlatBuffers build/codegen dependencyが増える
- batch欠落時のstate semanticsを実装する必要がある

### Risks and mitigations

- Risk: IP fragmentation
  - Mitigation: 1,200-byte budgetとbatch split
- Risk: stale frame表示
  - Mitigation: sequence、age threshold、latest-value store
- Risk: spoofed UDP
  - Mitigation: control authentication、session key、HMAC
- Risk: generated-code drift
  - Mitigation: compiler pinとCI regeneration check

## Validation

- packet loss/reorder/duplicate tests
- cross-language golden vectors
- 16台×120Hz synthetic load
- Wi‑Fi burst-loss test

## Revisit when

- production networkがQUICを要求する
- payload sizeまたはcodegenが支配的問題になる
- local SDK pathでshared memoryが必要になる
