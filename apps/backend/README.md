# Backend

TypeScript/Hono の Cloudflare Workers を独立した private workspace として管理します。
最初の公開契約は、固定 JSON を返す `GET /healthz` です。

## 開発コマンド

リポジトリルートで依存を解決してから、Backend の package script を実行します。

```sh
pnpm install --frozen-lockfile
pnpm --dir apps/backend types
pnpm --dir apps/backend typecheck
pnpm --dir apps/backend test
pnpm --dir apps/backend build
```

`pnpm --dir apps/backend dev` は Wrangler のローカル開発サーバーを起動します。
`types` は Wrangler が生成する `worker-configuration.d.ts` を更新します。
`build` は `wrangler deploy --dry-run --outdir dist` の bundle 検査であり、Cloudflare へ deploy しません。

`wrangler.jsonc` の `staging` と `production` は別のWorker名を持ちます。
secretは`vars`へ書かず、CloudflareとGitHub Environmentで環境別に管理します。
配布後のhealth確認は次のコマンドで実行できます。

```sh
BACKEND_HEALTH_URL=https://api-staging.beyond-labo.com node scripts/backend/smoke-health.mjs
```

stagingは`api-staging.beyond-labo.com`、productionは`api.beyond-labo.com`をCustom Domainとして使います。
`wrangler.jsonc`がCustom Domainと`workers_dev: false`を管理し、smokeは初回のDNS/TLS反映待ちを有限回再試行します。

Cloudflareへの配布経路、必要なvariables/secrets、rollbackは[Backend CI/CD運用手順](../../docs/operations/backend-ci-cd.md)を参照してください。

## 現在の範囲

- 実装済み: Workers module entrypoint、Hono の route composition、`GET /healthz`、Workers Runtime 契約テスト、secretless Backend CI、Terraform環境scaffold、環境別Custom Domain、staging/production配布workflow。
- 外部bootstrap後に実行可能: R2 remote state、staging自動deploy、production承認deploy。
- 未実装（後続範囲）: 実Cloudflare resource、OpenAPI生成、認証、DB、業務API。

[技術方針](../../docs/architecture/technology.md)と[配置規則](../../docs/architecture/package-structure.md)に従い、機能が増えたときだけ Domain / Application / Infrastructure を追加します。
