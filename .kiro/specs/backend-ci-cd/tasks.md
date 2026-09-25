---
type: Implementation Plan
title: "Backend CI/CD と Cloudflare 配布実装計画"
description: "pnpm 管理の Worker、Terraform 環境別 state、secretless CI、staging/production 配布の実装順"
status: draft
sources:
  - id: backend-design
    resource: ./design.md
    title: Backend 最小 Worker 設計
kiro:
  depends_on:
    - .kiro/specs/backend-ci-cd/requirements.md
    - .kiro/specs/backend-ci-cd/design.md
---

# Implementation Plan

## 今回実装する範囲

- [x] 1. pnpm 管理と Workers の実行設定を追加する
  - `apps/backend/package.json`、TypeScript/Vitest/Wrangler 設定、必要な root lockfile 更新を追加し、`pnpm install --frozen-lockfile` 後に Backend の script 名が解決できる。
  - `wrangler.jsonc` は非機密の entrypoint、compatibility date、最小 Worker 設定だけを持ち、実デプロイを起動しない。
  - 完了条件: `pnpm --dir apps/backend typecheck` と bundle dry-run の入口が存在し、秘密なしで設定を読める。
  - _Requirements: 1.1, 1.2, 2.1_
  - _Boundary: BackendPackage, WorkerConfiguration_

- [x] 2. Hono の `/healthz` Worker を実装する
  - `src/EntryPoint/index.ts`、`src/Composition/createApp.ts`、`src/Health/Presentation/healthRoute.ts` を設計どおりに作成する。
  - `GET /healthz` は 200 JSON の固定 payload、未定義 route は 404 とし、内部情報を返さない。
  - 完了条件: Worker module の default export が存在し、Node.js 専用 API と不要な Domain/Application の空実装を追加せず route を提供する。
  - _Requirements: 2.1, 2.2, 2.3, 2.4_
  - _Boundary: WorkerEntryPoint, BackendAppFactory, HealthRoute_
  - _Depends: 1_

- [x] 3. Workers Runtime 契約テストを追加する
  - `test/health.worker.test.ts` と Vitest Workers 設定で runtime request/response を実行し、health の status、JSON content type、payload の非公開情報不在、未知 route 404 を検証する。
  - 完了条件: テストがローカルで秘密なしに実行でき、失敗時に非ゼロ終了する。
  - _Requirements: 3.1, 3.2_
  - _Boundary: WorkerRuntimeTest_
  - _Depends: 2_

- [x] 4. pnpm 検証入口と現行文書を同期する
  - package scripts から typecheck、Workers Runtime test、Wrangler dry-run を再現可能な順序で実行できるようにする。
  - `apps/backend/README.md`、`docs/operations/development.md`、必要に応じて `scripts/verify.mjs` を更新し、既存 Worker の local verify と、外部 credential/Environment 設定後に実行する Terraform/CD の境界を分けて記載する。
  - 完了条件: repository verify が Backend の必須設定・script・test 入口の欠落を検出し、文書のコマンドが実在する。
  - _Requirements: 1.2, 1.3, 4.1, 4.2, 4.3_
  - _Boundary: BackendScripts, ProjectDocumentation_
  - _Depends: 1, 2, 3_

- [x] 5. 今回範囲の統合検証を完了する
  - frozen install 後に typecheck、Workers Runtime test、bundle dry-run、repository verify を実行する。
  - 実 Cloudflare deploy と Terraform/CD の credential を必要とする検証は外部設定後の新規タスクへ分離し、今回の既存 Worker 完了条件へ混ぜない。
  - 完了条件: 4 つの検証が成功し、失敗時は非ゼロ終了し、外部設定が必要な配布範囲が明記される。
  - _Requirements: 1.1, 1.3, 3.1, 3.2, 3.3, 4.3_
  - _Boundary: IntegrationValidation_
  - _Depends: 4_

- [x] 6. Terraform の環境別 root と R2 state 境界を追加する
  - `infra/cloudflare/environments/staging` と `production` に provider/version constraint、資格情報を持たない partial S3 backend、空の検証可能な root、outputs、各 `.terraform.lock.hcl` を追加する。
  - state key は環境ごとに分離し、R2 bucket bootstrap、backend credential、D1/KV/R2/Queue/DNS 等の未決定 resource は root に含めない。
  - Terraform と Wrangler の所有表、禁止 artifact（state、plan、`.terraform`、secret tfvars）を `infra/cloudflare/README.md` と ignore/verify 契約へ反映する。
  - 完了条件: 両 root で `terraform fmt -check`、`terraform init -backend=false`、`terraform validate` が秘密なしで成功し、同一 resource の二重管理がない。
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_
  - _Boundary: TerraformEnvironmentRoot_
  - _Depends: 5_

- [x] 7. Backend の secretless Pull Request CI を追加する
  - `.github/workflows/ci-backend.yml` を作成し、PR、`main` push、手動実行で GitHub-hosted runner、固定 Node.js/pnpm、SHA-pinned action、`contents: read`、concurrency を設定する。
  - frozen install、Wrangler generated types 差分、Backend typecheck/Workers Runtime test/Wrangler dry-run、staging/production 各 Terraform fmt/init backend=false/validate を順序どおり実行する。
  - Cloudflare/R2 credential、runtime secret、protected Environment、`pull_request_target` を参照しないことを静的検証する。
  - 完了条件: credential なしの CI workflow lint/static check と repository verify が全検証入口、SHA pin、最小権限、禁止参照を検出し、各失敗が non-zero になる。
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 9.1, 9.4_
  - _Boundary: BackendCiWorkflow_
  - _Depends: 6_

- [x] 8. `main` から staging への自動配布を追加する
  - `.github/workflows/cd-backend-staging.yml` を作成し、同一 SHA の verify → staging Environment の Terraform plan/apply → Supabase migrationとlinked履歴確認 → `wrangler deploy --env staging` → `BACKEND_HEALTH_URL/healthz` smoke の順を固定する。
  - `backend-staging` concurrency、Environment vars/secrets、R2 remote state、state/plan を artifact にしない契約を実装し、未検証の `use_lockfile` は有効化しない。
  - 任意の verify/plan/apply/deploy/smoke 失敗で後続 mutation を停止し、summary に commit SHA と deploy identifier を残す。
  - 完了条件: credential のモックまたは dry-run でジョブ順序、failure propagation、concurrency、secret 名/vars 名が検証できる。
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 9.1, 9.2, 9.3, 10.3, 10.4_
  - _Boundary: StagingDeployWorkflow_
  - _Depends: 7_

- [x] 9. production の preflight・承認・再計算配布を追加する
  - `.github/workflows/cd-backend-production.yml` を作成し、`backend-vX.Y.Z` tag と manual trigger、tag SHA の `main` ancestor check、同一 SHA の verify を実装する。
  - `production-plan` の read-only credential で `-lock=false` の非機密 plan summary を作り、saved plan を保存せず、`production` protected Environment の required reviewer 承認後に `backend-production` concurrency 下で plan を再計算して apply する。
  - apply 成功後だけSupabase migrationとlinked履歴確認を行い、その後に`wrangler deploy --env production`とhealth smokeを行う。`backend-production` concurrency、commit/run/version/URL/actor summary、staging/production credential分離を実装する。
  - 完了条件: approval 前の plan が apply に再利用されず、main 非包含 tag、verify failure、approval 未完了、smoke failure が変更処理を停止することを workflow 検査で確認できる。
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 9.1, 9.2, 9.3, 10.3_
  - _Boundary: ProductionDeployWorkflow_
  - _Depends: 7, 8_

- [x] 10. 運用文書、rollback、検証を同期する
  - `infra/cloudflare/README.md`、`apps/backend/README.md`、`docs/operations/backend-ci-cd.md`、必要な `scripts/verify.mjs` と `.gitignore` を更新し、secret/vars、R2 bootstrap、Environment/reviewer、state/plan 非公開、ownership、rollback の開始条件と実行者を記載する。
  - smoke failure 時に自動データ操作をせず安定 Worker version を 100% traffic に戻す手順、Worker rollback がSupabase dataやTerraform stateのrollbackではないこと、migrationのexpand/contractとlinked履歴確認を明記する。
  - frozen install、Backend verify、両 Terraform root の secretless validation、workflow static check、禁止ファイル検査、`git diff --check` を実行する。
  - 完了条件: 外部 credential/Environment/bootstrap が未設定でも local verification が成功し、実 Cloudflare apply/deploy の成功を主張せず、Requirement 1-10 の traceability と OKF check issues 0 を確認できる。
  - _Requirements: 4.1, 4.2, 4.3, 6.3, 9.5, 10.1, 10.2, 10.3, 10.4_
  - _Boundary: DeploymentRunbook, RepositoryVerification_
  - _Depends: 6, 7, 8, 9_

- [x] 11. Cloudflare Workers Custom Domain を環境別に接続する
  - `apps/backend/wrangler.jsonc` の `staging` に `api-staging.beyond-labo.com`、`production` に `api.beyond-labo.com` を `routes[].custom_domain: true` として定義し、両 environment の `workers_dev` を `false` にする。
  - `beyond-labo.com` zone が Worker 配布先と同じ account 内で Active であること、`api-staging` と `api` の A/AAAA/CNAME に既存競合がないことを初回 preflight で確認する。
  - Wrangler が Custom Domain、Cloudflare の自動 DNS/TLS を所有し、Terraform に同じ DNS、Route、Custom Domain resource を定義しない境界を実装と runbook に反映する。
  - staging の `BACKEND_HEALTH_URL` は `https://api-staging.beyond-labo.com`、production は `https://api.beyond-labo.com` とし、`production-plan` には登録しない。
  - Custom Domain 変更権限は初回 Workers product-level Admin、通常 product-level Editor と `beyond-labo.com` 限定の `Zone > Workers Routes > Edit` とし、per-Worker Editor や DNS Write を前提にしない。
  - DNS/TLS 反映直後の一時的な health failure を考慮し、smoke を 5 秒 timeout、12 回、5 秒間隔の有限 retry とする。
  - 完了条件: repository 内の設定、workflow、runbook、仕様が相互整合し、実 Cloudflare deploy/DNS変更を行わずに static 検証できる。実環境の Custom Domain 作成と証明書 Active は未実施として報告する。
  - _Requirements: 6.5, 6.6, 7.2, 7.3, 8.4, 8.5, 8.6, 9.2, 10.3, 10.4_
  - _Boundary: WorkerCustomDomain, DeploymentPreflight, DeploymentRunbook_
  - _Depends: 6, 7, 8, 9, 10_

- [x] 12. Supabase Terraform root と secretless local CI を同期する
  - `infra/supabase/environments/staging` と `production` の provider/version constraint、partial S3 backend、空の `main.tf`、lockfile を確認し、Cloudflare root と state/credential を混在させない。
  - `.github/workflows/ci-backend.yml` が Cloudflare と Supabase の全 environment root で `fmt -check`、`init -backend=false`、`validate` を credential なしで実行することを確認する。
  - `.github/workflows/ci-supabase.yml` が hosted credential なしで local migration、DB lint、pgTAP を実行し、local 成功を hosted staging/production の apply 成功として表示しないことを確認する。
  - `supabase/migrations/`、RLS、DB functions は Supabase CLI/稼働 DB が所有し、Terraform へ重複定義しない。Project resource、import block、apply は inventory/ownership review 後まで追加しない。
  - 完了条件: Supabase root と secretless CI の静的契約が現行ファイルと一致し、実 Supabase Project の Terraform apply/import、hosted migration、deploy は未実施として残る。
  - _Requirements: 5.3, 6.2, 6.3, 6.4, 9.2, 10.4, 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7_
  - _Boundary: SupabaseTerraformRoot, SupabaseMigrationCI_
  - _Depends: 6, 7, 8, 10_
