# アーキテクチャ決定記録

ADRは「何を選んだか」だけでなく、「なぜ選び、何を捨てたか」を保持します。

| ID | タイトル | Status |
| --- | --- | --- |
| [0001](0001-platform-native-stack.md) | Platform nativeな実装技術スタック | Accepted |
| [0002](0002-openvr-first-backend.md) | 交換可能なbackendとOpenVR優先の取得 | Accepted, conditional |
| [0003](0003-flatbuffers-over-udp.md) | 実時間姿勢のFlatBuffers over UDP配信 | Accepted |
| [0004](0004-multi-bridge-architecture.md) | 複数Bridgeアーキテクチャ | Accepted |
| [0005](0005-mcap-recording.md) | 正規化frameのMCAP記録 | Accepted |
| [0006](0006-stage-plane-content-transport.md) | Hubからcontentへのstage plane配信 | Accepted |

新しいADRは[template](0000-template.md)をコピーして作成します。

## Lifecycle

```text
Proposed
  → Accepted
  → Superseded

Proposed
  → Rejected
```

実機検証を条件とする判断は`Accepted, conditional`とし、条件をADR本文とhardware testで明示します。
