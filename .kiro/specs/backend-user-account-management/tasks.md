---
type: Implementation Plan
title: "Backend ユーザーアカウント管理実装計画"
description: "JWT、プロフィール、アカウント削除、DB保護の実装計画"
status: stable
sources:
  - id: backend-user-account-design
    resource: ./design.md
    title: Backendユーザーアカウント管理設計
kiro:
  depends_on:
    - .kiro/specs/backend-user-account-management/requirements.md
    - .kiro/specs/backend-user-account-management/design.md
---

# Implementation Plan

- [x] 1. Supabase JWT検証境界を実装する
  - JWKS署名、issuer、audience、期限、role、UUID subjectを検証し、失敗時に業務処理を呼ばないことを自動テストする。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 4.1, 4.3_
  - _Boundary: Auth_

- [x] 2. プロフィールAPIとRLSを実装する
  - GET/PUT `/v1/me`、1〜20 grapheme、固定アイコン、本人だけの保存、未設定応答を検証できる。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 4.1, 4.2, 4.3_
  - _Boundary: UserProfile_
  - _Depends: 1_

- [x] 3. Apple再認証とアカウント削除を実装する
  - fresh codeの交換と本人照合、Apple revoke、Supabase hard delete、逐次・同時競合の冪等受付、accepted/processing/completed/actionRequired、状況tokenを検証できる。
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 4.1, 4.3, 4.4_
  - _Boundary: AccountDeletion_
  - _Depends: 1, 2_

- [x] 4. Backend統合検証と運用設定例を完了する
  - typecheck、Workers test、dry-run buildが成功し、必要な通常変数とsecretが値なしで文書化される。
  - _Requirements: 1.4, 4.1, 4.2, 4.3, 4.4_
  - _Boundary: Composition, Operations_
  - _Depends: 1, 2, 3_

- [x] 5. Supabase CI/CDとリリース設定を実装する
  - 空DBへのmigration初期適用、DB lint、pgTAPをsecretless CIで実行する。
  - staging／productionでDB migrationをWorkerより先に適用し、protected Environmentからruntime設定を注入する。
  - TestFlight archiveへ公開Supabase／API設定だけを渡し、初回構築・通常変更・復旧・実機E2Eの手順を文書化する。
  - 初期構築の完成形とcheckpointを先に示し、既存状態にかかわらず未完了工程から再開できる手順として、staging／productionの別Free Organizationへの配置、必要な場合だけ行う既存Projectのtransfer、環境別Developer CI accountの招待、classic token発行、対応するGitHub Environmentへの登録を画面名と確認結果付きで文書化する。
  - 実ユーザー公開前にproductionだけをProへ変更し、PlanとCI権限境界を混同しない手順を文書化する。
  - 非対話migration、破壊的変更候補の機械検査、release ref由来検証、部分releaseの復旧案内を検証する。
  - _Requirements: 4.4, 4.5, 4.6, 4.7, 4.8, 4.9, 4.10, 4.11, 4.12, 4.13_
  - _Boundary: Database, Operations, Release_
  - _Depends: 1, 2, 3, 4_
