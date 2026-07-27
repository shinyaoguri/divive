# 実機検証計画

## 目的

この計画は、実装で隠せないハードウェア/runtime依存を最初に検証するためのGate 0です。成功した手順だけでなく、失敗条件とログを残します。

## 既知の制約

- VIVE Tracker 3.0はSteamVR Base Station 1.0/2.0を使用する
- VIVE Ultimate Trackerはinside-out trackingとVIVE Wireless Dongleを使用する
- HTCの製品情報ではUltimate Trackerは1台のPCまたはdongleにつき最大5台
- UltimateのPCセットアップはVIVE HubとSteamVRに依存する
- `XR_HTCX_vive_tracker_interaction`は未批准のOpenXR extension
- SteamVRのheadless運用はruntime更新で挙動が変わる可能性がある

参考:

- [VIVE Tracker 3.0 developer information](https://developer.vive.com/eu/hardware/tracker3/)
- [VIVE Ultimate Tracker product information](https://business.vive.com/uk/product/vive-ultimate-tracker/)
- [VIVE Ultimate Tracker PC setup](https://business.vive.com/us/support/ultimate-tracker/)
- [OpenVR API documentation](https://github.com/ValveSoftware/openvr/wiki/API-Documentation)
- [`XR_HTCX_vive_tracker_interaction`](https://registry.khronos.org/OpenXR/specs/1.1/man/html/XR_HTCX_vive_tracker_interaction.html)

## 必要な機材

### 初期検証

- Windows x86-64 physical machine
- wired 1GbE connection to Mac
- VIVE Tracker 3.0、3〜5台
- Tracker用dongle、cradle
- Base Station 1.0または2.0
- VIVE Ultimate Tracker、利用可能な台数
- VIVE Wireless Dongle
- Mac Hub development machine

### 検証ごとの記録項目

- Windows edition/build
- CPU、memory
- motherboard/USB controller
- NIC、link speed
- SteamVR version/channel
- VIVE Hub version
- OpenVR SDK header version
- OpenXR runtime/version/extensions
- Tracker model/serial/firmware
- dongleとUSB port配置
- base station model/firmware
- room lightingと大きさ
- network topology

## 証跡の配置

```text
hardware-tests/
└─ runs/
   └─ YYYY-MM-DD-machine-test/
      ├─ environment.md
      ├─ procedure.md
      ├─ result.md
      ├─ raw/
      └─ screenshots/
```

raw logにsecretや個人情報を含めません。大きなrecordingはGitへ直接commitせず、GitHub artifactまたは外部保管先とhashを記録します。

## Gate検証

M0のH0〜H6では[OpenVR実機検証probe](../bridge/probes/openvr/README.md)と[実機検証template](../hardware-tests/README.md)を使用します。

### H0: Runtime inventory

**Question:** runtimeとdeviceがWindowsからどう見えるか。

Procedure:

1. SteamVR/VIVE Hubをclean start
2. deviceを1台ずつ接続
3. runtime UI、USB、OpenVR device propertyを記録
4. software/firmware versionを記録

Pass:

- 各physical deviceをserialまたは同等のstable IDへ対応付けられる

2026-07-24のTracker 3.0実機結果:

- stock SteamVR 2.16.7はHMD未接続時に`Hmd Not Found (108)`で失敗
- `steamvr.requireHmd = false`だけを追加すると、Null Driverと非公式patchなしで成功
- Tracker 3.0を`GenericTracker`、Base Station 2.0×2を
  `TrackingReference`として列挙
- 結果は[Issue #12](https://github.com/shinyaoguri/divive/issues/12)へ記録

この結果によりH0はTracker 3.0について条件付きPASSとします。設定の再現性、長時間pose、
rate、identity復帰はH0.5/H1/H4/H5で判定します。

### H1: Tracker 3.0 without HMD

**Question:** ヘッドセットなしでSteamVRを起動し、TrackerをOpenVRから取得できるか。

Measure:

- setup手順
- required runtime settings
- `VRApplication_Background`接続
- `GenericTracker`列挙
- valid pose
- serial、velocity、battery

Preflight:

- [OpenVR probeのH0.5](../bridge/probes/openvr/README.md#h05-timing--pose-quality)
  を実行する
- 120Hz要求で実効110Hz以上を確認する
- 固定試験でkinematic discontinuityがないことを確認する
- `pose_valid`とtracking resultを別々に評価する

2026-07-27のTracker 3.0 H0.5結果:

- Windows高分解能waitable timerで3試験とも実効約120Hz、deadline miss 0
- 固定5分、緩速移動2分、遮蔽60秒でsequence gapとtimestamp reversalなし
- 固定・緩速移動とも`kinematic_discontinuity_samples == 0`
- 約11.5秒の完全遮蔽で`pose_valid=false`とdegraded tracking resultを観測し、
  遮蔽解除後約3.6秒で`running_ok`へ回復
- [Issue #12](https://github.com/shinyaoguri/divive/issues/12)でH0.5をPASSとし、
  Tracker 3.0 1台構成に限定してH1 GO

Pass:

- 再起動を含む3回の試行で同じ手順が再現する
- 30分以上valid poseを継続取得する
- `running_ok_pose_samples`とdegraded stateの時間を報告できる
- 固定区間で`kinematic_discontinuity_running_ok_samples`が0

推奨command:

```powershell
.\dist\windows-tools\divive-openvr-probe.exe `
  --trackers-only `
  --rate 120 `
  --duration 1800 `
  --prediction-seconds 0 `
  --output tracker3-h1-30m.jsonl
```

Fail/stop:

- 非再現な手動操作が毎回必要
- runtime updateで維持困難な非公開patchが必要

### H2: Ultimate without HMD

**Question:** VIVE Hubとdongleだけで、Ultimateの姿勢を公開APIから取得できるか。

Try in order:

1. OpenVR device enumeration
2. VIVE HubのVIVE Tracker emulation
3. OpenXR extension enumeration/action space

Record:

- headset要求の有無
- tracking map作成手順
- OpenVR class/property
- OpenXR extension/path
- serial stability
- VIVE Hub restart behavior

Pass:

- 公式配布runtime/APIだけで姿勢を取得できる
- restart後に自動または文書化可能な手順で復帰する

Fail/decision:

- headsetが必須なら目的の前提を変更するか、UltimateをMVP外にする
- 非公開protocolやBluetooth直結しか使えない場合はproduction backendにしない

### H3: Data fields

Tracker familyごとに次を`available / unavailable / unstable`で分類します。

| Field | Tracker 3.0 | Ultimate |
| --- | --- | --- |
| Serial | Available（H0 1台） | TBD |
| Position | Available（H0 1台） | TBD |
| Orientation | Available（H0 1台） | TBD |
| Linear velocity | Available（H0 1台） | TBD |
| Angular velocity | Available（H0 1台） | TBD |
| Tracking result/reason | Available（H0 1台） | TBD |
| Connected | Available（H0 1台） | TBD |
| Battery | Available（H0 1台） | TBD |
| Charging | Available（H0 1台） | TBD |
| Runtime role | TBD | TBD |

### H4: Rate and prediction

30 / 60 / 90 / 120 / 240Hzでpollし、次を測ります。

- unique pose更新率
- consecutive identical values
- timestampの可用性
- inter-sample interval
- scheduler wake lateness
- kinematic discontinuity
- CPU
- runtimeがpredictionしたposeか

requested send rateとnative measurement rateを混同しません。

### H5: Reconnect and identity

Scenarios:

- Tracker power off/on
- dongle unplug/replug
- USB port変更
- SteamVR restart
- VIVE Hub restart
- Windows logout/reboot
- battery depletion相当

Pass:

- stable IDへ戻る
- state transitionを観測できる
- Bridge process全体を手動再起動しなくても復帰できる、または復帰手順が決まる

### H6: Multi-device 3–5

Measure:

- 全deviceのsimultaneous valid rate
- USB errors
- radio drop
- device index reorder
- per-device latency/jitter差
- battery status polling impact

Pass:

- すべてのTrackerをserialで区別できる
- 60分試験で無制限queueや継続的なrate低下がない

### H7: Network baseline

有線1GbEと指定Wi‑Fiで比較します。

- packet loss
- out-of-order
- inter-arrival jitter
- burst loss
- reconnect

Wi‑Fi試験では2.4GHzをデータLANに使わず、Tracker/dongleとの物理距離とchannel条件を記録します。

### H8: Soak

- M1: 60分
- M2: 8時間
- M4: 24時間

Watch:

- memory
- handles/file descriptors
- CPU
- capture overrun
- packet counters
- log size
- state flapping
- clock offset

### H9: Space stability

Scenarios:

- runtime restart
- room setup変更
- Ultimate tracking map再生成
- base station power cycle
- Bridge machine移動

目的は`space_epoch`をいつ増やし、calibrationをいつ無効化すべきかを決めることです。

## 結果テンプレート

```markdown
# 検証結果

- Test ID:
- Date/time:
- Operator:
- Environment:
- Outcome: PASS / FAIL / INCONCLUSIVE

## 観察事項

## 測定値

## 証跡

## 想定外の動作

## 設計判断への影響

## 後続Issue
```

## Gate判定

M0の最後に次のいずれかをADRへ記録します。

- OpenVR single backend
- OpenVR + OpenXR backends
- Tracker 3.0 only MVP
- headset requirement accepted
- hardware/runtime構成を変更

`INCONCLUSIVE`を成功扱いしません。
