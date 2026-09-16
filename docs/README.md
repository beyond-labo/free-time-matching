# ドキュメント

2026-09-05 に提供された構成案を、このリポジトリの方針として整理しました。
2026-09-06 の追加指示により、TCA＋Clean Architecture、機能内の DTO 変換、予約ファイルを作らない方針へ更新しました。
製品名は「ひまっち（仮）」、コード上の名称は `himatch` とします。
既存のリポジトリ名 `free-time-matching` は変更しません。

| 文書 | 内容 |
| --- | --- |
| [製品の範囲](product/overview.md) | 添付から読み取れる機能と未確定の要件 |
| [技術方針](architecture/technology.md) | 採用方針、依存方向、未決事項 |
| [iOS の設計](architecture/ios-architecture.md) | TCA、MVVM との関係、DTO 変換、依存注入 |
| [パッケージ構成](architecture/package-structure.md) | 配置と所有責任、実装の状態 |
| [API 契約](architecture/api-contracts.md) | OpenAPI の生成、配布、互換性 |
| [構成の見直し結果](architecture/review-notes.md) | 層名、DTO 変換、予約ファイル削除の決定 |
| [開発手順](operations/development.md) | ローカルでの構成確認と実装開始手順 |
| [CI/CD 方針](operations/ci-cd.md) | ワークフローの責務と公開までの整備順序 |

## 文書の扱い

添付を出発点とし、追加指示による最新の決定を各文書へ反映します。
例示されたデータ構造や API パスは、業務仕様として確定したものとは扱いません。
添付にないフレームワーク、クラウド設定、バージョン、料金、機能要件は補完して確定しません。

今回の変更は文書化と構成の作成です。
機能実装へ進む際は、AGENTS.md に従って要件、設計、タスクを作成し、各段階をレビューします。
プロジェクト全体の steering と機能仕様はまだ作成されていません。
