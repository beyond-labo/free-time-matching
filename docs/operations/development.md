# 開発手順

## 現在の検証

Node.js を用意して、リポジトリルートで実行します。

```sh
node scripts/verify.mjs
```

JSON、workspaceの登録、ローカル文書リンク、iOS/Android/Backend CI/CD構成、BackendとTerraformの必須ファイル、credential非公開契約を確認します。

## Supabase Databaseの検証

DockerとSupabase CLI 2.117.0を用意し、リポジトリルートで実行します。

```sh
npx -y supabase@2.117.0 db start
npx -y supabase@2.117.0 db lint --local --schema public --level error --fail-on error
npx -y supabase@2.117.0 test db --local
npx -y supabase@2.117.0 stop --no-backup
```

`db start`は空のローカルPostgresへ`supabase/migrations/`を順番に適用します。
外部Projectの資格情報は使いません。
schema変更は新しいmigrationとして追加し、適用済みmigrationを編集しません。
環境設定と配備順序は[Supabase Auth・Database CI/CD](supabase-auth.md)に従います。

## Backend の build と test

Node.js と pnpm を用意し、リポジトリルートで実行します。

```sh
pnpm install --frozen-lockfile
pnpm --dir apps/backend types
pnpm --dir apps/backend typecheck
pnpm --dir apps/backend test
pnpm --dir apps/backend build
```

`types` は Wrangler が `apps/backend/worker-configuration.d.ts` を生成します。
`test` は Cloudflare Workers Runtime 相当で `GET /healthz` の status、JSON content type、固定 payload、内部情報非公開、未定義 route の 404 を確認します。
`build` は `wrangler deploy --dry-run --outdir dist` の bundle 検査で、実 Cloudflare deploy は行いません。

Backend の現在の実装範囲はhealth、Supabase JWT検証、本人プロフィール、アカウント削除です。
Terraform環境scaffoldとGitHub Actions CI/CDは実装済みですが、実apply/deployにはR2 bucket、Cloudflare token、GitHub Environmentの外部bootstrapが必要です。
OpenAPI生成、友達・暇・募集の業務APIは後続仕様です。

## Cloudflare Terraform のローカル検証

Terraform 1.15.1を用意し、資格情報なしで各rootを検証します。

```sh
terraform fmt -check -recursive infra/cloudflare
terraform -chdir=infra/cloudflare/environments/staging init -backend=false
terraform -chdir=infra/cloudflare/environments/staging validate
terraform -chdir=infra/cloudflare/environments/production init -backend=false
terraform -chdir=infra/cloudflare/environments/production validate
```

remote stateの初期化、Environment variables/secrets、実行順序は[Cloudflare infra](../../infra/cloudflare/README.md)と[Backend CI/CD運用手順](backend-ci-cd.md)を参照してください。

## iOS の build と test

Xcode 26.6、利用可能な iPhone Simulator、Python 3.9 以上、OpenSSL 3.4 以上を用意し、リポジトリルートで実行します。
CI の `macos-26` image では Python 3.14 系と OpenSSL 3.6 系を使用し、各 version は test log に出力されます。

```sh
bash scripts/ios/test.sh
```

スクリプトは最初に期限切れ、証明書・秘密鍵・profile の不一致、壊れた key、RSA/P-384 API key を扱う signing preflight の実 crypto fixture test を実行します。
続いて `apps/ios/Himatch.xcodeproj` の shared scheme `Himatch` を使い、署名なしで app と `HimatchTests` を build/test します。
最低 iOS は 17.0、Swift language mode は 6.0 です。
CI と App Store upload の build 環境は Xcode 26.6 に固定します。

## Backend の実装開始

1. 承認済み仕様と HTTP 実行基盤、テストツールを確認する。
2. `apps/backend/package.json` と lockfile の固定依存を使い、`pnpm install --frozen-lockfile` を実行する。
3. 機能に必要な層だけを作成し、`EntryPoint` と `Composition` で route を登録する。
4. `pnpm --dir apps/backend typecheck`、`test`、`build` を実行する。
5. OpenAPI、認証、DBなどの公開契約や永続resourceは、対応仕様と承認ができてから追加する。

## iOS の実装開始

1. TCA の Xcode 26.6 / Swift 6 / iOS 17 対応バージョンを確認する。
2. Swift Package Manager で固定した TCA 依存を導入し、解決結果を管理する。
3. 最初の機能の View、Reducer、State、Action を実装する。
4. Application の UseCase と Port、Infrastructure の Adapter を実装する。
5. 生成ツールと入力契約を固定し、DTO の変換を機能内へ閉じ込める。
6. Composition で依存を注入し、TestStore と Simulator で検証する。

TCA 1.26.1とsupabase-swiftの解決結果を固定し、認証・プロフィール・削除のProduction Compositionを検証します。

### iOSのローカル構成値

各開発者は、初回セットアップ時にリポジトリルートで次を実行します。

```sh
cp apps/ios/Config/Local.xcconfig.example apps/ios/Config/Local.xcconfig
```

コピー後の`Local.xcconfig`で、次の3項目を使用するstaging環境の値へ置き換えます。

```text
SUPABASE_URL = https:/$()/your-staging-project-ref.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_replace_me
API_BASE_URL = https:/$()/your-staging-api.example.com
```

`Debug.xcconfig`がこのファイルを任意読込し、`Config/Himatch-Info.plist`のbuild setting参照へ値を渡します。
`Local.xcconfig`はGit管理外であり、stagingの値や環境固有値をコミットしません。
xcconfigでは`//`がコメントとして扱われるため、URLは`https:/$()/example.com`形式で記述します。
`SUPABASE_SECRET_KEY`、`SUPABASE_DB_PASSWORD`、`SUPABASE_ACCESS_TOKEN`、`APPLE_PRIVATE_KEY`などのserver secretは設定しません。
設定後にXcodeで`File`、`Packages`、`Resolve Package Versions`の順に選び、`Himatch` schemeをDebug構成で実行します。
対応するWorker variables/secretsは別途必要です。
外部設定とstaging確認は[Supabase Auth・Database CI/CD](supabase-auth.md)に従います。

## Androidのbuildとtest

JDK 21、Android SDK Platform 37、Build Tools 36.0.0を用意し、リポジトリルートで実行します。

```sh
bash scripts/android/test.sh
```

Gradle Wrapper 9.6.0がlint、JVM単体テスト、debug APK buildを実行します。
AGPは9.4.0、AGP内蔵Kotlinは2.2.10、Compose BOMは2026.08.00、minSdkは26、compileSdkは37、targetSdkは36です。
JDK 21はbuild runtime/toolchainで、Android向けJava/Kotlin bytecode targetは17です。

## Androidの実装開始

1. 最初の製品機能の要件と状態管理方針を確定する。
2. 機能に必要なDomain、Application、Presentation、Infrastructureだけを作成する。
3. Compose UIからApplicationのuse caseへ接続し、DomainからAndroid/Composeを参照しない。
4. Backend公開契約と生成toolを固定し、外部DTOの変換を機能内へ閉じ込める。
5. JVM単体テストを基本にし、実際のUI受け入れ条件が生じたらCompose/端末testを追加する。

現在のCompose画面とlauncher iconはCI/CD経路を検証する最小成果物で、製品機能ではありません。
