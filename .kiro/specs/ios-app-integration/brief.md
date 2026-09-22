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
    - .kiro/steering/roadmap.md
    - .kiro/specs/ios-app-foundation/design.md
    - .kiro/specs/ios-availability/design.md
    - .kiro/specs/ios-friendship/design.md
    - .kiro/specs/ios-hosting/design.md
    - .kiro/specs/ios-safety-settings/design.md
---

# iOS アプリ統合 Brief

## Problem

Home は Availability と Hosting、統合受信箱は Friendship と Hosting、ブロックと削除は複数機能へ作用するが、集約投影とプロトタイプ整合性の所有者がない。

## Current State

各機能の独立 Port、Root Composition、共有 fixture、横断 read model、reset、統合テストがある。Release Composition は認証・プロフィール・削除を Production Adapter へ接続し、その他の業務機能だけを未接続または DEBUG Prototype 境界として残している。

## Desired Outcome

機能間の静的依存や業務データの重複を増やさず、Composition が各 Adapter を共通 scenario へ接続し、Home・Inbox・プロフィールへ read-only 投影を供給する。ブロック・削除後は影響投影を原子的に更新して再取得できる。

## Approach

Composition 配下の `HimatchPrototypeScenario` actor を未接続業務機能のプロトタイプ整合性境界とし、各機能 Adapter へ facet を注入する。認証・プロフィール・削除は Production Adapter を標準とする。UI集約は `AppProjectionRepository` が読み取り DTO として提供し、変更は所有機能の UseCase だけが行う。

## Scope

### In

- 共有 Prototype scenario、fixture seed/reset、機能 Adapter facet。
- Home、統合 Inbox、友達プロフィールの読み取り投影。
- Root Store と全機能 Navigation 合成。
- ブロック・削除後の横断 fixture 更新と統合テスト。

### Out

- 友達・暇・募集の本番 Backend トランザクション、Push、運営処理、業務 DB。

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
