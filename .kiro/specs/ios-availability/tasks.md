---
type: Implementation Plan
title: "iOS 暇時間実装計画"
description: "時間ポリシー、Repository、ホーム、編集、検証の実装計画"
status: stable
sources:
  - id: ios-availability-design
    resource: ./design.md
    title: iOS 暇時間設計
kiro:
  depends_on:
    - .kiro/specs/ios-availability/requirements.md
    - .kiro/specs/ios-availability/design.md
---

# Implementation Plan

- [ ] 1. 暇時間の Domain と Application 境界を実装する
  - 半開区間、15分境界、14日範囲、重複、公開設定、Repository / UseCase が純粋テストで検証できる。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.3, 5.1, 5.2_
  - _Boundary: AvailabilityDomain, AvailabilityApplication_

- [ ] 2. Prototype Adapter を実装する
  - 作成・更新・削除、version conflict、失敗を再現し、Reducer から直接保存状態へ触れない。
  - _Requirements: 4.1, 4.2, 4.3, 4.4_
  - _Boundary: PrototypeAvailabilityAdapter_
  - _Depends: 1_

- [ ] 3. ホーム時間軸を実装する
  - 自分の暇と確定予定、日時固定、新規登録、原因別の空状態を操作できる。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 5.3_
  - _Boundary: HomeTimelineFeature_
  - _Depends: 1, 2_

- [ ] 4. 暇時間編集シートを実装する
  - 初期2時間、15分調整、カテゴリ、公開説明、編集・削除、関連 Hosting 導線を操作できる。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 4.1, 4.2, 4.3, 4.4_
  - _Boundary: AvailabilityEditorFeature_
  - _Depends: 2, 3_

- [ ] 5. 暇時間の統合検証を完了する
  - Domain/Application/Reducer テストと Simulator 上の登録・編集・削除が成功する。
  - _Requirements: 1.1, 1.3, 2.1, 2.2, 2.3, 2.4, 3.1, 3.4, 4.1, 4.4, 5.1, 5.2, 5.3_
  - _Boundary: AvailabilityValidation_
  - _Depends: 1, 2, 3, 4_
