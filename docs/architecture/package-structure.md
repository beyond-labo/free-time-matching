# パッケージ構成

## 現在存在する構成

```text
free-time-matching/
├── apps/
│   ├── backend/
│   │   ├── README.md
│   │   └── package.json
│   └── ios/
│       └── README.md
├── docs/
│   ├── README.md
│   ├── product/
│   ├── architecture/
│   └── operations/
├── scripts/
│   └── verify.mjs
├── .github/workflows/
│   └── ci-repository.yml
├── .gitignore
├── package.json
├── pnpm-lock.yaml
├── pnpm-workspace.yaml
└── README.md
```

既存の AGENTS.md と Kiro 設定は維持します。
Backend は private workspace として登録し、iOS は Node パッケージにしません。
アプリやインフラの空ディレクトリは Git に保持しません。

## 実装時の配置規則

Backend は `src/<feature>/<layer>/`、iOS は `Himatch/<Feature>/<Layer>/` とします。
機能を束ねる中間ディレクトリは設けません。
Backend は kebab-case、iOS は PascalCase を使います。
必要な役割だけを層の下に置き、以下の例を一括生成しません。

### Backend の例

```text
src/hostings/
├── domain/
│   └── models/
├── application/
│   ├── use-cases/
│   └── ports/
├── presentation/
│   ├── handlers/
│   ├── schemas/
│   └── mappers/
└── infrastructure/
    └── repositories/
```

受信 HTTP の Handler と公開 DTO の変換は Presentation の責務です。
HTTP ごとの追加階層は、複数の通信方式を区別する必要が出てから検討します。
アプリ全体の起動と組み立ては `entrypoints/` と `composition/` が所有します。
これらも実装時に作ります。

### iOS の例

```text
Himatch/Hosting/
├── Domain/
│   └── Models/
├── Application/
│   ├── UseCases/
│   └── Ports/
├── Presentation/
│   ├── Views/
│   │   └── HostingView.swift
│   ├── Reducers/
│   │   └── HostingReducer.swift    # State と Action を同居させる
│   └── Dependencies/
│       └── HostingUseCasesDependency.swift
└── Infrastructure/
    ├── Adapters/
    │   └── HostingAPIAdapter.swift
    └── Mappers/
        └── HostingAPIMapper.swift
```

App の Composition が依存を組み立てます。
共有の生成クライアントが必要なら `Himatch/Platform/Networking/Generated/` に配置します。
Platform は機能のモデルを参照しません。
`App` と `Platform` は機能名に使用しません。
TCA の Store を囲う ViewModel は作成しません。

## 将来作成する成果物

- Backend の公開契約：`apps/backend/openapi/openapi.yaml`。
- iOS のプロジェクトとテスト：`apps/ios/Himatch.xcodeproj` と `HimatchTests/`。
- IaC：選定後の `infra/`。
- 契約生成、互換性チェック、アプリ CI、デプロイ：実行できる処理を実装してから追加。

`packages/contracts`、共有ドメイン型、共有 DB 型は作成しません。
