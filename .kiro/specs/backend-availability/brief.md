---
type: Brief
title: "Backend 暇時間 API"
description: "Supabase 認証下で本人の暇時間を安全に管理する実 API"
status: draft
sources:
  - id: current-availability-implementation
    resource: ../../../apps/backend/src/Availability/Presentation/AvailabilityRoutes.ts
    title: 現行 Availability HTTP 実装
  - id: ios-availability-requirements
    resource: ../ios-availability/requirements.md
    title: iOS 暇時間要件
kiro:
  depends_on:
    - .kiro/specs/automatic-friend-scheduling/requirements.md
    - apps/backend/src/Availability/Domain/Model/Availability.ts
    - apps/backend/src/Availability/Infrastructure/Repository/SupabaseAvailabilityRepository.ts
    - supabase/migrations/202609250001_availability.sql
    - supabase/tests/availability.test.sql
    - docs/architecture/api-contracts.md
---

## 第一段階での適用（2026-10-30）

本人限定APIとRLS、旧shareOnHostingの入力互換性を維持する。照合専用のsecurity definer境界はAutomaticSchedulingが所有する。追加migrationのRPC wrapperとstatement hookでlock順を揃え、暇変更の完了後にpendingを再検証する。union/subtractの一時分割で誤取消しない。

新しい受け入れ条件と実装タスクは [自動提案・予定成立](../automatic-friend-scheduling/requirements.md) と [その実装計画](../automatic-friend-scheduling/tasks.md) を正本とする。既存タスクのチェックは記載された既存契約の証拠であり、新しい提案・確定・通知・安全の達成を示さない。


# Backend 暇時間 API Brief

## 背景

現行 Worker には `/v1/availability` の認証済み route、Supabase REST repository、`availability_slots` migration が存在する。これは DEBUG 用のプロトタイプではなく、Supabase JWT と Postgres RLS を通る本人限定 API として iOS Availability が利用する境界である。

## 目的

本人の予定希望である暇時間をOR登録、一覧、区間削除できる実 API を安定した契約として定義する。招待・回答・予定確定は別機能の責務とし、Availability API は本人の登録データと公開ポリシー値だけを保持する。

## 範囲

- Supabase access token の検証と本人 ID の確定。
- 15 分単位、現在から 14 日以内の暇のOR統合・再送・一覧・区間減算。保存行は非重複へ正規化する。
- `privateUntilAccepted` を初期値とする公開ポリシーとカテゴリの検証。
- RLS、アカウント削除受付後の読み書き停止、migration、API/pgTAP/Worker テスト、観測可能なエラー境界。

## 対象外

募集時の候補探索、友達への暇時間公開、参加回答、予定確定、Push、非同期削除 Queue、管理者向け検索、OpenAPI 生成そのものは別仕様で扱う。

## 現状と未完了

API と migration の最小実装および一部テストは存在する。ただし OpenAPI の生成契約、同時作成時の再送・競合の永続的保証、Worker の構造化観測、staging/production での実 DB 接続証拠は未確定であり、本仕様のタスクで検証・補強する。
