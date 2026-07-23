# Architecture Decision Records

ADRは「何を選んだか」だけでなく、「なぜ選び、何を捨てたか」を保持します。

| ID | Title | Status |
| --- | --- | --- |
| [0001](0001-platform-native-stack.md) | Platform-native implementation stack | Accepted |
| [0002](0002-openvr-first-backend.md) | OpenVR-first acquisition with replaceable backends | Accepted, conditional |
| [0003](0003-flatbuffers-over-udp.md) | FlatBuffers over UDP for real-time pose | Accepted |
| [0004](0004-multi-bridge-architecture.md) | Multi-Bridge architecture | Accepted |
| [0005](0005-mcap-recording.md) | MCAP recording of normalized frames | Accepted |

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
