---
type: Research
title: "Backend 友達関係調査"
description: "フレンドコード未発行の原因と実 Backend 状態遷移の設計判断"
status: stable
sources:
  - id: current-production-composition
    resource: ../../../apps/ios/Himatch/App/Composition/AppCompositionRoot.swift
    title: iOS Production Composition
  - id: current-client-placeholder
    resource: ../../../apps/ios/Himatch/App/Domain/HimatchClient.swift
    title: Production Placeholder
  - id: current-api-contracts
    resource: ../../../docs/architecture/api-contracts.md
    title: API 契約
kiro:
  depends_on:
    - apps/ios/Himatch/App/Composition/AppCompositionRoot.swift
    - apps/ios/Himatch/App/Domain/HimatchClient.swift
    - apps/backend/src/Composition/createApp.ts
    - supabase/migrations/202609210001_auth_profile_and_deletion.sql
---

# 調査と設計判断

## Summary

- **Feature**: backend-friendship
- **Discovery Scope**: Complex Integration
- **Key Findings**:
  - Release は `HimatchClient.productionPlaceholder` を使い、`AppSnapshot.empty()` が空文字・期限切れコードを返す。
  - 既存 `ios-friendship` は Backend API・DB を明示的に対象外としており、UI の局所修正だけでは複数利用者の関係を作れない。
  - 既存 Backend は JWT 検証、利用者 JWT 付き Supabase REST、RLS を採用している。

## Research Log

### 未発行の再現箇所

- **Sources Consulted**: `AppCompositionRoot.swift`、`HimatchClient.swift`、`AppView.swift`。
- **Findings**: Release の `load` は常に `.empty()`、code は `""` と `.distantPast`。画面は code object の存在だけを見ているため空欄を表示する。
- **Implications**: UI fallback ではなく実 Backend Adapter と Backend の正本が必要。初回の接続・検証先は STG とする。

### Backend の認証・保存境界

- **Sources Consulted**: `createApp.ts`、`SupabaseProfileRepository.ts`、既存 migration。
- **Findings**: actor は検証済み JWT subject から取得し、通常操作は publishable key と利用者 access token で RLS を通す。複数行の友達承認は直接 REST の逐次操作では原子性を保証できない。
- **Implications**: 友達遷移は actor を内部確定する transactional RPC に置く。

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|---|---|---|---|---|
| iOS ローカル生成 | 端末だけでコードを表示 | 小変更 | 他者が解決不能、関係の正本がない | 不採用 |
| Backend 逐次 CRUD | API が table REST を複数回呼ぶ | 実装が単純 | 承認と関係作成が分離、競合に弱い | 不採用 |
| Transactional RPC | API UseCase と DB RPC で遷移 | 原子性、RLS actor、秘匿 | SQL 契約のテストが必要 | 採用 |

## Design Decisions

### Decision: 初回 snapshot でコードを自動発行する

- **Context**: 利用者が明示的な発行操作を知らなくても友達タブで共有できる必要がある。
- **Alternatives Considered**: プロフィール保存 trigger、友達タブで明示発行、snapshot の lazy issuance。
- **Selected Approach**: snapshot の有効コード欠落時に UseCase が生成・保存し、再取得して返す。
- **Rationale**: 既存利用者の backfill が不要で、Friendship 境界内に副作用を閉じ込められる。
- **Trade-offs**: GET 相当の初回処理が書き込みを伴うため、内部 UseCase とテストで明示する。

### Decision: unordered pair を一意制約にする

- **Context**: 相互申請や再送で二重友達を作らない。
- **Selected Approach**: 小さい UUID / 大きい UUID の組を DB 正本にし、申請 pending と成立済み関係へ unique constraint を置く。
- **Rationale**: API の事前確認だけに依存せず競合を DB で防げる。

### Decision: コードエラーを単一の公開エラーにする

- **Context**: コード探索から利用者・期限・ブロック状態を推測させない。
- **Selected Approach**: DB 内部理由を `invite_code_unavailable` に変換し、404 と同じ文言を返す。
- **Trade-offs**: 利用者向けの詳細トラブルシュートはできないが、再共有・再発行で回復できる。

### Decision: 解除後も関係 tombstone と単調 version を保持する

- **Context**: 関係行を物理削除して再成立時に version 1 へ戻すと、古い端末の `expectedVersion = 1` が新しい関係にも一致する ABA 問題が起きる。
- **Selected Approach**: unordered pair の行を `active = false` にして version を増やし、再成立は同じ行を再活性化してさらに version を増やす。公開 snapshot は active のみ返す。
- **Rationale**: 利用者にとっての解除を維持しながら optimistic concurrency token を関係の世代間で再利用しない。

### Decision: operation ID を対象 payload に拘束する

- **Context**: kind だけでは同じ operation ID を別申請・別相手へ再利用した際に誤って成功扱いになる。
- **Selected Approach**: actor / operation ID ごとに kind と対象・expected version の fingerprint を保存し、advisory lock 後に一致する再送だけを成功扱いする。同一 pair の申請作成も pair lock で直列化する。
- **Rationale**: 同一 payload の再送安全性と、異なる payload の競合を両立する。

## Risks & Mitigations

- RPC の security-definer が広い権限を持つ — `search_path = ''`、明示 schema、grant 対象限定、pgTAP で検査する。
- 初回 snapshot の同時発行 — owner の active unique と rotate RPC で一件へ収束する。
- Safety block 未接続 — 本仕様では対象外を明示し、Safety 本番化時の再検証 trigger とする。
- 高頻度コード試行 — 長い乱数コードと共通エラーを採用し、edge rate limit は運用基盤導入時の追加防御とする。

## Change Log

- 2026-09-23: ローカル Supabase CLI 2.117.0 で既存 migration からの初期適用、public schema lint、pgTAP 61 件を実行し成功。Friendship pgTAP は初回 ensure、解決、申請、承認、拒否、取消、解除、再成立、operation target binding、非当事者エラー統一を含む。
- 2026-09-23: Backend は Worker test 28 件、health smoke 3 件、Wrangler dry-run build、iOS は署名検査 13 件と Swift Testing 33 件、repository verify を実行し成功。STG への deploy と複数実アカウント smoke は本作業では未実施。
- 2026-09-23: 実装依頼と最新 `origin/main` のコード調査を根拠に、`Production Placeholder` を Backend Friendship へ置換し、初回は STG に接続する設計を追加。独立レビューに基づき operation target binding、pair lock、非当事者エラー統一、active tombstone と単調 version を追加。
