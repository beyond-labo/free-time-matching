---
type: Requirements
title: "Backend 暇時間 API 要件"
description: "認証済み利用者の暇時間を検証、保存、取得、削除する HTTP と DB の要件"
status: draft
sources:
  - id: availability-route
    resource: ../../../apps/backend/src/Availability/Presentation/AvailabilityRoutes.ts
    title: Availability route
  - id: availability-migration
    resource: ../../../supabase/migrations/202609250001_availability.sql
    title: Availability migration
  - id: ios-availability-contract
    resource: ../ios-availability/requirements.md
    title: iOS Availability 要件
kiro:
  depends_on:
    - apps/backend/src/Auth/Infrastructure/Adapter/SupabaseJwtVerifier.ts
    - apps/backend/src/Shared/Presentation/ApiError.ts
    - apps/backend/src/Availability/Infrastructure/Repository/SupabaseAvailabilityRepository.ts
    - supabase/migrations/202609210001_auth_profile_and_deletion.sql
    - supabase/tests/availability.test.sql
    - docs/architecture/api-contracts.md
---

# Backend 暇時間 API 要件

## Introduction

認証済み利用者が、自分の暇時間だけを UTC の時間区間として保存・取得・削除できる Backend 契約を定義する。認証は Supabase access token、所有者境界は JWT subject と Postgres RLS の両方で確定する。暇時間の登録は参加意思や予定確定を意味しない。

## Boundary Context

- **In scope**: `/v1/availability` の認証、入力検証、本人限定 CRUD、作成専用の再送・競合、RLS、削除状態との連動、migration、エラーと観測。
- **Out of scope**: 友達への直接公開、募集時の共有判定、参加回答、確定予定、Push、管理者検索、非同期アカウント削除。
- **Adjacent expectations**: iOS は本 API の DTO を内部 `AvailabilitySlot` へ変換する。Hosting は将来、承認済みの別契約を介して共有を要求する。Account deletion は削除受付後に通常アクセスを停止する。

## Requirements

### Requirement 1: 認証と本人境界
**Objective:** As a 利用者, I want 自分のセッションだけで API を利用したい, so that 他人の暇時間へ到達できない

#### Acceptance Criteria
1. When `/v1/availability` のいずれかへアクセスした, the Backend shall `Authorization: Bearer <Supabase access token>` を必須とし、JWT の `iss`、`aud`、`role`、UUID 形式の `sub`、有効期限を検証する
2. If 認証 header が欠落、不正、期限切れ、または別 issuer/audience である, then the Backend shall 本文を推測できる情報を返さず `401` と `unauthorized` を返す
3. When actor ID を決定した, the Backend shall JWT の `sub` を所有者として使い、リクエスト本文、URL、query の owner ID を所有者判定に使わない
4. The Backend shall 通常の Availability DB 操作へ publishable key と利用者 access token だけを渡し、service role key で RLS を迂回しない

### Requirement 2: 読み取りと公開境界
**Objective:** As a 利用者, I want 自分の暇時間を一覧したい, so that ホーム時間軸を復元できる

#### Acceptance Criteria
1. When 認証済み利用者が `GET /v1/availability` を呼んだ, the Backend shall `200` と `{ "slots": [...] }` を返し、各 slot に `id`、UTC の `start`、`end`、`category`、`visibility` だけを含める
2. The Backend shall 一覧結果を actor 自身の `owner_user_id` に限定し、別利用者の slot、内部キー、監査値、JWT、認証 header を返さない
3. While `visibility` が `privateUntilAccepted` である, the Backend shall 友達や未承認の利用者へその slot を返す別 endpoint を提供しない
4. The Backend shall 一覧を `start` 昇順で返し、区間の意味を `[start, end)` として扱う

### Requirement 3: 登録・入力検証
**Objective:** As a 利用者, I want 無効な暇時間を保存できないようにしたい, so that 時間軸と照合結果が壊れない

#### Acceptance Criteria
1. When `PUT /v1/availability/{id}` を呼んだ, the Backend shall UUID の `id` と JSON object を要求し、`start` と `end` を timezone 付き日時として UTC ISO 8601 に正規化する
2. The Backend shall `start < end`、両端が 15 分境界、`start` が現在以降、`end` が現在から 14 日以内であることを検証する
3. The Backend shall `category` を `null`、`game`、`meal`、`call`、`work` のいずれかに限定する
4. The Backend shall `visibility` を `privateUntilAccepted` または `shareOnHosting` に限定し、省略時は `privateUntilAccepted` とする
5. If JSON、UUID、日時、区間、カテゴリ、公開値のいずれかが不正である, then the Backend shall `400` と安定した `invalid_availability` または `invalid_json` を返し、永続化しない
6. The Database shall 静的な区間・15分境界・値をCHECK制約、現在から14日以内を更新時trigger、所有者単位の重複をexclusion制約でAPIの検証とは独立に強制する

### Requirement 4: 作成専用の再送と競合
**Objective:** As a クライアント, I want タイムアウト後に同じ作成を安全に再送したい, so that 重複や意図しない上書きを避けられる

#### Acceptance Criteria
1. When 指定 UUID が存在せず入力が有効である, the Backend shall その UUID の新しい slot を一度だけ作成し、`200` と作成済み DTO を返す
2. When 指定 UUID が同じ actor の既存 slot と一致し、入力の全フィールドが同じである, the Backend shall 作成済み DTO を `200` で返し、別行を作成しない
3. When 指定 UUID が同じ actor の既存 slot と一致するが入力が異なる, the Backend shall `409` と `availability_conflict` を返し、既存 slot を上書きしない
4. When 別 actor の slot ID を指定した, the Backend shall 所有者の存在を推測させない安全なエラーとして扱い、他 actor の行を更新または削除しない
5. When 同一 actor の異なる UUID が時間重複する, the Backend shall `409` と `availability_conflict` を返し、Postgres の exclusion constraint を勝者判定の正本とする
6. The Backend shall 作成処理を「既存を検索してから無条件更新する upsert」として実装せず、同時再送でも create-only の replay/conflict semantics を保持する

### Requirement 5: 削除とアカウント状態
**Objective:** As a 利用者, I want 自分の暇時間を削除したい, so that 古い候補を残さない

#### Acceptance Criteria
1. When 認証済み利用者が `DELETE /v1/availability/{id}` を呼んだ, the Backend shall actor 自身の slot だけを削除し、成功時に `204` を返す
2. If 対象が不存在または別 actor の slot である, then the Backend shall 他人の存在を列挙せず、安全な不存在または認可エラーとして処理する
3. While `is_account_active()` が false またはアカウント削除受付後である, the Database shall Availability の select、insert、update、delete を拒否する
4. When `auth.users` の利用者が削除された, the Database shall `on delete cascade` によりその actor の slot を残さない
5. The Backend shall 削除受付後に Availability を復元・変更できる成功レスポンスを返さない

### Requirement 6: エラーと観測
**Objective:** As a 運用者, I want 認証・入力・競合・依存障害を区別して観測したい, so that 個人情報を漏らさず復旧できる

#### Acceptance Criteria
1. The Backend shall `401` unauthorized、`400` invalid request、`409` availability conflict、`503` dependency failure を既存 error envelope の `error.code` で区別する
2. The Backend shall structured log に request ID、route、status、duration、error category、version/commit を必要に応じて記録し、access token、認証 header、slot 本文、user ID、時刻区間を既定で記録しない
3. If Supabase が非 2xx、予期しない JSON、制約違反を返した, then the Backend shall 利用者向け安定コードへ変換し、Supabase response body や秘密をレスポンス・ログへ転記しない
4. The Backend shall health check の成功を Availability の認証、RLS、migration、実データ整合性の証拠として扱わない

### Requirement 7: 契約・検証証拠
**Objective:** As a 開発者, I want 実 API の契約と証拠を追跡したい, so that Prototype の成功を本番認可の証拠と誤認しない

#### Acceptance Criteria
1. The Backend shall `/v1/availability` の request、response、status、error code、認証条件を Backend 所有の HTTP schema として管理する
2. The project shall route test、JWT verifier test、pgTAP/RLS test、typecheck、build の証拠を分けて記録し、未実施の staging/production 接続を成功と報告しない
3. The project shall 実装済みの最小テストが証明する範囲と、未検証の同時実行、実 Supabase、観測基盤、OpenAPI 生成の残件を仕様・実装計画に明記する
