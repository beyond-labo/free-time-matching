# Backend

TypeScript/Hono の Cloudflare Workers を独立した private workspace として管理します。
公開ヘルス契約に加え、Supabase Auth のアクセストークンで保護した本人プロフィールとアカウント削除 API を提供します。

## 認証とAPI

iOS は Sign in with Apple の identity token と nonce を Supabase Auth へ渡してセッションを取得します。
Backend は `Authorization: Bearer <Supabase access token>` を Supabase の JWKS で検証し、`iss`、`aud`、`role`、`sub` を確認します。
通常のDB操作では publishable key と利用者自身の access token だけを使い、Postgres RLSを迂回しません。

- `GET /v1/me`: `{ userId, profile: null | { nickname, presetIconKey } }`
- `PUT /v1/me`: `{ nickname, presetIconKey }` を保存する
- `POST /v1/account-deletion-requests`: `Idempotency-Key` と fresh Apple authorization code でApple認可失効とアカウント削除を同期実行する
- `GET /v1/account-deletion-requests/:reference`: `Authorization: Deletion <statusToken>` で削除結果を取得する

ニックネームはtrim後1〜20 grapheme、アイコンは `sun.max.fill`、`leaf.fill`、`gamecontroller.fill`、`figure.run` のいずれかです。
削除受付後はプロフィールを含む通常アクセスをWorkerとRLSの両方で拒否します。

DB migrationとRLSはリポジトリルートの `supabase/migrations/`、pgTAP検査は `supabase/tests/` にあります。
Pull Requestでは一時Postgresへmigrationを初期適用し、staging／production CDではWorkerより先に未適用migrationを反映します。

## Worker bindings

環境ごとに次の値をCloudflareへ設定します。実値はリポジトリへ保存しません。

| 区分 | 名前 | 用途 |
| --- | --- | --- |
| Variable | `SUPABASE_URL` | Supabase project URL |
| Variable | `SUPABASE_PUBLISHABLE_KEY` | 通常のAuth/Data API呼出し |
| Variable | `APPLE_CLIENT_ID` | native App ID / token audience |
| Secret | `SUPABASE_SECRET_KEY` | 削除用adapterだけが使用するAuth Admin資格情報 |
| Secret | `APPLE_TEAM_ID` | Apple client secretのissuer |
| Secret | `APPLE_KEY_ID` | Apple client secretのkey id |
| Secret | `APPLE_PRIVATE_KEY` | Apple client secret署名鍵 |
| Secret | `ACCOUNT_DELETION_STATUS_SECRET` | status tokenの決定的HMAC（32文字以上） |

`SUPABASE_SECRET_KEY` は通常のプロフィールRepositoryやJWT検証へ注入しません。
JWT issuerとJWKS URLは`SUPABASE_URL`の同一origin・固定pathから導出し、任意の鍵サーバーへ差し替えられないようにします。
Apple credentialとのsubject一致を確認した後だけ、削除adapterがApple tokenをrevokeし、Supabase Auth userをhard deleteします。
削除状態はAuth userへの外部キーを持たない最小tombstoneとして残り、公開status関数は生のstatus token hashを返しません。

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
secretは`vars`へ書かず、GitHub Environmentで環境別に管理します。
CDは公開Variableを`--var`、secretをephemeral runner上の`--secrets-file`として同じWorker versionへ渡します。
配布後のhealth確認は次のコマンドで実行できます。

```sh
BACKEND_HEALTH_URL=https://api-staging.beyond-labo.com node scripts/backend/smoke-health.mjs
```

stagingは`api-staging.beyond-labo.com`、productionは`api.beyond-labo.com`をCustom Domainとして使います。
`wrangler.jsonc`がCustom Domainと`workers_dev: false`を管理し、smokeは初回のDNS/TLS反映待ちを有限回再試行します。

Cloudflareへの配布経路、必要なvariables/secrets、rollbackは[Backend CI/CD運用手順](../../docs/operations/backend-ci-cd.md)、Supabase Projectとmigration運用は[Supabase Auth・Database CI/CD](../../docs/operations/supabase-auth.md)を参照してください。

## 現在の範囲

- 実装済み: Workers module entrypoint、Hono の route composition、`GET /healthz`、Workers Runtime 契約テスト、secretless Backend／Supabase CI、Terraform環境scaffold、環境別Custom Domain、DB migrationを先行するstaging/production配布workflow。
- 外部bootstrap後に実行可能: R2 remote state、staging自動deploy、production承認deploy。
- 実装済み（認証・ユーザー最小範囲）: Supabase JWT検証、本人プロフィール、RLS migration、Apple再認証を伴う同期アカウント削除、opaque tokenによる削除状況照会。
- 実装済み: JWT認証、本人プロフィール、友達コード・申請・相互承認・解除、アカウント削除受付。
- 未実装（後続範囲）: OpenAPI生成、暇・募集等の業務API、非同期削除Queue、実Cloudflare/Supabase resourceのbootstrap。

[技術方針](../../docs/architecture/technology.md)と[配置規則](../../docs/architecture/package-structure.md)に従い、機能が増えたときだけ Domain / Application / Infrastructure を追加します。
