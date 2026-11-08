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
    - .kiro/specs/automatic-friend-scheduling/requirements.md
    - .kiro/specs/ios-app-integration/requirements.md
    - .kiro/specs/ios-app-integration/design.md
---

## 第一段階での適用（2026-10-30）

AutomaticSchedulingの実Clientを共通認証へ注入し、起動/foreground/受信箱で再取得する。旧session・旧revisionの応答を捨てる。Home/Inbox/友達/設定へ提案・確定予定・許可を投影し、新機能の業務状態を所有元Reducerへ集約する。

新しい受け入れ条件と実装タスクは [自動提案・予定成立](../automatic-friend-scheduling/requirements.md) と [その実装計画](../automatic-friend-scheduling/tasks.md) を正本とする。既存タスクのチェックは記載された既存契約の証拠であり、新しい提案・確定・通知・安全の達成を示さない。


# Implementation Plan

- [ ] 1. 共有 Prototype scenario と feature facets を実装する
  - actor transaction、revision、既知 seed / reset、block/delete 横断更新を単体検証できる。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_
  - _Boundary: HimatchPrototypeScenario_

- [ ] 2. 横断読み取り投影を実装する
  - `AppFeature` の所有機能別 State から `HomeDashboard` と統合受信箱を投影し、変更操作を Store の Action で所有機能へ route する。旧Hostingの確定fixtureはDEBUGに限定し、AutomaticSchedulingの実確定予定は所有元Reducerの State / ActionをHome/Inboxから参照する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - _Boundary: HomeDashboard, AppFeature, AppView_
  - _Depends: 1_

- [ ] 3. Root Composition と Navigation を接続する
  - 全Adapter / UseCase / Reducerを注入し、通常Debug/Releaseでは認証・プロフィール・削除・Friendship・本人の暇時間・Hostingを実Backendへ固定し、3タブと各詳細をdelegate actionで遷移できる。暇OR登録と招待の成功・失敗をBackend応答で判定する。
  - プロフィール確定後の友達・暇時間の取得を並行し、領域別の読み込み・失敗・再試行を実装して、全画面の操作を塞がないことを検証する。
  - _Requirements: 3.1, 3.2, 3.6, 3.8, 3.9, 3.10, 3.11, 3.12_
  - Siriの実依存共有、認証後FIFO復帰、本人変更時失効の実装と検証は ios-siri-actions タスク3/5/6へ集約する。既存の本仕様全体の未完了状態は維持する。
  - 部分進捗（0.1.7、2026-11-08同期）: 明示DEBUGデモだけに `DemoScenarioClient` を依存として注入し、Root は `isDemo` のときだけ `business` を選ぶ。自動提案は `AutomaticSchedulingEffects.routingDemo` が所有者 `"demo"` だけを Prototype へ振り分け、通常Debug/Release・実アカウント・Siriの実依存を維持する。デモ保存・通常依存・招待遷移の回帰テストを含む168件成功とDebug/Releaseビルド成功を確認した。領域別読み込み等の残件は維持する。
  - _Boundary: AppCompositionRoot, AppRuntime, AppFeature_
  - _Depends: 1, 2_

- [ ] 4. repository verify と全機能統合テストを完了する
  - project構造、TCA pin、Supabase pin、entitlements、Swift Testing専用検査、STG接続設定、セッション復元・logout・削除後停止に加え、実Backendの暇OR・招待・回答と主要デモ経路を別々に検証する。旧Hostingの確定fixtureを実予定と混同せず、AutomaticSchedulingの実確定・取消とMCP回帰検証を別の証拠にする。
  - _Requirements: 3.3, 3.4, 3.5, 3.7, 3.8, 3.11, 3.12_
  - _Boundary: AppIntegrationValidation_
  - _Depends: 1, 2, 3_
