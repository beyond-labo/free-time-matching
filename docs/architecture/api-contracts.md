# API 契約

## 所有者と生成方向

公開契約は生成処理の実装時に `apps/backend/openapi/openapi.yaml` へ配置します。
Backend が HTTP スキーマ、OpenAPI の生成、実装との整合性、互換性、成果物の公開を所有します。
iOS と他 Backend は、公開契約から自身のクライアントを生成し、自身の内部モデルへ変換します。

```text
Backend HTTP Schema
        ↓ export-openapi
Backend 所有の OpenAPI
        ↓ 利用側が生成
Swift / TypeScript / Kotlin のクライアント
        ↓ Mapper
利用側の内部モデル
```

HTTP スキーマを正本とし、OpenAPI は生成物としてレビューします。
OpenAPI とリクエスト検証を別々に手動管理しません。
利用側が生成元の TypeScript コードを直接参照することは禁止します。

## 更新手順

1. Backend の HTTP スキーマとルートを変更する。
2. Backend が所有するエクスポート処理で OpenAPI を生成する。
3. 生成差分とサンプルレスポンスをレビューする。
4. 構文、規約、既存契約との互換性を検証する。
5. 利用側の契約更新 PR でクライアントを再生成する。
6. Backend のテストと iOS の Adapter テスト、ビルドを実行する。

生成物はコミットし、CI で再生成して差分と未追跡ファイルを検出する方針です。
生成ツール、設定、入力契約のバージョンを固定し、時刻などの非決定的な出力を避けます。
これらの生成と検証処理は今回まだ実装していません。

## 内部型の非公開

DB のキー、ビットマスク、TTL などを公開 DTO にそのまま流出させません。
たとえば暇時間を日時の区間として公開する場合は、各機能の Presentation のレスポンス Mapper で明示的に変換します。
具体的なフィールド、状態値、認可条件は各機能の仕様で決めます。
iOS では各機能の Infrastructure に API DTO と内部モデルの変換を置きます。
生成型は通信基盤と API Adapter / Mapper のみに制限し、Application、Domain、TCA の State と Action へ流しません。

## 契約の配布

同じモノレポでは、コード生成時だけ Backend の OpenAPI ファイルを参照できます。
生成されたクライアントを利用側に保持し、Backend の変更だけで iOS の通常ビルドを最新契約へ更新しません。
独立更新が必要になったら、公開した不変のバージョン付き契約を入力にします。

公開契約は、たとえば `himatch-api-openapi-v1.3.0.yaml` のように識別します。
公開したバージョンの内容は上書きしません。
GitHub Releases、オブジェクトストレージ等の配布先と保存期間は未決定です。
稼働中の `/openapi.json` を毎回取得する方式は、再現可能なビルドの主経路にしません。

## 互換性

初版の業務 API は `/v1` を接頭辞とする方針です。
`/v1/me`は本人プロフィールのGET/PUT、`/v1/account-deletion-requests`はApple再認証を伴う削除受付・状況照会として定義します。
保護APIは`Authorization: Bearer <Supabase access token>`を要求し、本人IDはJWTのsubjectからのみ確定します。
友達の`/v1/friendships`と関連 mutation は下記の固定契約として実装済みです。暇、募集の`/v1/availability-days`、`/v1/hostings`は引き続き候補であり未定義です。
古い iOS が残る前提で、既存クライアントの動作を維持します。

フィールド削除、名前変更、意味変更、リクエストの必須項目追加、レスポンス形状変更は互換性を検討します。
optional から required への変更は、リクエストとレスポンスで影響が異なるため、方向と生成クライアントの挙動を確認します。
optional フィールド追加も、利用側が未知フィールドを受け入れることを確認します。
enum 値追加は、未知値を扱えない生成クライアントを壊す可能性があるため、自動的に安全とは扱いません。

CI の比較対象は PR のベース契約とし、リリース時にはサポート中の公開契約も確認します。
構造差分ツールだけでは認可や意味の互換性は判断できないため、契約テストとレビューを併用します。
破壊的変更には旧 API の併存や非推奨期間を設けます。
サポート期間と廃止条件は未決定です。

## イベント契約

Outbox、SQS、通知 Worker を導入する場合は、単一 Backend 内部のデプロイ単位として扱う方針です。
別 Backend が購読する公開イベントを導入するときは、Producer 所有の JSON Schema または AsyncAPI としてバージョン管理します。
Producer と Consumer で TypeScript interface を直接共有しません。

## ユーザーアカウント契約

- `GET /v1/me` → `{ userId, profile: null | { nickname, presetIconKey } }`
- `PUT /v1/me` ← `{ nickname, presetIconKey }`。nicknameはtrim後1〜20 grapheme、iconは定義済み4値。
- `POST /v1/account-deletion-requests` ← `Idempotency-Key` headerと`{ appleAuthorizationCode }`。
- 削除応答は`{ reference, status, statusToken, message? }`。`status`は`accepted`、`processing`、`completed`、`actionRequired`を区別する。
- `GET /v1/account-deletion-requests/{reference}`は`Authorization: Deletion <statusToken>`で削除後も状況を取得する。

生のApple credential、Supabase token、secretを応答・ログへ含めません。

## 友達関係契約

すべての endpoint は `Authorization: Bearer <Supabase access token>` を要求し、本人 ID を JWT subject から確定します。最初の内部 TestFlight は build-time variable により staging API / Supabase へ接続します。

- `GET /v1/friendships` → `{ inviteCode, friends, incomingRequests, outgoingRequests }`。有効コードがなければ7日有効のコードを発行して返す。
- `POST /v1/friendship-invite-code/rotate` → 旧コードを失効し、新しい code を含む snapshot を返す。
- `POST /v1/friendship-invite-code/resolve` ← `{ code }` → `{ candidate: { userId, nickname, presetIconKey } }`。
- `POST /v1/friendship-requests` ← `{ code, operationId }` → mutation 後の snapshot。
- `POST /v1/friendship-requests/{requestId}/accept|reject|cancel` ← `{ operationId, expectedVersion }` → mutation 後の snapshot。
- `DELETE /v1/friendships/{friendId}` ← `{ operationId, expectedVersion }` → mutation 後の snapshot。

`friends` は `{ profile, version, createdAt }`、申請は `{ id, profile, version, createdAt }` を要素とします。profile は `userId`、`nickname`、`presetIconKey` だけです。コードの無効・期限切れ・失効・自己所有・不存在は `invite_code_unavailable` に統一し、version 競合は `friendship_conflict` として返します。mutation の operation ID は利用者ごとの再送安全性、version は楽観的競合検出に使用します。

## 現在の配置

HTTP実装は存在しますが、OpenAPI生成スクリプトと生成クライアントはまだ存在しません。初版iOS Adapterはプロフィール、友達関係、削除の固定契約を局所DTOへ変換し、生成経路導入時に置き換えます。
