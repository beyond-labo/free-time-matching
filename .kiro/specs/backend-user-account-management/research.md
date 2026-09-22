---
type: Research
title: "Backend ユーザーアカウント管理調査"
description: "Supabase Auth、RLS、Apple native認証と削除の調査"
status: stable
sources:
  - id: supabase-apple
    resource: https://supabase.com/docs/guides/auth/social-login/auth-apple
    title: Supabase Sign in with Apple
  - id: supabase-jwt
    resource: https://supabase.com/docs/guides/auth/jwts
    title: Supabase JWTs
  - id: supabase-user-data
    resource: https://supabase.com/docs/guides/auth/managing-user-data
    title: Supabase User Management
  - id: apple-account-deletion
    resource: https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple
    title: Apple account deletion and token revocation
  - id: supabase-managing-environments
    resource: https://supabase.com/docs/guides/deployment/managing-environments
    title: Supabase Managing Environments
  - id: supabase-database-migrations
    resource: https://supabase.com/docs/guides/deployment/database-migrations
    title: Supabase Database Migrations
  - id: supabase-database-testing
    resource: https://supabase.com/docs/guides/database/testing
    title: Supabase Database Testing
  - id: supabase-api-keys
    resource: https://supabase.com/docs/guides/getting-started/api-keys
    title: Supabase API Keys
  - id: supabase-platform-access-control
    resource: https://supabase.com/docs/guides/platform/access-control
    title: Supabase Access Control
  - id: supabase-personal-access-tokens
    resource: https://supabase.com/docs/guides/platform/personal-access-tokens
    title: Supabase Personal Access Tokens
  - id: supabase-project-transfers
    resource: https://supabase.com/docs/guides/platform/project-transfer
    title: Supabase Project Transfers
  - id: supabase-pricing
    resource: https://supabase.com/pricing
    title: Supabase Pricing
  - id: supabase-billing
    resource: https://supabase.com/docs/guides/platform/billing-on-supabase
    title: Supabase Billing
  - id: supabase-billing-faq
    resource: https://supabase.com/docs/guides/platform/billing-faq
    title: Supabase Billing FAQ
  - id: supabase-backups
    resource: https://supabase.com/docs/guides/platform/backups
    title: Supabase Database Backups
  - id: supabase-cost-control
    resource: https://supabase.com/docs/guides/platform/cost-control
    title: Supabase Cost Control
  - id: supabase-signing-keys
    resource: https://supabase.com/docs/guides/auth/signing-keys
    title: Supabase JWT Signing Keys
  - id: supabase-sessions
    resource: https://supabase.com/docs/guides/auth/sessions
    title: Supabase User Sessions
  - id: apple-app-id
    resource: https://developer.apple.com/help/account/identifiers/register-an-app-id
    title: Apple Register an App ID
  - id: apple-sign-in-key
    resource: https://developer.apple.com/help/account/capabilities/create-a-sign-in-with-apple-private-key
    title: Apple Create a Sign in with Apple private key
  - id: github-environments
    resource: https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments
    title: GitHub Managing environments for deployment
kiro:
  depends_on:
    - apps/backend/src/Composition/createApp.ts
    - apps/ios/Himatch/App/Presentation/AppView.swift
---

# 調査と設計判断

## Summary

- **Feature**: `backend-user-account-management`
- **Discovery Scope**: Complex Integration
- **Key Findings**:
  - native Apple認証はidentity tokenとraw nonceをSupabase `signInWithIdToken`へ渡す。
  - WorkerはSupabase JWKSでaccess JWTを検証し、通常DB操作は利用者JWTとRLSで制約できる。
  - Auth userのhard deleteはrefresh tokenを無効化するが、既発行access tokenは期限まで残るため追加のactive gateが必要である。
  - Apple token失効にはfresh authorization codeを交換して得たtokenと、server-side signing materialが必要である。
  - Supabaseの課金PlanはOrganization単位で、Proは停止回避、7日間の日次backup／log保持、Email supportを提供するが、Project-scoped roleはTeam以上である。
  - 現行DashboardではOrganization作成時に`Name`、`Type`、`Plan`を選び、Team招待ではOrganization-levelのDeveloperを選ぶ。classic token作成dialogは`Name`と`Expires in`だけを表示する。

## Design Decisions

### Decision: iOSは認証、WorkerはResource Server

- **Selected Approach**: iOSがnative Apple UIとSupabase sessionを所有し、WorkerはBearer JWTを検証する。
- **Rationale**: Apple UIとsession refreshを公式SDKへ委ね、Backendがrefresh tokenを重複保管しない。

### Decision: 通常経路に特権secretを使わない

- **Selected Approach**: profileはpublishable key＋user JWT＋RLS、hard deleteだけAuth admin secretを使う。
- **Rationale**: 誤実装時の権限範囲を限定し、RLSを実行時認可として維持する。

### Decision: 初版削除は同期処理

- **Alternatives Considered**: Cloudflare Queueによる非同期再試行。
- **Selected Approach**: 受付記録を先に確定し、Apple revokeとAuth hard deleteを同じ要求で実行する。失敗はactionRequiredで保持する。
- **Rationale**: 未採用のQueue resourceを増やさず、初版の削除義務と再試行可能な状態を満たす。
- **Trade-offs**: 一時障害の自動再試行は後続仕様で追加する。

### Decision: migrationをBackend releaseより先に適用する

- **Selected Approach**: Pull Requestで空DBへの初期適用とpgTAPを実行し、staging／production CDでは同じrelease内で`db push`をWorker deployより先に実行する。
- **Rationale**: schemaとWorkerの配布順を一つの直列化されたreleaseにし、別workflow間の競合を避ける。
- **Trade-offs**: Worker rollbackはDBを戻さないため、migrationはforward-onlyかつ旧Workerと互換なexpand / contractに制限する。

### Decision: 実行時設定をprotected Environmentから配布する

- **Selected Approach**: 公開値はWrangler `--var`、secretは一時JSONと`--secrets-file`、iOS公開値はXcode build settingとして注入する。
- **Rationale**: repositoryに環境値を固定せず、secretをlogやartifactへ残さず、Worker codeと設定を同じversionにまとめる。

### Decision: productionだけを別OrganizationのProにする

- **Alternatives Considered**: 2 Projectを同じPro Organizationへ置く、両OrganizationをFreeまたはProにする、Team PlanでProject-scoped roleを使う。
- **Selected Approach**: 初期構築では`beyond-labo-staging`の`himatch-staging`と`beyond-labo-production`の`himatch-production`をどちらもFreeとする。環境別CI accountを各OrganizationだけへDeveloperとして所属させ、各accountのclassic tokenを対応するGitHub Environmentだけへ登録する。実ユーザーを受け入れるApp Store公開前にproductionだけをProへ変更する。
- **Rationale**: productionに停止回避、backup、log保持、SupabaseへのEmail supportを与えながら、classic tokenの到達範囲をOrganization membershipで分離できる。Team PlanのProject-scoped roleは初版の規模と費用に見合わない。
- **Trade-offs**: Freeのstagingは非アクティブ時にpauseされ、backupとlog保持がproductionより弱い。stagingの安定性や同等性が必要になった時点で別途Proへ変更する。

## Risks & Mitigations

- Auth削除後もaccess JWTが残る — RLSのactive gateと短いJWT期限を運用設定にする。
- Apple credentialの取り違え — Apple ID tokenを検証しSupabase user identityと照合する。
- status token漏えい — 生tokenを保存・ログ出力せずhash照合する。
- legacy共有JWT secretではJWKS検証できない — Supabase Auth Signing Keysを非対称鍵にし、ES256 / RS256とローテーション中のJWKSをstagingで確認する。

## Change Log

- 2026-09-21: 最新mainのiOSプロトタイプを基準に、本番Supabase境界と同期削除を初版設計へ追加。
- 2026-09-22: Supabase採用決定を受け、secretless DB CI、環境承認付きmigration、Worker／TestFlight設定注入と運用手順を追加。
- 2026-09-22: 独立レビューを受け、Terraform失敗前のDB変更を避ける配備順、`db push --yes`、linked履歴確認、破壊的migration guard、部分release復旧表示、iOS release ref検証を追加。ローカルPostgresでDB lintとpgTAP 23件の成功を確認。
- 2026-09-22: 再レビューを受け、staging／productionのSupabase CI identityとaccess tokenを分離し、migration途中失敗時にもlinked履歴を復旧Summaryへ記録する境界を追加。
- 2026-09-22: remote環境名を`himatch-staging`／`himatch-production`へ固定し、東京region、Data API ON、自動table公開OFF、自動RLS ONを採用。初版は別Projectによる環境分離を維持し、Supabase Branchingは将来のPR preview候補へ限定。
- 2026-09-22: 現行のSupabase Dashboard、Apple Developer、GitHub EnvironmentのUI導線に合わせて初期構築手順を具体化。native-only Apple認証ではSupabaseのOAuth secretを使わず、Apple `.p8`はBackendのtoken失効だけへ渡す境界を明記。classic PATだけのFree PlanではProject単位のCI分離ができないため、別organization／別CI identityを使う実行手順を追加。
- 2026-09-22: ProでもProject-scoped roleは提供されないことを確認し、stagingとproductionを常に別Organization／別CI identityへ分離する方針へ更新。productionだけをApp Store公開前にPro、stagingをFreeとし、Proを可用性・backup・log・Email supportのために採用する手順を追加。
- 2026-09-22: Dashboardを再確認し、両OrganizationがFreeで各1 Project、TeamはOwnerだけ、owner accountのtokenは未発行、GitHub `staging` EnvironmentにSupabase tokenは未登録であることを確認。現在地からCI account招待を開始し、未分離時のOrganization作成とProject transfer、classic token発行、GitHub Environment登録、公開前のproduction Pro変更を別工程として実行するrunbookへ改訂。
- 2026-09-22: 運用手順を一時的なDashboard状態から独立させ、完成形とcheckpointを基準に未完了工程から再開できる構成へ改訂。Project transferは既存構成を補正する場合だけの経路とし、productionのPro変更は初期セットアップからApp Store公開前の工程へ分離。
