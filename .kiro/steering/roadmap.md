---
type: Roadmap
title: "iOS 初版ロードマップ"
description: "非公開の暇時間から友達との予定確定までを実現する iOS 初版の仕様分割"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
kiro:
  depends_on:
    - docs/product/overview.md
    - docs/architecture/ios-architecture.md
    - docs/architecture/api-contracts.md
---

# iOS 初版ロードマップ

## Overview

暇時間を常時公開せず、招待への参加承認を境界として友達との予定を成立させる iOS 初版を実装する。
Backend の公開契約は未実装のため、iOS は機能別 Port とプロトタイプ Adapter で画面・入力・状態遷移を検証可能にし、サーバー認可、複数ユーザー整合性、Push 配信、運営処理を実装済みとは扱わない。

## Approach Decision

単一の巨大仕様ではなく、ユーザーが独立して操作・検証できる機能境界へ分割する。
共通の起動・プロフィール・3タブを先に置き、暇時間と友達を並行可能な前提機能、募集を両者の下流、安全・設定を全フローへ作用する最後の境界とする。

## Scope

- iOS 17 以降の SwiftUI / TCA クライアント。
- Sign in with Apple のクライアント境界、初期説明、プロフィール、ホーム・友達・設定の3タブ。
- 暇時間、友達、募集・招待・回答・確定予定、安全機能、設定・退会の画面とクライアント状態遷移。
- Backend 未接続でも主要フローを再現するプロトタイプ Adapter と、後続 API Adapter が満たす Port。
- Apple の UGC、アカウント削除、Push 非必須、プライバシー申告に関する iOS 側の導線と説明。

対象外は Backend API・DB・認可、APNs 配信、運営管理画面、実データ削除ジョブ、正式な App Store 提出、チャット、自由投稿、位置情報、連絡先同期、カレンダー、決済、Android とする。

## Constraints

- 暇登録、参加 OK、予定確定を別の意思表示として扱う。
- 非公開情報の漏えい防止はサーバー責務であり、プロトタイプ表示だけを安全性の検証証拠にしない。
- Push を拒否しても受信箱から主要フローを完了できる。
- 画面のタップ領域は 44 x 44pt を一般基準とし、15分枠を小さなマスだけで操作させない。
- TCA と Clean Architecture の既存依存方向を維持する。
- iOS の単体・Reducer・統合テストは Swift Testing で記述し、XCTest を import または継承しない。

## Boundary Strategy

- `ios-app-foundation`: 起動、認証境界、プロフィール、3タブ、共通状態、Composition の入口。
- `ios-availability`: 自分の暇時間とホーム時間軸。公開ポリシーの選択を所有する。
- `ios-friendship`: 招待コード、友達申請、友達一覧、プロフィール操作を所有する。
- `ios-hosting`: 募集、照合結果のクライアント表現、招待回答、確定予定、受信箱を所有する。
- `ios-safety-settings`: 通報、ブロック、通知設定、規約導線、退会のユーザー操作を所有する。
- `ios-app-integration`: Home・Inbox の読み取り投影、共有 Prototype scenario、Root Composition、全機能統合検証を所有する。

## Specs (dependency order)

- [x] ios-app-foundation -- 起動説明、Sign in with Apple 境界、プロフィール、3タブと共通画面状態。Dependencies: none
- [x] ios-availability -- ホーム時間軸と暇時間の登録・編集・公開設定。Dependencies: ios-app-foundation
- [x] ios-friendship -- 友達一覧、招待コード、申請、プロフィール。Dependencies: ios-app-foundation
- [x] ios-hosting -- 募集作成、招待、回答、確定予定、進行中一覧。Dependencies: ios-app-foundation, ios-availability, ios-friendship
- [x] ios-safety-settings -- 通報、ブロック、通知設定、サポート、アカウント削除。Dependencies: ios-app-foundation, ios-friendship, ios-hosting
- [x] ios-app-integration -- 横断読み取り投影、Prototype scenario、Root Composition、統合検証。Dependencies: ios-app-foundation, ios-availability, ios-friendship, ios-hosting, ios-safety-settings

## Existing Spec Updates

- `ios-ci-cd`: 製品実装と TCA 追加後も既存 build/test/TestFlight 経路が成立することを再検証する。CI/CD の責務や秘密管理契約は変更しない。

## Direct Implementation Candidates

- `docs/product/overview.md` と iOS 関連文書を、初版仕様とプロトタイプ／Backend 未実装の境界へ同期する。
