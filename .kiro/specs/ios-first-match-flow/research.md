---
type: Research
title: "はじめてのお誘い動線の調査記録"
description: "現行アプリの分かりにくさ、採用した方針、既存仕様への反映対象"
status: draft
sources:
  - id: user-first-match
    resource: conversation://2026-11-08/first-match-flow
    title: 起動しただけでは分かりにくい初回マッチング体験の改善依頼と方針決定
  - id: prototype-first-match
    resource: ../../../docs/prototypes/first-match-flow.html
    title: はじめてのお誘い動線プロトタイプ
  - id: mock-v23
    resource: ../../../himatch-ios-native-mock-v23.html
    title: iOS Native Concept v23（友達の暇を一覧する案）
kiro:
  depends_on:
    - .kiro/steering/product.md
    - .kiro/specs/ios-app-foundation/requirements.md
    - .kiro/specs/ios-availability/requirements.md
    - .kiro/specs/ios-friendship/requirements.md
    - .kiro/specs/ios-hosting/requirements.md
    - .kiro/specs/ios-app-integration/requirements.md
    - apps/ios/Himatch/App/Composition/AppCompositionRoot.swift
    - apps/ios/Himatch/App/Domain/HimatchClient.swift
    - apps/ios/Himatch/App/Presentation/AppView.swift
    - apps/ios/Himatch/App/Presentation/Screens/HomeView.swift
---

# 調査記録

## 現行の要約
現行の製品契約（暇は非公開、選んだ友達全員へのお誘い、相手が選んだ時間だけの参加OK、予定確定は後続）は変えず、画面の構成・入力量・用語・到達経路を変える。
ホームの主役を時間軸から「次にやること」へ移し、時間候補からお誘いを始め、返事を選択肢から1回で送れるようにする。
要件は draft で未承認。既存仕様は承認済み・実装済みのため、この要件の承認後に下記の反映対象を更新する。

## 方針の決定（2026-11-08）
- 体験の軸：現行仕様のまま UI を洗練する。v23 モックの「友達の暇をホームに並べて声をかける」案は、公開範囲と Backend 契約の変更を伴うため採用しない。[^user-first-match]
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
2026-11-08 の要件承認後、次の受け入れ条件を所有仕様へ反映した（タスク1）。4仕様は元から全工程が未承認だったため承認の失効はなく、設計の画面構成の反映を各仕様の freshness に保留として記録した。

| 仕様 | 対象 | 変更内容 |
|---|---|---|
| ios-availability | Requirement 1（ホーム時間軸） | 時間軸をホームの主表示から、ホームから開く画面へ移す。操作仕様は維持。 |
| ios-availability | Requirement 2.1（常設の新規登録） | 常設の登録導線をホームの暇の区分と時間軸画面へ移す。 |
| ios-hosting | Requirement 1.1 | 時間軸の選択に加え、時間候補・暇・友達から始める経路を追加する。 |
| ios-hosting | Requirement 1.2 | 開催形態の表示名を「会い方」にし、初回未選択・前回値の初期値を追加する。 |
| ios-hosting | Requirement 2.2 | 表示文言を「お誘いを送りました」系へ変更する。 |
| ios-hosting | Requirement 3.2／3.7 | 返事の選択肢（全体・前半・後半・時間を指定）と1回の送信を明記する。 |
| ios-hosting | Requirement 6.1 | 未回答のお誘いと参加OKをホームにも表示することを追加する。 |
| ios-friendship | Requirement 3.6 | 遷移先を「時間軸選択」から「その友達を選択済みのお誘い作成画面」へ変える。 |
| ios-app-integration | Requirement 1.1／1.2 | ホーム投影の区分と順序、お知らせ件数を追加する。 |
| ios-app-integration | Requirement 3.4 | デモの主要経路に、デモ友達の参加OKと受け取り表示を加える。 |
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
- 提案（要件外）：「次はいつ遊ぶ？」の固定候補が、送信済みのお誘いと同じ時間でも表示される。要件 4.1 は暇候補だけを募集中と重なるときに除外するため、固定候補も除外するかは要件の変更として判断する。

## 変更記録
- 2026-11-08: 実装と検証の結果、実装で確定した事項を記録した。
- 2026-11-08: 設計を作成。上記の判断を追加した。
- 2026-11-08: 初版。動線プロトタイプと現行アプリの調査から要件を作成した。

[^user-first-match]: 2026-11-08 の依頼と、体験の軸・進め方・デモ修正の時期についての回答。
