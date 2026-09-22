---
type: Implementation Plan
title: "iOS CI/CD 実装計画"
description: "実行可能な iOS ターゲット、CI、TestFlight 配布、運用文書を導入するタスク"
status: stable
sources:
  - id: ios-ci-cd-design
    resource: ./design.md
    title: iOS CI/CD 設計
kiro:
  depends_on:
    - .kiro/specs/ios-ci-cd/requirements.md
    - .kiro/specs/ios-ci-cd/design.md
---

# Implementation Plan

- [x] 1. 実行可能な最小 iOS アプリとテストを追加する
  - SwiftUI app、AppIcon、Swift Testing、shared scheme を Xcode 26.6 で build/test でき、iOS テストは XCTest に依存しない。
  - _Requirements: 1.1, 1.5, 2.1_
  - _Boundary: iOSProject_

- [x] 2. 署名不要の iOS CI を追加する
  - ローカルスクリプトと GitHub Actions が同じ shared scheme を使い、PR/main で秘密なしに失敗を検出する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - _Boundary: TestScript, IOSCI_
  - _Depends: 1_

- [x] 3. TestFlight 配布経路を追加する
  - annotated tag／現在のmainに限定したmanual trigger、同一commitのtestとrelease、Environment、公開アプリ設定、preflight、署名、IPA export、API key upload、cleanup、artifact保存が接続される。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.3_
  - _Boundary: ReleaseScript, IOSCD_
  - _Depends: 1, 2_

- [x] 4. 外部設定と現行文書を同期する
  - Apple Developer、App Store Connect、GitHub のページ単位の手順、秘密名、確認・復旧手順と、実装済み／未実装の境界が文書から確認できる。
  - _Requirements: 3.4, 4.1, 4.2, 4.3_
  - _Boundary: Runbook, ProjectDocs_
  - _Depends: 2, 3_

- [x] 5. 統合検証と安全性レビューを完了する
  - repository verify、Swift Testing 専用検査、workflow 構文、Xcode build/test、差分レビューが成功し、外部資格情報が必要な upload の未検証範囲が明記される。
  - _Requirements: 1.1, 1.2, 1.4, 1.5, 2.3, 3.1, 3.2, 4.1_
  - _Boundary: IntegrationValidation_
  - _Depends: 1, 2, 3, 4_
