---
type: Runbook
title: "Cloudflare・Supabase Terraform 段階導入"
description: "既存資産の所有境界、import、state、drift、CI と復旧を定める"
status: draft
sources:
  - id: terraform-import
    resource: https://developer.hashicorp.com/terraform/language/import
    title: Terraform import blocks
  - id: terraform-state-security
    resource: https://developer.hashicorp.com/terraform/language/manage-sensitive-data
    title: Terraform sensitive state
  - id: cloudflare-import
    resource: https://developers.cloudflare.com/terraform/advanced-topics/import-cloudflare-resources/
    title: Cloudflare resource import
  - id: cloudflare-r2-backend
    resource: https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/
    title: Cloudflare R2 backend
  - id: supabase-provider
    resource: https://supabase.com/docs/guides/deployment/terraform/reference
    title: Supabase Terraform provider reference
  - id: supabase-import
    resource: https://supabase.com/docs/guides/deployment/terraform/tutorial
    title: Supabase existing Project import
kiro:
  depends_on:
    - infra/cloudflare/README.md
    - infra/supabase/README.md
    - docs/operations/backend-ci-cd.md
---

# Cloudflare・Supabase Terraform 段階導入

2026-09-25 時点のリポジトリ上の棚卸しと導入順を記録する。Cloudflare・Supabase の実アカウント API による全資産一覧と実 state の内容は、この調査では取得していない。リポジトリの宣言を実環境の存在証明とは扱わない。

Supabase の既存 Project を実際に管理対象へ移す際のコマンド、確認項目、停止条件は[専用手順書](./supabase-terraform-adoption.md)にまとめた。この PR では import と apply を行わない。

## 現在の所有と対象

| 資産 | 現在確認できる管理者 | Terraform への移行 |
| --- | --- | --- |
| staging / production Worker、version、binding、Custom Domain | Wrangler (`apps/backend/wrangler.jsonc`) | 現行 CD では移さない。Cloudflare provider に対応 resource があっても二重管理しない |
| Custom Domain が伴う DNS/TLS | Cloudflare と Wrangler | 移さない |
| R2 state bucket と R2 API credential | 手動 bootstrap と GitHub Environment | bucket を自分自身の backend root に取り込まない。将来は別 bootstrap root が必要 |
| その他の Cloudflare DNS・WAF・KV・Queue 等 | 実アカウント未棚卸し | ID と所有者、provider 対応、更新時の影響を確認して候補化 |
| Supabase staging / production Project、Auth 設定 | Dashboard と GitHub Environment | Management API 対応の設定だけを staging から import 候補化 |
| Supabase DB schema、RLS、関数 | `supabase/migrations/` と CLI | Terraform に重複宣言しない |
| Supabase 利用者、セッション、アプリデータ | 稼働 DB | Terraform 管理対象外 |
| Supabase API key、Edge Function secret、Worker secret、Apple資格情報 | 専用 secret 管理 | Terraform へ値を渡さない |

Cloudflare root は `infra/cloudflare/environments/{staging,production}` にあり、provider 5.23.0、現時点の managed resource は 0 件。Supabase root は `infra/supabase/environments/{staging,production}` に provider 1.9.0 で追加したが、同じく managed resource は 0 件。Supabase provider が公開する resource は Project、Settings、Branch、API key、Edge Function、Edge Function secrets、Third Party Auth などで、DB migration は含まれない。実際の provider 対応範囲と必要権限は対象ごとに再確認する。

## state と環境分離

```text
private R2 staging bucket                 private R2 production bucket
  cloudflare/staging/terraform.tfstate      cloudflare/production/terraform.tfstate
  supabase/staging/terraform.tfstate        supabase/production/terraform.tfstate
```

`scripts/terraform/init-r2-backend.sh` は root の provider と環境から key を決める。backend 認証は環境限定の R2 S3 credential、provider 認証は Cloudflare token または `SUPABASE_ACCESS_TOKEN`。state の読み取りにも機密閲覧権限が伴うため、private bucket、保存時暗号化、TLS、最小権限、アクセス記録、バックアップ/復元手順を実環境で確認する。state、plan、tfvars は Git、PR、公開 artifact、ログに載せない。`sensitive` 表示だけでは state 内の値を隠せない。

R2 S3 backend の lockfile 互換性は現環境で未検証。現行 workflow の環境別 `concurrency` は自動実行の排他として維持するが、手動操作との排他にはならない。import や apply を行う日は当該環境の自動 workflow を停止し、作業者を一人に限定する。lockfile の有効化は並行実行、stale lock、権限失敗を実 R2 で検証する別作業とする。

## 移行手順

1. **読み取り棚卸し**: Cloudflare account/zone と Supabase Project ごとに、名前・ID・リージョン・所有者・provider 対応を確認する。secret の値を取得、記録しない。Wrangler/CLI/Dashboard 所有のものを明示する。
2. **候補選定**: staging の影響が小さい設定を 1 resource だけ選ぶ。Cloudflare の既存資産には Cloudflare 公式の import 手順、Supabase Project には Supabase 公式の既存 Project import 手順を使う。Project 全体を import しても、その後に管理する属性を狭く保つ。
3. **構成と import block**: 実態と同じ属性を記述し、破壊可能な resource に `prevent_destroy` を設定する。provider の import ID 形式を対象 resource の公式リファレンスで確認する。`terraform plan` で `import` のみ、`add/change/destroy` が 0 件であることを gate にする。
4. **state へ取り込み**: 専用の承認された apply で import を確定する。直後に refresh-only plan と通常 plan を実施し、意図しない変更がないことを確認する。plan 原文は公開しない。
5. **drift 運用**: 定期の read-only plan を環境別 credential で実行し、差分の件数と種別だけ通知する。Dashboard 変更を見つけたら所有者を確認し、コードに取り込むか意図的に戻すかをレビューする。自動修復はしない。
6. **CI/CD**: PR は secretless `fmt/init -backend=false/validate`。実資産 plan は保護された Environment の読み取り権限で実施。production apply はレビュー後に plan を再計算し、`destroy` と予期しない `replace` を拒否する。最初の import が安定するまで Supabase root の自動 apply は追加しない。

## 復旧

Worker のコード配布は Wrangler の version rollback を使い、Terraform state を巻き戻さない。Terraform 管理の設定変更は前値を確認して新しい plan/apply で戻す。state の事故はバックアップを隔離して復旧手順を検証するまで apply を止める。`state rm` は管理解除のみで実資産は残るが、その後の二重管理を防ぐため所有者の引継ぎを同時に記録する。Supabase DB migration は Terraform の復旧対象ではなく、別の前方互換 migration とデータ復旧手順を用いる。

## 変更履歴

- 2026-09-25: リポジトリ上の Cloudflare/Wrangler/Supabase 資産と公式 Terraform 資料を照合し、Supabase の空 root と安全な import 順を追加。実アカウントの棚卸しは未実施。
