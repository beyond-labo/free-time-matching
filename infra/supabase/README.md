# Supabase Terraform の段階導入

このディレクトリは hosted Supabase の管理 API で扱える設定を Terraform に移すための、**宣言のみ**の土台です。staging / production は別 root と別 state を使います。現時点では管理対象 resource と import block はなく、`apply` しても既存 Project や Auth 設定を変更しません。

## 所有境界

| 対象 | 正本 |
| --- | --- |
| Project と Management API の設定、将来の Branch 等 | 対象を棚卸し・import した後の Terraform |
| DB schema、RLS、関数、migration | `supabase/migrations/` と Supabase CLI |
| Auth 利用者・セッション、アプリデータ | Supabase の稼働 DB。Terraform 管理対象外 |
| Worker、binding、Custom Domain | `apps/backend/wrangler.jsonc` と Wrangler |
| Worker 用 secret、Apple credential | GitHub Environment と Wrangler secret。Terraform に値を渡さない |

Supabase provider が扱える resource は Project、Settings、Branch、API key、Edge Function 等に限られます。API key や Edge Function secret は state に値が残り得るため、当面は Terraform へ取り込みません。既存の Project と Auth provider 設定は Dashboard 側の実態を確認してから、管理するフィールドだけを明示します。

## state と credential

Cloudflare R2 に既に用意した private な環境別 bucket を利用し、Cloudflare 用 state と異なる key `supabase/<environment>/terraform.tfstate` を使用します。R2 credential は当該環境の bucket だけを操作できるものに限定します。R2 側の排他ロック互換性は未検証のため、同一 state の plan/apply/import を並行実行しません。

Supabase provider は `SUPABASE_ACCESS_TOKEN` 環境変数から Management API token を受け取ります。設定ファイルや `*.tfvars` に token、DB password、service-role key を書きません。state と plan は機密として扱い、リポジトリや CI artifact に保存しません。実 credential を必要としない `fmt` と `init -backend=false`、`validate` のみを CI に追加します。

## 既存 Project を管理対象へ移す条件

1. staging と production の Project ID、組織、リージョン、Auth/Settings の管理対象フィールドを **値を伏せた棚卸し**としてレビューする。Project ID は state/plan に記録されるため公開ログへ出さない。
2. 対象を一つに絞り、既存 resource と同じ構成の `resource`、`import` block、`prevent_destroy` を用意する。最初は staging Project のみを候補とする。
3. 保護された実行環境で `plan` を取り、結果が `import` のみで `add/change/destroy` が 0 件であることを確認する。plan の原文と state は公開しない。
4. import 実行後の refresh-only plan と通常 plan を確認し、差異のあるフィールドを Terraform と Dashboard のどちらが所有するか決める。production へ広げる前に staging で運用する。
5. GitHub Environment ごとの read-only plan と承認付き apply を設ける。現在の Cloudflare CD に Supabase の空 root をそのまま追加して自動 apply しない。

Rollback は DB migration や Project の削除ではなく、該当設定の前値への再適用、または Terraform 所有からの除外を個別に計画する。`state rm` は実体を削除しないが state の管理関係を変えるため、承認された復旧手順でのみ実施する。

既存 Project を import する具体的な作業順は [Supabase Terraform 管理への移行手順](../../docs/operations/supabase-terraform-adoption.md)、全体の資産棚卸しと移行判断は [Terraform 導入計画](../../docs/operations/terraform-adoption.md) を参照してください。
