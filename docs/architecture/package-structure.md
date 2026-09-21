# パッケージ構成

## 現在存在する構成

```text
free-time-matching/
├── apps/
│   ├── backend/
│   │   ├── README.md
│   │   ├── package.json
│   │   ├── scripts/normalize-generated-types.mjs
│   │   ├── src/
│   │   │   ├── Composition/createApp.ts
│   │   │   ├── EntryPoint/index.ts
│   │   │   └── Health/Presentation/healthRoute.ts
│   │   ├── test/health.worker.test.ts
│   │   ├── tsconfig.json
│   │   ├── vitest.config.ts
│   │   ├── wrangler.jsonc
│   │   └── worker-configuration.d.ts
│   ├── ios/
│   │   ├── Himatch.xcodeproj/
│   │   ├── Himatch/
│   │   ├── HimatchTests/
│   │   └── README.md
│   └── android/
│       ├── app/
│       ├── gradle/wrapper/
│       ├── build.gradle.kts
│       └── settings.gradle.kts
├── docs/
│   ├── README.md
│   ├── product/
│   ├── architecture/
│   └── operations/
├── infra/
│   └── cloudflare/
│       ├── README.md
│       └── environments/
│           ├── staging/
│           └── production/
├── scripts/
│   ├── backend/smoke-health.mjs
│   ├── terraform/init-r2-backend.sh
│   ├── ios/
│   │   ├── test.sh
│   │   ├── release.sh
│   │   ├── validate_signing_assets.py
│   │   └── tests/
│   ├── android/
│   │   ├── test.sh
│   │   ├── release.sh
│   │   └── upload-play.mjs
│   └── verify.mjs
├── .github/workflows/
│   ├── ci-repository.yml
│   ├── ci-backend.yml
│   ├── cd-backend-staging.yml
│   ├── cd-backend-production.yml
│   ├── ci-ios.yml
│   ├── cd-ios-testflight.yml
│   ├── ci-android.yml
│   └── cd-android-play.yml
├── .gitignore
├── package.json
├── pnpm-lock.yaml
├── pnpm-workspace.yaml
└── README.md
```

既存の AGENTS.md と Kiro 設定は維持します。
Backendはprivate workspaceとして登録し、iOSとAndroidはNode packageにしません。
現在の iOS project は CI/CD の実経路を持つ最小アプリです。
配布前検査は `validate_signing_assets.py` と実 crypto fixture test に分離し、実 Apple 資格情報を使わず回帰確認できます。
製品機能の空ディレクトリはGitに保持しません。
`infra/cloudflare`は環境別stateと所有境界を実装したTerraform rootで、未決定resourceの置き場所として空ディレクトリを先行生成するものではありません。
現在のAndroid projectもCI/CDの実経路を持つ最小アプリです。

## 実装時の配置規則

Backendは`src/<Feature>/<Layer>/`、iOSは`Himatch/<Feature>/<Layer>/`、Androidは`app/src/main/java/<package>/<feature>/<layer>/`とします。
機能を束ねる中間ディレクトリは設けません。
BackendとiOSの機能、層、役割のpackage名はPascalCase（UpperCamelCase）、AndroidのJava/Kotlin package名はlowercaseに統一します。
役割名は `UseCase`、`Port`、`Mapper` のように単数形にします。
`apps/backend`、`apps/ios`、`apps/android`、`src`、`docs`などの配置用ディレクトリと、pnpmのpackage識別子`@himatch/backend`はこの規則の対象外です。
必要な役割だけを層の下に置き、以下の例を一括生成しません。

### Backend の例

```text
src/Hosting/
├── Domain/
│   └── Model/
├── Application/
│   ├── UseCase/
│   └── Port/
├── Presentation/
│   ├── Handler/
│   ├── Schema/
│   └── Mapper/
└── Infrastructure/
    └── Repository/
```

受信 HTTP の Handler と公開 DTO の変換は Presentation の責務です。
HTTP ごとの追加階層は、複数の通信方式を区別する必要が出てから検討します。
アプリ全体の起動と組み立ては `EntryPoint/` と `Composition/` が所有します。
Backend の最小 Worker では `EntryPoint/index.ts` が module export、`Composition/createApp.ts` が Hono と route の登録、`Health/Presentation/healthRoute.ts` が health 応答を所有します。
Cloudflare 型の生成物 `worker-configuration.d.ts` は Wrangler 設定から生成し、追跡対象にします。

### iOS の例

```text
Himatch/Hosting/
├── Domain/
│   └── Model/
├── Application/
│   ├── UseCase/
│   └── Port/
├── Presentation/
│   ├── View/
│   │   └── HostingView.swift
│   ├── Reducer/
│   │   └── HostingReducer.swift    # State と Action を同居させる
│   └── Dependency/
│       └── HostingUseCasesDependency.swift
└── Infrastructure/
    ├── Adapter/
    │   └── HostingAPIAdapter.swift
    └── Mapper/
        └── HostingAPIMapper.swift
```

App の Composition が依存を組み立てます。
共有の生成クライアントが必要なら `Himatch/Platform/Networking/Generated/` に配置します。
Platform は機能のモデルを参照しません。
`App` と `Platform` は機能名に使用しません。
TCA の Store を囲う ViewModel は作成しません。

## 将来作成する成果物

- Backend の公開契約：`apps/backend/openapi/openapi.yaml`。
- IaC resource：要件が確定した長寿命Cloudflare resourceだけを`infra/cloudflare`へ追加。
- 契約生成と互換性チェック：OpenAPI公開契約の仕様決定後に追加。

Backend CI、Terraform環境scaffold、staging/production deploy workflowは実装済みです。
実apply/deployはCloudflare/R2/GitHub Environmentの外部bootstrap後に実行します。

iOS の Xcode project、XCTest、Simulator CI、TestFlight upload は実装済みです。
App Store review と公開の自動化は現在の配布境界に含めません。
AndroidのGradle project、JVM単体テスト、lint/debug build CI、Google Play internal track uploadは実装済みです。
Google Play production公開とstore listing更新は現在の配布境界に含めません。

`packages/contracts`、共有ドメイン型、共有 DB 型は作成しません。
