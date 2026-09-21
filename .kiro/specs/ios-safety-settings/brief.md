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
    - .kiro/steering/roadmap.md
    - .kiro/specs/ios-app-foundation/brief.md
    - .kiro/specs/ios-friendship/brief.md
    - .kiro/specs/ios-hosting/brief.md
---

# iOS 安全機能と設定 Brief

## Problem

初版で自由入力を絞っても、表示名、申請、招待を通じた迷惑行為へ対処し、利用者がアプリ内で通報・ブロック・退会できる必要がある。

## Current State

設定、安全機能、通知設定、サポート、退会画面は未実装である。運営 Backend も存在しない。

## Desired Outcome

対象に近い場所から理由を選んで通報し、通報と独立してブロックできる。設定から通知、ブロック一覧、規約、プライバシー、問い合わせ、ログアウト、アカウント削除へ到達できる。削除は影響を説明し、受付と完了を区別する。

## Approach

Safety と AccountDeletion の Port を定義し、iOS は入力、影響確認、送信状態、受付状態を所有する。ブロックの横断的な予定影響は Hosting との Application 契約で表し、実サーバー処理と運営対応は対象外として明示する。

## Scope

### In

- 対象自動設定、定型理由、任意500文字の補足、重複送信防止を持つ通報シート。
- ブロック影響確認、ブロック一覧、解除しても友達関係を自動復活しない説明。
- 招待・回答・確定・取消の通知設定、任意の暇リマインダー、OS設定導線。
- 規約、プライバシー、コミュニティルール、問い合わせ、運営情報。
- 削除対象と予定影響、再認証要求、受付／処理中／完了／再試行の画面状態。

### Out

- 運営管理画面、通報 SLA の実運用、Apple token revoke、実データ削除、APNs、法令上の保持判断。

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
