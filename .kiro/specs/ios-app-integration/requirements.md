---
type: Requirements
title: "iOS アプリ統合要件"
description: "横断投影、共有プロトタイプ状態、Root Composition、統合検証の要件"
status: stable
sources:
  - id: ios-spec-cross-review
    resource: conversation://2026-09-20/ios-spec-cross-review
    title: iOS 初版仕様間レビュー
kiro:
  depends_on:
    - .kiro/specs/ios-app-integration/brief.md
---

# Requirements Document

## Introduction

各機能の所有権を維持しながら、Home、受信箱、プロフィール、ブロック・削除の横断表示とプロトタイプ動作を一つの Composition で統合する。

## Requirements

### Requirement 1: 横断読み取り投影

**Objective:** As a 利用者, I want 一つの画面で関連する状態を見たい, so that 機能間を行き来しても矛盾しない

#### Acceptance Criteria

1. The iOS app shall Home に自分の暇と確定予定を所有元 ID 付きの読み取り投影として表示する
2. The iOS app shall 統合受信箱に友達申請と Hosting 更新を要対応・進行中・終了として表示する
3. The iOS app shall 友達プロフィールにその友達との確定予定 ID を読み取り投影として提供する
4. The iOS app shall 投影からの変更操作を所有機能の Navigation / UseCase へ委譲する

### Requirement 2: 共有プロトタイプ整合性

**Objective:** As a 開発者, I want 一貫した複数ユーザー fixture で主要フローを再現したい, so that Backend前でも画面と状態遷移を検証できる

#### Acceptance Criteria

1. The prototype shall 一つの actor scenario が profile、availability、friendship、hosting、safety、deletion の fixture を直列化する
2. When block または account deletion を適用した, the prototype shall 関係、未確定回答、確定予定、受信箱を同じ actor transaction で更新する
3. The prototype shall 各機能 Adapter に必要な facet だけを渡し、Reducer から scenario へ直接アクセスさせない
4. The prototype shall テストごとに既知 seed へ reset できる
5. The iOS app shall Prototype 結果を本番認可・並行性・Push・削除完了の証拠として表示または報告しない

### Requirement 3: Root Composition と統合検証

**Objective:** As a 開発者, I want 全機能を一つの Store とテスト経路で組み立てたい, so that target membership や Navigation の未接続を検出できる

#### Acceptance Criteria

1. The AppCompositionRoot shall 全 Adapter、UseCase、Reducer を生成して Root Store へ注入する
2. The iOS app shall ホーム・友達・設定と各詳細を所有 ID / delegate action で遷移させる
3. The repository verification shall filesystem-synchronized app/test group、TCA 1.26.1、Package.resolved、entitlements の存在と整合を検査する
4. The integration tests shall デモ開始、暇登録、友達確認、募集、回答、確定、通報、ブロック、削除受付の主要経路を fixture で検証する
5. The repository verification shall iOSテストがSwift Testingを使用し、XCTestのimportまたはXCTestCase継承を含まないことを検査する
6. The AppCompositionRoot shall Releaseで認証・プロフィール・削除・Friendship・本人の暇時間の実Backend Adapterを注入し、DEBUGの明示的なデモだけでPrototype Adapterを使用する
7. The integration tests shall セッション復元、未設定プロフィール、ログアウト、削除後アクセス停止を検証する
8. The AppCompositionRoot shall 最初の内部TestFlightでbuild-time configurationからSTG SupabaseとSTG APIを選択する
9. The integration tests shall Release構成の暇登録が固定エラーを返さず、認証済み利用者のBackend応答で成功・失敗を判定することを検証する
10. When 認証済み利用者のプロフィールを取得してメイン画面へ遷移した, the iOS app shall 友達情報と本人の暇時間を並行して読み込み、各領域に読み込み中・失敗・再試行を表示し、片方の完了をもう片方や画面操作の条件にしない
