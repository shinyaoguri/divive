# OpenVR実機検証probe

Windows上のSteamVRへ`VRApplication_Background`として接続し、OpenVR device inventoryとposeをJSONLへ記録します。M0のH0〜H6で使う診断用プログラムであり、production Bridgeではありません。実機poseをMacへ送るM1 CLIは[OpenVR → UDP Bridge](../../tools/openvr-bridge/README.md)を参照してください。

## 現在の範囲

- OpenVR device indexとclass
- serial、manufacturer、model、tracking system、firmware
- wireless dongle、battery、charging
- 3x4 pose matrix
- position、quaternion
- linear/angular velocity
- connected、pose valid、tracking result
- requested rateに対する実効rate、frame間隔p50 / p95 / p99
- scheduler backend、wake lateness、missed deadline
- valid/unique/identical pose数
- tracking result別sample数
- 位置差分とOpenVR報告速度から求めるkinematic discontinuity

## 固定しているSDK

- OpenVR SDK: `2.15.6`
- commit: `0924064316de3effbcd1acf1e309182a2deb1c05`
- license: BSD-3-Clause

CMake configure時に公式[ValveSoftware/openvr](https://github.com/ValveSoftware/openvr)から取得し、Windows x64用`openvr_api.lib/.dll`を使用します。release artifactにはOpenVRのlicenseを同梱します。

## 必要環境

- Windows x86-64 physical machine
- Visual Studio 2022 C++ toolchain
- CMake 3.24以上
- Git
- SteamVR
- Tracker 3.0の場合はbase stationとTracker dongle
- Ultimateの場合はVIVE HubとVIVE Wireless Dongle

probeはSteamVRを起動しません。先にSteamVRと必要なVIVE serviceを起動してください。

## Tracker 3.0のheadless設定

[Issue #12](https://github.com/shinyaoguri/divive/issues/12)のSteamVR 2.16.7実機検証では、
stock設定は`Hmd Not Found (108)`でOpenVR初期化に失敗しました。
`steamvr.vrsettings`の`steamvr` sectionへ次だけを追加すると、HMD、Null Driver、
非公式patchなしでTracker 3.0とBase Station 2.0を列挙できました。

```json
{
  "steamvr": {
    "requireHmd": false
  }
}
```

これはSteamVRの運用設定であり、公開OpenVR APIの互換性契約ではありません。
既存設定をbackupし、Bridgeから無断で書き換えず、SteamVR更新後はH0/H1を再実行します。
`probe_start.scheduler`には実際に選択したWindows schedulerも記録されます。

## Build

PowerShellでrepository rootから実行します。

```powershell
cmake --preset windows-release
cmake --build --preset windows-release
ctest --preset windows-release
```

実行fileと`openvr_api.dll`は次へ生成されます。

```text
build/windows-release/bridge/probes/openvr/Release/
```

配布可能なfolderへまとめる場合:

```powershell
cmake --install build/windows-release `
  --config Release `
  --prefix dist/windows-tools
```

## 基本実行

全deviceを30秒記録:

```powershell
.\dist\windows-tools\divive-openvr-probe.exe `
  --rate 120 `
  --duration 30 `
  --origin standing `
  --output probe.jsonl
```

Generic Trackerだけを30分記録:

```powershell
.\dist\windows-tools\divive-openvr-probe.exe `
  --trackers-only `
  --rate 120 `
  --duration 1800 `
  --inventory-interval 1 `
  --prediction-seconds 0 `
  --output tracker-30m.jsonl
```

`--duration 0`はCtrl+Cまで実行します。全optionは次で確認できます。

```powershell
.\dist\windows-tools\divive-openvr-probe.exe --help
```

## H0.5 timing / pose quality

正式なH1の前に、HMD未接続かつ`requireHmd: false`で次を別々に実行します。
`$probe`はartifactを展開した実際のpathへ合わせます。

```powershell
$probe = ".\dist\windows-tools\divive-openvr-probe.exe"
$run = "hardware-tests\runs\YYYY-MM-DD-windows-h05"

New-Item -ItemType Directory -Force "$run\raw"

# Trackerをsensorが隠れない台へ固定する。
& $probe --trackers-only --rate 120 --duration 300 `
  --inventory-interval 0 --prediction-seconds 0 `
  --output "$run\raw\fixed-120hz-5m.jsonl"

# 手でゆっくり位置移動・全方向回転する。
& $probe --trackers-only --rate 120 --duration 120 `
  --inventory-interval 0 --prediction-seconds 0 `
  --output "$run\raw\slow-motion-120hz-2m.jsonl"

# 実行中に約10秒完全遮蔽し、その後回復させる。
& $probe --trackers-only --rate 120 --duration 60 `
  --inventory-interval 0 --prediction-seconds 0 `
  --output "$run\raw\occlusion-120hz-60s.jsonl"
```

暫定判定:

- 120Hz要求に対し`effective_rate_hz >= 110`
- sequence gapとtimestamp reversalがない
- 固定試験で`kinematic_discontinuity_samples == 0`
- `running_ok`中に非物理的な位置jumpがない
- 遮蔽時のtracking resultと回復を機械可読に確認できる

これらはOpenVRの絶対精度を保証する基準ではなく、H1を解釈できる計測環境か確認する
preflightです。

## JSONL event

| `type` | 内容 |
| --- | --- |
| `probe_start` | SDK、runtime path、実行option |
| `device_inventory` | device classとproperty availability |
| `pose_frame` | そのtickで列挙されたdeviceのpose |
| `probe_summary` | frame間隔、deadline、device別集計 |
| `error` | OpenVR初期化などの機械可読な失敗 |

propertyは`available`、`value`、OpenVRの`error`を分離します。battery `0`やbool `false`を「未提供」と誤認しません。

`probe_summary`には次を含みます。

- `effective_rate_hz`
- `interval_ms`: sample数、mean、min、p50、p95、p99、max
- `wake_lateness_ms`: scheduler deadlineからの遅れ
- `tracking_result_samples`
- `running_ok_pose_samples`と`degraded_valid_pose_samples`
- 最大位置step、算出速度、OpenVR報告速度との最大差
- `kinematic_discontinuity_samples`

kinematic discontinuityは、単一step 0.1m以上、算出速度10m/s以上、OpenVR報告速度との
差5m/s以上を同時に満たすsampleです。姿勢を除去・補正するfilterではなく、
H0/H1の診断値です。

## 終了code

| Code | 意味 |
| --- | --- |
| 0 | 正常終了 |
| 2 | OpenVR runtime未導入、未起動、接続失敗 |
| 64 | CLI option不正 |
| 73 | 出力fileを開けない |
| 74 | JSONL書き込み失敗 |
| 75 | Windows schedulerの作成・待機失敗 |

## 検証時の注意

- `prediction-seconds`はH4で明示的に比較する場合を除き`0`にする
- 最初は`--all-devices`でUltimateが別classとして見えないか確認する
- `--trackers-only`は`GenericTracker`以外を除外するため、H0/H2の最初には使わない
- `pose_valid=true`と`tracking_result=running_ok`を同義に扱わない
- `kinematic_discontinuity`は原因を断定せず、SteamVR logと操作記録を照合する
- JSONLへtoken、username、不要なmachine pathが含まれていないか共有前に確認する
- one-way latencyはこのprobeだけでは測定できない
