---
type: Requirements
title: "iOS 友達関係要件"
description: "招待コード、相互承認、友達管理、プロフィールの要件"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
kiro:
  depends_on:
    - .kiro/specs/ios-friendship/brief.md
    - .kiro/specs/ios-app-foundation/requirements.md
---

# Requirements Document

## Introduction

既知の相手とだけ、期限付き招待コードと相互承認によって友達関係を作り、申請・友達・プロフィールを管理する。

## Boundary Context

- **In scope**: コード表示・入力、プロフィール確認、申請、承認・拒否・取消、友達解除、プロフィール上の操作導線。
- **Out of scope**: 全ユーザー検索、連絡先同期、QR必須化、ブロックの横断効果、募集作成。
- **Adjacent expectations**: Safety が通報・ブロックを、Hosting が友達選択を所有する。

## Requirements

### Requirement 1: 友達一覧と申請状態

**Objective:** As a 利用者, I want 成立済み友達と申請を区別して確認したい, so that 関係状態を誤認しない

#### Acceptance Criteria

1. The iOS app shall 承認済み友達、受信申請、送信申請を別の区分で表示する
2. The iOS app shall 暇の有無、オンライン状態、最終アクセスで友達を並べ替えたり表示したりしない
3. If 各区分にデータがない, the iOS app shall 通信失敗と区別した空状態を表示する
4. When 受信申請を承認または拒否した, the iOS app shall サーバー応答後に該当状態を更新する
5. When 送信申請を取り消した, the iOS app shall 二重操作を防ぎ結果を一度だけ反映する

### Requirement 2: 招待コードによる追加

**Objective:** As a 利用者, I want 招待コードで特定の相手へ申請したい, so that 公開検索なしで既知の友達を追加できる

#### Acceptance Criteria

1. The iOS app shall 自分の期限付き招待コードを表示、共有、無効化、再発行できるクライアント操作を提供する
2. When コードを入力した, the iOS app shall 相手の表示名とプリセットアイコンを確認してから申請を送信する
3. If コードが無効、期限切れ、存在しない、またはブロックにより利用不可である, the iOS app shall 相手の存在や状態を区別して推測できない共通エラーを表示する
4. The iOS app shall カメラ権限や連絡先権限を友達追加の必須条件にしない

### Requirement 3: 友達プロフィールと解除

**Objective:** As a 利用者, I want 友達を確認して関係操作へ進みたい, so that 誘い、安全操作、解除を対象に近い場所から行える

#### Acceptance Criteria

1. When 友達プロフィールを開いた, the iOS app shall 表示名、プリセットアイコン、友達を誘う、通報、ブロック、友達解除を表示する
2. The iOS app shall 友達の一日の暇一覧と友達の友達一覧を表示しない
3. When 友達解除を確認した, the iOS app shall 新しい招待と共有が停止することを説明して解除 Port を呼ぶ
4. Where その友達との確定予定がある, the iOS app shall 予定が暗黙に消えないことと Hosting の離脱導線を表示する
5. If プロフィール権限を失った, the iOS app shall 詳細を残さず友達一覧へ戻す

### Requirement 4: 競合とプライバシー

**Objective:** As a 利用者, I want 再送や状態変化で不整合を起こしたくない, so that 友達関係が二重作成されない

#### Acceptance Criteria

1. The iOS app shall 申請・承認・拒否・取消・解除に一意な操作識別子または version を付けて Port へ渡す
2. If 最新状態と競合した, the iOS app shall 最新一覧を取得し直して結果を再確認させる
3. The iOS app shall 友達グラフのサーバー保存が App Store の Contacts データ分類に該当し得ることをプライバシー文書・申告タスクへ渡す

### Requirement 5: STG 実 API 接続

**Objective:** As a STG 利用者, I want 実 Backend の友達状態を端末間で共有したい, so that DEBUG fixture に依存せず友達を追加できる

#### Acceptance Criteria

1. When 認証済みプロフィールでメイン画面へ進んだ, the iOS app shall access token 付きで Backend Friendship snapshot を取得する
2. When 有効な招待コードがまだない, the iOS app shall Backend が自動発行したコードを取得して表示する
3. When コード確認、申請、承認、拒否、取消、解除、再発行を行った, the iOS app shall Backend 応答後の snapshot を表示する
4. If Backend がコード利用不可を返した, the iOS app shall 原因を区別しない共通エラーを表示する
5. If Backend が version conflict を返した, the iOS app shall snapshot を再取得して再確認を促す
6. While DEBUG デモを利用している, the iOS app shall Backend Friendship に接続せず再現可能な Prototype snapshot を使用する
7. The iOS app shall 接続先を build-time configuration から取得し、最初の内部 TestFlight では staging Supabase と staging API を使用する
