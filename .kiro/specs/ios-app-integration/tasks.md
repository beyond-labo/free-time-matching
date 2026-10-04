---
type: Implementation Plan
title: "iOS アプリ統合実装計画"
description: "共有シナリオ、投影、Composition、統合検証の計画"
status: stable
sources:
  - id: ios-app-integration-design
    resource: ./design.md
    title: iOS アプリ統合設計
kiro:
  depends_on:
    - .kiro/specs/ios-app-integration/requirements.md
    - .kiro/specs/ios-app-integration/design.md
---

# Implementation Plan

- [ ] 1. 共有 Prototype scenario と feature facets を実装する
  - actor transaction、revision、既知 seed / reset、block/delete 横断更新を単体検証できる。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_
  - _Boundary: HimatchPrototypeScenario_

- [ ] 2. 横断読み取り投影を実装する
  - Home、統合受信箱を owner ID 付きで返し、変更操作を所有機能へ route する。友達との確定予定は DEBUG Prototype fixture だけで投影する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - _Boundary: AppProjectionRepository_
  - _Depends: 1_

- [ ] 3. Root Composition と Navigation を接続する
  - 全Adapter / UseCase / Reducerを注入し、通常Debug/Releaseでは認証・プロフィール・削除・Friendship・本人の暇時間・Hostingを実Backendへ固定し、3タブと各詳細をdelegate actionで遷移できる。暇OR登録と招待の成功・失敗をBackend応答で判定する。
  - プロフィール確定後の友達・暇時間の取得を並行し、領域別の読み込み・失敗・再試行を実装して、全画面の操作を塞がないことを検証する。
  - _Requirements: 3.1, 3.2, 3.6, 3.8, 3.9, 3.10, 3.11, 3.12_
  - Siriの実依存共有、認証後FIFO復帰、本人変更時失効の実装と検証は ios-siri-actions タスク3/5/6へ集約する。既存の本仕様全体の未完了状態は維持する。
  - _Boundary: AppCompositionRoot, AppRuntime, AppFeature_
  - _Depends: 1, 2_

- [ ] 4. repository verify と全機能統合テストを完了する
  - project構造、TCA pin、Supabase pin、entitlements、Swift Testing専用検査、STG接続設定、セッション復元・logout・削除後停止に加え、実Backendの暇OR・招待・回答と主要デモ経路を別々に検証する。予定確定は未接続と明示する。
  - _Requirements: 3.3, 3.4, 3.5, 3.7, 3.8, 3.11, 3.12_
  - _Boundary: AppIntegrationValidation_
  - _Depends: 1, 2, 3_
