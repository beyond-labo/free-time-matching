# 技術方針

## アプリケーション境界

iOS と Backend は独立してビルド、リリース、更新します。
同じ PR で変更できても同時リリースを必須にしません。
Backend の内部型を共有せず、Backend 所有の OpenAPI を公開契約として利用します。
ドメインモデルは各アプリケーションが所有します。

## 採用方針と現在の状態

| 項目 | 方針 | 現在の状態 |
| --- | --- | --- |
| Backend | TypeScript、Clean Architecture | workspace 登録のみ |
| iOS | SwiftUI、TCA＋Clean Architecture | 方針決定。ライブラリとアプリは未導入 |
| パッケージ管理 | Backend は pnpm、iOS の依存は Swift Package Manager | pnpm の登録のみ |
| API | Backend の HTTP スキーマから OpenAPI を生成 | 未実装 |
| 利用側 | 固定した契約からクライアントを生成 | 生成ツールは未選定 |
| DB | DynamoDB を想定した例が提示されている | 採用とキー設計は未確定 |
| 非同期処理 | Outbox、SQS、通知 Worker を想定 | 実行基盤と配信保証は未設計 |
| IaC | 選定したツールで環境を管理 | ツールと公開先は未選定 |
| CI | 現存する文書と設定を検証 | リポジトリ検証のみ |

HTTP フレームワーク、スキーマライブラリ、生成ツール、テストツール、各バージョンは実装開始時に固定します。
TCA の採用方針と具体的なリリースバージョンの選定を分けます。
最低 iOS、Xcode / Swift、TCA の互換性を確認してから依存を導入します。
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

## 過剰な共通化を避ける

`packages/contracts`、共有ドメイン型、共有 DB 型は作成しません。
層ごとに同じ形の DTO を機械的に複製せず、外部契約や UI 都合が境界を越える場合に変換します。
機能も層も、実装する責務が生じてから作ります。
