---
type: Research
title: "Backend 暇時間 API 調査"
description: "現行の認証、Worker、Supabase migration、RLS、テスト証拠の調査記録"
status: draft
sources:
  - id: route-source
    resource: ../../../apps/backend/src/Availability/Presentation/AvailabilityRoutes.ts
    title: Availability route
  - id: repository-source
    resource: ../../../apps/backend/src/Availability/Infrastructure/Repository/SupabaseAvailabilityRepository.ts
    title: Supabase Availability repository
  - id: migration-source
    resource: ../../../supabase/migrations/202609250001_availability.sql
    title: Availability migration
  - id: db-test-source
    resource: ../../../supabase/tests/availability.test.sql
    title: Availability pgTAP test
  - id: worker-test-source
    resource: ../../../apps/backend/test/availability.worker.test.ts
    title: Availability Worker test
  - id: api-policy
    resource: ../../../docs/architecture/api-contracts.md
    title: API 契約方針
kiro:
  depends_on:
    - apps/backend/src/Composition/createApp.ts
    - apps/backend/src/Auth/Infrastructure/Adapter/SupabaseJwtVerifier.ts
    - supabase/migrations/202609210001_auth_profile_and_deletion.sql
    - .kiro/specs/ios-availability/requirements.md
---

# 調査と設計判断

## Summary

- **Feature**: `backend-availability`
- **Discovery Scope**: Extension / Complex Integration
- **Key Findings**:
  - `/v1/availability` は既に Hono、JWT verifier、Supabase REST adapter、migration まで実装されている。
  - route は 15 分単位・現在から 14 日以内・カテゴリ・visibility を検証し、DB は RLS、cascade、exclusion constraint、active account policy を持つ。
  - Worker test は authenticated route、invalid category、同一 payload replay、異なる payload conflict、delete を in-memory で確認するが、実 Supabase の同時作成と staging/production 接続は未証明である。

## Research Log

### 現行 Worker 境界

- **Context**: 実認証 API の責務と既存 Composition を確認した。
- **Sources Consulted**: `apps/backend/src/Availability/Presentation/AvailabilityRoutes.ts`, `apps/backend/src/Composition/createApp.ts`, `apps/backend/src/Auth/Infrastructure/Adapter/SupabaseJwtVerifier.ts`
- **Findings**: `createApp` は Availability repository を lazy dependency として `/v1` へ接続する。route は Bearer token を検証し、JWT subject を actor ID として repository へ渡す。`SUPABASE_SECRET_KEY` は通常の repository へ渡されない。
- **Implications**: 本仕様は既存の feature-first Port/Adapter 構造を維持し、認証方式を再実装しない。release composition の実 Supabase 接続が必須である。

### 入力と DB 制約

- **Context**: API の入力検証だけでなく、DB の最終防衛を確認した。
- **Sources Consulted**: `Availability.ts`, `AvailabilityRoutes.ts`, `202609250001_availability.sql`
- **Findings**: category は `game|meal|call|work|null`、visibility は `privateUntilAccepted|shareOnHosting`。日時は timezone 付き、15 分境界、現在から 14 日以内。DB は interval、quarter-hour、enum-like CHECK、window trigger、同一 owner の `[)` overlap exclusion を持つ。
- **Implications**: route と DB を重複防御として扱い、DB error code `23P01`, `23505`, `availability_overlap`, `23514`, `availability_invalid` を安定 error へ変換する。

### Privacy、RLS、アカウント削除

- **Context**: 非公開情報と削除状態が本 API で漏れないことを確認した。
- **Sources Consulted**: migration、`supabase/tests/availability.test.sql`、`202609210001_auth_profile_and_deletion.sql`、`apps/backend/src/Shared/Presentation/ApiError.ts`
- **Findings**: select/insert/update/delete policy は `owner_user_id = auth.uid()` と `public.is_account_active()` を要求する。`auth.users` 外部キーは cascade。pgTAP は別 actor の read/create を拒否し、削除 request 後に read/create が拒否されることを検証する。
- **Implications**: Worker 単独の owner check や prototype 表示を認可の証拠にしない。service role key を通常操作へ使わず、削除受付後は `account_deletion_in_progress` または RLS 拒否としてアクセス停止を維持する。

### 再送と競合

- **Context**: ユーザー指定の create-only idempotent replay/conflict semantics を現行実装と照合した。
- **Sources Consulted**: `SupabaseAvailabilityRepository.ts`, `availability.worker.test.ts`, migration
- **Findings**: 現行 adapter は ID で既存行を読み、全フィールド一致なら replay、差異なら `AvailabilityConflictError`、不存在なら POST する。DB exclusion constraint は同一 actor の重複を拒否する。Worker test は同一 payload replay と変更 conflict を確認する。
- **Implications**: 既存の `upsert` 名は Port 互換のため許容するが、仕様上の意味は create-only とする。lookup と POST の競合窓、同一 UUID の同時 insert、別 actor ID の情報漏えいを実 Supabase/統合テストで補う。

### 観測と検証限界

- **Context**: 実装済みテストの証明範囲を確認した。
- **Sources Consulted**: `apps/backend/test/availability.worker.test.ts`, `apps/backend/test/auth.worker.test.ts`, `supabase/tests/availability.test.sql`, `apps/backend/package.json`, `docs/architecture/api-contracts.md`
- **Findings**: Vitest の route/auth test と pgTAP SQL test が分離されている。Backend package には `typecheck`, `test`, `build` がある。OpenAPI 自動生成は API 方針上まだ未実装。structured logging の共通契約は CI/CD 文書にあるが Availability 固有の redaction 証拠はない。
- **Implications**: テスト成功を staging/production、JWKS、RLS 実行、観測基盤の証明と表現しない。HTTP schema/OpenAPI 生成、redacted logging、実 DB の concurrency は残件として task 化する。

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|---|---|---|---|---|
| Existing Port/Adapter | Hono → Port → Supabase REST → RLS | 現行構造、差し替えテスト、secret 分離 | adapter の競合窓を別途検証 | 採用 |
| service-role repository | Worker が service role で DB を操作 | server 側で一括制御 | RLS を迂回し privacy 境界を弱める | 不採用 |
| DB RPC only | 全 mutation を SQL function へ集約 | 原子的な replay/conflict を実装しやすい | API adapter、migration、RPC 契約が増える | 将来の同時性改善候補 |

## Design Decisions

### Decision: 本人 JWT + RLS の二重境界

- **Context**: 非公開の暇時間を本人限定で保存する。
- **Alternatives Considered**: Worker の owner check のみ、service role で server-side authorization、利用者 JWT と RLS。
- **Selected Approach**: JWT subject を actor として渡し、publishable key + bearer token で Supabase REST を呼ぶ。Postgres RLS を正本の最終防衛にする。
- **Rationale**: 既存 Auth/DB 方針と一致し、Worker のバグが他 actor の read/write を直ちに許可しない。
- **Trade-offs**: route と DB の検証が重複するが、制約漏れと migration 実行時の safety を別々に確認できる。
- **Follow-up**: staging で signed JWT と RLS を実接続して確認する。

### Decision: client UUID による create-only replay/conflict

- **Context**: ネットワーク再送で同じ slot が二重作成されることを防ぐ。
- **Alternatives Considered**: server UUID と無条件 upsert、Idempotency-Key テーブル、client UUID + payload 比較。
- **Selected Approach**: `PUT /availability/{id}` の client UUID を作成識別子とし、同一 payload は replay、差異は conflict、既存行を更新しない。
- **Rationale**: 現行 iOS/Worker の ID 契約を維持し、DB の PK と重複制約を利用できる。
- **Trade-offs**: lookup と insert の間の窓が残るため、同時挿入の最終結果は DB 制約と統合テストで証明する必要がある。
- **Follow-up**: 必要なら将来 SQL RPC へ移し、同一 UUID の atomic replay を強化する。

## Risks & Mitigations

- 同一 UUID の同時 create で片方が generic `23505` になる可能性 — Supabase error mapping と実 DB concurrency test を追加する。
- `now()` の route/DB 境界がずれる可能性 — 時計境界と migration trigger を別テストにする。
- log に user ID や時間区間が混入する可能性 — structured log の allowlist と redaction test を用意する。
- OpenAPI と route validation が乖離する可能性 — Backend schema を正本にして生成契約の導入を別タスクで明記する。

## References

- [API 契約](../../../docs/architecture/api-contracts.md) — Backend 所有 HTTP schema と `/v1` 方針
- [Supabase Auth・Database CI/CD](../../../docs/operations/supabase-auth.md) — migration と RLS の運用方針
- [Cloudflare Workers Hono](https://hono.dev/) — 現行 HTTP runtime の一次資料（2026-09-25確認対象、未取得）

## Change Log

### 2026-09-25

- ユーザー依頼と現行 Worker/migration/test の調査から新規仕様を作成した。
- 既存実装を「本番証明済み」とは扱わず、実 Supabase concurrency、staging/production、OpenAPI、観測 redaction を未検証として設計・タスクへ反映した。
