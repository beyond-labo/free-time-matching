---
type: Implementation Plan
title: "iOS アプリ基盤実装計画"
description: "TCA 導入から起動・認証・プロフィール・3タブ・統合検証までの計画"
status: stable
sources:
  - id: ios-app-foundation-design
    resource: ./design.md
    title: iOS アプリ基盤設計
kiro:
  depends_on:
    - .kiro/specs/ios-app-foundation/requirements.md
    - .kiro/specs/ios-app-foundation/design.md
---

# Implementation Plan

- [ ] 1. TCA と Xcode プロジェクト構造を導入する
  - TCA 1.26.1 を固定し、app/test フォルダの同期、entitlements、Package.resolved を build 可能にする。
  - _Requirements: 1.3, 3.1, 4.5_
  - _Boundary: AppCompositionRoot_

- [ ] 2. 認証とプロフィールの内側境界を実装する
  - Domain 値、Application Port / UseCase、DEBUG Prototype Adapter が Apple 型や TCA に依存せず検証できる。
  - _Requirements: 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4_
  - _Boundary: Authentication, Profile_
  - _Depends: 1_

- [ ] 3. Onboarding と ProfileSetup の画面状態を実装する
  - 説明、外部文書導線、Apple 標準ボタン、デモ導線、プロフィール検証、失敗・再試行を操作できる。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3_
  - _Boundary: OnboardingFeature, ProfileSetupFeature_
  - _Depends: 2_

- [ ] 4. 3タブと共通異常状態を合成する
  - AppFeature が排他的 route と suspension を所有し、ホーム・友達・設定のプレースホルダと logout を表示する。
  - _Requirements: 3.1, 3.2, 3.3, 4.1, 4.2, 4.3, 4.4, 4.5_
  - _Boundary: AppFeature, MainTabFeature_
  - _Depends: 3_

- [ ] 5. 基盤の単体・Reducer・起動検証を完了する
  - Domain/Application テスト、TestStore、Simulator build/test、既存 repository verify が成功する。
  - _Requirements: 1.1, 1.3, 1.4, 2.2, 2.3, 3.1, 3.3, 4.1, 4.2, 4.5_
  - _Boundary: AppFoundationValidation_
  - _Depends: 1, 2, 3, 4_

- [ ] 6. iOS CI/CD と技術文書を再検証する
  - TCA package 解決後の20分 CI、Sign in with Apple entitlement と provisioning profile preflight、archive 影響を確認し、TCA 未導入という現行文書を同期する。
  - _Requirements: 1.3, 3.1, 4.5_
  - _Boundary: IOSCICDRevalidation, ProjectDocs_
  - _Depends: 1, 5_
