# Requirements

Status: **Baseline for planning**

要求IDはIssue、PR、test resultから参照します。実機検証で成立しない要求は黙って弱めず、ADRとこの文書を更新します。

## Product objective

VIVE Trackerの6DoF姿勢をヘッドセットなしでWindowsから取得し、Mac上の複数コンテンツへ低遅延・安定して配信します。コンテンツはSteamVR/VIVE固有APIを直接扱いません。

## Assumptions

| ID | Assumption |
| --- | --- |
| ASM-001 | Windowsはx86-64 physical machine |
| ASM-002 | Macがcontent制作・実行の主環境 |
| ASM-003 | WindowsとMacは同一LAN |
| ASM-004 | 初期実機は3〜5台 |
| ASM-005 | 約16台は複数Bridgeを許容 |
| ASM-006 | Parallels上のWindows ARMはproduction対象外 |
| ASM-007 | Tracker 3.0には適切なbase stationとdongleがある |
| ASM-008 | UltimateにはVIVE Wireless DongleとVIVE Hubがある |

ASM-005は、Ultimateの1 PC/dongleあたり最大5台という公式制約を考慮したものです。

## Functional requirements

### Acquisition

| ID | Requirement | Priority |
| --- | --- | --- |
| ACQ-001 | BridgeはヘッドセットなしでTracker 3.0のposeを取得する | Must |
| ACQ-002 | Ultimateの公開・安定した取得経路をM0で判定する | Must |
| ACQ-003 | stable serialまたはpermanent IDを取得する | Must |
| ACQ-004 | positionとorientationを取得する | Must |
| ACQ-005 | 利用可能ならlinear/angular velocityを取得する | Should |
| ACQ-006 | tracking、lost、disconnectedを区別する | Must |
| ACQ-007 | 利用可能ならbattery/chargingを取得する | Should |
| ACQ-008 | runtime再起動とdevice再接続から復帰する | Must |
| ACQ-009 | 60 / 90 / 120Hzの送信rateを選べる | Must |

ACQ-001/002はhardware gateです。成立しない場合、目的または対応hardwareを再決定します。

### Transport

| ID | Requirement | Priority |
| --- | --- | --- |
| NET-001 | BridgeからHubへUDP unicastでposeを送る | Must |
| NET-002 | 過去frameを再送せず最新poseを優先する | Must |
| NET-003 | loss、duplicate、out-of-order、disconnectを検出する | Must |
| NET-004 | 有線LANと5/6GHz Wi‑Fiを扱う | Must |
| NET-005 | MTUを超えるIP fragmentationを避ける | Must |
| NET-006 | explicit addressと将来のmDNS discoveryを扱う | Should |
| NET-007 | reliable control channelをpose channelから分離する | Should |
| NET-008 | LAN公開時に認証とallowlistを使える | Must for production |
| NET-009 | BluetoothをBridge–Hubのpose経路に使わない | Must |

### Hub

| ID | Requirement | Priority |
| --- | --- | --- |
| HUB-001 | macOS native GUI appとして提供する | Must |
| HUB-002 | 複数Bridgeを識別して受信する | Must in data model |
| HUB-003 | contentごとにTracker、rate、profile、formatを設定する | Should |
| HUB-004 | latest canonical stateを保持する | Must |
| HUB-005 | role mappingを永続化する | Must |
| HUB-006 | tracking/status/network metricsをGUI/APIへ公開する | Must |
| HUB-007 | 通常はcontent/control APIをlocalhostへbindする | Must |
| HUB-008 | Simulator、Playback、Networkが同じinput interfaceを使う | Must |

### Content APIs

| ID | Requirement | Priority |
| --- | --- | --- |
| SDK-001 | Unity Packageを提供する | Must for M2 |
| SDK-002 | Unreal C++/Blueprint Pluginを提供する | Must for M3 |
| SDK-003 | p5.js TypeScript clientを提供する | Must for M3 |
| SDK-004 | Tracker IDまたはroleでlatest poseを取得する | Must |
| SDK-005 | tracking lost/reconnected eventを通知する | Must |
| SDK-006 | 補間量をclient単位で設定する | Should |
| SDK-007 | p5.jsはmessage backlogを描画しない | Must |
| SDK-008 | debug用JSON WebSocketを提供する | Must for M3 |
| SDK-009 | OSCは利用者要求を確認してから追加する | Could |

### Simulator

| ID | Requirement | Priority |
| --- | --- | --- |
| SIM-001 | Mac単体でvirtual Trackerを追加・削除する | Must |
| SIM-002 | ID、role、state、poseを編集する | Must |
| SIM-003 | 30 / 60 / 90 / 120Hzを生成する | Must |
| SIM-004 | static、circle、walk、jump、random presetを持つ | Should |
| SIM-005 | loss、delay、jitter、reordering、disconnect、lostを注入する | Must by M3 |
| SIM-006 | seedから障害を再現できる | Must |

### Recording

| ID | Requirement | Priority |
| --- | --- | --- |
| REC-001 | normalized Tracker Space frameを記録する | Must |
| REC-002 | 実機と同じHub APIで再生する | Must |
| REC-003 | speed、loop、seekを扱う | Must |
| REC-004 | schemaとapp versionを記録する | Must |
| REC-005 | calibration/runtime metadataを記録する | Must |
| REC-006 | 途中終了したrecordingを可能な範囲で回復する | Should |

### Calibration

| ID | Requirement | Priority |
| --- | --- | --- |
| CAL-001 | Tracker SpaceからStage Spaceへのrigid transformを管理する | Must |
| CAL-002 | profileを保存・読込する | Must |
| CAL-003 | origin、orientation、residualをGUIで確認する | Must |
| CAL-004 | scaleをrigid calibrationから分離する | Must |
| CAL-005 | tracking space ID/epochとprofile revisionを関連付ける | Must |
| CAL-006 | 異なるBridge spaceを較正なしで混合しない | Must |

## Non-functional requirements

### Performance

| ID | Target |
| --- | --- |
| PERF-001 | 標準送信rate 90Hz、60/120Hzを選択可能 |
| PERF-002 | Hub receiveからdistribution schedulingまでp99 2ms未満を目標 |
| PERF-003 | pose経路にunbounded queueを作らない |
| PERF-004 | 16台相当×120Hzのsynthetic loadをM4で通す |
| PERF-005 | clientごとにinterpolation bufferを設定可能 |

PERF-002はnetwork one-way latencyを含みません。測定点をtest reportに記載します。

### Reliability

| ID | Target |
| --- | --- |
| REL-001 | M1 60分、M2 8時間、M4 24時間のsoak |
| REL-002 | runtime/device/network再接続でprocess全体を再起動しなくても復帰 |
| REL-003 | role mappingをserialへ維持 |
| REL-004 | Bridge単位の障害をisolate |
| REL-005 | Recorder I/Oがpose distributionを停止させない |

### Security

| ID | Target |
| --- | --- |
| SEC-001 | content APIは既定localhost |
| SEC-002 | secret/tokenをlogへ出さない |
| SEC-003 | LAN公開時にcontrol認証 |
| SEC-004 | production UDP packetをsession/auth tagで検証 |
| SEC-005 | mDNS resultを信頼根拠にしない |

### Compatibility

| ID | Target |
| --- | --- |
| COMP-001 | Windows x86-64 physical machine |
| COMP-002 | macOS minimum versionをM2で固定 |
| COMP-003 | Unity LTS matrixをM2で固定 |
| COMP-004 | Unreal target versionをM3で固定 |
| COMP-005 | protocol minor versionでoptional field追加を許容 |
| COMP-006 | recording schema versionを保持 |

## Traceability

| Requirement group | Primary milestone | Primary evidence |
| --- | --- | --- |
| ACQ | M0–M1 | Hardware run、Bridge integration |
| NET | M1、M4 | Protocol conformance、network fault test |
| HUB | M2 | Swift package/UI tests |
| SDK | M2–M3 | Engine package tests/sample content |
| SIM | M2–M3 | Deterministic simulation tests |
| REC | M2 | MCAP round-trip/recovery |
| CAL | M2、M4 | Coordinate conformance、multi-space test |
| PERF | M1–M4 | Benchmarks、soak report |
| REL | M1–M4 | Fault/soak runs |
| SEC | M4 | Threat review、auth/replay tests |

## Open decisions

- Minimum macOS version
- Supported Unity LTS
- Supported Unreal version
- M0で確定するTracker/backend matrix
- production networkのTLS/VPN責務
- role uniqueness policy
- interpolationの既定値
- distribution pathのclient registration
- License
