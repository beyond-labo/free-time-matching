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

- [ ] 1. 友達関係の Domain / Application を実装する
  - 状態遷移、operationID、version、コード共通エラー、Repository / UseCase を検証できる。
  - _Requirements: 1.4, 1.5, 2.3, 3.3, 4.1, 4.2_
  - _Boundary: FriendshipDomain, FriendshipApplication_

- [ ] 2. Prototype Adapter と fixture を実装する
  - コード解決、申請、承認・拒否・取消・解除、競合を一貫した snapshot で再現する。
  - _Requirements: 1.1, 1.4, 1.5, 2.1, 2.2, 2.3, 3.3, 4.1, 4.2_
  - _Boundary: PrototypeFriendshipAdapter_
  - _Depends: 1_

- [ ] 3. 友達一覧と追加画面を実装する
  - 3区分、原因別空状態、コード表示・入力、プロフィール確認、申請操作が利用できる。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4_
  - _Boundary: FriendsListFeature, AddFriendFeature_
  - _Depends: 2_

- [ ] 4. プロフィールと隣接機能 delegate を実装する
  - 誘う、通報、ブロック、解除、確定予定への導線と権限喪失を検証できる。
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_
  - _Boundary: FriendProfileFeature_
  - _Depends: 2, 3_

- [ ] 5. 友達フローとプライバシー文書の検証を完了する
  - 単体・Reducer・Simulator フローが成功し、social graph の申告引継ぎが文書に残る。
  - _Requirements: 1.1, 1.4, 2.2, 2.3, 3.1, 3.3, 3.5, 4.1, 4.2, 4.3_
  - _Boundary: FriendshipValidation_
  - _Depends: 1, 2, 3, 4_
