---
type: Requirements
title: "iOS 募集・招待要件"
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

ホストが暇登録と同じ時間軸で候補を選び、選択した承認済み友達全員へ招待し、相手が明示的に選んだ一部の時間だけを回答する。予定の最終確定は後続工程とする。

## Boundary Context

- **In scope**: 募集作成、実Backend招待・回答・取消の iOS 状態、受信箱、漏えいしないレスポンス表示。
- **Out of scope**: 予定の最終確定・離脱、常時マッチング、実 Push、自由投稿、場所・URL。
- **Adjacent expectations**: Availability と Friendship を参照し、Safety のブロック結果を確定前契約で再確認する。

## Requirements

### Requirement 1: 募集作成

**Objective:** As a ホスト, I want 内容・時間・友達を確認して募集を始めたい, so that 意味が変わらない条件で回答を集められる

#### Acceptance Criteria

1. The iOS app shall 暇登録と同じ時間軸のタップ・長押しドラッグと範囲調整で候補を選び、友達と開催条件を確認して募集を作成する
2. The iOS app shall オンライン／オフライン、任意の定型カテゴリ、今後14日内の15分単位の候補区間、承認済み友達を指定できるようにし、オフラインでは定義済みエリアまたは「あとで相談」を選べるようにする
3. The iOS app shall 必要時間の入力を求めず、選択した候補区間をそのまま送る
4. If ホストの暇が候補区間の全部または一部にない, the iOS app shall 募集開始と同じ成功・失敗単位で本人の暇へOR登録する
5. When 募集開始を確認した, the iOS app shall 選んだ承認済み友達全員へ相手の暇登録の有無に関係なく招待することを説明する
6. While 募集中である, the iOS app shall 候補日時・開催形態の意味変更を許可せず取消して作り直す導線を提供する
7. The iOS app shall 登録済み暇の詳細と友達プロフィールからも同じ時間軸の招待操作へ進め、プロフィールからはその友達を選択済みにする

### Requirement 2: 非公開照合の表示契約

**Objective:** As a 友達, I want 暇登録の有無をホストに推測されたくない, so that 非公開のまま招待を受け取れる

#### Acceptance Criteria

1. The iOS app shall 募集開始結果に配信人数、非公開設定の配信対象、非該当理由、友達の暇登録状況を表示しない
2. The iOS app shall ホストへ「募集を開始しました。参加OKの回答があると表示されます」と表示する
3. The iOS app shall 招待の既読、未承認の初回辞退、回答しない理由をホストへ表示しない
4. The iOS app shall 友達の暇登録や共有設定を招待の送信条件・ホスト向け結果として表示しない
5. The iOS app shall 候補者がゼロでも非公開情報を理由に募集失敗と表示しない

### Requirement 3: 招待への回答

**Objective:** As a 招待された人, I want 自分で選んだ時間だけ参加 OK と回答したい, so that 暇登録が自動的な参加意思にならない

#### Acceptance Criteria

1. When 未回答の招待を開いた, the iOS app shall 主催者、開催形態、カテゴリ、自分が回答可能な候補時間、候補開始時刻から導出した具体的な回答期限を表示する
2. The iOS app shall 候補を初期選択せず、利用者が選んだ時間だけを回答として送る
3. Before 参加 OK を送る, the iOS app shall 選択時間と表示名が主催者へ伝わり確定後は参加者へ表示されることを説明する
4. While 募集中である, the iOS app shall 回答時間の変更と回答撤回を許可する
5. When 初回に見送った, the iOS app shall ホストへ辞退者名を表示する更新を生成しない
6. If 期限切れまたは過去の候補である, the iOS app shall 回答操作を停止する
7. The iOS app shall 回答時間を15分単位で候補の一部から選ばせ、参加OKまたは辞退を送れるようにし、回答だけで一般の暇時間を増やさない

### Requirement 4: 後続工程へ移管した予定確定

旧 4.1–4.6 の確定条件は今回の実Backend招待の完成条件から外す。予定確定の仕様を別途承認したときに再導入し、現行 Release で実装済みと表示しない。

### Requirement 5: 募集・回答・予定の状態遷移

**Objective:** As a 参加者, I want 役割と状態に合う操作だけを見たい, so that 取消や離脱を誤らない

#### Acceptance Criteria

1. The iOS app shall 募集を下書き、募集中、取消、期限切れとして表示し、募集中の候補範囲だけを一般の暇と区別する
2. The iOS app shall 回答を未回答、参加OK、見送り、撤回として表示する
3. When ホストが募集を取り消した, the iOS app shall 取消状態を受信者にも示し、本人の暇は残す
4. If 暇削除範囲が募集中の候補と重なる, the iOS app shall 削除を止めて募集取消へ案内する
5. The iOS app shall 暇枠の削除と回答撤回、募集取消を別操作にする

### Requirement 6: 受信箱と Push 非依存

**Objective:** As a 利用者, I want Push がなくても必要な操作を見つけたい, so that 通知権限を許可せず利用できる

#### Acceptance Criteria

1. The iOS app shall 募集招待、回答更新、取消を要対応、進行中、終了に分けて表示し、友達申請との統合は app integration の投影へ委譲する
2. When Push または一覧項目を開いた, the iOS app shall 最新状態と閲覧権限を取得してから詳細を表示する
3. If 退会、ブロック、期限切れ、権限喪失で操作できない, the iOS app shall 機密情報を表示せず必要最小限の理由を示す
4. The iOS app shall Push を主要状態の正本にせず、拒否されても回答まで進める

### Requirement 7: 冪等性と競合

**Objective:** As a 利用者, I want 連打や通信再送で状態が二重化しないことを期待する, so that 募集・回答・確定を信頼できる

#### Acceptance Criteria

1. The iOS app shall 募集開始、回答、取消へ一意な operationID を送り、既存状態の変更には expectedVersion も送る
2. While 操作を送信中である, the iOS app shall 同じ主操作の重複送信を防ぐ
3. If transport の結果が不明である, the iOS app shall 同じ operationID で状態照会または再試行する
4. The iOS app shall Prototype Adapter の結果をサーバー認可、漏えい防止、同時実行の合格証拠として扱わない
