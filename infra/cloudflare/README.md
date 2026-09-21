# Cloudflare Terraform

このディレクトリは、Cloudflare の長寿命インフラと Terraform state の境界だけを管理します。
Worker のscript、version、deployment、binding、Custom Domainは`apps/backend`のWranglerが所有し、同じCloudflare resourceをTerraformで重複管理しません。

## 環境と state

`environments/staging` と `environments/production` は独立した Terraform root です。
各 root は同じ provider 制約を持ちますが、`scripts/terraform/init-r2-backend.sh` が次の異なる key を選びます。

```text
cloudflare/staging/terraform.tfstate
cloudflare/production/terraform.tfstate
```

R2 bucket は Terraform root の外側で事前に bootstrap します。
各環境の GitHub Environment またはローカルの実行環境から、次の値を渡してください。

- `TF_STATE_BUCKET`: 事前作成済み R2 bucket 名
- `TF_STATE_ENDPOINT`: `https://<account-id>.r2.cloudflarestorage.com`
- `AWS_ACCESS_KEY_ID`: R2 API token の access key
- `AWS_SECRET_ACCESS_KEY`: R2 API token の secret key
- `CLOUDFLARE_API_TOKEN`: Cloudflare provider が読む API token
- `TF_VAR_cloudflare_account_id`: Cloudflare account ID（機密値ではない）

`init-r2-backend.sh` は root 名から環境を判定して state key を組み立てます。
backend config は `mktemp` で一時生成し、終了時に削除します。
credential は backend config や repository 内のファイルへ書き込みません。

## 排他と lockfile

Cloudflare R2 に対する Terraform S3 backend の native lockfile 互換性は、現時点では検証済みではありません。
そのため `use_lockfile` は有効化していません。
初期構成での排他は、GitHub Actions の環境別 `concurrency` を唯一の自動制御とします。
同じ state に対する手動 `terraform apply` は、該当 workflow の実行中に並行してはいけません。

将来 `use_lockfile` を有効化する場合は、実 R2 上で並行 plan/apply の排他、stale lock の回復、権限不足時の失敗を統合検証し、仕様と workflow を別変更として更新してください。

## 所有境界

- Terraform: 将来確定した長寿命Cloudflare resource、account/zone policy、remote state
- Wrangler: Workerのcode/version/deployment/binding、`api-staging.beyond-labo.com`と`api.beyond-labo.com`のCustom Domain
- Cloudflare: WranglerのCustom Domain作成に伴うDNSレコードとTLS証明書を自動作成
- 未決定のD1、KV、R2、Queue、WAFはこのscaffoldでは宣言しない

Custom Domainに対応するDNS、Workers Route、Custom Domain resource、TLS証明書をTerraformへ追加しません。

## ローカル検証

実 credential なしで、各 root を次のように検証できます。

```sh
terraform fmt -check -recursive infra/cloudflare
terraform -chdir=infra/cloudflare/environments/staging init -backend=false
terraform -chdir=infra/cloudflare/environments/staging validate
terraform -chdir=infra/cloudflare/environments/production init -backend=false
terraform -chdir=infra/cloudflare/environments/production validate
```

実 R2 state を使う init/apply は、必要な GitHub Environment またはローカル環境変数を設定した後にだけ実行してください。
state、plan、`.terraform`、secret を含む tfvars は commit や公開 artifact に含めません。

R2、Cloudflare API token、GitHub Environment、staging、productionの設定順は[Backend CI/CD運用手順](../../docs/operations/backend-ci-cd.md)を参照してください。
