# UDP send test

取得runtimeへ依存せず、simulated Tracker姿勢をWindowsまたはMacからMac Hubへ送る
M1結合テスト用CLIです。production Bridgeそのものではありません。

## 使い方

Mac側でreceiverを開始します。

```bash
cd hub
swift run divive-receiver --bind 0.0.0.0 --port 41320 --print-pose
```

Windows側でRelease buildしたsenderを実行します。

```powershell
.\build\windows-release\bridge\tools\send-test\Release\divive-bridge-send-test.exe `
  --host 192.168.1.20 `
  --port 41320 `
  --rate 90 `
  --frames 5400 `
  --trackers 5
```

Macだけで疎通を確認する場合:

```bash
./build/macos-debug/bridge/tools/send-test/divive-bridge-send-test \
  --host 127.0.0.1 \
  --frames 900
```

`--frames 0`はControl-Cまで送信します。frameが1,200 bytesに収まらない場合は
Tracker順を保った複数batchへ分割します。receiverは同一frameの未着batchを待たず、
次のframe到着時に欠落を確定します。

## このtoolで確認できること

- WindowsとMac間のUDP到達性とfirewall設定
- FlatBuffers/envelopeのcross-language互換性
- 60 / 90 / 120Hzでの受信rate
- Tracker数増加時のbatch分割
- sequence、duplicate、out-of-order、loss metricsの基本動作

OpenVR/VIVE Trackerの取得、role永続化、clock offset推定、HMACは含みません。実機
vertical sliceではM0で採用したbackendのcapture結果を、同じpacketizerとpublisherへ
接続します。
