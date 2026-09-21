---
type: Requirements
title: "iOS アプリ基盤要件"
description: "登録前説明、認証境界、プロフィール、3タブ、共通状態の要件"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
  - id: apple-authentication-services
    resource: https://developer.apple.com/documentation/authenticationservices/signinwithapplebutton
    title: SignInWithAppleButton
kiro:
  depends_on:
    - .kiro/specs/ios-app-foundation/brief.md
    - docs/architecture/ios-architecture.md
---

# Requirements Document

## Introduction

iOS 初版の入口として、暇時間の非公開原則を登録前に説明し、Sign in with Apple のクライアント認証境界、初期プロフィール、ホーム・友達・設定の3タブ、共通の異常状態を実装する。

## Boundary Context

- **In scope**: 初回説明、Apple 認証 UI と Port、プロフィール、3タブ、共通画面状態、プロトタイプ利用導線。
- **Out of scope**: Apple credential のサーバー検証、実セッション発行、Backend API、Push 許可、各タブの業務機能。
- **Adjacent expectations**: 後続仕様は基盤の Navigation と Composition を利用し、プロトタイプ結果を本番認証の証拠にしない。

## Requirements

### Requirement 1: 登録前説明と認証

**Objective:** As a 初回利用者, I want 保存・共有の前提を理解してから Apple で認証したい, so that 暇時間が意図せず公開されないと判断できる

#### Acceptance Criteria

1. When アプリを未登録状態で起動した, the iOS app shall 暇時間は初期設定で友達へ表示されず参加 OK した時間だけ主催者へ伝わることを表示する
2. The iOS app shall 登録前画面から利用規約、プライバシーポリシー、問い合わせ先へ到達できるようにする
3. When 利用者が Apple 認証を開始した, the iOS app shall Apple 標準の Sign in with Apple UI から authorization code を認証 Port へ渡す
4. If サーバー認証が利用できない, the iOS app shall 認証済みと扱わず再試行可能なエラーを表示する
5. Where DEBUG プロトタイプ導線が含まれる, the iOS app shall 実 Apple 認証と区別できる表示でデモ利用を開始できるようにする

### Requirement 2: 初期プロフィール

**Objective:** As a 登録利用者, I want 本名を必須にせず表示名とアイコンを設定したい, so that 必要最小限のプロフィールで利用できる

#### Acceptance Criteria

1. The iOS app shall 生成された仮名を表示名の初期値として提示する
2. When 1〜20文字の有効な表示名とプリセットアイコンを保存した, the iOS app shall サーバー検証の成功後に初期設定を完了する
3. If 表示名が空、20文字超過、またはサーバー拒否である, the iOS app shall 項目の近くに理由を表示して入力を保持する
4. The iOS app shall 本人識別に内部 ID を用い、表示名の一致を本人確認として扱わない

### Requirement 3: 3タブと役割別遷移

**Objective:** As a 利用者, I want ホーム・友達・設定から主要操作へ移動したい, so that 主催者と参加者で別アプリを使わずに済む

#### Acceptance Criteria

1. When 初期プロフィールが完了した, the iOS app shall ホーム、友達、設定の3タブを表示する
2. The iOS app shall 各機能の詳細を共通 Navigation 境界から表示し、業務データをアプリ全体状態へ重複保持しない
3. When ログアウトした, the iOS app shall 端末内セッションを破棄して登録前画面へ戻す

### Requirement 4: 共通の画面状態とアクセシビリティ

**Objective:** As a 利用者, I want 異常状態でも次の操作を判断したい, so that 空データや権限喪失と誤認しない

#### Acceptance Criteria

1. While 読み込み中である, the iOS app shall 操作対象が確定する前に空状態を表示しない
2. If 通信が失敗した, the iOS app shall 入力を必要に応じて保持し再試行を提供する
3. If 閲覧権限を失った, the iOS app shall 詳細を残さず安全な親画面へ戻す
4. While アカウントが利用停止中である, the iOS app shall 問い合わせ、ログアウト、アカウント削除への到達を維持する
5. The iOS app shall Dynamic Type、VoiceOver、色以外の状態表現、原則44×44pt以上のタップ領域を提供する
