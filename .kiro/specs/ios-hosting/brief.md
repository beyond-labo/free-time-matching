---
type: Brief
title: "iOS 募集と予定"
description: "募集、招待、参加回答、日時確定、予定管理を一連の画面で実現する"
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

# iOS 募集と予定 Brief

## Problem

暇登録だけでは参加意思や予定確定にならず、友達の非公開情報を漏らさずに募集から確定まで進める画面と状態遷移がない。

## Current State

募集、照合、受信箱、回答、予定確定は未実装で、Backend 公開契約も存在しない。

## Desired Outcome

ホストが開催形態、カテゴリ、候補期間、必要時間、友達を指定して募集を開始し、招待された人が自分で候補時間を選んで参加 OK、変更、撤回、見送りできる。ホストは回答者全員との共通時間から確定し、確定後は取消・離脱を扱える。

## Approach

Hosting の状態機械と時間区間演算を Domain / Application に置き、受信箱と詳細画面を共通の TCA 状態へ接続する。プロトタイプ Adapter は漏えいしないレスポンス形状と競合エラーを再現するが、実サーバー安全性の証拠にはしない。

## Scope

### In

- 3段階の募集作成、オンライン／オフライン、定型カテゴリ、候補期間、15分単位の必要時間、友達選択。
- 配信人数や不一致理由を表示しない募集完了。
- 招待未回答、回答済み、ホスト回答待ち、ホスト確定可能、確定、取消、期限切れの共通詳細。
- 自分が選んだ候補だけの共有、回答変更・撤回、共通候補からの確定。
- 要対応・進行中・終了の受信箱と Push 非依存の導線。

### Out

- 常時マッチング、配信人数、既読、辞退者の表示、自由タイトル、コメント、URL、場所自由入力。
- 実 Push、サーバー照合・認可・同時実行・冪等性の保証。

## Boundary Candidates

- Hosting / ParticipationResponse / ConfirmedPlan / HostingPolicy。
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
- 募集開始時だけ候補探索し、確定直前に最新回答・ブロック・予定重複を再確認する契約にする。
