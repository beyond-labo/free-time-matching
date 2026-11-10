---
type: Brief
title: "iOS 募集と招待"
description: "副経路の手動お誘い、選択肢からの返事、取消を実Backendで扱う"
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

> 適用範囲（2026-10-29）: この文書は既存の手動募集・招待・部分回答の互換性契約を記録する。第一段階の中心は [自動提案・予定成立](../automatic-friend-scheduling/requirements.md) へ置換した。本文の「対象外」は手動Hosting境界の対象外を意味し、製品全体の自動確定・通知を後続へ送る判断には使わない。既存タスクの完了は自動提案の達成証拠ではない。


# iOS 募集と招待 Brief

## Problem

暇登録だけでは相手へ招待が届かず、友達の非公開情報を漏らさずに募集と回答を進める実画面・状態遷移がない。

## Current State

着手時の Release 募集作成は固定エラーに接続され、実 Backend に募集と回答の保存先がなかった。今回、募集・招待・部分回答・取消の DB と Worker API、Release Adapter を追加した。STG に反映して2アカウントで確認する工程は残る。

## Desired Outcome

ホストがホームの各入口またはカレンダーの選択範囲から作成画面を開き、日時・友達・会い方を確認してお誘いを送る。相手は全部・前半・後半・時間指定から選び、1回で参加 OK または見送りを返せる。取消までを実 Backend で扱い、予定確定は AutomaticScheduling へ委譲する。

## Approach

カレンダーから始める場合だけ Availability の選択範囲を引き継ぎ、それ以外は時間候補・登録済み暇・友達を `InvitationComposerFeature` へ直接渡す。返事は `InvitationReplyFeature` と `ReplyChoicePolicy`、API・operationID・owner 照合は Root の `AppFeature`、通信は実 Backend Adapter が担う。Prototype はデモ専用に残し、実サーバー安全性の証拠にはしない。

## Scope

### In

- ホームの「自分で誘う」・時間候補・登録済み暇・友達、またはカレンダー選択範囲からのお誘い作成、オンライン／オフライン、定型カテゴリ、候補期間、友達選択。
- 配信人数や不一致理由を表示しない募集完了。
- 招待未回答、回答済み、取消、期限切れの詳細。
- 全部・前半・後半・時間指定から選ぶ返事、見送り、返事変更・撤回。
- 要対応・進行中・終了の受信箱と Push 非依存の導線。

### Out

- 常時マッチング、配信人数、既読、辞退者の表示、自由タイトル、コメント、URL、場所自由入力。
- 実 Push、友達の暇を用いた照合、予定の最終確定・離脱。

## Boundary Candidates

- Hosting / HostingInvitation / Participation / ReplyChoicePolicy / TimeCandidatePolicy。
- BackendHostingAdapter / HimatchClient の Hosting 操作。
- InvitationComposerFeature / InvitationReplyFeature / HomeDashboard / AppFeature。

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
