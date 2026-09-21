---
type: Requirements
title: "Backend CI/CD と Cloudflare 配布要件"
description: "pnpm 管理の Backend、Terraform 基盤、GitHub Actions CI/CD、Cloudflare 環境別配布の要件"
status: stable
sources:
  - id: approved-scope
    resource: user-request://2026-09-20/backend-minimum-worker
    title: ユーザー承認済みの実装範囲
  - id: backend-brief
    resource: ./brief.md
    title: Backend CI/CD 構成案
kiro:
  depends_on:
    - docs/architecture/technology.md
    - docs/architecture/package-structure.md
    - docs/architecture/api-contracts.md
    - docs/operations/development.md
---

# Requirements Document

## Introduction

Backend の実装入口を pnpm workspace の `apps/backend` に置き、TypeScript と Hono で Cloudflare Workers Runtime 上の HTTP サーバーを実行可能にする。Pull Request では秘密情報なしの検証を行い、`main` から staging、タグまたは手動実行から承認済み production へ、Terraform と Wrangler の責務を分離した配布経路を提供する。最初の公開契約は稼働確認に必要な `GET /healthz` だけとし、公開 hostname は `api-staging.beyond-labo.com` と `api.beyond-labo.com` の Custom Domain に固定する。

## Boundary Context

- **In scope**: `apps/backend` の pnpm package、TypeScript/Hono Worker、`GET /healthz` の JSON 契約、Workers Runtime テスト、型検査、bundle の dry-run、Terraform の環境別 root/state scaffold、R2 S3 remote state の partial config、Wrangler 管理の環境別 Custom Domain、Backend PR CI、staging 自動配布、production 承認配布、smoke/rollback 手順、関連 README と検証。
- **Out of scope**: Cloudflare account、R2 state bucket、GitHub Environment、branch protection、reviewer、secret の初期作成と実資格情報による apply/deploy、OpenAPI 自動生成・公開、認証、DB、業務 API、remote preview、production gradual deployment。
- **Adjacent expectations**: Backend は iOS/Android と独立してビルド・リリースし、将来の公開契約は Backend が所有する。Terraform は長寿命 resource と state、Wrangler は Worker script/version/deploy/binding/Custom Domain と対応する自動 DNS/TLS を所有し、同一 resource を二重管理しない。

## Requirements

### Requirement 1: pnpm 管理の実行可能 Backend

**Objective:** As a 開発者, I want pnpm から Backend の検査と実行を再現したい, so that ローカルと CI で同じ入口を使える

#### Acceptance Criteria

1. When `pnpm install --frozen-lockfile` がリポジトリルートで実行された, the Backend package shall `apps/backend` の TypeScript、Hono、Workers テスト依存を lockfile に従って解決できる
2. The Backend package shall `typecheck`、Workers Runtime test、`build` または Wrangler dry-run を pnpm script として提供する
3. If 型検査、テスト、bundle 検証のいずれかが失敗した, the Backend verification shall 非ゼロ終了する

### Requirement 2: Workers Runtime の HTTP サーバー

**Objective:** As a 運用担当者, I want Cloudflare Workers Runtime で起動できる最小サーバーがほしい, so that 後続の API 実装を安全に開始できる

#### Acceptance Criteria

1. When Worker module が Workers Runtime にロードされた, the Backend shall module entrypoint から Hono application を default export し、Node.js 専用 API を実行時に要求しない
2. The Backend shall Hono と Cloudflare 固有型を `EntryPoint`、`Composition`、`Presentation` の外側へ漏らさず、将来の Domain / Application が HTTP framework に依存しない配置を維持する
3. When `GET /healthz` を受信した, the Backend shall HTTP status `200` と `Content-Type: application/json` で、固定 JSON `{\"status\":\"ok\"}` を返す
4. If `/healthz` 以外の未定義 route を受信した, the Backend shall HTTP status `404` を返す

### Requirement 3: 実行時契約と検証

**Objective:** As a 開発者, I want health 契約を Workers Runtime 相当で検証したい, so that adapter の違いによる回帰を検出できる

#### Acceptance Criteria

1. When Workers Runtime test が実行された, the Backend test shall `GET /healthz` の status、JSON content type、body の公開フィールドが契約どおりであることを検証する
2. When Workers Runtime test が実行された, the Backend test shall 未定義 route の `404` と、health response に runtime binding、stack trace、環境変数などの内部情報が含まれないことを検証する
3. The Backend verification shall TypeScript 型検査と Wrangler の bundle dry-run を同一 package の pnpm 入口から再実行できる

### Requirement 4: 開発者向け境界の文書化

**Objective:** As a 開発者, I want Backend の現在の実装範囲と検証方法を知りたい, so that 未実装の配布経路を誤って前提にしない

#### Acceptance Criteria

1. When Backend の開発手順を参照した, the project documentation shall pnpm の install、typecheck、Workers Runtime test、bundle dry-run の実行方法を記載する
2. Where 実 Cloudflare credential、state bucket、GitHub Environment の bootstrap が未設定である, the project documentation shall それらをローカル完了事項と表現せず、外部設定後に実行する範囲として明記する
3. The repository verification shall Backend の追跡対象設定、script、テスト入口の欠落を検出できる

### Requirement 5: 秘密情報なしの Backend Pull Request CI

**Objective:** As a 開発者, I want pull request 上で Backend と Terraform の検証を再現したい, so that 秘密情報を fork や untrusted code に公開せずに merge gate を運用できる

#### Acceptance Criteria

1. When a pull request、`main` push、または手動実行が開始された, the Backend CI shall GitHub-hosted runner 上で commit SHA に固定した action、固定 Node.js/pnpm、`pnpm install --frozen-lockfile` を実行する
2. When frozen install が成功した, the Backend CI shall Wrangler 生成型を再生成して差分を検査し、Backend の typecheck、Workers Runtime test、Wrangler bundle dry-run を実行する
3. When Terraform の CI 検証が開始された, the Backend CI shall `infra/cloudflare/environments/staging` と `production` の各 root で `terraform fmt -check`、`terraform init -backend=false`、`terraform validate` を実行する
4. While a pull request workflow is running, the Backend CI shall Cloudflare API token、R2 state credential、runtime secret、protected Environment を参照せず、`contents: read` のみを付与する
5. If any required verification fails, the Backend CI shall non-zero で終了し、merge gate を成功として報告しない

### Requirement 6: Terraform の環境別 state と所有境界

**Objective:** As a インフラ担当者, I want staging と production の長寿命 Cloudflare resource と state を分離したい, so that 誤った環境の変更とツール間の二重管理を防げる

#### Acceptance Criteria

1. The infrastructure code shall `infra/cloudflare/environments/staging` と `infra/cloudflare/environments/production` を独立した Terraform root module として持ち、各 root が別の state key と apply credential 契約を持つ
2. When Terraform root が初期化された, the infrastructure code shall Cloudflare R2 S3 backend の partial configuration を使用し、bucket の作成・bootstrap と backend credential を repository の Terraform root に含めない
3. The infrastructure code shall Terraform provider/version constraint と各環境の `.terraform.lock.hcl` を追跡可能にし、`terraform.tfstate*`、`.terraform/`、`*.tfplan`、secret を含む tfvars を repository と公開 artifact に保存しない
4. Where Terraform が管理する対象を定義した, the infrastructure code shall 長寿命 resource と account/zone policy だけを Terraform の所有とし、初期 scaffold では未決定の D1、KV、R2、Queue、DNS、Route、Custom Domain 等を捏造しない
5. The deployment configuration shall Wrangler を Worker script、version、deployment、binding、Custom Domain、対応する自動 DNS/TLS の唯一の所有者とし、Terraform と同じ Cloudflare resource を宣言しない
6. The infrastructure documentation shall `beyond-labo.com` zone が Worker 配布先と同じ Cloudflare account にあり Active であることを初回 preflight で確認し、異なる account の場合は移管または Worker 配置先の決定まで実装を停止する

### Requirement 7: staging 自動配布

**Objective:** As a 開発者, I want 検証済みの `main` を staging へ自動配布したい, so that production 前に実環境の health 契約を確認できる

#### Acceptance Criteria

1. When `main` への push が発生した, the staging CD shall 同じ commit の Backend verify を成功させた後、GitHub Environment `staging` の資格情報で staging Terraform plan/apply を実行する
2. When staging Terraform apply が成功した, the staging CD shall lockfile の Wrangler を使って `wrangler deploy --env staging` を実行し、`api-staging.beyond-labo.com` の Custom Domain（`custom_domain: true`、`workers_dev: false`）を経由して `GET /healthz` smoke test を行う
3. When staging の Custom Domain を初回作成または更新した, the staging CD shall `BACKEND_HEALTH_URL=https://api-staging.beyond-labo.com` を使い、5 秒 timeout、最大 12 回、5 秒間隔の有限 retry で DNS/TLS 証明書の反映を待機する
4. If verify、Terraform plan/apply、Wrangler deploy、または有限 retry 後の smoke test が失敗した, the staging CD shall 後続の変更処理を実行せず non-zero で終了する
5. While staging deployment runs overlap, the staging CD shall 同一 staging Worker を concurrency で直列化し、未開始の古い run を置換できる

### Requirement 8: production 承認配布

**Objective:** As a リリース担当者, I want production 配布を追跡可能な commit と承認で制御したい, so that 意図しない production 変更を防ぎ安全にリリースできる

#### Acceptance Criteria

1. When `backend-vX.Y.Z` annotated tag または許可された手動実行が開始された, the production CD shall 対象 commit が `main` に含まれることと同一 commit の Backend verify 成功を確認する
2. When production preflight が開始された, the production CD shall Cloudflare read-only credential で production Terraform plan の非機密な要約だけを作り、R2 backend credential は state read に限定し、plan 全文または saved plan を public comment/artifact に保存しない
3. When preflight summary が確認された, the production CD shall required reviewer を設定した protected GitHub Environment `production` の承認を要求する
4. When `production` Environment の承認が完了した, the production CD shall saved plan を再利用せず環境別 concurrency で他の apply と直列化した上で plan を再計算して apply し、`api.beyond-labo.com` の Custom Domain（`custom_domain: true`、`workers_dev: false`）へ `wrangler deploy --env production` を行い、成功後に `GET /healthz` smoke test を実行する
5. When production の Custom Domain を初回作成または更新した, the production CD shall `BACKEND_HEALTH_URL=https://api.beyond-labo.com` を使い、5 秒 timeout、最大 12 回、5 秒間隔の有限 retry で DNS/TLS 証明書の反映を待機する
6. The `production-plan` Environment shall not register `BACKEND_HEALTH_URL` and shall not execute production deploy or health smoke.
7. The production CD shall job summary に commit SHA、Terraform run、Worker version または deployment identifier、deployment URL、実行者を記録し、staging と production の credential と runtime secret を混在させない

### Requirement 9: CI/CD の安全な実行契約

**Objective:** As a リポジトリ管理者, I want CI/CD の権限と入力を最小化したい, so that 公開 repository でも untrusted code が配布権限を得ないようにしたい

#### Acceptance Criteria

1. The CI/CD workflows shall GitHub-hosted runner、job 単位の最小 `permissions`、action の完全な commit SHA pin、workflow 単位の concurrency を使用する
2. The deployment workflows shall account ID、state bucket、staging/production health URL 等の非機密値を GitHub `vars`、Cloudflare API token と R2 access key を GitHub Environment `secrets` から受け取り、source、`.tfvars`、backend config、artifact に実値を書き込まない
3. The Cloudflare write token shall 初回 Worker 作成時だけ Workers product-level Admin、通常運用では product-level Editor を使い、`beyond-labo.com` zone に限定した `Zone > Workers Routes > Edit` を付与する。Custom Domain は per-Worker role 非対応のため per-Worker Editor へ縮小せず、Custom Domain 自動作成に DNS Write を要求しない
4. While Cloudflare R2 に対する Terraform S3 lockfile の互換性が実環境で検証されていない, the deployment workflows shall `use_lockfile` を有効化せず環境別 GitHub Actions concurrency を排他制御の正本とし、同一 state に対する手動実行との並行を運用上禁止する
5. While untrusted pull request code is running, the CI/CD workflows shall `pull_request_target` で checkout せず、deploy credential を持つ job を起動しない
6. The infrastructure and workflow paths shall ownership review と branch protection の対象として文書化され、Terraform plan 全文・state・saved plan を公開しない

### Requirement 10: rollback と外部実行境界

**Objective:** As a 運用担当者, I want deploy failure と未設定環境を安全に扱いたい, so that code rollback と data/state rollback を混同せず復旧できる

#### Acceptance Criteria

1. When staging または production smoke test が失敗した, the deployment runbook shall 自動でデータ操作を行わず、直前の安定 Worker version を Wrangler/Cloudflare の rollback 手順で 100% traffic に戻す手順を示す
2. The deployment runbook shall Worker version rollback は D1/KV/R2/Queue 等の状態や Terraform state を戻さないこと、将来の migration は expand/contract と後方互換を満たすことを明記する
3. Before the first Custom Domain deployment, the deployment runbook shall Cloudflare Dashboard で `beyond-labo.com` zone の account 一致と Active 状態を確認し、DNS Records で `api-staging` と `api` の A、AAAA、CNAME を確認し、既存レコードがあれば削除せず競合解消を停止条件にする
4. While Cloudflare credentials、R2 bucket、GitHub Environment、reviewer、health URL が未設定である, local verification shall scaffold、fmt、backend=false init、validate、secretless CI 検査までを完了条件とし、実 Cloudflare apply/deploy の成功を主張しない
5. The project documentation shall staging/production の secret・vars 契約、bootstrap の担当境界、account/zone preflight、DNS競合、Custom Domain の DNS/TLS 自動作成、証明書反映直後の有限 retry、rollback の開始条件と実行者を具体的なパスから参照できるようにする
