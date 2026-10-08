---
type: Implementation Plan
title: "Siri 操作公開の実装タスク"
description: "操作サービス、Apple 連携、共通 runtime、画面引継ぎと検証"
status: stable
sources:
  - id: siri-design
    resource: ./design.md
    title: Siri 操作公開設計
kiro:
  depends_on:
    - .kiro/specs/ios-siri-actions/requirements.md
    - .kiro/specs/ios-siri-actions/design.md
---

# Implementation Plan

- [x] 1. Apple の公式契約と独立レビューを設計へ統合する
  - App Intent、Query、Shortcuts、認証、iOS17と新OSのAPI差を公式資料とSDKで照合する。Opus 5.5 の設計レビューで重要指摘を解消する。
  - _Requirements: 1.1, 1.3, 4.2, 5.4, 5.5_
  - _Boundary: SystemActions design_

- [x] 2. 入力モデル・操作準備・安全な実行と再送を実装する
  - 日時・属性統合・最新対象・本人一致を検証し、確認前は書き込まない。送信前に保護記録を保存し、同じID・payloadの再送と競合後の新規操作を分離する。
  - 単体テストで無効日時、日付またぎ、連鎖属性、認証・退会停止、結果不明・重複送信を検証する。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 3.4, 3.6, 3.7, 3.8, 4.1, 4.3, 4.4, 4.5, 5.1, 5.2, 5.3, 5.6_
  - _Depends: 1_
  - _Boundary: SystemActionService, models, journal_

- [x] 3. 本人束縛の共通実依存と明示属性を接続する
  - Store と Intent が実Adapter構成を共有し、送信時に本人の一致を検証する。募集カテゴリと本人暇カテゴリ未選択を分離する。
  - Adapterテストで明示nil属性の維持とアカウント切替の誤送信防止を検証する。Debug通常起動は実Adapter、デモの明示開始だけPrototypeを注入することを検証する。
  - _Requirements: 2.2, 2.3, 3.4, 4.1, 4.3, 5.3_
  - _Depends: 1, 2_
  - _Boundary: AppRuntime, AppCompositionRoot, HimatchClient, Hosting Adapter_

- [x] 4. 4操作を Siri とショートカットへ公開する
  - 日本語フレーズ、パラメータ、固定選択、本人限定Entity Query、同名解決、まとめ確認、ロック検査、結果の日本語応答を実装する。iOS 18以降はSiri内確認、iOS 17の募集送信・取消は準備済み入力を保存して既存アプリ内確認へ引き継ぐ。
  - 2026-10-07: 非推奨API呼出しを除去し、MCP Debug/Releaseは警告0件、関連回帰20件成功。iOS 17実機復帰はタスク7に残す。
  - iOS17以降でAPI availabilityとmetadata抽出をビルドで検証する。Entityの同名、ロック時候補ゼロ、別本人の複合ID拒否を単体テストする。
  - _Requirements: 1.1, 1.2, 1.3, 2.6, 3.1, 3.2, 3.3, 3.5, 4.2, 4.4, 4.5, 5.1_
  - _Depends: 2, 3_
  - _Boundary: AppIntents, entities, AppShortcutsProvider_

- [x] 5. 認証・属性選択・再試行の画面引継ぎを統合する
  - cold/warm launch、認証後、scene再activeで入力を復元する。別本人へ引き継がず、成功後は暇・募集を再取得する。
  - Rootテストで再入力不要、二重通知、同一操作再試行、サインアウト時失効を検証する。
  - _Requirements: 1.2, 1.4, 2.3, 2.5, 3.2, 4.1, 4.3, 5.1, 5.2, 5.3, 5.6_
  - _Depends: 2, 3, 4_
  - _Boundary: Handoff, AppFeature, AppView, SystemActionReviewView_

- [x] 6. ビルド・回帰検証・独立レビューと仕様同期を完了する
  - supabase DBテストで期限経過後のcreate再送、version更新後のcancel再送、異なるpayload拒否、union/subtract窓外再送を検証する。
  - Swift Testing、Debug/Releaseビルド、metadata抽出、Simulator起動を検証し、実装レビューの重要指摘を修正する。
  - Siri仕様、App Integration、Hosting、横断文書へ実装の契約と証拠を同期し、未実施の実機検証を完了と混同しない。
  - _Requirements: 1.1, 1.4, 3.7, 4.1, 4.2, 4.3, 4.4, 4.5, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_
  - _Depends: 2, 3, 4, 5_
  - _Boundary: cross-feature integration, supabase replay verification_

- [ ] 7. 実機で日本語 Siri とショートカットの成立を確認する
  - 4操作、同名・複数友達、ロック・認証、確認、foreground引継ぎ、成功・失敗を入口別・OS別に記録する。
  - 実機が利用できなければ未実施と不足手順を明記し、このタスクを完了にしない。
  - _Requirements: 5.4, 5.5_
  - _Depends: 6_
  - _Boundary: physical-device verification_

## 検証状態

2026-10-04: 設計レビューと実装・Swift Testing 146件・DB pgTAP 71件の確認済み証拠を記録したが、初回Opus実装NO-GOのP1-1〜4でタスク2/4/5を再評価し、修正後MCP155件成功・0失敗とコード意味照合に基づいて再完了とした。タスク1/3の受け入れ証拠も維持する。タスク6のRelease/Simulator/独立実装レビューは進行中、タスク7の実機日本語Siri・Shortcutsは未実施。仕様の同期状態や工程承認はこれらの検証完了を意味しない。
