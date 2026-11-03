---
type: Brief
title: "iOS アプリ統合"
description: "横断読み取り投影、共有プロトタイプ状態、Root Composition を所有する"
status: stable
sources:
  - id: ios-spec-cross-review
    resource: conversation://2026-09-20/ios-spec-cross-review
    title: iOS 初版仕様間レビュー
kiro:
  depends_on:
    - .kiro/specs/automatic-friend-scheduling/requirements.md
    - .kiro/steering/roadmap.md
    - .kiro/specs/ios-app-foundation/design.md
    - .kiro/specs/ios-availability/design.md
    - .kiro/specs/ios-friendship/design.md
    - .kiro/specs/ios-hosting/design.md
    - .kiro/specs/ios-safety-settings/design.md
---

## 第一段階での適用（2026-10-30）

AutomaticSchedulingの実Clientを共通認証へ注入し、起動/foreground/受信箱で再取得する。旧session・旧revisionの応答を捨てる。Home/Inbox/友達/設定へ提案・確定予定・許可を投影し、新機能の業務状態を所有元Reducerへ集約する。

新しい受け入れ条件と実装タスクは [自動提案・予定成立](../automatic-friend-scheduling/requirements.md) と [その実装計画](../automatic-friend-scheduling/tasks.md) を正本とする。既存タスクのチェックは記載された既存契約の証拠であり、新しい提案・確定・通知・安全の達成を示さない。


# iOS アプリ統合 Brief

## Problem

Home は Availability と Hosting、統合受信箱は Friendship と Hosting、ブロックと削除は複数機能へ作用するが、集約投影とプロトタイプ整合性の所有者がない。

## Current State

各機能の独立 Port、Root Composition、共有 fixture、横断 read model、reset、統合テストがある。Release Composition は認証・プロフィール・削除・Friendship・本人の暇時間・Hosting を実 Backend Adapter へ接続し、最初の内部 TestFlight は STG を向く。AutomaticSchedulingの提案・実確定予定・許可・安全操作も実Adapterへ接続する。旧Hostingの確定fixtureはDEBUGに限定し、実環境E2Eと配信検証は別に記録する。

## Desired Outcome

機能間の静的依存や業務データの重複を増やさず、Composition が各 Adapter を共通 scenario へ接続し、Home・Inbox・プロフィールへ read-only 投影を供給する。ブロック・削除後は影響投影を原子的に更新して再取得できる。

## Approach

Composition 配下の `HimatchPrototypeScenario` actor を未接続業務機能のデモ境界とし、各機能 Adapter へ facet を注入する。認証・プロフィール・削除・Friendship・本人の暇時間・Hosting・AutomaticSchedulingは実Backend Adapterを標準とする。UI集約は読み取り投影を使い、変更は所有機能に委譲する。

## Scope

### In

- 共有 Prototype scenario、fixture seed/reset、機能 Adapter facet。
- Home、統合 Inbox、友達プロフィールの読み取り投影。
- Root Store と全機能 Navigation 合成。
- ブロック・削除後の横断 fixture 更新と統合テスト。

### Out

- 暇・募集の実 Backend トランザクションと API 自体、Push、運営処理。Root Composition は両 Adapter の注入を所有する。

## Boundary Candidates

- HimatchPrototypeScenario、AppProjectionRepository、AppCompositionRoot、MainTab integration tests。

## Out of Boundary

各機能の業務規則を再実装せず、所有機能の Port / Policy を呼ぶ。

## Upstream / Downstream

- Upstream: 新規5仕様すべて。
- Downstream: iOS Simulator 統合テストと将来の API Composition。

## Existing Spec Touchpoints

- Extends: ios-app-foundation の Composition。
- Adjacent: ios-ci-cd の build/test。

## Constraints

- Integration 以外の機能は他機能の Presentation / Infrastructure を import しない。
- Prototype 成功を Backend 安全性の証拠にしない。
