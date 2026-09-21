# 技術方針

## アプリケーション境界

iOS、Android、Backendは独立してビルド、リリース、更新します。
同じ PR で変更できても同時リリースを必須にしません。
Backend の内部型を共有せず、Backend 所有の OpenAPI を公開契約として利用します。
ドメインモデルは各アプリケーションが所有します。

## 採用方針と現在の状態

| 項目 | 方針 | 現在の状態 |
| --- | --- | --- |
| Backend | TypeScript、Hono、Cloudflare Workers、Clean Architecture | `apps/backend` に最小Worker、`GET /healthz`、Workers Runtimeテスト、staging/production配布設定を導入。実deployは外部bootstrap待ち |
| iOS | Swift 6、SwiftUI、最低 iOS 17。TCA＋Clean Architecture。テストは Swift Testing | TCA 1.26.1 と初版プロトタイプを導入。iOS テストでは XCTest を使用しない |
| Android | AGP 9.4.0、AGP内蔵Kotlin 2.2.10、Jetpack Compose、最低API 26。Clean Architecture | CI/CD用の最小アプリとJVM単体テストを導入。製品機能は未導入 |
| パッケージ管理 | Backend はpnpm、iOSはSwift Package Manager、AndroidはGradle Wrapper | AndroidはGradle 9.6.0とCompose BOM 2026.08.00を固定 |
| API | Backend の HTTP スキーマから OpenAPI を生成 | 未実装 |
| 利用側 | 固定した契約からクライアントを生成 | 生成ツールは未選定 |
| DB | DynamoDB を想定した例が提示されている | 採用とキー設計は未確定 |
| 非同期処理 | Outbox、SQS、通知 Worker を想定 | 実行基盤と配信保証は未設計 |
| IaC | Terraform、Cloudflare provider、R2 remote state | staging/production別rootとpartial backendを導入。未決定のCloudflare resourceは未宣言 |
| CI/CD | GitHub Actions | iOS/AndroidのCI/CDに加え、Backend secretless CI、staging自動配布、production承認配布workflowを導入 |

Backend は Hono と Cloudflare Workers Vitest plugin を導入し、依存バージョンを `apps/backend/package.json` と `pnpm-lock.yaml` に固定します。
HTTP スキーマライブラリ、生成ツール、OpenAPI 公開は後続仕様で決めます。
Workerのscript/version/deployment/bindingとCustom DomainはWrangler、将来の長寿命resourceとaccount/zone policyはTerraformを唯一の所有者とし、同じresourceを二重管理しません。
`api-staging.beyond-labo.com`と`api.beyond-labo.com`に対応するDNS、Workers Route、Custom Domain、TLS証明書はTerraformへ重複定義しません。
初期Terraform scaffoldはstateと所有境界だけを確定し、D1/KV/R2/Queue/DNS/WAFを推測して作成しません。
TCA の採用方針と具体的なリリースバージョンの選定を分けます。
最低 iOS 17、Xcode 26.6、Swift 6 を現在の build 境界とし、TCA 1.26.1 を Swift Package Manager で固定します。
提示されたエントリーポイント名だけで Lambda や API Gateway の採用を確定しません。

## 層名と役割名

層名は Backend と iOS ともに `Domain / Application / Presentation / Infrastructure` とします。
依存の組み立ては `Composition` またはアプリ起動部分が所有します。

| 名前 | 意味 | 使用方針 |
| --- | --- | --- |
| Presentation | 外部入力と出力をアプリケーションへ接続する層 | Backend の受信 HTTP と iOS の UI |
| Application | ユースケースと必要な外部操作の契約 | UI、HTTP、具体的 SDK に依存しない |
| Domain | 業務モデルと不変条件 | 外部の通信や UI を知らない |
| Infrastructure | 外部接続の実装 | API、DB、ストレージの Adapter |
| Port | 内側の呼び出し側が定義する操作の契約 | 通常は Application の役割 |
| Gateway | 外部サービスとの接続を表す役割 | 必要なら具体的な接続コンポーネント名に使う |
| HTTP | 通信方式 | 層名として使わない |

`Gateway` は層名にすると受信 API と外部 API 呼び出しが混在しやすく、`Port` は契約と実装の区別を失います。
このプロジェクトでは層名を上表に統一し、クラスや役割名に `Handler`、`Repository`、`Adapter`、`Mapper` を使います。
`Presentation/HTTP/` も「層／通信方式」としては成立しますが、HTTP しか扱わない初期段階では不要です。

## Backend の配置と依存

```text
Presentation → Application → Domain
Infrastructure → Application / Domain の Port
Composition → 各実装を接続
```

受信 HTTP は各機能の `src/<Feature>/Presentation/` に置きます。
ルート、Handler、公開スキーマ、レスポンス変換を機能内で所有します。
全体の起動処理は機能のルート登録を組み立てるだけにし、業務判断を持ちません。
HTTP が必要な最初の機能を実装するときにディレクトリを作成します。

外部 API や DB への接続は `src/<Feature>/Infrastructure/` に置きます。
複数機能で実際に利用する通信基盤のみ、全体の技術基盤へ抽出します。
Domain と Application は HTTP スキーマ、DB レコード、外部 SDK を import しません。

Clean Architecture の依存規則と、境界を越えるデータを内側に適した形式へ変換する考え方を適用しています。
層名と配置の具体形は、このプロジェクトの決定です。
[原典](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)

## iOS

[iOS の設計](ios-architecture.md)に、TCA と MVVM の対応、DTO 変換、依存注入、テスト方針を定めます。
TCA の State と Reducer は Presentation に置き、Domain と Application から TCA を参照しません。

## Android

[Androidの設計](android-architecture.md)に、Composeと機能配置、依存方向、テスト境界を定めます。
Gradle/CIはLTSのJDK 21で実行し、Android向けJava/Kotlin bytecodeは17に固定します。compileSdk 37とtargetSdk 36を分離し、ライブラリのcompile要件とGoogle Playのruntime behavior opt-inを混同しません。

## 過剰な共通化を避ける

`packages/contracts`、共有ドメイン型、共有 DB 型は作成しません。
層ごとに同じ形の DTO を機械的に複製せず、外部契約や UI 都合が境界を越える場合に変換します。
機能も層も、実装する責務が生じてから作ります。
