---
type: Brief
title: "Siri 予定・ホスト操作の探索"
description: "既存の暇時間・募集操作を音声から実行する境界"
status: stable
sources:
  - id: user-siri-low-effort
    resource: conversation://2026-10-04/siri-low-effort
    title: Siri 操作公開と予定調整の負荷最小化の依頼
kiro:
  depends_on:
    - .kiro/steering/product.md
    - .kiro/specs/ios-availability/requirements.md
    - .kiro/specs/ios-hosting/requirements.md
    - .kiro/specs/ios-friendship/requirements.md
---

# Siri 予定・ホスト操作

## Problem
予定の設定・調整に画面を開く、日時を選び直す、友達を探す負荷がある。ユーザーはこの負荷を可能な限りゼロにし、Siri へ操作を公開することを求めている。[^user-siri-low-effort]

## Current State
iOS 17 以降の SwiftUI/TCA アプリに本人の暇の登録・区間削除と、承認済み友達への募集作成・取消がある。App Intents の公開はない。予定の最終確定は現行製品の対象外。

## Desired Outcome
Siri とショートカットから日時と必要な条件を指定し、同じ業務操作を実行する。既に渡した値は聞き直さず、不足や曖昧さだけを補う。

## Approach
独立仕様 `ios-siri-actions` がシステムからの入力・対象解決・結果応答を所有する。暇や募集の業務契約は既存仕様を再利用する。App Intents は Apple の公式公開経路を採用候補とし、具体的な構成は要件承認後の設計で確定する。

## Scope
- In: 暇登録、区間削除、日時・友達・開催条件を指定する募集作成、本人の募集取消、日本語の発見導線、認証・競合・失敗からの復帰。
- Out: 予定の最終確定、カレンダー連携、自由文を独自 AI で解釈する機構、招待への自動参加、他人の暇の照会、アカウント削除、Push 公開。

## Boundary Candidates
システム操作入口、承認済み友達と本人の募集の対象解決、既存操作への委譲、必要時の画面引継ぎ。

## Out of Boundary
Backend の認可・永続化、暇のOR統合、募集と本人暇登録の原子性、予定確定は所有しない。

## Upstream / Downstream
上流: ios-app-foundation、ios-availability、ios-friendship、ios-hosting。下流: ios-app-integration の Composition と実機検証。

## Existing Spec Touchpoints
Adjacent: ios-availability と ios-hosting の操作契約。Extends: ios-app-integration の起動・認証後の引継ぎ。新しい仕様を既存機能の別実装にしない。

## Constraints
iOS 17、日本語、既存の認証・非公開初期値・15分単位・今後14日・冪等性を維持する。負荷低減を本人の意思の推測で代替しない。

[^user-siri-low-effort]: 2026-10-04 のユーザー依頼。「ユーザー不可」は文脈から「ユーザー負荷」と解釈した。
