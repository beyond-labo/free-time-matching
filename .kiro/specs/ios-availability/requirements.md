---
type: Requirements
title: "iOS 暇時間要件"
description: "ホーム時間軸と非公開を初期値にした暇時間の登録・編集要件"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
  - id: user-direct-selection
    resource: conversation://2026-09-24/availability-direct-selection
    title: タップと長押しドラッグによる最小操作の暇時間入力
kiro:
  depends_on:
    - .kiro/specs/ios-availability/brief.md
    - .kiro/specs/ios-app-foundation/requirements.md
---

# Requirements Document

## Introduction

利用者が自分の今後14日間を縦時間軸で見て、15分単位の暇時間を登録・編集・削除し、枠ごとに非公開または募集時共有を選べるようにする。

## Boundary Context

- **In scope**: 自分の時間軸、暇枠、定型カテゴリ、公開設定、日時検証、空・失敗状態。
- **Out of scope**: 友達の暇表示、常時公開、サーバー認可、募集照合、確定予定の変更。
- **Adjacent expectations**: Hosting は暇枠を参照するが、参加回答と確定予定を別に所有する。

## Requirements

### Requirement 1: ホーム時間軸

**Objective:** As a 利用者, I want 今後の自分の暇と予定を時系列で見たい, so that 登録する日時を直感的に選べる

#### Acceptance Criteria

1. The iOS app shall 現在から14日先までを縦方向に移動できる時間軸として表示する
2. The iOS app shall 時間軸上に自分の暇枠と確定予定だけを表示し、友達の暇、オンライン状態、最終アクセスを表示しない
3. When 利用者が日表示の時間軸をタップした, the iOS app shall その位置を含む15分枠を画面内で選択し、編集シートを自動で開かない
4. If 暇枠がない, the iOS app shall 通信失敗と区別して登録を促す空状態を表示する
5. When 利用者が日表示の時間軸を長押しして上下へドラッグした, the iOS app shall 開始位置と現在位置を含む連続範囲を15分境界へ合わせて選択する
6. When 長押し成立前に利用者が縦方向へ移動した, the iOS app shall 範囲選択を開始せず時間軸のスクロールを優先する
7. While 範囲を選択または調整している, the iOS app shall 15分の区切り、選択範囲、開始・終了時刻、長さ、調整ハンドルを即時表示する

### Requirement 2: 暇枠の入力と検証

**Objective:** As a 利用者, I want 最小操作で正確な暇時間を登録したい, so that 詳細な予定表を作らず照合へ使える

#### Acceptance Criteria

1. When 常設の新規登録または詳細調整を開始した, the iOS app shall 時間軸から引き継いだ表示日時を15分境界へ丸め、位置指定がない場合は現在の次の15分境界を開始とし、2時間後の終了と未選択カテゴリを初期値にする
2. The iOS app shall 開始と終了を15分単位で調整し、日付またぎを許可する
3. If 終了が開始以前、開始が過去、または14日範囲外である, the iOS app shall 保存を止めて理由を表示する
4. If 新規枠が既存枠と重複する, the iOS app shall 重複を警告し既存枠の編集へ誘導する
5. The iOS app shall ゲーム、ご飯、通話、作業など定義済みカテゴリだけを送信し、未選択も許可する
6. When 時間軸上の有効な選択を確認した, the iOS app shall 明示的な登録操作だけで未選択カテゴリかつ「参加OKするまで非公開」の暇枠を保存し、詳細調整を選んだ場合は選択範囲を変更せず編集シートへ引き継ぐ
7. If 選択が過去、14日範囲外、または既存枠と重複する, the iOS app shall 選択を保持して理由をその場に表示し、登録操作を無効にする

### Requirement 3: 公開設定

**Objective:** As a 利用者, I want 暇枠ごとに共有条件を理解して選びたい, so that 暇登録と参加承認を混同しない

#### Acceptance Criteria

1. When 新規枠を作成した, the iOS app shall 「参加OKするまで非公開」を初期値にする
2. When 「募集時に主催者へ共有」を選ぶ, the iOS app shall 募集と重なる部分だけ主催者へ表示され自動参加にはならないことを説明する
3. The iOS app shall 以前の枠で選んだ募集時共有を新規枠へ自動継承しない
4. The iOS app shall 暇登録を参加 OK または予定確定として表示しない

### Requirement 4: 編集と関連状態

**Objective:** As a 利用者, I want 暇枠を後から直せる, so that 予定変更を正確に反映できる

#### Acceptance Criteria

1. When 既存枠を選択した, the iOS app shall 日時、カテゴリ、公開設定を編集し保存できる
2. When 暇枠を削除した, the iOS app shall 関連する回答や確定予定を暗黙に削除しない
3. Where 関連する回答または予定がある, the iOS app shall 暇編集とは別の変更・離脱導線を表示する
4. If 保存または削除に失敗した, the iOS app shall 成功扱いせず入力を保持して再試行を提供する

### Requirement 5: 日時とアクセシビリティ

**Objective:** As a 利用者, I want タイムゾーンや文字サイズが変わっても誤解なく操作したい, so that 実際と異なる日時を共有しない

#### Acceptance Criteria

1. The iOS app shall 保存・比較用の絶対時刻と表示用タイムゾーンを区別し、画面に現在のタイムゾーンを表示する
2. When 端末タイムゾーンが変わった, the iOS app shall 同じ絶対時刻を新しいローカル表示へ変換する
3. The iOS app shall 15分枠を小さなマスへのタップだけに依存させず、44×44ptを一般基準とするハンドル、ボタン、VoiceOver代替操作を提供する
4. The iOS app shall タップ、長押し成立、15分境界の変更、登録成功、登録失敗を視覚表示と触覚フィードバックで区別し、色だけを状態の手掛かりにしない
