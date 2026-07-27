# ドキュメント

このディレクトリはdiviveの設計、実装計画、運用上の制約を管理します。コードと文書が矛盾した場合は、矛盾を放置せずIssueまたはADRで解消します。

## 読む順番

別端末や別agentから開発を再開する場合は、最初に
[開発引き継ぎ](handoff.md)を読んでください。通常の設計確認は次の順です。

1. [Requirements](requirements.md)
2. [Architecture](architecture.md)
3. [Hardware Validation](hardware-validation.md)
4. [Implementation Plan](implementation-plan.md)
5. [Protocol](protocol.md)
6. [Calibration](calibration.md)
7. [Development](development.md)
8. [ADR index](adr/README.md)

## 文書の責務

| 文書 | 責務 |
| --- | --- |
| [Handoff](handoff.md) | 現在地、未完了事項、別端末・別agentへの再開手順 |
| [Requirements](requirements.md) | 機能・非機能要求、前提、traceability |
| [Architecture](architecture.md) | システム境界、責務、データフロー、障害時挙動 |
| [Implementation Plan](implementation-plan.md) | 作業順序、依存関係、各PhaseのExit Criteria |
| [Roadmap](roadmap.md) | Milestone単位のスコープと優先順位 |
| [Hardware Validation](hardware-validation.md) | ハードウェア依存の仮説と実機証跡 |
| [Protocol](protocol.md) | wire contract、時刻、順序、互換性 |
| [Calibration](calibration.md) | 座標空間、変換、プロファイル |
| [Development](development.md) | ツールチェーン、テスト、CI、リリース |
| [ADR](adr/README.md) | 変更理由を含む設計判断の履歴 |

## ステータス表記

- **Proposed**: 検討中で、実装の前提にしてはいけない
- **Accepted**: 実装の基準
- **Accepted, conditional**: 検証Gateの通過を条件に採用
- **Superseded**: 新しいADRに置き換えられた
- **Rejected**: 検討したが採用しない

## 更新ルール

- 文書、Issue、PR本文、コードコメントは日本語を基本とし、技術識別子は必要に応じて英語を維持する
- 公開プロトコル、座標規約、対応ハードウェアの変更は文書とテストを同じPRで更新する
- 既存のAccepted ADRを直接書き換えて歴史を消さない。新しいADRで置き換える
- 実機依存の結論には、機材、runtime、firmware、ログ、日時を添える
- ロードマップの進捗はIssueを正とし、この文書群は目的と完了条件を保持する
- 将来構想とMVP要件を混同しない
