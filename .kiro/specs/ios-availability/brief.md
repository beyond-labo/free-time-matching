---
type: Brief
title: "iOS 暇時間"
description: "ホームのリスト・カレンダーで暇と募集中候補を確認し、暇をOR登録・区間削除する"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
kiro:
  depends_on:
    - .kiro/steering/roadmap.md
    - .kiro/specs/ios-app-foundation/brief.md
---

# iOS 暇時間 Brief

## Problem

利用者が予定を入れたい時間を友達へ常時公開せずに登録する。重複は一つの暇として扱い、一部だけ消したり友達を誘った範囲を区別したりする操作が必要である。

## Current State

時間モデル、ホーム時間軸、登録画面、公開設定、本人限定Backend接続は存在する。Backend には本人区間のOR統合・区間減算と募集中削除guardを追加した。iOS の時間軸からのOR登録・区間削除・募集導線と、0.1.7のリスト初期表示・カレンダー切替は実装済みで、既存枠の内容編集保存は別途未実装である。

## Desired Outcome

今後14日を初期表示のリストで確認し、明示的にカレンダーへ切り替えて、表示中の日時から15分単位・初期2時間の暇をOR登録し、選択した区間だけを複数枠から削除できる。新規枠は「参加OKするまで非公開」を初期値とし、募集時共有との違いを理解できる。募集中の候補部分だけを一般の暇と区別する。

## Approach

Availability の Domain / Application / Infrastructure / Presentation を feature-first に置き、絶対時刻と表示タイムゾーンを分離する。ホームは自分の暇と募集中候補を区別して扱い、他人の暇は表示しない。確定予定は DEBUG Prototype に限る。

## Scope

### In

- 14日間のリスト初期表示と日・週カレンダーへの切替、今日へ戻る操作、表示日時の固定。
- 15分単位、初期2時間、日付またぎ、過去時刻防止、重複・接続する暇のOR統合。
- 定型カテゴリ、非公開／募集時共有、OR登録・区間削除、募集中の部分投影。Releaseでは本人限定Backend APIへ登録・参照・削除を接続する。
- 暇なし、通信失敗、読み込みの異なる空状態。

### Out

- 他人の暇一覧、常時公開、カレンダー同期、通知リマインダー設定。
- サーバー認可の実装自体と募集照合。サーバー認可は backend-availability が所有する。

## Boundary Candidates

- AvailabilitySlot / AvailabilityVisibility / TimeGridPolicy。
- AvailabilityRepository / AvailabilityUseCase。
- HomeTimelineFeature / AvailabilityEditorFeature。

## Out of Boundary

暇枠を参加回答や確定予定として扱わない。確定予定の変更・離脱は Hosting へ委譲する。

## Upstream / Downstream

- Upstream: ios-app-foundation。
- Downstream: ios-hosting。

## Existing Spec Touchpoints

- Adjacent: `docs/architecture/api-contracts.md` の公開 DTO 方針。

## Constraints

- 保存・比較は絶対時刻、表示は端末のタイムゾーンを明示する。
- 公開範囲を広げる選択は新規枠へ自動継承しない。
