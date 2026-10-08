---
type: Design
title: "iOS 暇時間設計"
description: "時間区間ポリシーとホーム・編集画面の責務設計"
status: stable
sources:
  - id: ios-availability-research
    resource: ./research.md
    title: iOS 暇時間調査
kiro:
  depends_on:
    - .kiro/specs/ios-availability/requirements.md
    - .kiro/specs/ios-app-foundation/design.md
---

# Design Document

## Overview

Availability を独立機能として、Domain の `AvailabilitySlot` と `AvailabilityPolicy`、Presentation の HomeTimeline / AvailabilityEditor、DEBUG 用 Prototype、Release 用 Backend Adapter を使う。Application の独立 Repository / UseCase は後続タスクで分離する。時間は `Date` の半開区間 `[start, end)` として扱う。

## Boundary Commitments

### This Spec Owns

- 自分の暇枠、公開ポリシー、入力検証、ホームのリスト・カレンダーと編集シート。Release は本人暇と募集中候補を投影し、確定予定は DEBUG fixture の読み取り表示に限定する。

### Out of Boundary

- 他人への開示可否の最終判定、参加回答、確定予定のライフサイクル。

### Allowed Dependencies

- ios-app-foundation の Navigation / common UI、Foundation Calendar / TimeZone。

### Revalidation Triggers

- API の日時表現、対象期間、入力粒度、公開ポリシー、Hosting 参照契約の変更。

## Architecture

```mermaid
graph LR
    HomeTimelineView --> HomeTimelineFeature
    EditorView --> AvailabilityEditorFeature
    Features --> AvailabilityUseCase
    AvailabilityUseCase --> AvailabilityRepository
    PrototypeAdapter --> AvailabilityRepository
    BackendAvailabilityAdapter --> AvailabilityRepository
    AvailabilityPolicy --> AvailabilityUseCase
```

`AvailabilityPolicy` は15分境界と範囲を検証し、重なる・接する暇をOR統合候補として計算する。Reducer は入力中の表示状態と属性の統合確認を所有する。

保存は App の `HimatchClient` を Reducer の Effect から呼ぶ。明示的に開始した DEBUG デモは Prototype、通常 Debug と Release は `BackendAvailabilityAdapter` が本人限定の GET、区間OR、区間減算を使う。認証SDKから現在のsessionを取得し、利用者JWTでBackendへ送る。成功後は一覧 GET で本人枠を再取得し、古い読み込み応答が保存後の枠を上書きしないよう利用者IDと更新番号で制御する。失敗は空一覧へ変換せず、入力を保持する。サーバー認可は backend-availability が所有する。

### Domain ポリシー

`AvailabilityPolicy` は次の純粋関数を持ち、Presentation の初期値と入力補正はすべてこれを通す。

- `quarterHour`（15分）、`window`（14日）、`defaultDuration`（2時間）。
- `isQuarterHourAligned`：分が15の倍数で、秒とナノ秒が0。`validate` の `notQuarterHour` 判定に使う。
- `floorToQuarterHour`、`nextQuarterHour(after:)`（現在位置からの開始）、`latestEnd(now:)`（`now + 14日` を15分境界へ切り下げた登録可能な最終終了）。
- `draftInterval(anchor:now:)`：時間軸の位置を切り下げて開始とし、次の15分境界より前なら引き上げる。終了は `min(開始 + 2時間, latestEnd)`。15分も取れなければ nil。

### ホームのリストとカレンダー（HomeTimelineFeature）

- State に `presentation`（`.list` / `.calendar`、初期値 `.list`）を追加し、ホーム上部の明示的な切替で変更する。日・週表示モードとは独立させ、保存中は切替を無効にする。
- リストは表示範囲内の終了前項目を日付別・開始時刻順にまとめ、各行に種別ラベルと時刻を表示する。日付またぎは対象日ごとに投影し、タップは既存の項目詳細へ渡す。Release は本人暇と募集中候補、確定予定は DEBUG fixture に限定する。
- 切替は選択日、未保存範囲、操作モードをリセットしない。両表示のコンテナを ZStack 内に保持し、非表示側はタッチとアクセシビリティの対象から除外する。カレンダーのスクロール位置は同じ View セッションで保持し、表示形式の永続設定は追加しない。
- 選択範囲の確認バーはカレンダー表示中だけ表示する。リストから登録・招待の既存 delegate を使い、時間選択の操作モードと友達プロフィールからの招待は `.calendar` へ移る。Siri と外部 focus は既存の表示形式と日時引継ぎ処理を維持する。

- 今日の0時を起点とする14日（index 0〜13）を日表示と週表示で切り替える。週表示は今日から7日と次の7日の2ページとし、範囲外の日を表示しない。
- State は表示形式、カレンダーの日・週表示モード、起点日、選択日 index、選択中の項目、15分境界へ正規化済みの選択範囲と検証・保存状態を持つ。生の指位置と長押し進行状態は View の `@GestureState` に限定する。項目データは親の snapshot から読み取り専用の `HomeScheduleItem`（本人暇、募集中候補、DEBUG fixture の予定）として受け取る。これが現行の `HomeScheduleProjection` にあたる。
- 日付変更・タイムゾーン変更・表示時に `refreshWindow` で起点日を再計算し、選択中の日付を維持する。
- 日表示は1時間を44pt以上の行とする。タップは位置を含む15分だけを画面内で選択し、シートを開かない。時間軸上の透明な `UIViewRepresentable` が `UITapGestureRecognizer` と `UILongPressGestureRecognizer`（0.3秒・許容移動10pt）を1組だけ所有する。長押し成立後に上下へドラッグすると、開始位置と現在位置を含む範囲を `TimelineSelection.normalized` で15分境界へ合わせる。長押し前に動いた場合は祖先 `UIScrollView.panGestureRecognizer` が先に成立してタップと長押しを失敗させ、通常の縦スクロールを所有する。既存ブロックと選択ハンドルは透明面より上に配置する。
- 選択中は15分補助線、半透明の範囲、開始・終了ハンドル、開始・終了時刻と長さを重ねて表示する。ハンドルのドラッグも最寄りの15分境界へ合わせ、最低15分と1日境界を越えない。選択開始と境界変更に異なる触覚フィードバックを出す。
- 親は選択のたびに日時と範囲を検証する。過去・14日範囲外は選択を消さず理由を表示して登録を無効にする。既存暇との重複・接続はOR統合候補として示し、属性が異なる場合はカテゴリと公開設定を保存前に選ばせる。
- 有効な選択では下部確認バーに範囲、長さ、「参加OKまで非公開」を表示する。「非公開で登録」はカテゴリ nil・`privateUntilAccepted` で保存し、「詳細を調整」は同じ範囲を編集シートへ渡す。選択だけでは保存せず、成功時だけ選択を消し、失敗時は再試行用に保持する。
- VoiceOver では行ごとの :00 を既定アクション、:15/:30/:45 をカスタムアクションとして提供し、選択範囲には開始・終了を15分ずつ調整するアクション、登録、詳細調整、取消を提供する。週表示の時刻セルは該当日の日表示へ移り15分を選択する。アクセシビリティ文字サイズでは週表示を日ごとの一覧へ切り替える。
- 常設の「暇を登録」だけは delegate `startAvailability(anchor: nil)` で親へ通知し、次の15分境界から2時間の編集状態を作る。
- 既存の暇をタップすると詳細（範囲・公開設定・招待・削除）を表示する。削除モードは時間軸の範囲選択を共用し、重なる複数枠から選択範囲だけを差し引く。募集中の候補と重なる削除は止めて Hosting の取消へ案内する。
- 日付をまたぐ枠は日ごとに半開区間で切り分け、重なる暇と予定は横に並べる（`TimelineLayout`）。

### 暇の編集シート（AvailabilityEditorFeature）

- 開始と終了を絶対時刻で保持し、上部の要約（開始→終了、日付、長さ、日付またぎ、表示タイムゾーン）を入力のたびに更新する。
- 開始・終了それぞれに ±15分ボタンと15分刻みの日時ピッカー（`UIDatePicker.minuteInterval = 15`）を置き、受け取った値は Reducer で15分境界へ切り下げる。開始の移動は長さを保ち、終了は `開始 + 15分` から `latestEnd` の範囲に収める。
- 長さプリセットは15分・30分・1時間・2時間・3時間・6時間。`latestEnd` を超えるものは無効にする。
- 検証結果は日時と範囲を毎回評価して表示し、無効な間は保存しない。既存暇との重複・接続は統合後の範囲と属性を示す。開始が過ぎた場合は次の15分へ合わせる操作を出す。
- 時計は `@Dependency(\.date)` から取得し、各操作と保存直前に再評価する。新規枠の id は `@Dependency(\.uuid)` で作る。
- 公開設定は説明付きの2択で、編集状態は開くたびに作り直すため常に「参加OKするまで非公開」から始まる。暇登録が参加OKや予定確定ではないことを明記する。
- 保存失敗時は入力を保持し、理由を表示して再試行できる。

## File Structure Plan

```text
apps/ios/Himatch/Availability/
├── Domain/AvailabilityModels.swift              # 実装済み：モデルと AvailabilityPolicy
├── Application/Port/AvailabilityRepository.swift # 未実装（タスク1）
├── Application/UseCase/ManageAvailability.swift  # 未実装（タスク1）
├── Infrastructure/Adapter/PrototypeAvailabilityAdapter.swift # 未実装（タスク2）
└── Presentation/
    ├── Reducer/HomeTimelineFeature.swift
    ├── Reducer/AvailabilityEditorFeature.swift
    ├── Component/{TimelineLayout,TimelineSelection,AvailabilityFormatting,QuarterHourDatePicker}.swift
    └── View/{HomeTimelineView,TimelineGridViews,TimelineSelectionViews,AvailabilityEditorView}.swift
apps/ios/Himatch/App/Presentation/Screens/HomeView.swift  # snapshot → HomeScheduleItem の写像と Home の合成
apps/ios/HimatchTests/Availability/
apps/ios/HimatchTests/Domain/AvailabilityPolicyTests.swift
```

`TimelineLayout.swift` は `HomeScheduleItem`（HomeScheduleProjection の現行形）を定義する。共通の色・余白・ボタン部品は `App/Presentation/DesignSystem/` を使う。

## Data Model and Contracts

- 現行の `AvailabilitySlot`: id、start、end、optional category、visibility。端末間の内容編集を導入する際に version を追加する。
- `AvailabilityVisibility`: `privateUntilAccepted` / `shareOnHosting`。
- 現行Backend契約: 本人の list、UUID指定の create と同内容の再送、delete。異なる内容で同じUUIDを再利用すると競合。将来の Repository 契約では create(command,idempotencyKey)、update(id,version,command)、delete(id,version) を提供する。
- `AvailabilityError`: invalidInterval、past、outsideWindow、hostingConflict、transport。
- `HomeScheduleProjection` は Availability と Hosting の表示用項目を Integration から受け取る読み取り契約で、確定予定の変更を提供しない。

OR統合は重なるか端点が接する区間を連鎖的にまとめ、減算は選択範囲との半開区間差を残す。募集中の範囲は Hosting の候補区間を時間軸へ重ねて投影し、暇枠全体へ状態を広げない。

## Requirements Traceability

| Requirement | Components | Validation |
|---|---|---|
| 1.1-1.12 | HomeTimelineFeature, TimelineLayout, TimelineSelection, HomeView | reducer / selection / layout tests, list/calendar retention inspection |
| 2.1-2.7 | AvailabilityPolicy, AvailabilityEditorFeature, AppFeature | policy / TestStore |
| 3.1-3.4 | Visibility, AvailabilityEditorFeature | state / copy tests |
| 4.1-4.4 | ManageAvailability, AvailabilityEditorFeature | repository conflict tests, save failure TestStore |
| 5.1-5.4 | AvailabilityFormatting, day/week controls, selection overlay | timezone / accessibility / feedback inspection |

## Error and Testing Strategy

- 入力エラーは項目近傍、競合は最新取得後の再確認、通信失敗は入力保持。
- Domain: 15分境界（秒を含む）、最短15分、日付またぎ、14日境界、半開区間のORと差、属性、タイムゾーン変更。
- Application: Repository 成功・競合・再送。
- Presentation: タップで15分、上下ドラッグの正規化、日境界、ハンドル調整、長押し閾値、保存直前の再検証、直接登録、詳細への同一範囲引継ぎ、失敗時の選択保持、日／週の移動範囲、公開説明、削除と Hosting 導線。
- Integration: Home の直接選択からOR登録、区間削除、友達招待への引継ぎ、保存後の該当日と募集中部分の表示（AppFeature TestStore）。実ドラッグ、スクロール競合、VoiceOver は Simulator 手動確認の対象とする。
