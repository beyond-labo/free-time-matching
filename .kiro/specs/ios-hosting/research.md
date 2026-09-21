---
type: Research
title: "iOS 募集・招待・予定調査"
description: "時間照合、プライバシー projection、状態競合の設計判断"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
kiro:
  depends_on:
    - docs/architecture/api-contracts.md
    - .kiro/specs/ios-availability/design.md
    - .kiro/specs/ios-friendship/design.md
---

# 調査と設計判断

## Summary

- 暇枠、参加回答、確定予定は異なる意思表示・整合性境界である。
- ホスト向け response 自体から配信人数・辞退者・登録有無を除く必要がある。
- iOS は operationID / expectedVersion を扱えるが、冪等性・認可の保証は Backend が所有する。

## Design Decisions

### Decision: 役割別画面ではなく共通詳細を使う

- **Selected Approach**: HostingDetailFeature が role と lifecycle から表示状態を導く。
- **Rationale**: 同じ状態の重複実装と遷移ずれを避ける。

### Decision: Host detail は参加 OK の投影だけを受け取る

- **Alternatives Considered**: 全 invitee 状態、UI だけで非表示。
- **Rationale**: API に不要情報を含めず、推測と実装事故を減らす。

### Decision: Prototype と本番保証を分離する

- **Rationale**: 単一端末 fixture はサーバーのアクセス制御、並行性、Push を検証できない。

## Risks & Mitigations

- 複数機能の fixture 不整合 — Composition が単一 actor store を各 Prototype Adapter へ注入する。
- 交差計算とサーバー候補のずれ — Domain tests を共有契約へ反映し、最終確定は server preflight を正本にする。
- 辞退通知から漏えい — 初回見送りを host projection へ含めない。

## Change Log

- 2026-09-20: ユーザー提示の募集、回答、確定、漏えい防止、受信箱要件を新規仕様へ反映。
