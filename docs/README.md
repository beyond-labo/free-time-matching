# ドキュメント

2026-09-05 に提供された構成案を、このリポジトリの方針として整理しました。
製品名は「ひまっち（仮）」、コード上の名称は `himatch` とします。
既存のリポジトリ名 `free-time-matching` は変更しません。

| 文書 | 内容 |
| --- | --- |
| [製品の範囲](product/overview.md) | 添付から読み取れる機能と未確定の要件 |
| [技術方針](architecture/technology.md) | 採用方針、依存方向、未決事項 |
| [パッケージ構成](architecture/package-structure.md) | 配置と所有責任、実装の状態 |
| [API 契約](architecture/api-contracts.md) | OpenAPI の生成、配布、互換性 |
| [構成の見直し候補](architecture/review-notes.md) | HTTP 配置、iOS の Mapper、予約ファイルなどの検討事項 |
| [開発手順](operations/development.md) | ローカルでの構成確認と実装開始手順 |
| [CI/CD 方針](operations/ci-cd.md) | ワークフローの責務と公開までの整備順序 |

## 文書の扱い

添付の明示的な構成と推奨方針を採用します。
例示されたデータ構造や API パスは、業務仕様として確定したものとは扱いません。
添付にないフレームワーク、クラウド設定、バージョン、料金、機能要件は補完して確定しません。

今回の変更は文書化と構成の作成です。
機能実装へ進む際は、AGENTS.md に従って要件、設計、タスクを作成し、各段階をレビューします。
プロジェクト全体の steering と機能仕様はまだ作成されていません。
