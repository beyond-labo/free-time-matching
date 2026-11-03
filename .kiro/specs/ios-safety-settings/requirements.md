---
type: Requirements
title: "iOS 安全機能・設定要件"
description: "通報、ブロック、通知、サポート、アカウント削除の要件"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
  - id: apple-review-guidelines
    resource: https://developer.apple.com/app-store/review/guidelines/
    title: App Review Guidelines
  - id: apple-account-deletion
    resource: https://developer.apple.com/support/offering-account-deletion-in-your-app
    title: Offering account deletion in your app
kiro:
  depends_on:
    - .kiro/specs/automatic-friend-scheduling/requirements.md
    - .kiro/specs/ios-safety-settings/brief.md
    - .kiro/specs/ios-hosting/requirements.md
---

## 第一段階での適用（2026-10-30）

自動提案・予定と友達プロフィールの定型通報/ブロックを実Backendへ接続する。匿名相手は提案IDから解決する。既存Prototypeの任意補足やblock一覧を実保存・実提供されたと表示しない。ブロック/退会でpendingと未来予定を停止する。通知許可・device登録とAPNs配送はAutomaticScheduling/Notificationへ委譲する。

新しい受け入れ条件と実装タスクは [自動提案・予定成立](../automatic-friend-scheduling/requirements.md) と [その実装計画](../automatic-friend-scheduling/tasks.md) を正本とする。既存タスクのチェックは記載された既存契約の証拠であり、新しい提案・確定・通知・安全の達成を示さない。


# Requirements Document

## Introduction

利用者が表示名・申請・招待に対する通報とブロックを対象近くから実行し、設定から通知、サポート、規約、ログアウト、アカウント削除へ到達できるようにする。

## Boundary Context

- **In scope**: iOS の通報・ブロック入力と状態、設定、通知設定、サポート文書導線、Apple再認証を伴う実アカウント削除。
- **Out of scope**: 運営管理、SLA、非同期削除Queue。APNs配信と通報・ブロックのBackend横断処理はAutomaticSchedulingが所有し、本仕様の入口から実契約へ接続する。
- **Adjacent expectations**: Backend はApple token失効とSupabase Auth user削除を所有し、iOSへ必要最小限の削除状態だけ返す。

## Requirements

### Requirement 1: 通報

**Objective:** As a 利用者, I want 問題の対象に近い場所から通報したい, so that IDや証拠を自分で調べず運営へ伝えられる

#### Acceptance Criteria

1. When プロフィール、友達申請、招待、募集詳細、自動提案・予定から通報を開いた, the iOS app shall 対象ユーザーまたは募集・提案を自動設定する。匿名提案は提案IDからサーバーが対象を解決し、相手IDを開示しない
2. The iOS app shall 不適切な表示名、迷惑な招待、なりすまし、嫌がらせ、その他の定型理由と定型通報を提供する。既存Prototypeの任意補足は実保存されたと表示しない
3. The iOS app shall 通報者情報を相手へ表示しないことと運営が確認することを説明する
4. When 通報が受理された, the iOS app shall 受付番号と完了を表示し任意のブロック導線を提供する
5. If 送信が失敗または結果不明である, the iOS app shall 受付済みと表示せず同じ operationID で照会・再送できるようにする

### Requirement 2: ブロック

**Objective:** As a 利用者, I want 通報と独立して相手をブロックしたい, so that 以後の関係と招待を止められる

#### Acceptance Criteria

1. The iOS app shall 通報せずブロック、ブロックせず通報の両方を許可する
2. Before ブロックを実行する, the iOS app shall 匿名の2人提案の固定効果として、友達解除、新規申請・招待停止、未確定提案と今後の確定予定の取消を確認表示し、相手の識別情報や影響IDを返す旧Prototype previewを使わない
3. When ブロックが完了した, the iOS app shall 誰が誰をブロックしたかを他の参加者へ表示しない
4. When ブロックを解除した, the iOS app shall 友達関係と以前の招待が自動復活しないことを表示する
5. When ブロックを確認した, the iOS app shall 最新の関係・提案・予定に同じ固定効果を原子的に適用し、成功応答のsnapshotから再取得する。結果不明なら同じ操作IDで再試行する
6. When ブロックが完了した, the iOS app shall Backendの最新snapshotと所有機能の再読込で各投影を更新し、友達解除、未確定回答無効化、今後の招待停止、確定予定の離脱または取消結果を表示する

### Requirement 3: 通知設定と Push 非必須

**Objective:** As a 利用者, I want 必要な通知だけ選びたい, so that Pushを拒否してもアプリを利用できる

#### Acceptance Criteria

1. The iOS app shall 自動提案、確定、取消の通知許可を変更できるようにする
2. The iOS app shall 暇登録リマインダーを初期オフにし、有効化時だけ曜日・時刻を設定する
3. The iOS app shall 通知拒否後に繰り返し許可を迫らず、OS通知設定への明示的な導線を提供する
4. The iOS app shall Push 許可をログイン、受信箱、回答、確定の利用条件にしない
5. The iOS app shall 通知プレビュー例に日時、相手名、暇時間などの機密情報を含めない
6. If 通知設定の保存に失敗した, the iOS app shall OS の許可状態とアプリ内購読設定を混同せず、入力を保持して再試行を提供する

### Requirement 4: 設定とサポート

**Objective:** As a 利用者, I want アカウント・安全・支援情報へ一か所から到達したい, so that 問題時にも自己解決または連絡できる

#### Acceptance Criteria

1. The iOS app shall 設定にプロフィール、ログアウト、アカウント削除、通知、問い合わせ、利用規約、プライバシー、コミュニティルール、バージョン、運営情報を表示する
2. While 利用停止中である, the iOS app shall 問い合わせ、ログアウト、アカウント削除への到達を維持する
3. The iOS app shall 実際に連絡可能な問い合わせ先をアプリ内と公開 Support URL の準備事項として示す
4. The iOS app shall 友達グラフを Contacts / linked to user / App Functionality として申告する引継ぎをプライバシー文書へ残す

### Requirement 5: アカウント削除

**Objective:** As a 利用者, I want アプリ内から退会を開始したい, so that アカウントと関連データを削除できる

#### Acceptance Criteria

1. When 削除画面を開いた, the iOS app shall プロフィール・暇・友達・未確定回答の削除、主催予定の取消、参加予定からの離脱、セッション失効を説明する
2. The iOS app shall 主催中の予定を理由に削除を拒否しない
3. The iOS app shall 削除理由、追加の電話番号・メール登録、サポート連絡を必須にしない
4. When freshなApple再認証が成功して削除を実行した, the iOS app shall authorization codeと冪等キーを削除Portへ送り、受付時点でSupabaseセッションと端末アクセスを停止する
5. Where 削除処理に時間がかかる, the iOS app shall 受付番号、所要期間、処理中、完了、再試行状態を区別する
6. If Apple token revoke または後続削除が一時失敗した, the iOS app shall アクセス停止済みの受付を成功前へ戻さず、状況照会と再試行状態を表示する
7. The iOS app shall 既に閲覧された情報やスクリーンショットまで消せるとは説明しない

### Requirement 6: 入力制限と運営境界

**Objective:** As a 運営者, I want 自由入力を最小化して是正対象を特定したい, so that 初版の安全運用を実行できる

#### Acceptance Criteria

1. The iOS app shall 他人へ表示する自由入力を1〜20文字の表示名に限定し、カテゴリ・アイコン・エリアは定義済み値だけ送る
2. The iOS app shall 通報補足を他の利用者へ表示しない
3. The iOS app shall 通報対象 ID、募集 ID、理由、operationID を運営 Port へ送る
4. The iOS app shall 運営による非表示・利用停止を受信した場合に安全な代替表示へ更新する
