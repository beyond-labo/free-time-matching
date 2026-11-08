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
    - .kiro/specs/automatic-friend-scheduling/requirements.md
    - .kiro/specs/ios-app-integration/brief.md
---

## 第一段階での適用（2026-10-30）

AutomaticSchedulingの実Clientを共通認証へ注入し、起動/foreground/受信箱で再取得する。旧session・旧revisionの応答を捨てる。Home/Inbox/友達/設定へ提案・確定予定・許可を投影し、新機能の業務状態を所有元Reducerへ集約する。

新しい受け入れ条件と実装タスクは [自動提案・予定成立](../automatic-friend-scheduling/requirements.md) と [その実装計画](../automatic-friend-scheduling/tasks.md) を正本とする。既存タスクのチェックは記載された既存契約の証拠であり、新しい提案・確定・通知・安全の達成を示さない。


# Requirements Document

## Introduction

各機能の所有権を維持しながら、Home、受信箱、プロフィール、ブロック・削除の横断表示とプロトタイプ動作を一つの Composition で統合する。

## Requirements

### Requirement 1: 横断読み取り投影

**Objective:** As a 利用者, I want 一つの画面で関連する状態を見たい, so that 機能間を行き来しても矛盾しない

#### Acceptance Criteria

1. The iOS app shall Home に自分の暇を所有元 ID 付きの読み取り投影として表示し、AutomaticSchedulingの提案と確定予定を実Backendの読み取り投影として表示し、旧Hostingの確定fixtureだけDEBUGに限定する。区分の順序と案内は [ios-first-match-flow](../ios-first-match-flow/requirements.md) Requirement 2・3 に従う
2. The iOS app shall 統合受信箱に友達申請・AutomaticSchedulingの提案/確定/取消と、既存Hosting更新を要対応・進行中・終了として表示し、入口に未対応の友達申請・未回答の提案・未回答のお誘い・未読の参加OKの合計件数を表示する
3. The iOS app shall 友達プロフィールからAutomaticSchedulingの実確定予定を確認・取消できるようにし、旧Hostingの確定fixtureと区別する
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
4. The integration tests shall DEBUG のデモ開始（友達なし・友達あり）、暇登録、友達確認、自動提案の許可・提案・双方の参加OKによる確定、募集、回答、デモ友達の参加OKと受け取り表示、確定、通報、ブロック、削除受付の主要経路を fixture で検証し、旧Hostingのfixture確定をReleaseの提供機能として扱わず、自動提案の実確定は別の実契約試験で検証する
5. The repository verification shall iOSテストがSwift Testingを使用し、XCTestのimportまたはXCTestCase継承を含まないことを検査する
6. The AppCompositionRoot shall Releaseで認証・プロフィール・削除・Friendship・本人の暇時間・Hosting・AutomaticSchedulingの実Backend Adapterを注入し、DEBUGの明示的なデモだけでPrototype Adapterを使用する
7. The integration tests shall セッション復元、未設定プロフィール、ログアウト、削除後アクセス停止を検証する
8. The AppCompositionRoot shall 最初の内部TestFlightでbuild-time configurationからSTG SupabaseとSTG APIを選択する
9. The integration tests shall Release構成の暇登録が固定エラーを返さず、認証済み利用者のBackend応答で成功・失敗を判定することを検証する
10. When 認証済み利用者のプロフィールを取得してメイン画面へ遷移した, the iOS app shall 友達情報と本人の暇時間を並行して読み込み、各領域に読み込み中・失敗・再試行を表示し、片方の完了をもう片方や画面操作の条件にしない
11. When 認証済み利用者が受信箱を開いた, the iOS app shall 実Backendから本人の募集と招待を取得し、別アカウントで作成された招待へ部分回答できる
12. The integration tests shall Release構成の募集作成が固定Placeholderエラーを返さず、本人暇登録・招待送信・受信・回答の実Backend契約を検証する
