---
type: Brief
title: "iOS 募集と招待"
description: "暇の時間軸からの実招待、参加回答、募集取消を実現する"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
kiro:
  depends_on:
    - .kiro/steering/roadmap.md
    - .kiro/specs/ios-app-foundation/brief.md
    - .kiro/specs/ios-availability/brief.md
    - .kiro/specs/ios-friendship/brief.md
---

# iOS 募集と招待 Brief

## Problem

暇登録だけでは相手へ招待が届かず、友達の非公開情報を漏らさずに募集と回答を進める実画面・状態遷移がない。

## Current State

着手時の Release 募集作成は固定エラーに接続され、実 Backend に募集と回答の保存先がなかった。今回、募集・招待・部分回答・取消の DB と Worker API、Release Adapter を追加した。STG に反映して2アカウントで確認する工程は残る。

## Desired Outcome

ホストが暇登録と同じ時間軸で候補期間を選び、友達全員へ招待し、相手が自分で候補の一部を選んで参加 OK または見送りできる。募集取消までを実 Backend で扱う。予定確定は後続工程へ移管する。

## Approach

時間軸の選択部品を Availability と共用し、Hosting の状態と招待回答は実 Backend Adapter へ接続する。Prototype はデモ専用に残し、実サーバー安全性の証拠にはしない。

## Scope

### In

- 暇登録と共通の時間軸による募集作成、オンライン／オフライン、定型カテゴリ、候補期間、友達選択。
- 配信人数や不一致理由を表示しない募集完了。
- 招待未回答、回答済み、取消、期限切れの詳細。
- 自分が選んだ一部の候補だけの回答、見送り、回答変更・撤回。
- 要対応・進行中・終了の受信箱と Push 非依存の導線。

### Out

- 常時マッチング、配信人数、既読、辞退者の表示、自由タイトル、コメント、URL、場所自由入力。
- 実 Push、友達の暇を用いた照合、予定の最終確定・離脱。

## Boundary Candidates

- Hosting / ParticipationResponse / HostingPolicy。
- HostingRepository / HostingUseCases。
- HostingCreationFeature / HostingDetailFeature / InboxFeature。

## Out of Boundary

友達追加と暇編集を所有せず、必要時は明示的な Navigation 契約で各機能へ移動する。

## Upstream / Downstream

- Upstream: ios-app-foundation、ios-availability、ios-friendship。
- Downstream: ios-safety-settings。

## Existing Spec Touchpoints

- Adjacent: `docs/architecture/api-contracts.md`。Backend 実装時に公開契約の別仕様が必要。

## Constraints

- 暇登録、参加 OK、予定確定を別エンティティ・別操作として保持する。
- 選択した承認済み友達全員を招待し、相手の暇登録の有無をホストへ示さない。
