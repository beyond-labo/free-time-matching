---
type: Implementation Plan
title: "iOS 安全機能・設定実装計画"
description: "通報、ブロック、通知、設定、削除、統合検証の計画"
status: stable
sources:
  - id: ios-safety-settings-design
    resource: ./design.md
    title: iOS 安全機能・設定設計
kiro:
  depends_on:
    - .kiro/specs/ios-safety-settings/requirements.md
    - .kiro/specs/ios-safety-settings/design.md
---

# Implementation Plan

- [ ] 1. Safety と削除の Domain / Application 境界を実装する
  - Report、BlockImpact、NotificationSettings、DeletionStatus と operationID / version 契約を単体検証できる。
  - _Requirements: 1.2, 1.5, 2.1, 2.2, 2.4, 2.5, 2.6, 3.1, 3.2, 3.6, 5.4, 5.5, 5.6, 6.1, 6.2, 6.3_
  - _Boundary: SafetyApplication, AccountDeletionApplication_

- [ ] 2. Prototype Safety / Deletion / NotificationSettings Adapter を実装する
  - 通報受付、重複抑止、block preview conflict と更新投影、通知設定の保存失敗、削除 accepted / processing / completed / actionRequired を再現する。
  - _Requirements: 1.4, 1.5, 2.2, 2.3, 2.5, 2.6, 3.6, 5.4, 5.5, 5.6, 6.4_
  - _Boundary: PrototypeSafetyAdapter, PrototypeAccountDeletionAdapter, PrototypeNotificationSettingsAdapter_
  - _Depends: 1_

- [ ] 3. 通報とブロック画面を実装する
  - 対象自動設定、定型理由、500文字補足、成功・失敗、独立操作、影響 preview・再確認を操作できる。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_
  - _Boundary: ReportFeature, BlockFeature_
  - _Depends: 2_

- [ ] 4. 設定・通知・サポート画面を実装する
  - 設定一覧、通知カテゴリ、初期オフのリマインダー、OS設定、規約・問い合わせ、利用停止中の許可導線を表示する。
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 4.1, 4.2, 4.3, 4.4_
  - _Boundary: SettingsFeature, NotificationSettingsFeature_
  - _Depends: 1_

- [x] 5. アカウント削除画面とProduction Adapterを実装する
  - 削除影響、fresh Apple再認証、冪等なBackend要求、session停止、完了、actionRequiredを区別し、主催予定や追加連絡先を削除の障害にしない。
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7_
  - _Boundary: AccountDeletionFeature_
  - _Depends: 2, 4_

- [ ] 6. 安全・設定の統合検証と審査引継ぎを完了する
  - 単体・Reducer・Simulator フロー、公開文書導線、Privacy Label / Backend / 運営の未実装境界を検証・文書化する。
  - _Requirements: 1.1, 1.4, 1.5, 2.1, 2.2, 2.5, 3.3, 3.4, 3.5, 4.1, 4.2, 4.3, 4.4, 5.1, 5.4, 5.5, 5.6, 6.1, 6.2, 6.3, 6.4_
  - _Boundary: SafetySettingsValidation_
  - _Depends: 1, 2, 3, 4, 5_
