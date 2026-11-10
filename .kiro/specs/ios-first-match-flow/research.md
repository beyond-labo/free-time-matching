---
type: Research
title: "はじめての予定までの動線の調査記録"
description: "現行アプリの分かりにくさ、自動提案を主軸にした方針、レビュー指摘、既存仕様への反映対象"
status: draft
sources:
  - id: user-first-match
    resource: conversation://2026-11-08/first-match-flow
    title: 起動しただけでは分かりにくい初回マッチング体験の改善依頼と方針決定
  - id: prototype-first-match
    resource: ../../../docs/prototypes/first-match-flow.html
    title: はじめてのお誘い動線プロトタイプ
  - id: user-auto-axis
    resource: conversation://2026-11-08/first-match-auto-axis
    title: 自動提案を主軸に両立する決定と独立レビュー指摘
kiro:
  depends_on:
    - .kiro/steering/product.md
    - .kiro/specs/ios-app-foundation/requirements.md
    - .kiro/specs/ios-availability/requirements.md
    - .kiro/specs/ios-friendship/requirements.md
    - .kiro/specs/ios-hosting/requirements.md
    - .kiro/specs/ios-app-integration/requirements.md
    - .kiro/specs/automatic-friend-scheduling/requirements.md
    - apps/ios/Himatch/App/Composition/AppCompositionRoot.swift
    - apps/ios/Himatch/App/Domain/HimatchClient.swift
    - apps/ios/Himatch/App/Presentation/AppView.swift
    - apps/ios/Himatch/App/Presentation/Screens/HomeView.swift
---

# 調査記録

## 現行の要約
自動提案を主軸にする。案内は 友達とつながる → 暇を登録して自動提案を許可 → 提案に参加OK の3段階で、提案の予定が確定するか手動のお誘いで参加OKをやり取りすると完了する。手動のお誘いはホームの「自分で誘う」と友達画面からの副経路として残す。
自動提案（automatic-friend-scheduling）と手動のお誘い（ios-hosting）の製品契約は変えず、ホームの構成・入力量・用語・到達経路・アカウント境界での画面状態を変える。Backend は返事変更の版確認の不具合だけを直した。
2026-11-08 の改訂で要件の意味が変わったため承認を外し、2026-11-10 にユーザーが改訂後の要件・設計・タスクを承認した。

## 自動提案を主軸にする改訂（2026-11-08）
- 最新の main（adc0ea1）に自動提案と確定予定のホーム表示、アイマノの識別子が入り、この仕様の「ホストが時間を選んで誘う」を主とする案内と衝突した。ユーザーは「自動提案を主軸に両立」を選んだ。[^user-auto-axis]
- 採用：案内を 友達とつながる → 暇を登録して自動提案を許可 → 提案に参加OK にする。ホームは 申請・提案・届いたお誘い・案内・決まった予定・自分のお誘い・暇・自分で誘う の順。主操作は友達がいれば「暇を登録」。棄却：手動のお誘いを主のまま提案を下に並べる案（main の第一段階の方針と逆になる）、手動のお誘いを削除する案（既存の互換契約と ios-hosting の要件を壊す）。
- 準備段階の3項目（今後の暇・全体設定・友達別の許可）は本人の状態だけで判定し、相手の許可は表示しない（automatic-friend-scheduling 1.x と同じ非公開の扱い）。
- 提案カードと確定予定の振る舞いは main の `SchedulingProposalCard` をそのまま使い、この仕様では配置だけを持つ。

## 独立レビューの指摘と対応（2026-11-08）
読み取り専用の独立レビュー（判定 REJECTED）の指摘を次のとおり扱った。
| 指摘 | 判断 | 対応 |
|---|---|---|
| P1 参加OK後の返事変更・取消が実Backendで409 | 既存要件 7.8・ios-hosting 3.4 を満たさないバグ | `hosting_respond_before_scheduling` を版一致時に受け付ける migration と pgTAP。要件は不変 |
| P1 アカウント切替で作成・返事・バナーが残り、遅れた結果に所有者確認がない | 要件の欠落 | Requirement 12 を追加。`resetAccountScopedState` と結果 Action の `owner` 照合 |
| P2 友達0人・暇0件でホームから暇を登録できない、引き下げ更新で友達を再取得しない | 要件の欠落 | 2.5 を常時表示に、2.7 を追加。`homeRefreshed` |
| P2 送信中に閉じて再送すると重複作成 | 要件の欠落 | 5.12 を追加。送信中の close を子と Root で無視 |
| 仕様の同期不足と v23 モック参照 | 文書の不備 | v23 モックの参照を削除し、関連仕様・文書を同期 |
| main との統合 | 方針判断 | 上記の改訂。main の自動提案・確定予定の表示・アイマノ識別子を維持 |

## 方針の決定（2026-11-08）
- 体験の軸：現行仕様のまま UI を洗練する。友達の暇をホームに並べて声をかける案は、公開範囲と Backend 契約の変更を伴うため採用しない（同日の改訂で自動提案を主軸に変更。上記参照）。[^user-first-match]
- 進め方：動線プロトタイプで確認してから仕様化し、その後に実装する。
- 壊れているデモ：体験改善と同じ仕様の中で直す（Requirement 10）。
- プロトタイプで未決だった2点は、製品方針の「既存情報と安全な初期値で入力を減らす」「意思が変わる箇所だけ確認する」に沿って次のとおり要件化した。承認時に変更できる。
  - 会い方：受け取る側の判断を変える項目なので初回は未選択で選ばせ、2回目以降は前回値を初期値にする（Requirement 5.5）。
  - 前半・後半：候補が2時間以上のとき15分境界で2分割する（Requirement 7.2）。

## 現行アプリの調査（2026-11-08、iPhone 18 Pro Simulator、Debug ビルド）
- ホームの主表示は日/週切替・日付列・タイムゾーン表示・15分グリッドで、友達と遊ぶために何をするかの説明がない（`HomeView.swift`、`HomeTimelineView.swift`）。
- 友達0人でも「友達を誘う」が押せ、時間選択モードに入ってから招待先がいないことが分かる。
- お誘い作成画面は開催形態・エリア・カテゴリ・暇のカテゴリ・暇の公開設定・統合確認・友達を並べ、送信は右上の「募集を開始」（`AppView.swift` の `HostingEditorView`）。
- 届いたお誘いはベルから開くシートにあり、ベルに件数表示がない。返事は±ボタンで開始・終了を15分ずつ動かし、「この範囲で回答」→「この時間で参加OK」の2段階（`InvitationResponseCard`）。
- 参加OKはホームの「募集中 n件」バナーから開くシートかお知らせの「進行中」にだけ表示される。
- 「デモデータで試す」は、表示名を入力して保存すると「最新の状態を取得できませんでした。」で止まる。`AppCompositionRoot` が `himatchClient` に常に `runtime.business` を注入しており、その `saveProfile` は `HimatchClient.productionPlaceholder` の `PrototypeError.notFound` を返す。`HimatchPrototypeScenario` は Preview でしか使われていない。これは `ios-app-integration` Requirement 3.4 と 3.6 に反する既存の不具合であり、要件の変更ではない。
- 同じデモ経路で表示名欄が空で表示された。`ios-app-foundation` Requirement 2.1（生成された仮名を初期値にする）との一致は実装時に確認する。

## 既存仕様への反映対象
次の受け入れ条件を所有仕様へ反映した（タスク1）。main の0.1.7〜0.1.8で更新された本文（リストとカレンダー、自動提案の投影）に重ねて反映し、各仕様の設計に変更の補足、research に変更理由を記録した。

| 仕様 | 対象 | 変更内容 |
|---|---|---|
| ios-availability | Requirement 1（リストとカレンダー） | リストとカレンダーをホームの主表示から、ホームから開くカレンダー画面へ移す。操作仕様は維持。 |
| ios-availability | Requirement 2.1（常設の新規登録） | 登録の開始点をホームの暇の区分・案内・主操作とカレンダー画面にする。 |
| ios-availability | Requirement 7.1 | 画面上の名称を「お誘い中」にする。 |
| ios-hosting | Requirement 1.1 | 時間軸の選択に加え、時間候補・暇・友達から始める経路を追加する。 |
| ios-hosting | Requirement 1.2 | 開催形態の表示名を「会い方」にし、初回未選択・前回値の初期値を追加する。 |
| ios-hosting | Requirement 2.2 | 表示文言を「お誘いを送りました」系へ変更する。 |
| ios-hosting | Requirement 3.2／3.7 | 返事の選択肢（全体・前半・後半・時間を指定）と1回の送信を明記する。 |
| ios-hosting | Requirement 6.1 | 未回答のお誘いと参加OKをホームにも表示することを追加する。 |
| ios-friendship | Requirement 3.6 | 遷移先を「時間軸選択」から「その友達を選択済みのお誘い作成画面」へ変える。 |
| ios-app-integration | Requirement 1.1／1.2 | ホーム投影の区分と順序、お知らせ件数（未回答の提案を含む）を追加する。 |
| ios-app-integration | Requirement 3.4 | デモの主要経路に、自動提案の確定とデモ友達の参加OKと受け取り表示を加える。 |
| automatic-friend-scheduling | Requirement 9.4 | ホームで本人暇・提案・確定予定を区別する条件をこの仕様の区分で満たす。本文の変更なし。 |
| backend-hosting / ios-hosting | research | 返事変更の版確認の不具合修正を記録する。要件の変更なし。 |
| ios-siri-actions | Requirement 1.1 | Siri の語句（「募集を取り消す」など）は範囲外。用語統一に合わせるかは別途判断する。 |

`ios-app-foundation` の Requirement 1.1 は今回の Requirement 1.2 で満たし続けるため変更不要。

## 要件レビュー
主要経路（友達0人、友達あり、お誘い送信、返事、参加OK受信、複数人）、失敗（送信・返事の失敗、期限切れ、取消）、非公開表示（配信人数・未回答者・見送り・友達の暇を出さない）、アクセシビリティ、DEBUG と Release の境界を照合した。
Backend の新しい契約は必要としない。参加OKの検出は既存の募集取得結果の差分、案内の完了状態は端末内の記録で満たせる見込みであり、方式は設計で決める。
品質レビューの合格はユーザー承認ではない。

## 設計の判断（2026-11-08）
- 既存機能の拡張として軽量調査（コードと契約の確認）で進めた。新しい外部依存はない。
- お誘い作成の入力は `AppFeature` の Root State に11フィールドで置かれているため、`InvitationComposerFeature` へ切り出す。返事も `InvitationReplyFeature` に分ける。API 呼び出しと冪等性は既存の `AppFeature` ハンドラに残し、子は delegate で内容だけを返す。ホームの区分は状態を持たない投影関数にし、区分ごとの Reducer は作らない。
- 参加OKの新着検出は Push や新 API を使わず、既存の `loadHostings` 結果を端末内の既読キーと比べる。取得のきっかけにホーム表示と前面復帰を加える。棄却案：Backend に既読管理を追加する（今回の範囲外の契約変更）。
- 案内の完了・会い方の前回値・既読キーは UserDefaults にアカウント別で保存する。表示名や時刻を平文で保存しない。棄却案：Backend のプロフィールに保存する（API 変更が必要）。
- 参加OKの取消は `docs/architecture/api-contracts.md` の `PUT /v1/hostings/{id}/response` が `accepted`／`declined` だけを受けるため、`declined` で送る。ios-hosting 3.5 によりホストへの通知は生成されない。
- デモは `isDemo` のとき Prototype シナリオの client を使うように切り替え、シナリオを `#if DEBUG` で囲む。現状はシナリオが Release にもコンパイルされている。
- `HostingMode` の rawValue は Codable と Adapter 変換で使われるため変えず、表示名だけ「会う」にする。
- 作成画面の日時選択は同日内とし、日付をまたぐ範囲は時間軸からの開始で扱う。要件 5.2 は日付と15分単位の開始・終了の選択を求めるだけで、日付またぎは ios-availability 2.2 の時間軸で満たされる。

## 実装と検証（2026-11-08）
- Swift Testing 206件が成功（新規の Domain・投影・Reducer・Root・デモ主要経路テストを含む）。Debug と Release（generic iOS Simulator、署名なし）のビルドが成功し、Release バイナリに `HimatchPrototypeScenario`・`DemoScenarioClient`・デモ文言が含まれないことを確認した。
- iPhone 18 Pro Simulator でデモを一巡した：友達なし開始 → 友達招待シート → デモ申請承認 → 案内2段階目の時間候補 → お誘い作成 → 送信結果 → 返事待ち → デモ友達の参加OK（バナー・件数・カード表示・案内完了）→ 友達あり開始 → 返事（前半）→ 参加OK済み表示 → カレンダー画面。最大の Dynamic Type でホームを確認した。画面記録は `docs/prototypes/screenshots/`。
- 検証で見つけて直した不具合：デモで回答後に届いたお誘いが更新されない（Root が先頭要素だけを反映していた）、デモの端末内記録が次のデモへ持ち越される、デモのお誘い作成が本人の暇へ登録されない、最大の文字サイズで時間候補チップがはみ出す。
- 未実施：VoiceOver の実読み上げ確認（読み上げ文言はコードで設定済み）、実機と STG Backend の複数アカウントでの確認。
- 提案（要件外）：「自分で誘う」（旧「次はいつ遊ぶ？」）の固定候補が、送信済みのお誘いと同じ時間でも表示される。要件 4.1 は暇候補だけを募集中と重なるときに除外するため、固定候補も除外するかは要件の変更として判断する。

## 自動提案を主軸にした実装と検証（2026-11-08）
- 新しいブランチ `feature/ios-first-match-flow` を origin/main（adc0ea1）から作り、旧ブランチの実装を移した。14ファイルの競合を、main の自動提案・確定予定の表示・アイマノ識別子を残して解消した。
- Swift Testing 241件が成功。追加：案内の準備段階と提案での完了、ホーム区分と件数（提案・決まった予定）、デモの自動提案（オン・許可・提案・参加OK・相手の参加OK・確定・案内完了）、`routingDemo` の振り分け、アカウント切替での破棄、旧アカウントの結果の破棄、送信中に閉じない、引き下げ更新で友達を再取得。既存の境界テスト3件は、境界で revision を進める仕様に合わせて期待値を更新した。
- Debug・Release（generic iOS Simulator）のビルドが成功し、Release バイナリにデモの型と文言が含まれないことを確認した。
- iPhone 17 Simulator のデモ（友達あり）で、案内の準備3項目 → 自動提案オン → 友達の許可 → 提案の到着（件数2）→ 参加OK（件数1）→ 相手の参加OK → 「決まった予定」に相手名つきで表示、案内の完了、手動のお誘い作成画面を確認した。
- 検証で見つけて直した不具合：カレンダー画面の項目に確定提案が含まれていなかった。
- Backend：Supabase CLI 2.117.0 で `db reset --local` 後に `db lint` と `test db` が成功（hosting は46件）。修正前の関数では参加OK後の変更が `hosting_conflict` になることを同じテストで再現した。
- 未実施：VoiceOver の実読み上げ、実機と STG Backend の複数アカウントでの確認、CI。

## 変更記録
- 2026-11-10: ユーザーが改訂後の要件・設計・タスクを承認した（PR #20 のレビュー時）。関連4仕様（ios-availability, ios-hosting, ios-friendship, ios-app-integration）の承認は別途。
- 2026-11-08: 自動提案を主軸に要件・設計・タスクを改訂し、独立レビューの指摘（Requirement 2.5・2.7・5.12・12、Backend の返事変更）を反映した。要件以降の承認を外した。v23 モックの参照を削除した。
- 2026-11-08: 実装と検証の結果、実装で確定した事項を記録した。
- 2026-11-08: 設計を作成。上記の判断を追加した。
- 2026-11-08: 初版。動線プロトタイプと現行アプリの調査から要件を作成した。

[^user-first-match]: 2026-11-08 の依頼と、体験の軸・進め方・デモ修正の時期についての回答。
[^user-auto-axis]: 2026-11-08、main 統合時の方針の質問に対する「自動提案を主軸に両立」の回答と、同日の独立レビュー結果。
