# OpenVR実機検証probe

Windows上のSteamVRへ`VRApplication_Background`として接続し、OpenVR device inventoryとposeをJSONLへ記録します。M0のH0〜H6で使う診断用プログラムであり、production Bridgeではありません。

## 現在の範囲

- OpenVR device indexとclass
- serial、manufacturer、model、tracking system、firmware
- wireless dongle、battery、charging
- 3x4 pose matrix
- position、quaternion
- linear/angular velocity
- connected、pose valid、tracking result
- requested rateに対する実frame間隔
- valid/unique/identical pose数
- missed deadline数

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

## JSONL event

| `type` | 内容 |
| --- | --- |
| `probe_start` | SDK、runtime path、実行option |
| `device_inventory` | device classとproperty availability |
| `pose_frame` | そのtickで列挙されたdeviceのpose |
| `probe_summary` | frame間隔、deadline、device別集計 |
| `error` | OpenVR初期化などの機械可読な失敗 |

propertyは`available`、`value`、OpenVRの`error`を分離します。battery `0`やbool `false`を「未提供」と誤認しません。

## 終了code

| Code | 意味 |
| --- | --- |
| 0 | 正常終了 |
| 2 | OpenVR runtime未導入、未起動、接続失敗 |
| 64 | CLI option不正 |
| 73 | 出力fileを開けない |
| 74 | JSONL書き込み失敗 |

## 検証時の注意

- `prediction-seconds`はH4で明示的に比較する場合を除き`0`にする
- 最初は`--all-devices`でUltimateが別classとして見えないか確認する
- `--trackers-only`は`GenericTracker`以外を除外するため、H0/H2の最初には使わない
- JSONLへtoken、username、不要なmachine pathが含まれていないか共有前に確認する
- one-way latencyはこのprobeだけでは測定できない
