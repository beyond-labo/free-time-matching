---
type: Requirements
title: "Backend ユーザーアカウント管理要件"
description: "Apple認証済みセッション、プロフィール、アカウント削除のBackend要件"
status: stable
sources:
  - id: user-auth-management
    resource: conversation://2026-09-21/user-auth-management
    title: iOS初版のユーザー情報管理方針
kiro:
  depends_on:
    - .kiro/specs/backend-user-account-management/brief.md
    - .kiro/specs/ios-app-foundation/requirements.md
    - .kiro/specs/ios-safety-settings/requirements.md
---

# Requirements Document

## Introduction

iOS初版でSign in with Appleから得たSupabaseセッションを検証し、本人のプロフィール管理とアプリ内アカウント削除を提供する。

## Boundary Context

- **In scope**: Supabase JWT検証、本人プロフィールの取得・保存、Apple再認証を伴う削除、RLS、削除状況の取得。
- **Out of scope**: メール・パスワード認証、Android、友達・暇・募集の永続化、運営管理画面、非同期Queue。
- **Adjacent expectations**: iOSはAppleのnative認証とSupabaseセッション保存を所有し、BackendへBearer tokenを送る。将来の業務テーブルも削除受付済みアカウントを拒否する。

## Requirements

### Requirement 1: 認証済み本人の確定

**Objective:** As a 利用者, I want Appleで認証した自分のデータだけへアクセスしたい, so that 他人の識別子を指定して閲覧・変更できない

#### Acceptance Criteria

1. When 保護APIを呼び出した, the Backend shall Supabaseの公開鍵でBearer JWTの署名、issuer、audience、期限、roleを検証する
2. If tokenが欠落、不正、期限切れ、またはauthenticated roleでない, the Backend shall 業務処理を実行せず401を返す
3. The Backend shall JWTのsubjectを唯一の本人IDとして使用し、request bodyまたはpathから本人IDを受け付けない
4. The Backend shall token、Apple credential、secretを通常ログへ出力しない

### Requirement 2: プロフィール管理

**Objective:** As a 登録利用者, I want ニックネームとプリセットアイコンを保存したい, so that 本名や自由画像を登録せず利用できる

#### Acceptance Criteria

1. When 認証済み利用者が自分のプロフィールを取得した, the Backend shall 未設定または本人のnicknameとpresetIconKeyを返す
2. When 1〜20 graphemeのnicknameと許可済みpresetIconKeyを保存した, the Backend shall 本人IDへ関連付けて冪等に保存する
3. If nicknameまたはpresetIconKeyが不正である, the Backend shall 保存せず項目を識別できる400応答を返す
4. The Backend shall 行レベル認可により本人以外のプロフィール読取・作成・更新を拒否する
5. The Backend shall プロフィール削除権限を通常の利用者へ付与しない

### Requirement 3: アカウント削除

**Objective:** As a 利用者, I want Appleで再認証してアカウントを削除したい, so that Supabase認証情報と関連プロフィールをアプリ内から削除できる

#### Acceptance Criteria

1. When freshなApple authorization codeと冪等キーを伴う削除要求を受けた, the Backend shall 現在のSupabase本人とApple credentialのsubjectが一致することを確認する
2. If 再認証が不正、期限切れ、または別人である, the Backend shall 削除受付へ進まず401または403を返す
3. When 削除を受理した, the Backend shall Apple token失効、Supabase Auth userのhard delete、プロフィールのcascade deleteを実行する
4. If 同じ冪等キーで削除要求を再送した, the Backend shall 重複処理せず同じ受付結果を返す
5. If Apple失効または後続削除が失敗した, the Backend shall 受付記録をactionRequiredとして保持し、通常プロフィールAPIへのアクセスを拒否する
6. The Backend shall opaqueな状況照会tokenでaccepted、processing、completed、actionRequiredを区別して取得できるようにし、生tokenは保存しない
7. The Backend shall Supabaseの特権secretとApple署名鍵を削除用Adapterだけへ注入し、通常プロフィール処理へ渡さない

### Requirement 4: データ保護と検証可能性

**Objective:** As a 開発者, I want 認証・RLS・削除境界を資格情報なしで検証したい, so that 外部サービスへ接続せず回帰を検出できる

#### Acceptance Criteria

1. The repository shall JWT失敗、本人固定、プロフィール検証、逐次・同時競合の冪等削除、別人Apple credential拒否を自動テストする
2. The database migration shall RLS、固定アイコン制約、nickname制約、Auth user削除時のプロフィールcascadeを定義する
3. The Backend shall 外部Supabase・Apple操作をPortとして差し替え可能にする
4. The repository shall 実資格情報をソース、テストfixture、Wrangler設定へ保存しない
5. When pull requestまたはmain pushを検証する, the repository shall 外部資格情報を使わず空のローカルPostgresへ全migrationを適用し、DB lintとpgTAPを実行する
6. When stagingまたはproductionへBackendを配布する, the deployment shall 対象Supabase Projectへ未適用migrationをWorkerより先に適用し、環境別の公開設定とsecretを同じWorker versionへ渡す
7. When TestFlight用Release archiveを作成する, the deployment shall `SUPABASE_URL`、publishable key、Backend API URLだけをbuild settingとして埋め込み、server secretをiOSへ渡さない
8. If migrationに破壊的変更候補が含まれる, the repository shall 承認済みcontract migrationを示す明示的なreview markerがない限りCIを失敗させる
9. When TestFlight releaseを開始する, the deployment shall 厳密なversion形式のannotated tagが`origin/main`に含まれること、または手動実行が現在の`main`であることを検証し、確定した同一commitをtestとreleaseに使う
10. The deployment shall stagingとproductionで別のSupabase CI identityとaccess tokenを使い、一方のEnvironment credentialから他方のProjectへ到達できないようにする
11. When remote Supabase環境を初期構築する, the runbook shall 東京regionの`himatch-staging`と`himatch-production`を別Projectとして作成し、Data APIを有効、自動table公開を無効、自動RLSを有効にし、Supabase Branchingを環境分離へ使わない手順を定義する
12. When remote Supabase環境を初期構築する, the runbook shall `beyond-labo-staging`と`beyond-labo-production`をFreeで分離した完成形を先に示し、既存状態にかかわらず未完了のcheckpointから再開できるように、Organization／Project作成、既存Projectのtransferによる補正、環境別Developer CI accountの招待、各accountからのclassic personal access token発行、対応するGitHub Environmentだけへの登録を画面名、選択値、確認結果とともに定義する
13. Before 実ユーザーを受け入れるApp Store公開, the runbook shall stagingをFreeのまま維持してproductionだけをProへ変更し、Plan変更後も別Organizationと別CI accountのmembershipをclassic personal access tokenの権限境界として維持する手順を定義する
