---
type: Design
title: "iOS 友達関係設計"
description: "友達・申請状態機械と招待コード画面の責務設計"
status: stable
sources:
  - id: ios-friendship-research
    resource: ./research.md
    title: iOS 友達関係調査
kiro:
  depends_on:
    - .kiro/specs/automatic-friend-scheduling/requirements.md
    - .kiro/specs/ios-friendship/requirements.md
    - .kiro/specs/ios-app-foundation/design.md
---

## 第一段階での適用（2026-10-30）

友達別の自動提案許可はAutomaticSchedulingの設定を表示・更新する。友達承認を許可に読み替えない。関係解除で許可とpendingを失効させ、確定予定は暗黙に消さない。通報・ブロックは実APIへ委譲する。

新しい受け入れ条件と実装タスクは [自動提案・予定成立](../automatic-friend-scheduling/requirements.md) と [その実装計画](../automatic-friend-scheduling/tasks.md) を正本とする。既存タスクのチェックは記載された既存契約の証拠であり、新しい提案・確定・通知・安全の達成を示さない。


# Design Document

## Overview

Friendship が関係と申請のクライアント状態を所有し、一覧、コード入力、プロフィールを TCA 状態として構成する。Release は build-time configuration が指す Backend Friendship API（最初の内部 TestFlight は STG）、DEBUG デモは共有 Prototype scenario を利用する。安全操作と自動提案許可は所有機能へIDを渡して委譲する。既存手動募集のNavigation delegateは互換性として維持する。

## Boundary Commitments

### This Spec Owns

- 友達、受信・送信申請、招待コード、プロフィール、解除の iOS 契約と状態、および実 Backend Adapter。最初の Release build は STG を接続先とする。

### Out of Boundary

- ブロックの適用、通報保存、募集、コード生成の安全性、友達グラフのサーバー認可。

### Allowed Dependencies

- ios-app-foundation の Navigation / common UI、backend-friendship の公開 HTTP 契約。

### Revalidation Triggers

- 友達状態、コード契約、プロフィール公開項目、Safety / Hosting delegate の変更。

## Architecture

```mermaid
graph LR
    FriendsListView --> FriendsListFeature
    AddFriendView --> AddFriendFeature
    FriendProfileView --> FriendProfileFeature
    Features --> FriendshipUseCase
    Features --> FriendshipClient
    FriendshipClient --> BackendAdapter
    FriendshipClient --> PrototypeAdapter
    Features --> DelegateActions
```

## File Structure Plan

```text
apps/ios/Himatch/Friendship/
├── Domain/Model/{Friendship,FriendRequest,InviteCode}.swift
├── Domain/Policy/FriendshipPolicy.swift
├── Application/Port/FriendshipClient.swift
├── Application/Port/FriendPlanProjection.swift
├── Infrastructure/Adapter/BackendFriendshipAdapter.swift
└── Presentation/
    ├── Reducer/{FriendsList,AddFriend,FriendProfile}Feature.swift
    └── View/{FriendsList,AddFriend,FriendProfile}View.swift
apps/ios/HimatchTests/Friendship/
```

## State and Contracts

- `FriendshipStatus`: friends / incoming / outgoing は別コレクションではなく1状態の投影とする。
- `FriendshipClient`: snapshot、resolveCode、sendRequest、accept、reject、cancel、remove、rotateCode。実 Backend 操作は access token を明示的に受け取る。
- 変更入力は operationID と expectedVersion を持つ。
- `FriendshipError`: unavailableCode、conflict、permissionLost、transport。コードの詳細理由は外へ出さない。

FriendProfile の delegate は `invite(friendID)`、`report(target)`、`block(userID)` と DEBUG Prototype 専用の `openPlan(planID)`。他機能の View や Adapter を import しない。
`FriendPlanProjection` は旧HostingのDEBUG fixture用として維持する。実際の自動提案・予定はAutomaticSchedulingの投影を使い、Friendshipはその予定の正本を持たず確認・取消へ委譲する。

## Requirements Traceability

| Requirement | Components | Validation |
|---|---|---|
| 1.1-1.5 | FriendsListFeature | state / conflict tests |
| 2.1-2.4 | AddFriendFeature, InviteCode | privacy / reducer tests |
| 3.1-3.5 | FriendProfileFeature | delegate / permission tests |
| 4.1-4.3 | Repository, docs handoff | idempotency / review |
| 5.1-5.7 | BackendFriendshipAdapter, AppFeature, Composition | adapter / reducer / integration tests |

## Testing Strategy

- Domain: 状態遷移、自己申請・重複申請の拒否。
- Application: code 共通エラー、operationID、version conflict。
- Presentation: 3区分、空・失敗、プロフィール delegate、入力保持。
- Integration: code → profile → request → accept → friend。
- Infrastructure: HTTP DTO、Bearer token、共通 code error、409 conflict の変換。

## はじめての予定動線による変更
友達一覧の各行の「誘う」と友達プロフィールの「自分で誘う」は、その友達を選択済みにした `InvitationComposerFeature` を開く（時間軸の選択モードには入らない）。友達プロフィールの自動提案の許可トグルは AutomaticScheduling のまま。ホームの案内から友達の許可へ進む場合、友達が2人以下なら案内上の許可ボタン、3人以上なら友達タブへ移る。詳細は [ios-first-match-flow の設計](../ios-first-match-flow/design.md)。
