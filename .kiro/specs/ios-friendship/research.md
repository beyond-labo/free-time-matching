---
type: Research
title: "iOS 友達関係調査"
description: "友達状態、コード秘匿、隣接機能境界の設計判断"
status: stable
sources:
  - id: apple-app-privacy
    resource: https://developer.apple.com/app-store/app-privacy-details/
    title: App privacy details
kiro:
  depends_on:
    - docs/product/overview.md
    - docs/architecture/api-contracts.md
---

# 調査と設計判断

## Summary

- 友達グラフをサーバー保存する場合、Privacy Nutrition Label の Contacts に含まれ得る。
- コードエラーはクライアントでも分類を潰し、存在探索の手掛かりを表示しない。
- Safety と Hosting は delegate で接続し、Friendship が横断挙動を所有しない。

## Design Decisions

### Decision: 単一の関係状態を投影する

- **Selected Approach**: pendingIncoming / pendingOutgoing / friends を同じ ID と version を持つ状態から表示する。
- **Rationale**: 競合時に複数リスト間の二重所属を防ぐ。

### Decision: コード失敗を共通表示にする

- **Rationale**: 無効、期限、存在、ブロックの差を利用者探索へ使わせない。

## Risks & Mitigations

- Prototype がコードの安全性を証明してしまう — UI 契約のみと文書化し、Backend 要件を別途必要とする。
- Release が空の `Production Placeholder` を使いコード未発行になる — `backend-friendship` の実 Backend Adapter を注入し、最初は STG、DEBUG デモだけ Prototype を使う。
- 解除で予定が消える — Hosting への delegate を表示して別操作にする。

## Change Log

- 2026-09-20: ユーザーの友達追加・管理・公開制約を新規仕様へ反映。
- 2026-09-23: `BackendFriendshipAdapter`、友達状態の Reducer/UI、旧 session 応答の破棄、手動再読込、権限喪失時の詳細画面 dismiss を実装。署名検査 13 件と Swift Testing 33 件を iPhone 17 Pro Max Simulator で確認。STG 実アカウント smoke は未実施。
- 2026-09-23: 実装依頼と `Production Placeholder` の調査に基づき、`backend-friendship` を上流に追加し、最初の内部 TestFlight は STG の実 Backend へ接続する方針に更新。
