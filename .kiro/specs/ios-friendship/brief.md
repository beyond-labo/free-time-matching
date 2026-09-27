---
type: Brief
title: "iOS 友達関係"
description: "招待コードと相互承認による友達追加・管理を実現する"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
kiro:
  depends_on:
    - .kiro/steering/roadmap.md
    - .kiro/specs/ios-app-foundation/brief.md
---

# iOS 友達関係 Brief

## Problem

既知の友達だけを安全に招待対象へ加える手段がなく、公開プロフィールや全ユーザー検索を避けながら関係を成立させられない。

## Current State

DEBUG Prototype には友達一覧と招待コード・申請操作のデモがある。Release は Backend Friendship Adapter を通して実 API へ接続し、承認済み友達を取得する。今回の募集ではこの承認済み友達だけを招待先に選び、友達プロフィールからは当該友達を選択済みにして時間軸へ進む。

## Desired Outcome

まず STG Backend が発行する期限付き招待コードを共有・入力し、相手プロフィールを確認して申請し、相手の承認後だけ友達になる。承認済み、受信申請、送信申請を区別し、拒否・取消・解除・通報・ブロックへ進める。

## Approach

Friendship の表示状態と操作契約を Domain / Application に置き、Release は build-time configuration が指す Backend Adapter（初回は STG）、DEBUG デモは Prototype Adapter を介して友達タブとプロフィールを構成する。

## Scope

### In

- 友達、受信申請、送信申請の一覧。
- 招待コードの表示・入力・無効化・再発行のクライアント契約。
- 申請、承認、拒否、取消、友達解除。
- build-time configuration が指す実 API（初回は STG）からの snapshot 読み込みと mutation 後の再取得。
- プロフィールから誘う・通報・ブロックへ進む導線。

### Out

- 全ユーザー検索、連絡先同期、QR 必須化、友達の友達一覧。
- ブロック・通報の Backend 保存と横断適用。

## Boundary Candidates

- Friendship / FriendshipRequest / InviteCode。
- FriendshipClient / BackendFriendshipAdapter。
- FriendsListFeature / AddFriendFeature / FriendProfileFeature。

## Out of Boundary

ブロックの横断的効果と通報送信は Safety が所有する。募集作成は Hosting が所有する。

## Upstream / Downstream

- Upstream: ios-app-foundation、backend-friendship。
- Downstream: ios-hosting、ios-safety-settings。

## Existing Spec Touchpoints

- Adjacent: `docs/product/overview.md` の友人関係領域。

## Constraints

- 暇の有無で並べ替えず、他人の登録状況を表示しない。
- 無効コード、ブロック、存在しない利用者を区別して列挙しないエラー表現を使う。
