---
type: Requirements
title: "Backend 友達関係要件"
description: "STG の実 Backend における招待コード発行、申請、相互承認、友達管理の要件"
status: stable
sources:
  - id: backend-friendship-brief
    resource: ./brief.md
    title: Backend 友達関係 Brief
kiro:
  depends_on:
    - .kiro/specs/backend-friendship/brief.md
    - .kiro/specs/ios-friendship/requirements.md
    - .kiro/specs/backend-user-account-management/requirements.md
---

# Requirements Document

## Introduction

認証済みかつプロフィール設定済みの利用者が、期限付き招待コードと相互承認を通じてまず STG 環境で友達関係を作成・管理できるようにする。iOS の接続先は build-time configuration に従い、今回 production 環境へ deploy しない。

## Boundary Context

- **In scope**: コード発行・解決・再発行、申請送信・承認・拒否・取消、一覧、解除、認証・認可・競合処理。
- **Out of scope**: 全ユーザー検索、連絡先同期、ブロック・通報保存、募集、Push、運営処理。
- **Adjacent expectations**: User がプロフィールと削除状態を、iOS Friendship が利用者操作を、Safety がブロックを所有する。

## Requirements

### Requirement 1: 招待コードの発行と秘匿

**Objective:** As a 利用者, I want 自分専用の期限付きコードを取得したい, so that 公開検索を使わず既知の相手へ共有できる

#### Acceptance Criteria

1. When プロフィール設定済みの認証利用者が初めて友達 snapshot を取得した, the Friendship API shall 有効期限付きの招待コードを自動発行して返す
2. When 利用者がコードを再発行した, the Friendship API shall 以前の有効コードを同一トランザクションで失効させ新しいコードを返す
3. The Friendship API shall 招待コードを暗号学的乱数から生成し、ログとエラー応答へ平文コードを含めない
4. If コードが無効、期限切れ、失効済み、存在しない、自己所有、または利用不可である, the Friendship API shall 理由を区別しない共通エラーを返す
5. If プロフィール未設定またはアカウント削除処理中である, the Friendship API shall コードを発行しない

### Requirement 2: コード解決と申請

**Objective:** As a 利用者, I want コードの相手を確認して申請したい, so that 意図した相手にだけ友達申請を送れる

#### Acceptance Criteria

1. When 有効な他者コードを解決した, the Friendship API shall 相手の user ID、表示名、プリセットアイコンだけを返す
2. When 解決済み相当の有効コードで申請を送信した, the Friendship API shall 送信者と受信者を JWT とコードから確定し pending 申請を一件作成する
3. If 同じ二者間に pending 申請または友達関係がある, the Friendship API shall 二重の申請または友達関係を作成しない
4. When 同一 operation ID の送信を再試行した, the Friendship API shall 同じ結果を返し状態を重複更新しない
5. The Friendship API shall 受信申請と送信申請を区別し、相手の最小プロフィールと version を snapshot に含める

### Requirement 3: 申請状態の遷移

**Objective:** As a 利用者, I want 受信申請を判断し送信申請を取り消したい, so that 自分の意思で友達関係を確定できる

#### Acceptance Criteria

1. When 受信者が current version の申請を承認した, the Friendship API shall 申請を accepted に更新し一意な友達関係を同一トランザクションで作成する
2. When 受信者が current version の申請を拒否した, the Friendship API shall 申請を rejected に更新し友達関係を作成しない
3. When 送信者が current version の申請を取り消した, the Friendship API shall 申請を cancelled に更新する
4. If 操作者、状態、または expected version が最新状態と一致しない, the Friendship API shall 状態競合を返し最新 snapshot の再取得を要求する
5. When 同一 operation ID の承認・拒否・取消を再試行した, the Friendship API shall 状態を二重更新しない

### Requirement 4: 友達一覧と解除

**Objective:** As a 利用者, I want 成立済み友達を確認して解除したい, so that 現在の関係を管理できる

#### Acceptance Criteria

1. When 利用者が友達 snapshot を取得した, the Friendship API shall 成立済み友達を相手の最小プロフィールと relation version 付きで返す
2. The Friendship API shall 友達の暇、オンライン状態、最終アクセス、友達の友達を返さない
3. When 当事者が current version の友達関係を解除した, the Friendship API shall その関係を削除し以後の snapshot から除外する
4. When 同一 operation ID の解除を再試行した, the Friendship API shall 同じ完了結果を返す
5. If 当事者でない利用者が申請または友達関係を操作した, the Friendship API shall 対象の存在を明かさず操作を拒否する

### Requirement 5: STG iOS 接続

**Objective:** As a STG iOS 利用者, I want 実 Backend のコードと友達状態を操作したい, so that Prototype に依存せず友達を追加できる

#### Acceptance Criteria

1. When STG を指す Release Composition が認証済みプロフィールを読み込んだ, the iOS app shall access token 付きで友達 snapshot を取得し発行済みコードを表示する
2. When iOS 利用者がコードを確認して申請した, the iOS app shall operation ID と expected version を必要な操作へ渡しサーバー結果後に表示を更新する
3. When iOS 利用者が承認・拒否・取消・解除・再発行した, the iOS app shall 多重操作を防ぎ成功後の snapshot を表示する
4. If API がコード利用不可を返した, the iOS app shall 相手の存在や状態を区別しない共通エラーを表示する
5. If API が競合を返した, the iOS app shall 最新 snapshot を再取得し再確認を促す
6. The delivery workflow shall 最初の内部 TestFlight の `SUPABASE_URL` と `API_BASE_URL` を staging Project と staging API に向ける
