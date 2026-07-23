# ADR 0004: Multi-Bridge architecture

- Status: Accepted
- Date: 2026-07-23

## Context

初期構成はWindows 1台、Tracker 3〜5台ですが、将来は約16台を想定します。Ultimate Trackerは公式情報上、1台のPCまたはdongleにつき最大5台です。Tracker 3.0もUSB/radio/runtime上限を単一PCで保証できません。

複数Windows nodeを後から追加すると、ID、clock、tracking space、calibrationのmodel変更が大きくなります。

## Decision

Hubとprotocolは最初から複数Bridgeを識別します。

- stable `bridge_id`
- process `session_id`
- `tracking_space_id`
- `space_epoch`
- Bridgeごとのsequence/clock metrics
- tracking spaceごとのStage calibration
- Bridge障害のisolation

MVP UIは1 Bridgeに最適化してよいですが、data modelからBridge identityを省略しません。

## Alternatives considered

### Single Bridge until scale is needed

MVPは短くなりますが、public IDとrecording schemaへBridge/spaceを後付けする破壊的変更が必要です。

### Multiple dongles on one Windows PC

一部hardwareで可能でも、Ultimateの公式5台上限やUSB/radio構成を一般化できません。optimizationとして検証できますがarchitectureの前提にはしません。

### Separate Hub per Bridge

Bridgeごとの空間は分離できますが、複数contentとStage統合の中心が失われます。

## Consequences

### Positive

- 16台への安全な拡張経路
- hardware/radio/USB障害の分離
- tracking spaceを誤って混合しにくい
- recordingとdiagnosticsでsourceを特定できる

### Negative

- ID、clock、UI、profileが早期から複雑になる
- Bridge間clock syncと空間較正が必要
- 複数machineの運用コストが増える

### Risks and mitigations

- Risk: 異なる空間を同一Stageへ誤配信
  - Mitigation: space ID/epochとcalibration validity gate
- Risk: Bridge clock差
  - Mitigation: per-Bridge clock modelとuncertainty
- Risk: role collision
  - Mitigation: Hubがrole uniqueness policyを管理

## Validation

- 2つのsimulated Bridgeを異なるspaceで接続
- 一方のdisconnectが他方へ影響しない
- calibrationなしspaceの配信拒否
- same serial namespace collision test

## Revisit when

- 公式に単一nodeで必要台数が保証され、複数node要件がなくなった
