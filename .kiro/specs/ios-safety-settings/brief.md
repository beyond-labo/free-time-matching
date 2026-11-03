---
type: Brief
title: "iOS 安全機能と設定"
description: "通報、ブロック、通知設定、サポート、アカウント削除の導線を実現する"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
  - id: apple-review-guidelines
    resource: https://developer.apple.com/app-store/review/guidelines/
    title: App Review Guidelines
kiro:
  depends_on:
    - .kiro/specs/automatic-friend-scheduling/requirements.md
    - .kiro/steering/roadmap.md
    - .kiro/specs/ios-app-foundation/brief.md
    - .kiro/specs/ios-friendship/brief.md
    - .kiro/specs/ios-hosting/brief.md
---

## 第一段階での適用（2026-10-30）

自動提案・予定と友達プロフィールの定型通報/ブロックを実Backendへ接続する。匿名相手は提案IDから解決する。既存Prototypeの任意補足やblock一覧を実保存・実提供されたと表示しない。ブロック/退会でpendingと未来予定を停止する。通知許可・device登録とAPNs配送はAutomaticScheduling/Notificationへ委譲する。

新しい受け入れ条件と実装タスクは [自動提案・予定成立](../automatic-friend-scheduling/requirements.md) と [その実装計画](../automatic-friend-scheduling/tasks.md) を正本とする。既存タスクのチェックは記載された既存契約の証拠であり、新しい提案・確定・通知・安全の達成を示さない。


# iOS 安全機能と設定 Brief

## Problem

初版で自由入力を絞っても、表示名、申請、招待を通じた迷惑行為へ対処し、利用者がアプリ内で通報・ブロック・退会できる必要がある。

## Current State

設定、安全機能、通知設定、サポート、退会画面とプロトタイプ状態遷移がある。アカウント削除は fresh Apple 再認証、Apple token revoke、Supabase Auth hard delete を行う Production Backend へ接続し、定型通報・ブロック・通知登録をAutomaticSchedulingの実契約へ接続する。運営管理と実配信の実環境確認は別の準備事項である。

## Desired Outcome

対象に近い場所から理由を選んで通報し、通報と独立してブロックできる。設定から通知、規約、プライバシー、問い合わせ、ログアウト、アカウント削除へ到達できる。ブロックは対象近くで操作し、実リスト未提供の人数を表示しない。削除は影響を説明し、受付と完了を区別する。

## Approach

Safety と AccountDeletion の Port を定義し、iOS は入力、影響確認、送信状態、受付状態を所有する。削除と新しい安全操作を実Adapterへ接続する。匿名の2人提案では影響IDを返す旧Prototype previewを使わず、友達解除・申請/招待停止・未確定提案と未来予定の取消を定型文で確認し、最新状態へサーバーで適用する。運営管理は対象外とする。

## Scope

### In

- 対象自動設定、定型理由、任意500文字の補足、重複送信防止を持つ通報シート。
- 匿名性を守る固定のブロック影響確認。旧Prototypeの一覧・解除導線は実提供と扱わない。
- 招待・回答・確定・取消の通知設定、任意の暇リマインダー、OS設定導線。
- 規約、プライバシー、コミュニティルール、問い合わせ、運営情報。
- 削除対象と予定影響、再認証要求、受付／処理中／完了／再試行の画面状態。

### Out

- 運営管理画面、通報 SLA の実運用、友達・暇・募集データの実削除、APNs、法令上の保持判断。

## Boundary Candidates

- Report / BlockImpact / AccountDeletionStatus。
- SafetyRepository / AccountDeletionRepository / NotificationSettingsRepository。
- ReportFeature / BlockedUsersFeature / SettingsFeature / AccountDeletionFeature。

## Out of Boundary

サーバー認可、送信待ち通知の停止、既存予定の一貫した更新を iOS 単独で保証しない。

## Upstream / Downstream

- Upstream: ios-app-foundation、ios-friendship、ios-hosting、Apple の審査・削除ガイド。
- Downstream: Backend 安全運用・削除処理仕様、App Store 申告。

## Existing Spec Touchpoints

- Adjacent: `ios-ci-cd` の TestFlight 配布境界、`docs/product/overview.md`。

## Constraints

- 通報失敗時に受付済みと表示しない。
- Push を拒否しても主要機能を利用でき、通知本文へ機密情報を含めない。
- 退会をサポート連絡や追加の電話・メール登録へ依存させない。
