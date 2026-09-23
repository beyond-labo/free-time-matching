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
  - Home、統合受信箱、友達予定を owner ID 付きで返し、変更操作を所有機能へ route する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - _Boundary: AppProjectionRepository_
  - _Depends: 1_

- [x] 3. Root Composition と Navigation を接続する
  - 全Adapter / UseCase / Reducerを注入し、Releaseでは認証・プロフィール・削除とFriendshipを実Backendへ固定し、3タブと各詳細をdelegate actionで遷移できる。
  - _Requirements: 3.1, 3.2, 3.6, 3.8_
  - _Boundary: AppCompositionRoot, AppFeature_
  - _Depends: 1, 2_

- [ ] 4. repository verify と全機能統合テストを完了する
  - project構造、TCA pin、Supabase pin、entitlements、Swift Testing専用検査、STG接続設定、セッション復元・logout・削除後停止と主要デモ経路のbuild/test/smokeが成功し、未接続Backend範囲を区別する。
  - _Requirements: 3.3, 3.4, 3.5, 3.7, 3.8_
  - _Boundary: AppIntegrationValidation_
  - _Depends: 1, 2, 3_
