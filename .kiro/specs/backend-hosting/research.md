---
type: Research
title: "Backend 友達招待調査"
description: "既存の空白と今回の契約判断"
status: stable
sources:
  - id: user-hosting-20260926
    resource: conversation://2026-09-26/availability-hosting-invitations
    title: 暇時間と友達招待に関する確定指示
kiro:
  depends_on:
    - .kiro/specs/backend-availability/design.md
    - .kiro/specs/backend-friendship/design.md
---

# 調査と設計判断

## Summary

着手時の Release の募集操作は固定エラーの Placeholder に接続され、DBに招待がなかった。今回、本人の暇と友達関係を利用する募集 RPC・Worker API・iOS 接続を追加した。ローカル DB の pgTAP と Worker テストは通過した。STG 反映後の2アカウント実機確認は未実施である。

## Design Decisions

### Decision: 暇と募集を原子的に作成する

- **Selected Approach**: DB RPC 内で本人暇OR統合と募集・招待先の保存を確定する。
- **Rationale**: 未登録時間からの招待で、暇だけまたは招待だけが残る状態を防ぐ。

### Decision: 招待先の暇を配信条件にしない

- **Selected Approach**: 選んだ承認済み友達全員へ送信し、回答した一部の時間だけをホストへ公開する。
- **Rationale**: 本人の予定希望と参加意思を分け、受信者の非公開情報を漏らさない。

## Change Log

- 2026-09-26: ユーザーの計画承認により、実Backendで招待・受信・部分回答までを対象とし、最終予定確定は後続に分離した。
- 2026-09-27: 招待・回答・取消を別レコードと RPC で実装。友達行ロック、本人暇との原子的統合、役割別投影、再送・version 競合を Worker/pgTAP で確認した。STG の送受信確認は残る。
- 2026-09-27: クロス仕様レビューにより、作成レスポンスは `{ hosting }` のみで本人暇は別途再取得する契約へ記述を修正。回答期限は別フィールドを返さず候補開始時刻から導出する。
