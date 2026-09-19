# パッケージ構成

## 現在存在する構成

```text
free-time-matching/
├── apps/
│   ├── backend/
│   │   ├── README.md
│   │   └── package.json
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
├── scripts/
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
製品機能やインフラの空ディレクトリは Git に保持しません。
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
これらも実装時に作ります。

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
- IaC：選定後の `infra/`。
- 契約生成、互換性チェック、Backend CI とデプロイ：実行できる処理を実装してから追加。

iOS の Xcode project、XCTest、Simulator CI、TestFlight upload は実装済みです。
App Store review と公開の自動化は現在の配布境界に含めません。
AndroidのGradle project、JVM単体テスト、lint/debug build CI、Google Play internal track uploadは実装済みです。
Google Play production公開とstore listing更新は現在の配布境界に含めません。

`packages/contracts`、共有ドメイン型、共有 DB 型は作成しません。
