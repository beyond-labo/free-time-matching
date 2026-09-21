---
type: Research
title: "iOS アプリ統合調査"
description: "機能間依存、読み取り投影、プロトタイプ整合性の設計判断"
status: stable
sources:
  - id: ios-spec-cross-review
    resource: conversation://2026-09-20/ios-spec-cross-review
    title: iOS 初版仕様間レビュー
kiro:
  depends_on:
    - .kiro/steering/roadmap.md
---

# 調査と設計判断

## Summary

- Home / Inbox / FriendProfile は複数所有データを表示するため、単一機能へ吸収すると循環する。
- 読み取り投影と変更 UseCase を分けることで業務データの二重所有を避けられる。
- 共有 prototype は Composition のみに置き、各機能へ facet を注入する。

## Design Decisions

### Decision: App integration を独立仕様にする

- **Alternatives Considered**: Foundation へ全状態を集約、各機能が相互 import、別々の fixture。
- **Selected Approach**: read model と shared scenario を下流 Integration が所有する。
- **Rationale**: 依存循環と fixture 不整合を避け、Production Adapter 交換点を保つ。

## Risks & Mitigations

- prototype が巨大な本番モデルになる — デモ専用とし、本番では API projection を使用する。
- actor 一つが並行性挙動を隠す — 本番の競合・冪等性は Backend 検証対象として別扱いにする。

## Change Log

### 2026-09-21

ユーザーのiOSテスト戦略に合わせ、単体・Reducer・統合テストをSwift Testingへ統一した。`xcodebuild test`と既存test targetは維持し、repository verifyとCIでXCTestのimport・継承の再混入とテスト0件を拒否する。

- 2026-09-20: 独立仕様間レビューの Critical 指摘を受けて新規作成。
