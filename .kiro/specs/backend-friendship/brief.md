---
type: Brief
title: "Backend 友達関係"
description: "期限付き招待コードと相互承認による実 Backend の友達関係を STG から提供する"
status: stable
sources:
  - id: user-friendship-implementation
    resource: conversation://2026-09-23/friendship-implementation
    title: 友達関係とフレンドコード発行の実装依頼
kiro:
  depends_on:
    - .kiro/steering/roadmap.md
    - .kiro/specs/backend-user-account-management/design.md
    - .kiro/specs/ios-friendship/requirements.md
---

# Backend 友達関係 Brief

## Problem

Release 構成の友達機能が空の Production Placeholder に接続されているため、認証済み利用者にも招待コードが発行されず、複数利用者の間で友達関係を成立させられない。

## Current State

- iOS には Prototype fixture のコード表示と一部の状態遷移だけがある。
- Backend と Supabase には友達コード、申請、成立済み関係の契約と保存先がない。
- `AppSnapshot.empty()` は空文字かつ期限切れのコードを返す。

## Desired Outcome

STG のプロフィール設定済み認証利用者へ期限付き招待コードを自動発行し、コードを知る相手だけがプロフィール確認、申請、承認を経て友達になれる。受信・送信申請、取消・拒否・解除、コード再発行を実 API と DB の一貫した状態として扱う。

## Approach

Backend の Friendship 境界が公開 API と業務遷移を所有し、Supabase の security-definer RPC が利用者 JWT を基準に複数行更新を原子的に行う。iOS は専用 Adapter からこの契約を利用し、Prototype は DEBUG デモだけに残す。

## Scope

### In

- 招待コードの自動発行、表示、失効、再発行。
- コード解決と申請送信。
- 受信・送信申請、承認、拒否、取消。
- 成立済み友達一覧と友達解除。
- JWT 認証、本人起点の認可、再送安全性、共通エラー。
- 最初の内部 TestFlight が向く STG API / Supabase への実接続。接続先は build-time configuration で選び、production へ直結しない。

### Out

- 全ユーザー検索、連絡先同期、QR 必須化。
- ブロック・通報の本番保存と横断効果。
- 暇時間・募集の実 Backend 接続、Push 配信、運営画面、production 環境への deploy。

## Boundary Candidates

- Backend: Friendship aggregate、ManageFriendships、FriendshipRepository、FriendshipRoutes。
- Data: friend invite codes、friendship requests、friendships、transactional RPC。
- iOS touchpoint: FriendshipClient、BackendFriendshipAdapter、AppFeature の接続。

## Out of Boundary

Safety がブロック・通報を、Hosting が募集と確定予定を所有する。Friendship は友達成立・解除によって隣接機能へ渡す ID だけを所有する。

## Upstream / Downstream

- Upstream: backend-user-account-management、ios-app-foundation。
- Downstream: ios-friendship、ios-hosting、ios-safety-settings、ios-app-integration。

## Existing Spec Touchpoints

- Extends: `ios-friendship` を Prototype 契約から STG の実 API 接続へ更新する。
- Extends: `ios-app-integration` の Release Composition と共有 snapshot を更新する。
- Extends: `docs/architecture/api-contracts.md` に `/v1/friendships` 契約を追加する。

## Constraints

- 無効・期限切れ・存在しないコードを外部応答で区別しない。
- 本人 ID は JWT subject から確定し、要求 body から信用しない。
- 承認と友達作成は同一トランザクションで行う。
- 招待コードは推測耐性のある乱数を使い、平文をログへ出さない。
