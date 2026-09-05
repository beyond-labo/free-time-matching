# 技術方針

## アプリケーション境界

iOS と Backend は、独立してビルド、リリース、更新できるアプリケーションです。
同じ PR で双方を変更できても、同時リリースを必須にしません。
ドメインモデルは各アプリケーションが所有します。

Backend の TypeScript 型や HTTP スキーマを、iOS や別 Backend に直接 import させません。
API 契約の共有には Backend 所有の OpenAPI を使用します。
`packages/contracts` は作成しません。

## 技術の採用方針と決定状況

| 項目 | 方針 | 今回の状態 |
| --- | --- | --- |
| リポジトリ | モノレポ | 既存リポジトリを使用 |
| Backend | TypeScript | パッケージと strict な設定の土台のみ |
| Node パッケージ管理 | pnpm workspace | Backend のみを登録 |
| iOS | Swift / SwiftUI | ソース配置の土台のみ |
| API 契約 | Backend の HTTP スキーマから OpenAPI を生成 | 契約置き場のみ |
| API 利用側 | OpenAPI から言語別クライアントを生成 | 生成ツールは未選定 |
| 永続化 | DynamoDB を想定した設計例 | 採用確定、キー設計、SDK 導入は未実施 |
| 非同期処理 | Outbox、SQS、通知 Worker を想定 | 配置のみ。配信保証は未設計 |
| HTTP 実行環境 | HTTP と Authorizer のエントリーポイントを分離 | フレームワークと実行サービスは未選定 |
| IaC | `infra/` で管理 | Terraform / CDK 等は未選定 |
| CI/CD | GitHub Actions の責務を分割 | 構成検証のみ実行可能 |

エントリーポイント名から AWS Lambda や API Gateway の採用を確定しません。
添付の DynamoDB、SQS、EventBridge への言及も、利用範囲と実行基盤を選定する材料として扱います。
EventBridge は将来の別 Backend とのイベント連携例であり、初期依存に追加しません。

HTTP フレームワーク、HTTP スキーマライブラリ、テストツール、OpenAPI のバージョンと生成ツール、Node.js / pnpm / TypeScript のバージョンは未選定です。
ローカルにインストールされているバージョンを、そのまま採用バージョンにはしません。

## Backend の依存方向

```text
HTTP Route → Application Use Case → Domain
Infrastructure → Domain / Application が定義する Port
app.ts / entrypoints → 各実装を組み立てる
```

Domain は HTTP、OpenAPI、DynamoDB、外部 SDK を知りません。
Application は業務の手順を調整し、具体的な DB や通知サービスを直接生成しません。
永続化レコードは Repository で内部モデルに変換し、公開レスポンスは Presenter で変換します。
他機能の Infrastructure や HTTP 実装を直接参照せず、公開された Application の契約を通します。

HTTP は `interfaces/http/` にまとめ、機能固有の Domain と Application は `src/<feature>/` に置きます。
全体の `infrastructure/` は DB 接続、メッセージング、通知接続、可観測性などの技術基盤を所有します。
機能固有の Repository は `src/<feature>/infrastructure/` に置きます。
一般的な機能単位の配置に対する例外として、HTTP とアプリ組み立ての位置を添付どおり維持します。

## iOS の依存方向

```text
View → ViewModel → UseCase → Port
API Adapter → Port を実装
Generated DTO → Mapper → iOS 内部モデル
App → 実装の組み立てと注入
```

SwiftUI の View に生成 DTO を渡しません。
生成型は `Core/API/` 内に閉じ込め、Mapper で各機能のモデルへ変換します。
ViewModel から具体的な APIClient を直接構築しません。
機能が増えたら `Himatch/<Feature>/` 内に Domain、Application、Infrastructure、Presentation、Composition を必要に応じて配置します。
今回、添付にない画面や UseCase の実装は追加しません。

## 共有パッケージの条件

複数アプリが実際に使い、特定ドメインに依存せず、公開 API と互換性方針があり、独立してバージョン管理できるものだけを候補にします。
ロガー、トレース、テスト支援も、まず Backend 内に置きます。
ドメインモデル、API DTO、DB レコードを共有するパッケージは作りません。
