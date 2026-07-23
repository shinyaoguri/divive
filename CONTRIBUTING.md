# コントリビューションガイド

## 言語方針

このリポジトリでは日本語を基本言語とします。

- ドキュメント、Issue、PR本文、コードコメントは原則として日本語で記述する
- API名、型名、field名、protocol名、コマンドなど、正確さのため必要な技術識別子は英語表記を維持する
- source codeの識別子は各言語の慣習に従い英語とする
- 外部利用者向けに英語版が必要になった場合も、日本語文書を正として翻訳版を分離する
- 既存の英語だけの文章を更新するときは、合理的な範囲で日本語へ揃える

## 実装PRを開く前に

1. 関連するRoadmap milestoneを確認する
2. acceptance criteriaをIssueへ書く
3. hardware/runtime依存なら検証方法を先に書く
4. architecture、protocol、座標規約を変える場合はADRを作る
5. 実装と無関係な変更を同じPRへ混ぜない

## Issueの種類

- **Hardware validation**: 実機仮説、環境、手順、証跡、結論
- **Feature**: 利用者、成果、受入基準
- **Bug**: 再現手順、期待値、実際、環境
- **ADR proposal**: 変更する判断、候補、トレードオフ

Issueは実装手段ではなく、検証可能な完了状態を中心に書きます。

## Pull Request

PR本文に次を含めます。

- 変更内容
- 変更理由
- スコープ外
- 検証方法と結果
- hardware/runtime matrix
- protocol/recording/calibrationへの影響
- rollbackまたは互換性上の注意

Draft PRは、取得API、protocol、SDK public APIの早期相談に使います。

## 設計判断

[ADR template](docs/adr/0000-template.md)をコピーし、連番を付けます。

- StatusをProposedで開始
- context、decision、alternatives、consequencesを記録
- Accepted ADRの意味を変更するときは新しいADRでsupersedeする
- 実機結果を根拠にする場合はhardware test runへリンクする

## 実機証跡

[Hardware Validation](docs/hardware-validation.md)のlayoutとresult templateを使います。

- 失敗ログも残す
- runtime/firmware versionを省略しない
- raw dataが大きい場合はhashと保管先を残す
- screenshotだけをmachine-readable logの代わりにしない

## Protocol変更

- schema compatibilityを説明する
- golden vectorsを更新する
- C++、Swiftと該当SDKのconformance testを更新する
- major/minor version判断を書く
- unknown field/enumの挙動を確認する

## セキュリティとプライバシー

- token、secret、個人情報をcommitしない
- LANだから安全と仮定しない
- diagnostic bundleにsecretが含まれないことを確認する
- 脆弱性の公開報告方法は外部公開前に`SECURITY.md`で定義する
