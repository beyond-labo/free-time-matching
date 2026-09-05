# パッケージ構成

添付のディレクトリ構成を基に、機能名をソースルート直下へ配置します。
Backend は `src/<feature>/<layer>/`、iOS は `Himatch/<Feature>/<Layer>/` を基本とし、機能を束ねる中間ディレクトリは設けません。
Node workspace のパッケージは `apps/backend` のみです。
iOS は pnpm のパッケージにせず、独立した Xcode アプリとして管理します。
`infra` はインフラ、`tooling` は開発用ツール、`scripts` はルートからの操作を所有します。

## ディレクトリ

```text
free-time-matching/
├── apps/
│   ├── backend/
│   │   ├── src/
│   │   │   ├── entrypoints/
│   │   │   │   ├── http.ts
│   │   │   │   ├── authorizer.ts
│   │   │   │   ├── outbox-dispatcher.ts
│   │   │   │   └── notification-worker.ts
│   │   │   ├── auth/
│   │   │   ├── users/
│   │   │   ├── friendships/
│   │   │   ├── availability/
│   │   │   ├── hostings/
│   │   │   ├── notifications/
│   │   │   ├── account-deletion/
│   │   │   ├── interfaces/http/
│   │   │   │   ├── routes/
│   │   │   │   ├── schemas/
│   │   │   │   ├── presenters/
│   │   │   │   └── errors/
│   │   │   ├── infrastructure/
│   │   │   │   ├── database/
│   │   │   │   ├── messaging/
│   │   │   │   ├── notifications/
│   │   │   │   └── observability/
│   │   │   └── app.ts
│   │   ├── openapi/
│   │   │   ├── openapi.yaml
│   │   │   ├── examples/
│   │   │   │   ├── authentication/
│   │   │   │   ├── availability/
│   │   │   │   └── hostings/
│   │   │   └── README.md
│   │   ├── scripts/export-openapi.ts
│   │   ├── test/
│   │   │   ├── unit/
│   │   │   ├── integration/
│   │   │   └── contract/
│   │   ├── package.json
│   │   └── tsconfig.json
│   └── ios/
│       ├── Himatch/
│       │   ├── App/
│       │   ├── Core/API/
│       │   │   ├── APIClient.swift
│       │   │   ├── APIConfiguration.swift
│       │   │   ├── Mappers/
│       │   │   └── Generated/
│       │   └── Resources/
│       ├── Config/openapi-generator-config.yaml
│       ├── Scripts/generate-api-client.sh
│       ├── HimatchTests/
│       └── Himatch.xcodeproj/      # 予約位置。Xcode プロジェクトは未作成
├── infra/
│   ├── bootstrap/
│   ├── modules/
│   └── environments/
├── docs/
│   ├── README.md
│   ├── product/
│   ├── architecture/
│   └── operations/
├── tooling/openapi/
│   ├── lint-config.yaml
│   └── check-breaking-change.sh
├── scripts/
│   ├── bootstrap.sh
│   ├── verify.sh
│   └── verify.mjs
├── .github/workflows/
│   ├── ci-backend.yml
│   ├── ci-ios.yml
│   ├── openapi-contract.yml
│   └── deploy.yml
├── .gitignore
├── Makefile
├── pnpm-workspace.yaml
├── pnpm-lock.yaml
├── package.json
└── README.md
```

既存の開発ルールと Kiro 設定は維持しています。
各 Backend 機能には `domain/`、`application/`、`infrastructure/` の空の配置を用意しています。
機能の詳細な役割ディレクトリは、仕様が決まってから責務に合わせて追加します。
iOS の具体的な機能ディレクトリは、画面と UseCase が決まってから `Himatch/` 直下に作成します。

## 命名規則

Backend のディレクトリは小文字の kebab-case、iOS のディレクトリは PascalCase とします。
機能の中に層を置き、その層で必要になった責務だけを追加します。
例は `src/availability/application/` と `Himatch/Availability/Application/` です。
`entrypoints`、`interfaces`、`infrastructure`、`App`、`Core`、`Resources` は技術的な責務を持つ予約名として、機能名に使用しません。

## 配置ごとの責務

| 配置 | 所有するもの | 所有しないもの |
| --- | --- | --- |
| `src/<feature>/domain` | 業務モデルと規則 | HTTP、DB SDK |
| `src/<feature>/application` | UseCase と Port | HTTP DTO、具体的な外部接続 |
| `src/<feature>/infrastructure` | 機能固有の Repository と Adapter | 他機能の内部実装 |
| `interfaces/http` | リクエスト検証、ルート、公開レスポンス変換、エラー表現 | 永続化レコード |
| `infrastructure` | 技術基盤の接続と可観測性 | 共有ドメインモデル |
| `entrypoints` | 実行環境との接続 | 業務規則 |
| `app.ts` | 依存の組み立て | 業務規則 |
| `openapi` | Backend の公開契約と例 | Backend 内部型の公開 |
| `Himatch/<Feature>` | iOS の機能と内部モデル | Backend の型 |
| `Himatch/Core/API` | 通信、生成クライアント、Mapper | 画面状態と UI ロジック |
| `Himatch/App` | 起動と依存の組み立て | 各機能の業務規則 |
| `infra/bootstrap` | IaC 実行に必要な初期基盤 | 業務コード |
| `infra/modules` | 再利用するインフラ定義 | アプリの DTO |
| `infra/environments` | 環境ごとのインフラ構成 | 認証情報の平文保存 |

## 作成範囲

今回は配置、文書、依存のない workspace 設定、構成検証を作成しました。
エントリーポイントは空の TypeScript モジュールです。
Swift ファイル、OpenAPI、生成ツール設定、Xcode の配置は未実装と分かる予約ファイルです。
添付内の `availability.ts` などの具体例は、業務実装を示す例として扱い、空の業務型を量産しません。

`scripts/verify.mjs` は今回の構成確認用に追加したファイルです。
`packages/contracts` と、将来候補の別 Backend や公開イベントスキーマは作成しません。
