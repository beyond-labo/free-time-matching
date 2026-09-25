---
type: Implementation Plan
title: "Backend 暇時間 API 実装計画"
description: "認証済み Availability API、RLS、再送競合、観測、縦断検証の計画"
status: draft
sources:
  - id: availability-requirements
    resource: ./requirements.md
    title: Backend 暇時間 API 要件
  - id: availability-design
    resource: ./design.md
    title: Backend 暇時間 API 設計
kiro:
  depends_on:
    - apps/backend/src/Availability/Presentation/AvailabilityRoutes.ts
    - apps/backend/src/Availability/Infrastructure/Repository/SupabaseAvailabilityRepository.ts
    - supabase/migrations/202609250001_availability.sql
    - supabase/tests/availability.test.sql
    - apps/backend/test/availability.worker.test.ts
---

# Implementation Plan

- [ ] 1. Backend Availability の HTTP 契約と入力検証を固定する
  - `GET /v1/availability`、`PUT /v1/availability/{id}`、`DELETE /v1/availability/{id}` の request/response/error を schema 相当の一箇所へ整理し、既存 error envelope と一致させる。
  - Bearer JWT、UUID、JSON object、UTC instant、15分境界、現在から14日、category、visibility、省略時 default を route test で検証する。
  - `401`、`400`、`409`、`503` の code と本文が token・slot本文・Supabase response body を漏らさないことを確認する。
  - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 3.1, 3.2, 3.3, 3.4, 3.5, 6.1, 6.3, 7.1_
  - _Boundary: AvailabilityPresentation, AvailabilityValidation_

- [ ] 2. create-only replay/conflict と同時性を永続化境界で補強する
  - 同じ actor・同じ UUID・同じ全 payload の再送を同じ DTO で返し、異なる payload を `availability_conflict` として既存行を変更せず返す。
  - 別 actor の UUID の存在を列挙せず、異なる UUID の時間重複は exclusion constraint の conflict として扱う。
  - lookup と create の競合窓を実 Supabase で再現し、必要な場合は安全な SQL/RPC または error mapping を追加する。
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_
  - _Boundary: AvailabilityRepository, AvailabilityInfrastructure_
  - _Depends: 1_

- [ ] 3. Availability migration と RLS/削除境界を検証・補正する (P)
  - owner FK cascade、quarter-hour/interval/category/visibility CHECK、14日 window trigger、owner+range exclusion、owner index を migration で再確認する。
  - select/insert/update/delete の全 policy が `auth.uid()` と `public.is_account_active()` を要求することを pgTAP で確認する。
  - 別 actor、削除受付後、auth user hard delete 後の read/write/残存データを pgTAP または許可された integration DB で確認する。
  - _Requirements: 1.4, 2.2, 3.6, 5.1, 5.2, 5.3, 5.4, 5.5_
  - _Boundary: AvailabilityData, AvailabilityPrivacy_

- [ ] 4. Worker と DB の観測・秘密情報保護を追加する (P)
  - route/status/duration/request ID/error category/version の allowlist logging を実装または既存共通 logger へ接続する。
  - token、Authorization header、slot本文、日時区間、user ID、Supabase response body がログとレスポンスへ出ない redaction test を追加する。
  - 認証失敗、validation、conflict、dependency failure を運用上識別できるが個人を再構成できない category へ変換する。
  - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - _Boundary: AvailabilityObservability, SharedErrorHandling_

- [ ] 5. Backend API の実行証拠と未検証範囲を確定する
  - route/auth tests、pgTAP、typecheck、build を実行し、テストごとの証明範囲を記録する。
  - signed Supabase JWT、RLS、同時 replay/conflict、削除受付後停止を staging または許可された integration 環境で検証する。環境・secret が無い場合は未実施として記録する。
  - HTTP schema/OpenAPI 生成が導入済みかを確認し、未導入なら公開契約の生成・差分検査を後続作業として残す。
  - `backend-availability` の仕様文書、API 契約、必要な downstream iOS 仕様を同期し、OKF check と意味照合を通す。
  - _Requirements: 2.1, 4.5, 5.3, 6.2, 7.1, 7.2, 7.3_
  - _Boundary: AvailabilityValidation, ContractIntegration_
  - _Depends: 1, 2, 3, 4_
