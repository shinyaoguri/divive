# Contributing

## Before opening an implementation PR

1. 関連するRoadmap milestoneを確認する
2. acceptance criteriaをIssueへ書く
3. hardware/runtime依存なら検証方法を先に書く
4. architecture、protocol、座標規約を変える場合はADRを作る
5. 実装と無関係な変更を同じPRへ混ぜない

## Issue types

- **Hardware validation**: 実機仮説、環境、手順、証跡、結論
- **Feature**: 利用者、成果、受入基準
- **Bug**: 再現手順、期待値、実際、環境
- **ADR proposal**: 変更する判断、候補、トレードオフ

Issueは実装手段ではなく、検証可能な完了状態を中心に書きます。

## Pull requests

PR本文に次を含めます。

- 変更内容
- 変更理由
- スコープ外
- 検証方法と結果
- hardware/runtime matrix
- protocol/recording/calibrationへの影響
- rollbackまたは互換性上の注意

Draft PRは、取得API、protocol、SDK public APIの早期相談に使います。

## Architecture decisions

[ADR template](docs/adr/0000-template.md)をコピーし、連番を付けます。

- StatusをProposedで開始
- context、decision、alternatives、consequencesを記録
- Accepted ADRの意味を変更するときは新しいADRでsupersedeする
- 実機結果を根拠にする場合はhardware test runへリンクする

## Hardware evidence

[Hardware Validation](docs/hardware-validation.md)のlayoutとresult templateを使います。

- 失敗ログも残す
- runtime/firmware versionを省略しない
- raw dataが大きい場合はhashと保管先を残す
- screenshotだけをmachine-readable logの代わりにしない

## Protocol changes

- schema compatibilityを説明する
- golden vectorsを更新する
- C++、Swiftと該当SDKのconformance testを更新する
- major/minor version判断を書く
- unknown field/enumの挙動を確認する

## Security and privacy

- token、secret、個人情報をcommitしない
- LANだから安全と仮定しない
- diagnostic bundleにsecretが含まれないことを確認する
- 脆弱性の公開報告方法は外部公開前に`SECURITY.md`で定義する
