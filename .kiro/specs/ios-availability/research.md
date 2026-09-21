---
type: Research
title: "iOS 暇時間調査"
description: "日時表現、重複、ホーム表示境界の設計判断"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
kiro:
  depends_on:
    - docs/architecture/api-contracts.md
    - docs/architecture/ios-architecture.md
---

# 調査と設計判断

## Summary

- 絶対時刻の半開区間と表示タイムゾーンを分ける。
- 15分の離散マスを永続表現にせず、区間を Domain の正本とする。
- ホームは本人の暇と確定予定だけを集約し、友達の暇を導入しない。

## Design Decisions

### Decision: 半開区間を採用する

- **Selected Approach**: `[start, end)`。
- **Rationale**: 連続する枠を重複扱いせず、照合の共通部分を一貫して計算できる。

### Decision: 公開範囲の広い値を継承しない

- **Selected Approach**: 新規枠は常に `privateUntilAccepted`。
- **Rationale**: 操作回数より誤公開防止を優先する。

## Risks & Mitigations

- DST / timezone 変更 — Calendar で表示だけ変換し、保存は絶対時刻。
- Home が Hosting データを所有する — 確定予定は表示用契約だけ受け取り、ライフサイクルは Hosting に残す。

## Change Log

- 2026-09-20: ユーザー提示の時間・公開ルールを新規仕様へ反映。
