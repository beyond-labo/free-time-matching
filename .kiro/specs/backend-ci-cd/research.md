---
type: Research
title: "Backend CI/CD と Cloudflare 配布調査"
description: "pnpm、Workers Runtime、Terraform R2 state、GitHub Actions CI/CD の採用根拠"
status: draft
sources:
  - id: backend-brief
    resource: ./brief.md
    title: Backend CI/CD 構成案
  - id: hono-workers
    resource: https://hono.dev/docs/getting-started/cloudflare-workers
    title: Hono on Cloudflare Workers
  - id: cloudflare-testing
    resource: https://developers.cloudflare.com/workers/testing/
    title: Cloudflare Workers testing
  - id: cloudflare-wrangler-dry-run
    resource: https://developers.cloudflare.com/workers/wrangler/commands/#deploy
    title: Wrangler deploy command
  - id: cloudflare-custom-domains
    resource: https://developers.cloudflare.com/workers/configuration/routing/custom-domains/
    title: Cloudflare Workers Custom Domains
  - id: cloudflare-wrangler-configuration
    resource: https://developers.cloudflare.com/workers/wrangler/configuration/
    title: Wrangler configuration
  - id: cloudflare-workers-authorization
    resource: https://developers.cloudflare.com/workers/authorization/workers/
    title: Cloudflare Workers authorization
  - id: cloudflare-certificate-statuses
    resource: https://developers.cloudflare.com/ssl/reference/certificate-statuses/
    title: Cloudflare certificate statuses
  - id: cloudflare-dns-same-name
    resource: https://developers.cloudflare.com/dns/manage-dns-records/troubleshooting/records-with-same-name/
    title: Cloudflare DNS records with same name
  - id: cloudflare-r2-s3
    resource: https://developers.cloudflare.com/r2/data-access/s3-api/api/
    title: Cloudflare R2 S3 API compatibility
  - id: terraform-s3-backend
    resource: https://developer.hashicorp.com/terraform/language/backend/s3
    title: Terraform S3 backend
  - id: github-environments
    resource: https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment
    title: GitHub Actions environments
  - id: github-pinning-actions
    resource: https://docs.github.com/en/actions/reference/security/secure-use
    title: GitHub Actions secure use
  - id: local-technology-policy
    resource: ../../../docs/architecture/technology.md
    title: 技術方針
  - id: local-package-structure
    resource: ../../../docs/architecture/package-structure.md
    title: パッケージ構成
  - id: supabase-terraform-scaffold
    resource: ../../../infra/supabase/README.md
    title: Supabase Terraform の段階導入
  - id: backend-ci-workflow
    resource: ../../../.github/workflows/ci-backend.yml
    title: Backend CI
  - id: supabase-ci-workflow
    resource: ../../../.github/workflows/ci-supabase.yml
    title: Supabase CI
kiro:
  depends_on:
    - docs/architecture/technology.md
    - docs/architecture/package-structure.md
    - docs/architecture/api-contracts.md
    - docs/operations/development.md
    - infra/supabase/environments/staging/main.tf
    - infra/supabase/environments/production/main.tf
    - .github/workflows/ci-backend.yml
    - .github/workflows/ci-supabase.yml
---

# 調査と設計判断

## Summary

- **Feature**: `backend-ci-cd`
- **Discovery Scope**: Existing spec extension
- **Key Findings**:
  - Backend は pnpm workspace の private package として登録済みだが、実行入口・依存・検査 script は未実装である。
  - Hono は Workers の module entrypoint と `app.fetch` を組み合わせられ、受信 HTTP と route composition に責務を限定できる。
  - Workers Runtime の request/response を実際に通すテストを採用し、型検査と Wrangler bundle dry-run を同じ package script で再現する。
  - Terraform は環境別 root/state と provider/backend の検証可能な scaffold に限定し、未決定の Cloudflare resource を捏造しない。
  - PR CI は資格情報なしで Backend verify と Terraform fmt/init backend=false/validate を行い、trusted Environment のみが plan/apply/deploy を実行する。
  - Worker が API origin であるため、`api-staging.beyond-labo.com` と `api.beyond-labo.com` は通常の Route ではなく Wrangler の `custom_domain: true` で管理する。
  - Custom Domain は Cloudflare が DNS レコードと Advanced Certificate を自動作成するため、Terraform に DNS、Route、Custom Domain resource を重複定義しない。
  - 初回 deploy 前に同一 account 内の `beyond-labo.com` zone が Active であることと、`api-staging` / `api` の A、AAAA、CNAME 競合がないことを確認する。
  - Custom Domain 変更には初回 Workers product-level Admin、通常は product-level Editor と `beyond-labo.com` に限定した `Zone > Workers Routes > Edit` を使う。Custom Domains は per-Worker roles 非対応で、DNS Write は自動 DNS 作成だけでは不要である。
  - staging は `main` push、production は `backend-vX.Y.Z` tag または manual で trigger し、production は read-only plan と protected approval 後の plan 再計算を必須にする。
  - `infra/supabase/environments/staging` と `production` は provider、version constraint、partial S3 backend、空の `main.tf`、lockfile を持つが、resource/import block はまだない。
  - `.github/workflows/ci-backend.yml` は Cloudflare と Supabase の全 environment root に対して `fmt -check`、`init -backend=false`、`validate` を credential なしで実行する。
  - `.github/workflows/ci-supabase.yml` は hosted credential を使わず local database を起動し、migration、DB lint、pgTAP を実行する。これは staging/production Project への apply 証拠ではない。
  - Supabase Terraform は Management API 設定の将来境界であり、DB schema、RLS、関数、migration、Auth 利用者・session は Supabase CLI/稼働 DB の所有として分離する。

## Research Log

### pnpm workspace と package 境界

- **Context**: 既存 `apps/backend/package.json` は空の private workspace で、Backend だけを独立検証する入口が必要だった。
- **Sources Consulted**: `docs/architecture/technology.md`、`docs/architecture/package-structure.md`、`docs/operations/development.md`（2026-09-20確認）。
- **Findings**: 依存と script は Backend package に閉じ、root の pnpm workspace と lockfile から frozen install できる構成が方針に合う。層名は `Domain / Application / Presentation / Infrastructure`、起動は `EntryPoint / Composition` が所有する。
- **Implications**: 初期機能は業務ロジックを持たないため、`src/EntryPoint` と `src/Composition`、必要最小限の `src/Health/Presentation` だけを作成する。

### Hono と Workers Runtime

- **Context**: Node.js サーバーではなく Cloudflare Workers の module worker を最初の実行基盤にする必要がある。
- **Sources Consulted**: [Hono on Cloudflare Workers](https://hono.dev/docs/getting-started/cloudflare-workers)（2026-09-20確認）。
- **Findings**: Hono application は `fetch` handler を提供し、Workers の default module export から直接公開できる。Node.js の `http` server や `process.env` を前提にしない。
- **Implications**: Hono は Presentation/Composition と entrypoint に限定し、Workers bindings も現時点では health response に露出させない。

### Workers Runtime テストと bundle 検証

- **Context**: adapter を Node.js の mock だけで検証すると Workers 固有の実行差異を見逃す。
- **Sources Consulted**: [Cloudflare Workers testing](https://developers.cloudflare.com/workers/testing/)、[Wrangler deploy command](https://developers.cloudflare.com/workers/wrangler/commands/#deploy)（2026-09-20確認）。
- **Findings**: Cloudflare の Vitest integration は Workers Runtime 相当の request/response テストを提供し、Wrangler の deploy dry-run は実デプロイせず bundle 構成を検査できる。
- **Implications**: health route と未知 route を runtime test で確認し、型検査後に dry-run を実行する。外部 Cloudflare 認証や実環境への変更は発生させない。

### Vitest と Cloudflare plugin の互換性

- **Context**: 調査時点の候補だった Vitest 5.0.1 と Cloudflare Vitest plugin 1.1.13 を組み合わせると、Workers test の起動時に構文エラーが発生した。
- **Sources Consulted**: package registry metadata、`pnpm-lock.yaml`、Workers Runtime test の実行結果（2026-09-20確認）。
- **Findings**: plugin 1.1.13 と Vitest 4.1.11 の組み合わせでは、同じ Worker entrypoint を通る3件の runtime test が成功した。
- **Implications**: 実行証拠のある Vitest 4.1.11を固定する。Vitestのmajor更新はplugin互換性とruntime testを再確認するrevalidation triggerとする。

### Terraform R2 S3 backend と環境分離

- **Context**: staging/production の state を分離し、state と credential を公開 repository や artifact に出さずに GitHub Actions から利用する必要がある。
- **Sources Consulted**: [Cloudflare R2 S3 API](https://developers.cloudflare.com/r2/data-access/s3-api/api/)、[Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)、[Terraform state](https://developer.hashicorp.com/terraform/language/state)（2026-09-20確認）。
- **Findings**: R2 は S3-compatible endpoint を提供する。Terraform S3 backend は backend block と init-time config を分離できるため、repository には `backend "s3" {}` の partial declaration だけを置き、bucket/key/endpoint/credential を外部から注入できる。state は resource metadata を含むため、plan/state を公開 artifact にしない。一方、HashiCorp は代替 S3 実装を保証せず、Cloudflare の R2 backend 例も `use_lockfile` を有効化していないため、native lockfile の互換性は未確認である。
- **Implications**: `infra/cloudflare/environments/{staging,production}` を別 root とし、R2 bucket bootstrap は Terraform root 外の runbook とする。CI は `-backend=false` で secretless validation を行う。実 plan/apply は Environment credential と環境別 GitHub Actions concurrency で直列化し、初期構成では `use_lockfile` を使わない。実 R2 上の並行実行と stale lock 回復を統合検証できた場合だけ別変更で有効化する。

### GitHub Environment、最小権限、action pin

- **Context**: production apply/deploy は reviewer 承認が必要で、PR の untrusted code には credential を公開できない。
- **Sources Consulted**: [GitHub Actions environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)、[GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use)、`docs/operations/backend-ci-cd.md`（2026-09-20確認）。
- **Findings**: protected Environment は required reviewer を deployment job の gate にでき、workflow/job の `permissions` は最小化できる。third-party action は full-length commit SHA pin が supply-chain risk を下げ、untrusted PR と privileged deployment を分離する必要がある。
- **Implications**: PR workflow は `pull_request`、`contents: read`、GitHub-hosted runner、credential なしとし、production は read-only plan と approval 後の write job を分離する。action SHA は実装時にレビュー済みの値へ固定し、tag/branch を使わない。

### Terraform と Wrangler の所有境界

- **Context**: Terraform provider と Wrangler の双方が Cloudflare resource を操作できるため、同一 resource の二重管理を避ける必要がある。
- **Sources Consulted**: [Cloudflare Terraform best practices](https://developers.cloudflare.com/terraform/advanced-topics/best-practices/)、[Cloudflare Workers environments](https://developers.cloudflare.com/workers/wrangler/environments/)、[Wrangler deploy](https://developers.cloudflare.com/workers/wrangler/commands/#deploy)（2026-09-20確認）。
- **Findings**: Terraform は長寿命 infrastructure に適し、Wrangler は Worker code/version/deployment に対応する。resource を複数 tool で管理すると drift と競合を生むため、項目ごとに唯一の所有者を定義する必要がある。
- **Implications**: 初期 Terraform scaffold は provider/state 境界のみとし、Worker script、version、deployment、binding、Route、Custom Domain は Wrangler の唯一所有とする。D1/KV/R2/Queue 等の長寿命 resource は product 要件が確定してから別タスクで選定する。

### Supabase Terraform root と local CI

- **Context**: 現行リポジトリに Supabase の staging/production Terraform root と、DB migration/RLS の secretless CI が追加されたため、既存の Cloudflare-only 設計との責務境界を同期する必要がある。
- **Sources Consulted**: `infra/supabase/environments/{staging,production}`、`infra/supabase/README.md`、`.github/workflows/ci-backend.yml`、`.github/workflows/ci-supabase.yml`、`docs/operations/development.md`（2026-09-25確認）。
- **Findings**: 両 Supabase root は `supabase/supabase` provider 1.9.0、Terraform `>=1.10.0,<2.0.0`、credential-free partial S3 backend、空の `main.tf`、lockfile を持つ。Backend CI は Cloudflare/Supabase の全 root を `fmt`、`init -backend=false`、`validate` する。Supabase CI は `supabase db start`、`db lint --local`、`test db --local` を実行する。
- **Implications**: Supabase root の存在と static/local CI の成功は、hosted Project の Terraform apply/import、Supabase token、DB password、staging/production migration の成功を意味しない。既存 Cloudflare/Wrangler の所有境界は維持し、Supabase schema/RLS/migration は Supabase CLI/稼働 DB に残す。

### Supabase 管理対象の保留条件

- **Context**: 空 root に将来 resource を追加する際の誤 apply と secret state 混入を防ぐ必要がある。
- **Sources Consulted**: `infra/supabase/README.md`（2026-09-25確認）。
- **Findings**: Project ID、組織、リージョン、Auth/Settings の inventory を値を伏せてレビューし、一つの staging resource から import-only plan、refresh-only plan、通常 plan を確認してから管理対象を決める手順が既に文書化されている。API key、Edge Function secret は state に残り得るため当面取り込まない。
- **Implications**: inventory、ownership、read-only plan、import review、prevent_destroy、Environment protection が揃うまで Supabase Terraform の apply/import を行わず、CI の static validation と local DB test を完了条件にする。

### Cloudflare Workers Custom Domain と権限

- **Context**: Worker が API の origin であり、`workers.dev` の公開や通常の Route との二重管理を避けながら、取得済み zone の hostname を正式な入口にする必要がある。
- **Sources Consulted**: [Cloudflare Workers Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)、[Wrangler configuration](https://developers.cloudflare.com/workers/wrangler/configuration/)、[Workers authorization](https://developers.cloudflare.com/workers/authorization/workers/)、[Certificate statuses](https://developers.cloudflare.com/ssl/reference/certificate-statuses/)、[DNS records with same name](https://developers.cloudflare.com/dns/manage-dns-records/troubleshooting/records-with-same-name/)（いずれも 2026-09-20 確認）。
- **Findings**: Wrangler の `routes` に hostname と `custom_domain: true` を設定すると、Worker を Custom Domain の origin として扱える。Custom Domain は zone 所有権が必要で、Cloudflare が DNS レコードと Advanced Certificate を作成する。既存 CNAME は Custom Domain と競合し、既存 A/AAAA も同じ hostname のサービスと競合し得るため、作成前に確認する。証明書は `Initializing`、`Pending Validation`、`Pending Issuance`、`Pending Deployment` を経て `Active` になる。
- **Permissions**: 初回 Worker 作成には Workers product-level Admin、既存 Worker の通常 deploy には Workers product-level Editor が必要である。Custom Domain の add/update/remove には、現行Dashboardで`Zone > Workers Routes > Edit`と表示されるzone-scoped権限を`beyond-labo.com`だけに付与する。Cloudflare API資料では同じ書き込み権限が`Workers Routes Write`と表記される場合がある。Custom Domains は per-Worker roles に対応しないため、per-Worker Editor へ縮小しない。Custom Domain の自動 DNS 作成だけを目的に DNS Write を付与しない。
- **Implications**: staging は `api-staging.beyond-labo.com`、production は `api.beyond-labo.com` とし、両方の `workers_dev` を `false` にする。Terraform は同じ DNS、Route、Custom Domain resource を定義せず、smoke は証明書反映直後の一時的失敗を 5 秒 timeout、12 回、5 秒間隔で有限 retry する。

### 実環境の read-only preflight

- **Context**: 推測で account をまたいだ Custom Domain 作成を実装しないため、ユーザーが指定した Google account の Cloudflare Dashboard で zone と DNS を確認した。
- **Observed**: Cloudflare Dashboard の `Hiiragi589.work@gmail.com's Account` で Workers 設定と `beyond-labo.com` の登録画面を確認した。公開 DNS の NS は `greg.ns.cloudflare.com` と `celine.ns.cloudflare.com` で、`api-staging` と `api` の A、AAAA、CNAME は確認時点で応答がなかった。
- **Boundary**: この確認は同一 account と競合なしの read-only preflight の証拠であり、Custom Domain 作成、DNS変更、Worker deploy、証明書発行の成功を意味しない。初回運用時にも Dashboard で zone の `Active` と account 一致を再確認する。

## Architecture Pattern Evaluation

| Option | Strengths | Risks / Limitations | Decision |
|---|---|---|---|
| Hono module Worker | Workers の契約に直接対応し、route test が `app.fetch` へ接続できる | Node.js middleware はそのまま使えない | 採用 |
| Node.js HTTP server | ローカル開発が単純 | Cloudflare Runtime と契約が異なり、今回の実行基盤から外れる | 不採用 |
| 大規模 Clean Architecture の先行導入 | 将来の境界を先に固定できる | 業務責務のない段階で空抽象化が増える | 不採用。必要な層だけ作る |

## Design Decisions

### Decision: `/healthz` の公開 payload を最小化する

- **Context**: 稼働確認は必要だが、binding 名・環境・stack trace などの内部情報を公開しない必要がある。
- **Selected Approach**: 固定的で内部情報を含まない JSON オブジェクトを返し、日時や version のような非決定値を初期契約へ入れない。
- **Trade-offs**: 詳細な診断情報は得られないが、公開面とテストを安定させ、将来の認証済み diagnostics と分離できる。

### Decision: 実デプロイはしない

- **Context**: ユーザーの承認はサーバー実装とローカル検証の範囲で、Cloudflare account の変更を含まない。
- **Selected Approach**: Wrangler の dry-run のみを完了条件とし、Terraform/CD は後続タスクへ分離する。
- **Trade-offs**: 実環境の到達性は未検証だが、資格情報なしの再現可能な実装検証を先に成立させる。

## References

- [Hono on Cloudflare Workers](https://hono.dev/docs/getting-started/cloudflare-workers) — module Worker と `app.fetch` の契約。
- [Cloudflare Workers testing](https://developers.cloudflare.com/workers/testing/) — Workers Runtime テストの選定根拠。
- [Wrangler commands](https://developers.cloudflare.com/workers/wrangler/commands/) — dry-run の実行入口。

## Change Log

### 2026-09-22

`backend-user-account-management`仕様で承認されたSupabase migrationと実行時設定注入を既存Backend配布へ合成した。Terraform apply、DB migrationとlinked履歴確認、Worker deploy、health smokeの順序を現行契約として同期し、Worker rollbackがDB rollbackではない境界を維持した。

### 2026-09-20

ユーザーの実装順承認を受け、brief の広い CI/CD 構成案から、今回実装する最小 Worker、運用 endpoint `GET /healthz`、pnpm scripts、runtime test、型検査、bundle dry-run、README/既存検証の更新だけを現行範囲として確定した。`/healthz` の公開 payload は固定 `{\"status\":\"ok\"}` とし、内部情報を返さない。Terraform、CD、OpenAPI、実デプロイは brief の後続範囲として扱い、今回の実行タスクには含めない。

Wrangler 4.129.1 の生成型に末尾空白が含まれるため、`types` script は生成直後に末尾空白だけを正規化する。型の意味は変更せず、追跡済み生成物と `git diff --check` を再現可能に保つ。

当初候補の Vitest 5.0.1 は Cloudflare Vitest plugin 1.1.13 との組み合わせで起動できなかったため、Workers Runtime test が成功した Vitest 4.1.11へ固定した。

ユーザーの追加実装依頼により、既存の最小 Worker 仕様を Backend CI/CD、Cloudflare Terraform、staging/production 配布へ拡張した。追加範囲の根拠は brief と上記の R2 S3、Terraform backend、GitHub Environment、Actions secure-use の一次資料である。Terraform resource の具体的選定は未決定のため、環境別 provider/state scaffold と検証だけを確定し、bucket bootstrap と実 credential による apply/deploy は今回のローカル完了条件から除外した。

### 2026-09-20 Custom Domain 方針の同期

ユーザー承認により、Worker API の正式な公開入口を `api-staging.beyond-labo.com` と `api.beyond-labo.com` の Custom Domain に確定した。
Wrangler の `custom_domain: true` と `workers_dev: false` を環境別設定の正本とし、Terraform へ DNS、Route、Custom Domain resource を重複定義しない。
Cloudflare 公式資料で Custom Domain の zone 所有、DNS/TLS 自動作成、証明書状態、Workers 権限、per-Worker role 非対応を確認した。
同日、指定された Google account の Cloudflare Dashboard を read-only で確認し、`beyond-labo.com` の管理画面が同一 account に表示され、公開 DNS では `api-staging` と `api` の A/AAAA/CNAME 応答がなかった。
実際の Custom Domain 作成、DNS変更、Worker deploy、証明書発行は実行していない。

### 2026-09-25 Supabase Terraform scaffold 同期

`infra/supabase/environments/staging` と `production` の空 Terraform root、provider/version constraint、partial backend、lockfile、および Backend CI の全 root static validation、Supabase local migration/RLS CI を現行根拠として追加した。DB schema/RLS/migration の Supabase CLI 所有と Cloudflare/Wrangler の既存所有境界は維持した。Supabase Project の apply/import、hosted staging/production migration、実 credential による plan/deploy は未実施であり、既存の承認と実装完了フラグを失効させた。
