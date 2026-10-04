---
type: Roadmap
title: "iOS 初版ロードマップ"
description: "暇時間のOR管理と友達への実招待・回答までの仕様分割"
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

暇時間を本人が予定を入れたい時間として扱い、重複登録はOR統合する。選択した承認済み友達全員へ実Backendで招待し、相手が部分時間を回答できる。予定の最終確定とPush配信は後続工程とする。
Backend のうちユーザーアカウント管理、友達関係、本人限定の暇時間を実 Backend 境界とし、Sign in with Apple、Supabaseセッション、プロフィール、期限付き招待コード、友達申請・承認・解除、暇枠の登録・参照・削除、アカウント削除を接続する。初回接続先は STG とし、production 環境への deploy は別工程とする。募集・Push・運営処理は引き続きプロトタイプ境界とし、実環境の複数ユーザー整合性を実装済みとは扱わない。

## Approach Decision

単一の巨大仕様ではなく、ユーザーが独立して操作・検証できる機能境界へ分割する。
共通の起動・プロフィール・3タブを先に置き、暇時間と友達を並行可能な前提機能、募集を両者の下流、安全・設定を全フローへ作用する最後の境界とする。

## Scope

- iOS 17 以降の SwiftUI / TCA クライアント。
- Sign in with Apple のクライアント境界、初期説明、プロフィール、ホーム・友達・設定の3タブ。
- 暇時間のOR統合・区間削除、友達、募集・招待・部分回答、安全機能、設定・退会の画面とクライアント状態遷移。
- 認証・プロフィール・友達関係・本人の暇・募集・回答・取消の実 Backend Adapter（初回 STG）と、未接続の主要フローを再現するDEBUG専用Prototype Adapter。
- Apple の UGC、アカウント削除、Push 非必須、プライバシー申告に関する iOS 側の導線と説明。

対象外は友達の暇の直接共有・募集照合、予定の最終確定、Push・APNs配信、友達ブロック・通報のBackend保存、運営管理画面、非同期削除Queue、正式な App Store 提出、チャット、自由投稿、位置情報、連絡先同期、カレンダー、決済、Android とする。

## 製品の共通方針

[製品方針](product.md) に従い、予定設定・調整の再入力や再選択を減らす。Siri 連携は既存の暇・募集操作への新しい入口として扱い、参加OK・予定確定や公開範囲の意味を変更しない。

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
- `ios-hosting`: 時間軸からの募集、招待・部分回答・取消、受信箱を所有する。
- `ios-safety-settings`: 通報、ブロック、通知設定、規約導線、退会のユーザー操作を所有する。
- `ios-app-integration`: Home・Inbox の読み取り投影、共有 Prototype scenario、Root Composition、全機能統合検証を所有する。
- `backend-user-account-management`: Supabase JWT検証、本人プロフィール、Apple再認証を伴うアカウント削除を所有する。
- `backend-friendship`: 招待コード、申請、相互承認、友達一覧・解除の実 API・DB を所有し、最初に STG で検証する。
- `backend-availability`: 本人限定の暇枠登録・参照・区間OR・減算を所有する。
- `backend-hosting`: 承認済み友達への実招待・受信・部分回答・取消と認可を所有する。

## Specs (dependency order)

- [x] ios-app-foundation -- 起動説明、Sign in with Apple 境界、プロフィール、3タブと共通画面状態。Dependencies: none
- [x] backend-user-account-management -- Supabase認証済み本人、プロフィール、アカウント削除。Dependencies: ios-app-foundation, ios-safety-settings
- [x] backend-friendship -- 期限付き招待コード、申請、相互承認、友達一覧・解除。Dependencies: backend-user-account-management
- [x] backend-availability -- 本人限定の暇枠登録・参照・区間OR・減算。Dependencies: backend-user-account-management, ios-availability
- [x] backend-hosting -- 承認済み友達への実招待・受信・部分回答・取消。Dependencies: backend-availability, backend-friendship
- [x] ios-availability -- ホーム時間軸と暇時間の登録・編集・公開設定。Dependencies: ios-app-foundation
- [x] ios-friendship -- 友達一覧、招待コード、申請、プロフィールのSTG実接続。Dependencies: ios-app-foundation, backend-friendship
- [x] ios-hosting -- 時間軸からの募集、実招待、部分回答、取消。Dependencies: ios-app-foundation, ios-availability, ios-friendship, backend-hosting
- [x] ios-safety-settings -- 通報、ブロック、通知設定、サポート、アカウント削除。Dependencies: ios-app-foundation, ios-friendship, ios-hosting
- [x] ios-app-integration -- 横断読み取り投影、Prototype scenario、Root Composition、統合検証。Dependencies: ios-app-foundation, ios-availability, ios-friendship, ios-hosting, ios-safety-settings

- [ ] ios-siri-actions -- Siri・ショートカットからの暇登録・区間削除、募集条件設定・作成・取消。設計生成済み。工程承認の正本は spec.json。Dependencies: ios-app-foundation, ios-availability, ios-friendship, ios-hosting

## Existing Spec Updates

- `ios-app-foundation`: Production Apple認証、セッション復元、プロフィールAPIを対象へ追加する。
- `ios-safety-settings`: fresh Apple再認証、削除API、ローカルアクセス停止を対象へ追加する。
- `ios-app-integration`: Release Compositionで認証・友達関係・暇の実 Backend Adapterを必須にし、初回接続先を STG、PrototypeをDEBUGへ限定する。
- `ios-friendship`: Release CompositionでBackend Friendship Adapterを必須にし、最初の内部 TestFlight ではコード・申請・友達をSTGへ接続する。
- `ios-ci-cd`: 製品実装と TCA 追加後も既存 build/test/TestFlight 経路が成立することを再検証する。CI/CD の責務や秘密管理契約は変更しない。

- `ios-app-integration`: Siri 操作から認証・画面へ入力を引き継ぐ Composition 契約を、Siri 要件承認後に設計・タスクへ同期する。既存実装の完了状態とは分けて管理する。

## Direct Implementation Candidates

- `docs/product/overview.md` と iOS 関連文書を、認証・プロフィール・削除・友達関係・本人の暇の実 Backend 境界（初回 STG）と、その他機能のPrototype境界へ同期する。

## 変更履歴

- 2026-09-25: TestFlight Releaseで暇登録が固定エラーを返す事象を受け、本人限定の暇登録・参照・削除を実Backend境界へ追加した。募集照合や友達向け共有は引き続き未実装。
