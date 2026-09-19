---
type: Implementation Plan
title: "Android CI/CD 実装計画"
description: "実行可能なAndroidアプリ、CI、Google Play internal track配布、運用文書を導入するタスク"
status: stable
sources:
  - id: android-ci-cd-design
    resource: ./design.md
    title: Android CI/CD 設計
kiro:
  depends_on:
    - .kiro/specs/android-ci-cd/requirements.md
    - .kiro/specs/android-ci-cd/design.md
---

# Implementation Plan

- [x] 1. 実行可能な最小Androidアプリと単体テストを追加する
  - Compose app、Gradle Wrapper、JVM単体テストをJDK 21とAndroid SDK Platform 37でbuild/testでき、targetSdk 36、Android向けbytecode 17を維持する。
  - _Requirements: 1.1, 2.1_
  - _Boundary: AndroidProject_

- [x] 2. 秘密を使わないAndroid CIを追加する
  - ローカルスクリプトとGitHub Actionsが同じlint、単体テスト、debug buildを使い、PR/mainで失敗を検出する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - _Boundary: TestScript, AndroidCI_
  - _Depends: 1_

- [x] 3. Google Play internal track配布経路を追加する
  - tag/manual trigger、Environment、署名preflight、AAB生成、Play API upload、cleanup、artifact保存が接続される。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3_
  - _Boundary: ReleaseScript, PlayUpload, AndroidCD_
  - _Depends: 1, 2_

- [x] 4. 外部設定と現行文書を同期する
  - Play Console、Google Cloud、GitHubのページ単位の手順、秘密名、確認・復旧手順と実装済み／未実装の境界が文書から確認できる。
  - _Requirements: 3.4, 4.1, 4.2, 4.3_
  - _Boundary: Runbook, ProjectDocs_
  - _Depends: 2, 3_

- [x] 5. 統合検証と安全性レビューを完了する
  - repository verify、Gradle build/test、workflow構文、差分レビューが成功し、外部資格情報が必要なuploadの未検証範囲が明記される。
  - _Requirements: 1.1, 1.2, 1.4, 2.3, 3.1, 3.2, 4.1_
  - _Boundary: IntegrationValidation_
  - _Depends: 1, 2, 3, 4_
