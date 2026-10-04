---
type: Requirements
title: "Siri 予定・ホスト操作要件"
description: "音声からの暇時間と募集の操作、入力補完、結果応答"
status: stable
sources:
  - id: user-siri-low-effort
    resource: conversation://2026-10-04/siri-low-effort
    title: Siri 操作公開と予定調整の負荷最小化の依頼
kiro:
  depends_on:
    - .kiro/steering/product.md
    - .kiro/specs/ios-availability/requirements.md
    - .kiro/specs/ios-hosting/requirements.md
    - .kiro/specs/ios-friendship/requirements.md
---

# Requirements Document

## Introduction
予定の設定・調整の負荷を可能な限りゼロに近づけるため、既存の暇時間・募集操作を Siri とショートカットへ公開する。ここで予定の設定は本人の暇時間・募集候補の設定を指し、予定の最終確定は含めない。[^user-siri-low-effort]

## Boundary Context
- In scope: システム操作入口、必要パラメータの補完、本人に許可された対象の解決、既存操作の呼出し、結果と復帰導線。
- Out of scope: 予定確定、参加回答、自動参加、カレンダー、独自音声認識・自由文解析、第三者の暇の照会。
- Adjacent expectations: 暇の日時検証・OR統合・区間削除は Availability、募集の作成・取消・競合・認可は Hosting、友達の承認状態は Friendship、セッションと画面引継ぎは App Integration の既存契約を使う。

## Requirements

### Requirement 1: 発見と入力負荷
**Objective:** 利用者が画面操作を繰り返さず予定候補を設定できる。
1. The iOS app shall 日本語の Siri とショートカットから「暇を登録」「暇を削除」「友達を誘う」「募集を取り消す」の操作を発見・実行できるようにする
2. When 利用者が有効なパラメータを渡した, the iOS app shall 同じ値の再入力や画面での再選択を要求しない
3. If 必須の日時・対象・開催形態が不足または曖昧である, the iOS app shall 未確定の項目だけを確認し、値を推測して書き込みを行わない
4. If システム上で操作を完了できずアプリへ移る必要がある, the iOS app shall 解決済み入力と目的の操作を引き継ぎ、認証後も最初から入力させない

### Requirement 2: 暇時間の登録・区間削除
**Objective:** 利用者が日時指定だけで本人の暇時間を設定・調整できる。
1. When 暇登録を実行した, the iOS app shall 指定した開始・終了を既存と同じ15分単位・今後14日・未来時刻の条件で検証して本人の暇へOR登録する
2. The iOS app shall 新規登録のカテゴリを未選択、公開設定を「参加OKするまで非公開」にし、過去の共有設定を継承しない
3. If 重複枠の属性統合に利用者の選択が必要である, the iOS app shall 対象の統合結果を確認してから保存する
4. When 暇削除を実行した, the iOS app shall 指定範囲だけを本人の暇から差し引き、残区間と属性を保持する
5. If 削除範囲が本人の募集中候補に重なる, the iOS app shall 削除を止めて募集取消へ案内し、募集や参加回答を暗黙に取り消さない
6. If 日時が条件を満たさない, the iOS app shall 補正後の日時で勝手に保存せず、理由と修正すべき項目を返す

7. The iOS app shall 日付またぎを許可し、解決した絶対時刻と表示タイムゾーンを区別して、確認・アプリ引継ぎでも同じ絶対時刻を保持する
8. If 日付またはタイムゾーンが曖昧である, the iOS app shall 確認してから日時を確定し、端末タイムゾーン変更によって保存済みの絶対時刻を変更しない

### Requirement 3: ホストとしての募集設定・取消
**Objective:** ホストが日時・友達・開催条件を音声から設定できる。
1. The iOS app shall 募集作成で開始・終了、複数の承認済み友達、オンライン／オフライン、任意の定型カテゴリ、オフラインの定義済みエリアまたは「あとで相談」を指定できるようにする
2. If 同名の友達または複数の取消候補が存在する, the iOS app shall 候補を識別できる情報で選択を求め、名前だけで対象を決めない
3. Before 募集を送信する, the iOS app shall 日時・開催条件・選択した友達をまとめて提示し、対象全員へ招待することを一度確認する
4. When 募集作成が成功した, the iOS app shall 未登録の本人暇を同じ成功・失敗単位でOR登録し、友達の暇登録有無を送信条件にしない
5. Before 本人の募集を取り消す, the iOS app shall 対象の日時と開催条件を確認し、取消後も本人の暇を保持する
6. While 募集中である, the iOS app shall 候補日時・開催形態の上書き変更を公開せず、取消して作り直す操作へ案内する
7. The iOS app shall 暇登録、募集、参加OK、予定確定を別の意思表示として扱い、音声操作で自動参加や自動確定を生成しない
8. The iOS app shall 募集候補日時の解決・確認・画面引継ぎにも要件2.7–2.8と同じ絶対時刻・タイムゾーンの契約を適用する

### Requirement 4: 認証と非公開情報
**Objective:** 利用者が音声経由でも自分の権限の範囲で操作できる。
1. If 未認証・セッション失効・退会受付済みである, the iOS app shall データ更新を行わず、必要な認証またはアクセス停止を案内する
2. While 端末がロックされている, the iOS app shall 個人の日時・友達・募集の照会と変更を端末の認証が済むまで実行しない
3. The iOS app shall 操作時に本人の権限と友達・募集の最新状態を検証し、権限外または期限切れの候補を実行しない
4. The iOS app shall ホストへの結果に相手の暇、未回答・辞退・既読、配信人数を含めない
5. The iOS app shall access token、個人の日時、友達情報、音声入力の内容をアプリの計測ログへ記録しない

### Requirement 5: 結果・再送・検証
**Objective:** 利用者が成功を誤認せず、再入力や二重操作を避けられる。
1. When 永続化が成功した, the iOS app shall 操作が完了したことを日本語で返し、アプリの再取得でも同じ結果を表示する
2. If 通信失敗または競合が生じた, the iOS app shall 成功扱いせず、解決済み入力を保持した再試行または最新状態への復帰を提供する
3. If 送信結果が不明である, the iOS app shall 元の operationID・入力・expectedVersion を維持して状態照会または再送を行う
4. The iOS app shall iOS 17 以降の実機で、日本語 Siri からの発見、パラメータ補完、同名対象の選択、ロック・認証、画面引継ぎ、成功・失敗の応答を検証する
5. The iOS app shall ショートカット実行と Siri 実行の両方について、音声で完了できる操作と画面引継ぎが必要な条件を検証結果に明示する
6. If 競合が確定した, the iOS app shall 最新状態を再取得し、利用者が対象と操作を再確認してから新しい operationID と expectedVersion で変更を実行する

[^user-siri-low-effort]: 2026-10-04 の Siri 操作公開とユーザー負荷最小化の依頼。
