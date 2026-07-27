# OpenVR → UDP Bridge

Windows上のOpenVR `GenericTracker`姿勢をcanonical modelへ正規化し、Mac Hubへ
FlatBuffers/UDPで送るM1 vertical slice用CLIです。

取得threadはOpenVRを60 / 90 / 120Hzでpollし、capacity 1のlatest-value mailboxへ
渡します。packetizeと`sendto`は専用threadで実行するため、ネットワークが遅い場合も
古い姿勢をqueueせず、未送信の値を最新frameで上書きします。

## 現在確認済みの前提

[Issue #12](https://github.com/shinyaoguri/divive/issues/12)の2026-07-27実機検証では、
次の構成でOpenVR poseを約120Hzで取得できました。

- Windows x86-64実機
- VIVE Tracker 3.0 1台
- Base Station 2.0 2台
- SteamVR 2.16.7
- HMD未接続
- `steamvr.requireHmd=false`
- Null Driver、非公式patchなし

`requireHmd`はBridgeが自動変更しません。SteamVR設定をbackupしたうえでoperatorが管理し、
SteamVR更新後はH0/H1を再実行します。Ultimate Trackerと複数Trackerは未検証です。

## Build

Windowsのrepository rootから実行します。

```powershell
cmake --preset windows-release
cmake --build --preset windows-release
ctest --preset windows-release
cmake --install build/windows-release `
  --config Release `
  --prefix dist/windows-tools
```

`dist\windows-tools\`へ次が配置されます。

- `divive-openvr-bridge.exe`
- `divive-openvr-probe.exe`
- `openvr_api.dll`
- OpenVR license

## Bridgeと追跡空間のID

`bridge_id`はWindows Bridgeのinstallation、`tracking_space_id`はSteamVRの追跡空間を
識別します。毎回生成せず、初回だけ作って安全な設定ファイルへ保存します。

```powershell
$identityDirectory = ".\config\local"
New-Item -ItemType Directory -Force $identityDirectory

if (-not (Test-Path "$identityDirectory\bridge-id.txt")) {
  [guid]::NewGuid().ToString() |
    Set-Content "$identityDirectory\bridge-id.txt" -NoNewline
}
if (-not (Test-Path "$identityDirectory\tracking-space-id.txt")) {
  [guid]::NewGuid().ToString() |
    Set-Content "$identityDirectory\tracking-space-id.txt" -NoNewline
}

$bridgeId = Get-Content "$identityDirectory\bridge-id.txt"
$trackingSpaceId = Get-Content "$identityDirectory\tracking-space-id.txt"
```

SteamVR Room Setupのやり直し、Base Station配置変更などで追跡空間の意味が変わった場合は、
`tracking_space_id`を新しくするか`space_epoch`を増やします。古いcalibrationを新しい空間へ
自動適用してはいけません。

## Mac Hubへ送る

Mac Hub GUIを起動し、`UDP受信`を選びます。同一LANから受信するため、設定を
`0.0.0.0:41320`として「受信開始」を押します。

```bash
cd hub
swift run divive-hub-app
```

MacのLAN内addressを確認し、WindowsからBridgeを起動します。

```powershell
& .\dist\windows-tools\divive-openvr-bridge.exe `
  --host 192.168.1.20 `
  --port 41320 `
  --rate 90 `
  --bridge-id $bridgeId `
  --tracking-space-id $trackingSpaceId `
  --space-epoch 1 `
  --origin standing `
  --prediction-seconds 0 `
  --duration 0
```

`--duration 0`はCtrl+Cまで送信します。標準出力にはOpenVR inventory、選択scheduler、
session/space IDと、終了時のcapture、上書き、送信、deadline統計を表示します。

Tracker IDはシリアル取得時に`openvr/serial/<serial>`として送ります。シリアルを取得
できない場合だけ`openvr/session/device-<index>`へfallbackし、再起動後の恒久IDとは
扱いません。logical roleはBridgeで付けず、Mac Hubのrole mappingを正とします。

## 状態の正規化

| OpenVR状態 | Canonical state | reason |
| --- | --- | --- |
| disconnected | `disconnected` | `device_unplugged` |
| connected、valid、`running_ok` | `tracking` | `none` |
| out of range | `lost` | `out_of_range` |
| その他のinvalid/degraded | `lost` | `runtime_pose_invalid` |

OpenVR standing spaceはcanonicalと同じ右手系、metre、+X右、+Y上、-Z前なので、
Bridgeでは軸反転しません。position、quaternion、linear/angular velocityをそのまま
canonical fieldへ写像します。battery/chargingはOpenVR propertyが利用可能な場合だけ
含めます。

## 現段階の制約

- runtime切断後の自動再初期化と指数backoffは未実装
- ID設定fileの自動作成・保護は未実装
- Hubとのclock offset推定は未実装
- UDP HMAC、sender allowlist、control channelは未実装
- Windows→Mac実機60分soakは未実施

認証前のUDP受信は信頼できるprivate LANだけで使用してください。
