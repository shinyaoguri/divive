# ADR 0005: 正規化frameのMCAP記録

- Status: Accepted
- Date: 2026-07-23

## 背景

録画は長時間の姿勢、status、calibration eventを保存し、Mac単体でseek、loop、速度変更して再生する必要があります。将来のschema evolution、途中終了、metadata、複数topicを扱います。

独自binary logは初期実装が小さくても、index、seek、recovery、inspection toolを自作する負担が増えます。

## 決定

- containerはMCAP
- pose payloadはwireと同じcanonical FlatBuffers
- Tracker Spaceへ正規化したframeを記録
- content profile適用前の値を正とする
- calibration/profile/runtime情報をmetadata/eventとして保存
- PlaybackはHubの`FrameSource`として実装

## 検討した選択肢

### Custom append-only binary

依存が少ない一方、index、schema metadata、repair tool、cross-language inspectionを自作する必要があります。

### SQLite

queryとmetadata管理は容易ですが、高頻度時系列のchunk、stream write、外部tool互換を追加設計する必要があります。

### JSON Lines

debugには有用ですが、サイズ、encode cost、seek、長時間記録に不利です。

### CSV

単純な解析には便利ですが、複数Tracker、status event、schema evolution、quaternion/metadataを自然に扱えません。必要ならMCAPからexportします。

## 影響

### 利点

- indexed seekとchunked writing
- metadata/topicの分離
- Swift/C++/TypeScript等のlibrary
- 外部inspection/export toolを利用できる
- recording format自作範囲を減らせる

### 欠点

- MCAP dependencyとformat知識が必要
- Swift libraryのfeature差を考慮する必要
- content適用後の見た目を完全再現するにはprofileも必要

### リスクと対策

- Risk: abrupt terminationで末尾indexがない
  - Mitigation: streamed read/recovery test、定期chunk close
- Risk: schemaとapp versionが不明
  - Mitigation: attachment/metadataへschema hashとversion
- Risk: disk遅延がpose pathを止める
  - Mitigation: dedicated writerとbounded buffer/drop counter

## 検証

- 1時間recording、seek、loop、速度変更
- process kill後のread/recovery
- schema minor versionの読み込み
- Network/Simulator/Playbackの同一output test

## 見直す条件

- Swift MCAP libraryが必要機能を満たさない
- production recording量でI/O要件を満たさない
- 規制や暗号化要件がcontainer変更を要求する
