# ドキュメント

2026-09-05 に提供された構成案を、このリポジトリの方針として整理しました。
2026-09-21 時点では、非公開を基本とするiOS初版、AppleのみのSupabase認証・プロフィール・削除境界、Swift Testing専用方針まで反映しています。
製品名は「ひまっち（仮）」、コード上の名称は `himatch` とします。
既存のリポジトリ名 `free-time-matching` は変更しません。

| 文書 | 内容 |
| --- | --- |
| [製品の範囲](product/overview.md) | iOS初版の製品契約、対象外、外部準備事項 |
| [技術方針](architecture/technology.md) | 採用方針、依存方向、未決事項 |
| [iOS の設計](architecture/ios-architecture.md) | TCA、MVVM との関係、DTO 変換、依存注入 |
| [Android の設計](architecture/android-architecture.md) | Compose、機能配置、依存方向、テスト境界 |
| [パッケージ構成](architecture/package-structure.md) | 配置と所有責任、実装の状態 |
| [API 契約](architecture/api-contracts.md) | OpenAPI の生成、配布、互換性 |
| [構成の見直し結果](architecture/review-notes.md) | 層名、DTO 変換、予約ファイル削除の決定 |
| [開発手順](operations/development.md) | ローカルでの構成確認と実装開始手順 |
| [Supabase Auth・Database CI/CD](operations/supabase-auth.md) | Project作成、Apple認証、migration、GitHub設定、staging／production運用 |
| [CI/CD](operations/ci-cd.md) | ワークフロー一覧と共通の保護方針 |
| [Backend CI/CD](operations/backend-ci-cd.md) | Cloudflare、Terraform、staging、productionの運用手順 |
| [iOS CI/CD](operations/ios-ci-cd.md) | 署名とTestFlight配布の運用手順 |
| [Android CI/CD](operations/android-ci-cd.md) | 署名とGoogle Play internal track配布の運用手順 |
| [iOS初版の実装・リリース判定](operations/ios-first-release-readiness.md) | プロトタイプで検証済みの範囲とリリース前の残件 |

## 文書の扱い

添付を出発点とし、追加指示による最新の決定を各文書へ反映します。
例示されたデータ構造や API パスは、業務仕様として確定したものとは扱いません。
添付にないフレームワーク、クラウド設定、バージョン、料金、機能要件は補完して確定しません。

機能実装へ進む際は、AGENTS.md に従って要件、設計、タスクを作成し、各段階をレビューします。
Backend CI/CDの仕様は`.kiro/specs/backend-ci-cd/`、iOS CI/CDの仕様は`.kiro/specs/ios-ci-cd/`、Android CI/CDの仕様は`.kiro/specs/android-ci-cd/`にあります。
iOS初版の依存順は`.kiro/steering/roadmap.md`、各機能仕様は`.kiro/specs/ios-*`、Backendのユーザー管理仕様は`.kiro/specs/backend-user-account-management`にあります。iOSは認証・プロフィール・削除をProductionへ接続し、それ以外はPrototype、AndroidはCI/CD用の最小アプリです。
