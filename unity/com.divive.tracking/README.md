# com.divive.tracking

divive Hubが配信するStage Spaceの6DoF姿勢をUnityで受け取るUPM packageです。

使い方、public contract、座標変換、テスト手順は[unity/README.md](../README.md)に
まとめています。実装の背景は次を参照してください。

- [通信プロトコル](../../docs/protocol.md)
- [stage plane wire contract](../../protocol/README.md)
- [ADR 0006](../../docs/adr/0006-stage-plane-content-transport.md)

## 構成

| 場所 | 内容 |
| --- | --- |
| `Runtime` | SDK本体 |
| `Runtime/Generated` | `protocol/schema`からflatcが生成したbinding |
| `Runtime/ThirdParty/FlatBuffers` | FlatBuffers C# runtime（Apache-2.0） |
| `Tests/Editor` | EditMode testとgolden fixture |

`Runtime/Generated`は手で編集しません。schemaを変えたら再生成します。

```bash
python3 scripts/generate_bindings.py
```
