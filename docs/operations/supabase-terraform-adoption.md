---
type: Runbook
title: "既存 Supabase Project を Terraform 管理へ移す手順"
description: "staging から安全に棚卸し、import、差分確認、運用開始するための実行手順"
status: stable
sources:
  - id: supabase-tutorial
    resource: https://supabase.com/docs/guides/deployment/terraform/tutorial
    title: Supabase Terraform tutorial
  - id: supabase-reference
    resource: https://supabase.com/docs/guides/deployment/terraform/reference
    title: Supabase Terraform provider reference
  - id: terraform-import
    resource: https://developer.hashicorp.com/terraform/language/import
    title: Terraform import
  - id: terraform-sensitive
    resource: https://developer.hashicorp.com/terraform/language/manage-sensitive-data
    title: Terraform sensitive data
kiro:
  depends_on:
    - infra/supabase/environments/staging/providers.tf
    - infra/supabase/environments/staging/backend.tf
    - scripts/terraform/init-r2-backend.sh
    - docs/operations/backend-ci-cd.md
---

# 既存 Supabase Project を Terraform 管理へ移す手順

2026-09-25 時点の手順。この PR は空の Terraform root と静的検証までを用意する。**PR のマージだけで既存 Project は Terraform 管理にならない。** 実アカウントの棚卸し、構成追加、import、state の確認は別の作業で、まず staging の一資産を対象に実施する。この文書は手順書であり、今回の作業では hosted Supabase に対する import、plan、apply を行わない。

## 1. 対象と担当を確定する

| 対象 | 正本 | この移行での扱い |
| --- | --- | --- |
| Project と Management API で扱う設定 | import 後の Terraform | staging の一資産から段階的に管理する |
| DB schema、RLS、関数 | `supabase/migrations/` と Supabase CLI | Terraform へ移さない |
| Auth 利用者、セッション、アプリデータ | 稼働 DB | Terraform 対象外 |
| API key、DB password、Worker secret | 保護された secret 管理 | Git、PR、ログに値を書かない。Project resource の必須 `database_password` は例外的に安全な実行環境から渡し、state も機密として扱う |
| Worker と binding | Wrangler | Terraform へ重複宣言しない |

Supabase の公式チュートリアルは、既存 Project の import ID に Project ref を使い、`supabase_project` に `organization_id`、`name`、`database_password`、`region` を指定する。`supabase_settings` は Project ref に対する部分更新で、指定した項目だけを管理できる。provider の対象 resource と属性は作業日に[公式リファレンス](https://supabase.com/docs/guides/deployment/terraform/reference)で再確認する。Project import と settings の更新を同じ初回 apply にまとめない。

担当者は staging Project 管理者、R2 state 管理者、変更レビュー担当者を決める。作業日には当該環境の自動 Terraform 実行を止め、同じ state を操作する担当者を一人にする。現行 R2 backend の lockfile 互換性は実環境で未検証であり、GitHub Actions の `concurrency` は手元の CLI との排他を保証しない。

## 2. 読み取り専用で現物を棚卸しする

Supabase Dashboard と GitHub Environment の設定を確認し、次の**識別情報と設定値の種類**を非公開の作業記録に整理する。token や password の値は転記しない。

| 確認項目 | 合格条件 |
| --- | --- |
| staging / production の Project ref、organization ID、region、Project 名 | 環境を取り違えないよう二人で突き合わせた |
| 対象 Project の現行設定、Dashboard 変更担当 | Terraform に移す属性と Dashboard に残す属性を列挙した |
| staging の DB password の保管元 | 既存値を安全に受け取れる。再設定を import 作業と同時に行わない |
| R2 staging bucket、endpoint、state key | `supabase/staging/terraform.tfstate` が Cloudflare 用および production 用 state と独立している |
| state bucket の権限、暗号化、履歴・復元 | state/plan に DB password 等が載り得ることを前提に、閲覧者と復旧手順を確認した |
| CI/CD と他の管理ツール | 同じ Project 設定を二重に apply するものがない |

すでに `supabase/staging/terraform.tfstate` が存在する場合は、作成者・所有者・state 内の resource を確認するまで進まない。`init -reconfigure` は既存 state の移設操作ではない。既存の別 backend から移す必要がある場合は、バックアップと移設手順を別途レビューし、ここで `-migrate-state` を試行しない。

## 3. credential と作業場所を準備する

Terraform は root と lock file の版に合わせる。リポジトリのルートから以下を実行する。`fmt/init -backend=false/validate` は実 Project への変更を伴わない。

```bash
terraform version
terraform -chdir=infra/supabase/environments/staging fmt -check
terraform -chdir=infra/supabase/environments/staging init -backend=false -input=false
terraform -chdir=infra/supabase/environments/staging validate
```

実 state を使う作業では、保護された端末または承認付きの専用ジョブに、環境限定の `SUPABASE_ACCESS_TOKEN`、`TF_STATE_BUCKET`、`TF_STATE_ENDPOINT`、`AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY` を secret store から注入する。`TF_STATE_ENDPOINT` は R2 の S3 endpoint。`set -x`、コマンド履歴への値の直書き、`*.tfvars` の Git 登録を避ける。token と R2 credential は staging に必要な権限だけを持つものとする。

Project resource を使う段階では、既存 DB password を保護された `TF_VAR_database_password` 等で渡す設計にする。変数名・属性は実際の HCL と一致させる。**`sensitive = true` は CLI 表示を抑えるだけで state 内の値を消さない。** plan ファイルと state は機密資料として扱う。Secret を読める人にだけ state bucket の権限を付ける。

## 4. staging の remote state を初期化する

前項の棚卸しが通った後だけ実行する。スクリプトは root のパスから `supabase/staging/terraform.tfstate` を決める。Cloudflare root を渡すと別 key になるので、次の引数をそのまま確認する。

```bash
bash scripts/terraform/init-r2-backend.sh staging "$PWD/infra/supabase/environments/staging"
terraform -chdir=infra/supabase/environments/staging state list
```

最初の `state list` は空であることを確認する。resource が出たら停止して既存の所有関係を調べる。R2 へのアクセス失敗、期待外の bucket/key、別環境の Project が見えた場合も停止する。state や plan の生データを PR/CI artifact に添付しない。

## 5. 既存 Project の import 用変更を作る

別 PR で staging root に**既存 Project と同じ** `supabase_project` resource と `import` block を追加する。以下は形を示す例であり、値を埋めた完成版ではない。実 Project ref は保護された `TF_VAR_linked_project` から渡す。DB password はコードに書かず、上記の保護された変数を使う。

```hcl
variable "linked_project" { type = string }
variable "database_password" {
  type      = string
  sensitive = true
}

resource "supabase_project" "existing" {
  organization_id   = "<staging の organization ID>"
  name              = "<既存の Project 名>"
  database_password = var.database_password
  region            = "<既存の region>"

  lifecycle {
    prevent_destroy = true
  }
}

import {
  to = supabase_project.existing
  id = var.linked_project
}
```

`<...>` はレビュー用の説明で、実行前に既存値で置換する。Project 名や region が違うと import と同時に更新・置換が提案され得る。Project ref を PR 本文や CI ログに出さない。Terraform の[import block](https://developer.hashicorp.com/terraform/language/import)は resource block と state のアドレスを対応させる。

## 6. 変更計画を確認してから import する

作業者だけが読める一時ディレクトリに plan を保存する。ファイルとコマンド出力に識別子や機密値が含まれ得るため、共有画面、公開ログ、PR artifact へ出さない。

```bash
umask 077
workdir="$(mktemp -d)"
terraform -chdir=infra/supabase/environments/staging plan -input=false -lock=true -out="$workdir/staging.tfplan"
```

**適用条件**: 対象 Project ref と resource アドレスが一致し、import だけが提案され、create/update/delete/replace が一件もなく、意図しない data source や output に secret が出ないこと。`terraform show "$workdir/staging.tfplan"` は機密を扱える作業者の画面でだけ確認する。条件を満たさない場合は apply せず、HCL と現物の差を調べて再 plan する。`-target` や自動承認で差分を隠さない。

レビュー担当者が同じ plan の対象・操作・state key を確認した後、保護された実行環境で次を実施する。この手順書の作成時点では未実施。

```bash
terraform -chdir=infra/supabase/environments/staging apply -input=false "$workdir/staging.tfplan"
terraform -chdir=infra/supabase/environments/staging state list
terraform -chdir=infra/supabase/environments/staging plan -refresh-only -input=false
terraform -chdir=infra/supabase/environments/staging plan -input=false
```

import 後に `supabase_project.existing` が一件だけ state にあり、refresh-only と通常 plan に予期しない差分がないことを確認する。差分が出た場合は、Dashboard と HCL のどちらを直すべきか判断するまで次の apply を止める。plan を保存したまま放置せず、組織の機密ファイル保持規則に従って破棄する。

## 7. 設定の管理を段階的に増やす

Project import が安定した後、別 PR で `supabase_settings` の一つの設定群だけを候補にする。[公式チュートリアル](https://supabase.com/docs/guides/deployment/terraform/tutorial)によると settings は指定フィールドの部分更新で、resource の作成/更新は既存 Project 設定への API 操作になる。**plan の `create` 表示を「新 Project 作成」と読み替えず、対象・操作を resource ごとに確認する。** Auth URL、OAuth、SMTP、API 設定などはユーザーのログインや Worker の接続に影響するので、先に現値、変更先、切戻し手順、staging の動作確認を記録する。API key や secret の Terraform 化はこの段階に含めない。

CI の PR チェックは現行どおり `fmt/init -backend=false/validate` のみ。remote plan を導入するなら、保護された Environment で読み取り権限を用い、結果は操作種別と件数だけ通知する。自動 apply は行わず、レビュー済み plan と同じ commit・同じ環境に対して明示的に実行する。production は staging の import と運用が安定し、別の棚卸しと承認が済んでから、production root と `supabase/production/terraform.tfstate` で同じ手順を行う。

## 異常時・復旧

| 状況 | 行動 |
| --- | --- |
| import plan に update/delete/replace がある | apply 停止。既存値、provider の必須属性、Project ref を再照合する |
| state が既に存在する、他作業と競合する | 操作停止。所有者と state の履歴を確認する。安易に上書きしない |
| import 後に drift が出る | 変更元を特定し、HCL 修正または別 plan の設定更新としてレビューする |
| state を誤操作した疑い | apply 停止。R2 の保護されたバックアップとアクセス記録を確保し、復旧計画をレビューする。`state rm` や state の直接編集を即席で行わない |
| Project 設定変更で障害が出る | 記録した前値へ新たな plan/apply または Supabase 管理者の手動復旧を行い、state との整合を再確認する |
| DB migration に問題が出る | Terraform state では直さず、前方修正 migration と DB 復旧手順を使う |

## 完了判定

- [ ] staging の Project ref・organization・region・名前と管理範囲を二人で確認した
- [ ] R2 state の bucket/key、閲覧権限、バックアップ、手動操作との排他を確認した
- [ ] import plan に対象一件の import 以外の操作がないことを確認した
- [ ] レビュー済み plan だけを apply し、state と二種類の plan を再確認した
- [ ] staging のログイン、Worker→Supabase、暇登録/取得/削除を実機または hosted 環境で確認した
- [ ] Dashboard と Terraform の所有境界、運用担当、drift 対応を記録した
- [ ] production への展開は staging の運用実績を見て別途判断した

## 参照

- [Supabase Terraform チュートリアル](https://supabase.com/docs/guides/deployment/terraform/tutorial)
- [Supabase provider リファレンス](https://supabase.com/docs/guides/deployment/terraform/reference)
- [Terraform import](https://developer.hashicorp.com/terraform/language/import)
- [Terraform の機密データと state](https://developer.hashicorp.com/terraform/language/manage-sensitive-data)

## 変更履歴

- 2026-09-25: 既存 Project の import と段階的な settings 管理を、実行条件・停止条件・事後確認まで具体化。実環境操作は未実施。
