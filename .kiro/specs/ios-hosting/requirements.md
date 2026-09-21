---
type: Requirements
title: "iOS 募集・招待・予定要件"
description: "募集作成、非公開照合、参加回答、予定確定、受信箱の要件"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
kiro:
  depends_on:
    - .kiro/specs/ios-hosting/brief.md
    - .kiro/specs/ios-availability/requirements.md
    - .kiro/specs/ios-friendship/requirements.md
---

# Requirements Document

## Introduction

ホストが友達と候補期間を指定し、条件が重なる相手へ招待し、参加者が明示的に選んだ時間だけを回答し、ホストが全回答者との共通時間から予定を確定する。

## Boundary Context

- **In scope**: 募集作成、招待・回答・確定・取消・離脱の iOS 状態、受信箱、漏えいしないレスポンス表示。
- **Out of scope**: サーバー認可、常時マッチング、実 Push、自由投稿、場所・URL、Backend API 実装。
- **Adjacent expectations**: Availability と Friendship を参照し、Safety のブロック結果を確定前契約で再確認する。

## Requirements

### Requirement 1: 募集作成

**Objective:** As a ホスト, I want 内容・時間・友達を確認して募集を始めたい, so that 意味が変わらない条件で回答を集められる

#### Acceptance Criteria

1. The iOS app shall 内容と時間、友達、確認の3段階で募集を作成する
2. The iOS app shall オンライン／オフライン、任意の定型カテゴリ、今後14日内の候補期間、15分単位の必要時間、承認済み友達を指定できるようにし、オフラインでは定義済みエリアまたは「あとで相談」を選べるようにする
3. When 必要時間を初めて入力する, the iOS app shall 1時間を初期値にする
4. If ホストの暇が候補期間にない, the iOS app shall 本人に知らせず暇枠を作らず、Availability の登録へ移動できるようにする
5. When 募集開始を確認した, the iOS app shall 条件が重なる友達へ招待することと非公開設定の相手の配信有無を表示しないことを説明する
6. While 募集中である, the iOS app shall 日時・必要時間・開催形態の意味変更を許可せず取消して作り直す導線を提供する

### Requirement 2: 非公開照合の表示契約

**Objective:** As a 友達, I want 暇登録の有無をホストに推測されたくない, so that 非公開のまま招待を受け取れる

#### Acceptance Criteria

1. The iOS app shall 募集開始結果に配信人数、非公開設定の配信対象、非該当理由、友達の暇登録状況を表示しない
2. The iOS app shall ホストへ「募集を開始しました。参加OKの回答があると表示されます」と表示する
3. The iOS app shall 招待の既読、未承認の初回辞退、回答しない理由をホストへ表示しない
4. Where 暇枠が募集時共有である, the iOS app shall `sharedAvailability` 投影として Backend が返した友達 ID と募集条件との重複部分だけを該当ホストへ表示し、非公開招待者の配信対象と混在させない
5. The iOS app shall 候補者がゼロでも非公開情報を理由に募集失敗と表示しない

### Requirement 3: 招待への回答

**Objective:** As a 招待された人, I want 自分で選んだ時間だけ参加 OK と回答したい, so that 暇登録が自動的な参加意思にならない

#### Acceptance Criteria

1. When 未回答の招待を開いた, the iOS app shall 主催者、開催形態、カテゴリ、自分が回答可能な候補時間、具体的な期限を表示する
2. The iOS app shall 候補を初期選択せず、利用者が選んだ時間だけを回答として送る
3. Before 参加 OK を送る, the iOS app shall 選択時間と表示名が主催者へ伝わり確定後は参加者へ表示されることを説明する
4. While 募集中である, the iOS app shall 回答時間の変更と回答撤回を許可する
5. When 初回に見送った, the iOS app shall ホストへ辞退者名を表示する更新を生成しない
6. If 期限切れまたは過去の候補である, the iOS app shall 回答操作を停止する

### Requirement 4: ホストによる確定

**Objective:** As a ホスト, I want 参加 OK の全員が参加できる一つの日時を確定したい, so that アプリ内で日程調整を終えられる

#### Acceptance Criteria

1. When 参加 OK の回答がある, the iOS app shall 回答者名、承認時間、全回答者とホストの共通候補を表示する
2. If 全員の共通候補がない, the iOS app shall 回答変更または募集の作り直しへ誘導する
3. Before 確定操作を送る, the iOS app shall 日時と参加者を再表示する
4. When 確定を送る, the iOS app shall 最新回答、ブロック、アカウント状態、予定重複を version とともに再確認する Port を呼ぶ
5. If 確定中に状態が変わった, the iOS app shall 最新状態を再取得して再確認を求める
6. The iOS app shall ホストと友達1人未満の予定を確定しない

### Requirement 5: 募集・回答・予定の状態遷移

**Objective:** As a 参加者, I want 役割と状態に合う操作だけを見たい, so that 取消や離脱を誤らない

#### Acceptance Criteria

1. The iOS app shall 募集を下書き、募集中、確定、取消、期限切れとして表示する
2. The iOS app shall 回答を未回答、参加OK、見送り、撤回として表示する
3. When ホストが確定予定を取り消した, the iOS app shall 取消状態を表示して参加者に必要な更新を受信箱で示す
4. When 参加者が確定予定から離脱した, the iOS app shall 最新状態を取得し、ホストだけになった予定を取消として表示する
5. The iOS app shall 暇枠の削除と回答撤回、確定予定の取消・離脱を別操作にする
6. The iOS app shall 集合場所や接続先は普段の連絡手段で確認する案内を確定画面へ表示する

### Requirement 6: 受信箱と Push 非依存

**Objective:** As a 利用者, I want Push がなくても必要な操作を見つけたい, so that 通知権限を許可せず利用できる

#### Acceptance Criteria

1. The iOS app shall 募集招待、回答更新、確定、取消を要対応、進行中、終了に分けて表示し、友達申請との統合は app integration の投影へ委譲する
2. When Push または一覧項目を開いた, the iOS app shall 最新状態と閲覧権限を取得してから詳細を表示する
3. If 退会、ブロック、期限切れ、権限喪失で操作できない, the iOS app shall 機密情報を表示せず必要最小限の理由を示す
4. The iOS app shall Push を主要状態の正本にせず、拒否されても回答・確定まで進める

### Requirement 7: 冪等性と競合

**Objective:** As a 利用者, I want 連打や通信再送で状態が二重化しないことを期待する, so that 募集・回答・確定を信頼できる

#### Acceptance Criteria

1. The iOS app shall 募集開始、回答、確定、取消、離脱へ一意な operationID と expectedVersion を送る
2. While 操作を送信中である, the iOS app shall 同じ主操作の重複送信を防ぐ
3. If transport の結果が不明である, the iOS app shall 同じ operationID で状態照会または再試行する
4. The iOS app shall Prototype Adapter の結果をサーバー認可、漏えい防止、同時実行の合格証拠として扱わない
