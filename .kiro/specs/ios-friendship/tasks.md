---
type: Implementation Plan
title: "iOS 友達関係実装計画"
description: "友達状態、Repository、一覧、追加、プロフィール、検証の計画"
status: stable
sources:
  - id: ios-friendship-design
    resource: ./design.md
    title: iOS 友達関係設計
kiro:
  depends_on:
    - .kiro/specs/ios-friendship/requirements.md
    - .kiro/specs/ios-friendship/design.md
---

# Implementation Plan

- [x] 1. 友達関係の Domain / Application 契約を実装する
  - snapshot、operationID、version、コード共通エラー、実 Backend / Prototype 両方から利用する Client を検証できる。
  - _Requirements: 1.4, 1.5, 2.3, 3.3, 4.1, 4.2, 5.1, 5.3_
  - _Boundary: FriendshipDomain, FriendshipApplication_

- [x] 2. Backend Adapter と DEBUG Prototype を実装する
  - Backend のコード解決、申請、承認・拒否・取消・解除、競合を DTO 変換し、DEBUG は fixture で再現する。
  - _Requirements: 1.1, 1.4, 1.5, 2.1, 2.2, 2.3, 3.3, 4.1, 4.2, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7_
  - _Boundary: BackendFriendshipAdapter, PrototypeFriendshipAdapter_
  - _Depends: 1_

- [x] 3. 友達一覧と追加画面を実装する
  - 3区分、原因別空状態、コード表示・入力、プロフィール確認、申請操作が利用できる。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 5.1, 5.2, 5.3, 5.4, 5.5_
  - _Boundary: FriendsListFeature, AddFriendFeature_
  - _Depends: 2_

- [ ] 4. プロフィールと隣接機能 delegate を実装する
  - 誘う、通報、ブロック、解除、確定予定への導線と権限喪失を検証できる。
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_
  - _Boundary: FriendProfileFeature_
  - _Depends: 2, 3_

- [ ] 5. 友達フローとプライバシー文書の検証を完了する
  - Adapter・Reducer・Simulator の STG 実 Backend 契約と DEBUG デモが成功し、social graph の申告引継ぎが文書に残る。
  - _Requirements: 1.1, 1.4, 2.2, 2.3, 3.1, 3.3, 3.5, 4.1, 4.2, 4.3, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7_
  - _Boundary: FriendshipValidation_
  - _Depends: 1, 2, 3, 4_
