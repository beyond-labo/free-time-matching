---
type: Brief
title: "Backend 友達招待"
description: "本人の暇時間に基づく招待の送信、受信、回答、取消"
status: stable
sources:
  - id: user-hosting-20260926
    resource: conversation://2026-09-26/availability-hosting-invitations
    title: 暇時間と友達招待に関する確定指示
kiro:
  depends_on:
    - .kiro/specs/backend-availability/requirements.md
    - .kiro/specs/backend-friendship/requirements.md
---

# Backend 友達招待 Brief

## Problem

Release では募集作成が未接続で失敗し、招待が相手へ届かない。Prototype の募集は一つの端末内だけに保存される。

## Current State

本人の暇と友達関係には認証済み Backend がある。Hosting の実 API と DB はなく、iOS の画面は独立した日時フォームを用いる。

## Desired Outcome

ホストが時間軸で選んだ時間に承認済み友達全員を誘い、相手が受信箱で参加できる一部の時間を回答できる。ホストには参加OKだけが見え、募集中の範囲は一般の暇と区別できる。

## Approach

Hosting を Availability、Friendship と別の所有境界にする。作成時の本人暇OR統合と招待保存、回答、取消、募集中範囲の削除判定を DB トランザクションで確定する。

## Scope

### In

- 認証済み友達への全件招待、本人暇の原子的な登録、受信、部分区間の参加OK、辞退、取消、期限切れ。
- 本人・招待相手ごとの読み取り投影、操作ID再送、version競合、RLS、DBとWorkerの検証。

### Out

- 最終予定の確定、Push配信、友達の暇の照合やホストへの公開、グループの作成・管理。

## Upstream / Downstream

- Upstream: backend-availability、backend-friendship、backend-user-account-management。
- Downstream: ios-hosting、ios-availability、ios-app-integration。

## Constraints

- 暇登録、招待への参加OK、予定確定は別の意思表示とする。
- 選択した友達の暇登録の有無を招待の送信条件にしない。
- 将来のグループ追加に備え、招待先を型付き target として受け取る。
