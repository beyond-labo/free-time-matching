---
type: Requirements
title: "Backend 友達招待要件"
description: "暇時間に基づく実招待とプライバシーを保った回答"
status: stable
sources:
  - id: user-hosting-20260926
    resource: conversation://2026-09-26/availability-hosting-invitations
    title: 暇時間と友達招待に関する確定指示
kiro:
  depends_on:
    - .kiro/specs/backend-hosting/brief.md
    - .kiro/specs/backend-availability/requirements.md
    - .kiro/specs/backend-friendship/requirements.md
---

# Requirements Document

## Introduction

本人が予定を入れたい候補時間へ承認済み友達を誘い、相手の明示的な回答を実 Backend に保存する。招待先の暇登録は配信条件に使わない。

## Boundary Context

- **In scope**: 招待作成、本人暇との原子的な整合、本人・受信者の一覧と詳細、部分回答、辞退、取消、期限、認可。
- **Out of scope**: 予定確定、Push、友達の暇の公開、グループ管理。
- **Adjacent expectations**: Availability は本人の暇のOR統合と区間削除を所有し、Friendship は承認済み関係を所有する。

## Requirements

### Requirement 1: 認証と招待先

**Objective:** As a ホスト, I want 選んだ友達だけを安全に誘いたい, so that 暇の有無によらず予定を提案できる

#### Acceptance Criteria

1. When 招待 API を呼んだ, the Backend shall Supabase access token を検証し、ホストを JWT subject から確定する
2. When 招待先を指定した, the Backend shall `{ type: "friend", id }` の重複しない対象だけを受け、各対象との承認済み友達関係を検証する
3. When 招待を作成した, the Backend shall 選んだ承認済み友達全員へ、相手の暇登録と公開設定の有無に関係なく招待を保存する
4. If 対象に未承認・解除済み・本人・不存在の利用者が含まれる, the Backend shall 招待と本人の暇を一件も変更せず、安全なエラーを返す

### Requirement 2: 募集の作成と本人暇

**Objective:** As a ホスト, I want 選んだ時間にまとめて招待したい, so that 暇登録の有無で失敗しない

#### Acceptance Criteria

1. The Backend shall 候補区間を UTC の半開区間、15分境界、現在から14日以内として検証し、オンライン／オフライン、任意の定型カテゴリとエリアを受け取る
2. When 招待を作成した, the Backend shall 候補区間を本人の暇へOR統合し、募集と全招待先の保存を同一トランザクションで確定する
3. When 作成が成功した, the Backend shall 候補区間だけを募集中の範囲として保持し、開始時刻を回答期限とする
4. When 同じ actor と operation ID で再送した, the Backend shall 募集と暇を重複作成せず同じ操作結果を返す
5. If 入力、友達関係、DB処理が失敗した, the Backend shall 暇だけ、または招待の一部だけを残さない

### Requirement 3: 受信と公開範囲

**Objective:** As a 利用者, I want 自分に関係する募集だけを見たい, so that 他人の暇や回答を知られない

#### Acceptance Criteria

1. The Backend shall 一覧・詳細をホスト本人または招待された本人へ限定し、第三者へ募集の存在を明かさない
2. The Backend shall 受信者へホストの最小プロフィール、候補区間、開催形態、カテゴリ、エリア、本人の回答状態だけを返し、回答期限は返却した候補開始時刻から一意に導けるようにする
3. The Backend shall ホストへ自分の募集と参加OKした友達の名前・回答区間だけを返し、未回答者、辞退者、既読、友達の暇登録状況を返さない
4. The Backend shall 受信者間で互いの回答や招待状態を公開しない

### Requirement 4: 回答

**Objective:** As a 招待された友達, I want 参加できる一部だけを回答したい, so that 自分の意思が正確に伝わる

#### Acceptance Criteria

1. When 受信者が参加OKを送る, the Backend shall 本人が選んだ一つ以上の15分単位の区間を候補範囲内として保存する
2. When 受信者が辞退した, the Backend shall 回答状態を保存し、ホスト向け投影へ辞退者を含めない
3. The Backend shall 回答だけで受信者の一般的な暇時間を登録または変更しない
4. If 募集が取消済み、期限切れ、または expectedVersion が現在と異なる, the Backend shall 回答を変更せず競合を返す
5. When 同じ操作IDを再送した, the Backend shall 回答を二重更新しない

### Requirement 5: 取消と暇削除の境界

**Objective:** As a ホスト, I want 募集を明示的に取り消したい, so that 暇の編集と招待状態が混同されない

#### Acceptance Criteria

1. When ホストが current version で取消した, the Backend shall 募集を取消状態とし受信者の回答を停止する
2. If 募集中の候補区間に重なる本人暇の区間削除を要求した, the Database shall 暇を変更せず拒否する
3. When 募集取消後に同じ暇削除を要求した, the Backend shall Availability の通常の区間減算を許可する
4. The Backend shall 取消によって本人の暇や受信者の回答履歴を暗黙に削除しない

### Requirement 6: 検証と観測

**Objective:** As a 開発者, I want 認可と並行操作の根拠を確認したい, so that Prototype の動作を実環境の保証と誤認しない

#### Acceptance Criteria

1. The project shall Worker route test、DB/RLS test、型検査、build を分けて実施する
2. The project shall 別利用者の参照・操作、非友達への招待、同時再送、回答競合、募集中削除拒否を検証する
3. The Backend shall token、友達の暇、辞退状態、候補区間を通常ログへ記録しない
