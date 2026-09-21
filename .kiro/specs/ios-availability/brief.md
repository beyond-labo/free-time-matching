---
type: Brief
title: "iOS 暇時間"
description: "ホーム時間軸と非公開を初期値にした暇時間の登録・編集を実現する"
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

利用者が友達へ常時公開せずに暇時間を預け、後の募集照合へ使える操作がない。

## Current State

時間モデル、ホーム時間軸、登録・編集画面、公開設定は未実装である。

## Desired Outcome

今後14日を縦方向に見ながら、表示中の日時から15分単位・初期2時間の暇枠を登録、編集、削除できる。新規枠は「参加OKするまで非公開」を初期値とし、募集時共有との違いを理解できる。

## Approach

Availability の Domain / Application / Infrastructure / Presentation を feature-first に置き、絶対時刻と表示タイムゾーンを分離する。ホームは自分の暇と確定予定だけを扱い、他人の暇は表示しない。

## Scope

### In

- 14日間の縦時間軸、今日へ戻る操作、表示日時の固定。
- 15分単位、初期2時間、日付またぎ、過去時刻防止、重複警告。
- 定型カテゴリ、非公開／募集時共有、登録・編集・削除。
- 暇なし、通信失敗、読み込みの異なる空状態。

### Out

- 他人の暇一覧、常時公開、カレンダー同期、通知リマインダー設定。
- サーバー認可と募集照合。

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
