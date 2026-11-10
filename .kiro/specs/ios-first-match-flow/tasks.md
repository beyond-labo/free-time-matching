---
type: Implementation Plan
title: "はじめての予定までの動線の実装タスク"
description: "既存仕様の同期、判定ロジック、デモ修復、作成・返事の子機能、ホーム再構成、自動提案を主軸にした統合、アカウント境界、文言、検証"
status: draft
sources:
  - id: requirements
    resource: ./requirements.md
    title: iOS はじめての予定までの動線要件
  - id: design
    resource: ./design.md
    title: iOS はじめての予定までの動線の設計
kiro:
  depends_on:
    - .kiro/specs/ios-first-match-flow/requirements.md
    - .kiro/specs/ios-first-match-flow/design.md
---

# Implementation Plan

- [x] 1. 既存仕様の要件をこの仕様に合わせて同期する
  - [調査記録の反映対象](research.md#既存仕様への反映対象)に沿って ios-availability、ios-hosting、ios-friendship、ios-app-integration の requirements.md を更新し、置き換わった記述を現行本文に残さない。
  - 各仕様の research に変更理由を記録し、sync の規約で設計・タスクの承認と ready を再評価する。影響する完了タスクを再オープンする。
  - main 統合後は main の本文（リストとカレンダー、自動提案の投影）に重ねて反映し、automatic-friend-scheduling・backend-hosting・ios-siri-actions は入力の変化を照合して research に記録する。
  - 完了条件：4仕様の要件本文がこの仕様と矛盾せず、`okf.py check` がリポジトリ全体で問題を出さず、この仕様の `freshness.pending` が空になる。
  - _Requirements: 2.2, 4.1, 4.5, 4.6, 5.4, 6.1, 7.2, 7.6, 9.1, 10.1_

- [x] 2. 純粋な判定ロジックを Domain に追加する
- [x] 2.1 (P) 時間候補の生成規則を実装する
  - 今夜・明日の夜・当日を含む直近の土曜午後と、募集中と重ならない暇の最大2件を返す。過去開始の繰り下げ、残り1時間未満と14日超の除外、今夜と土曜の重複排除を含む。
  - 完了条件：固定カレンダーの Swift Testing で 16:00、19:30、21:10、土曜当日、14日上限、暇候補の除外と件数上限が通る。
  - _Requirements: 4.1, 4.2, 4.3_
  - _Boundary: TimeCandidatePolicy_
- [x] 2.2 (P) 返事の選択肢、全員そろう時間、会い方の表示名を実装する
  - 2時間以上の候補の前半・後半（15分境界の中点）と、指定範囲の開始・終了の候補を返す。参加OKが2人以上のとき候補と全員の重なりを返す。`HostingMode` に「オンライン」「会う」の表示名を追加し rawValue は変えない。
  - 完了条件：1時間45分・2時間15分・3時間の分割、指定範囲の境界、重なりあり・なし・1人の各テストが通り、既存の HostingPolicy テストが回帰しない。
  - _Requirements: 7.2, 7.3, 8.3, 9.1_
  - _Boundary: ReplyChoicePolicy, HostingPolicy, HostingMode_
- [x] 2.3 (P) 参加OKの新着判定を実装する
  - 自分の募集中のお誘いの参加者から、既読キー集合にない参加と時間変更を求め、現在有効なキーの集合を返す。キーは ID と区間から作り名前や時刻文字列を含めない。
  - 完了条件：新規、既読、時間変更、取消済み・他人の募集の除外、キーの内容のテストが通る。
  - _Requirements: 8.1_
  - _Boundary: ParticipationNoticeDetector_
- [x] 2.4 (P) 案内の段階判定と端末内記録を実装する
  - `FirstMatchProgress` で友達0人（共有済みかどうか）、自動提案の準備（今後の暇・全体設定・友達別許可）、提案への参加OK（未回答の提案の有無）、完了（確定した提案または手動の参加OK）・閉じた後の非表示を判定する。`FirstMatchLocalStore` の Port、UserDefaults 実装、メモリ実装、DependencyKey を追加する。
  - 完了条件：段階の各遷移とホスト側・招待側の完了判定のテスト、アカウント別キーの保存・読込・削除と読込失敗時の既定値のテストが通る。
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 5.5_
  - _Boundary: FirstMatchProgress, FirstMatchLocalStore_

- [x] 3. DEBUG デモを Prototype シナリオへ接続し直す
  - `HimatchPrototypeScenario` と新しい `DemoScenarioClient` を `#if DEBUG` で囲み、友達なし・友達ありの2種の seed、デモ友達の申請と参加OKの操作を追加する。
  - `AppFeature` の全 Effect をデモ時は `DemoScenarioClient.business`、それ以外は `himatchClient` を使う関数経由に置き換え、`startDemo(Seed)` と登録前画面の2つの開始ボタンを追加する。表示名の初期値を seed の仮名にする。
  - 完了条件：デモでプロフィール保存が成功してホームへ進む TestStore テスト、2種の seed のテストが通り、Release 構成のビルドが成功してシナリオの型を参照しない。
  - _Requirements: 1.3, 10.1, 10.2, 10.4_
  - _Depends: 1_
  - _Boundary: HimatchPrototypeScenario, DemoScenarioClient, AppFeature, AppCompositionRoot, AppDependencies_

- [x] 4. お誘い作成を子機能へ切り出す
- [x] 4.1 (P) お誘い作成の Reducer を実装する
  - `InvitationStart`（白紙・候補・範囲・友達）からの初期化、前回の会い方の適用、不足項目の判定、属性の異なる既存暇との競合と選択、入力変更ごとの operationID 更新、送信と失敗の状態を実装する。
  - 完了条件：候補・範囲・友達からの初期化、初回未選択と前回値、不足項目の順序、競合時の送信不可、送信 delegate の `HostingDraft`（新規範囲は未選択・非公開）の TestStore テストが通る。
  - _Requirements: 4.4, 4.5, 4.6, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 6.5_
  - _Boundary: InvitationComposerFeature_
  - _Depends: 2.1, 2.4_
- [x] 4.2 お誘い作成画面と送信結果を Root に統合する
  - `InvitationComposerView`（いつ・だれと・会い方・なにする、下部固定の送信と送信先の名前、届き方と非公開の暇の説明）と `InvitationSentView` を作り、`AppFeature` の11個のお誘い入力フィールドと関連 Action を子の Scope と delegate に置き換える。成功時に前回の会い方を保存し、失敗時はアラートを出さず画面を保持する。
  - 旧 `HostingEditorView` を削除し、時間軸の範囲・暇の詳細・友達一覧・友達プロフィールからの開始を新しい画面へつなぐ。
  - 完了条件：Root の TestStore で作成成功→送信結果表示と前回値保存、作成失敗→入力保持、各開始経路の初期値が検証でき、Simulator で作成画面を最後まで操作できる。
  - _Requirements: 4.4, 4.5, 4.6, 5.1, 5.10, 5.11, 6.1, 6.2, 6.5_
  - _Depends: 3, 4.1_

- [x] 5. 返事を子機能へ切り出す
- [x] 5.1 (P) 返事の Reducer を実装する
  - 初期未選択、参加OK済みなら現在の時間を指定範囲として復元、選択肢と指定範囲、参加OK・見送り・取消の delegate、期限切れ・取消済みでの操作停止、失敗時の選択保持を実装する。
  - 完了条件：初期状態、各選択肢の範囲、1回の送信で `respond(.accepted, [range])`、取消で `respond(.declined, [])`、終了状態で送信不可、失敗後の選択保持の TestStore テストが通る。
  - _Requirements: 7.2, 7.3, 7.6, 7.8, 7.9, 7.10_
  - _Boundary: InvitationReplyFeature_
  - _Depends: 2.2_
- [x] 5.2 返事画面を Root に統合する
  - `InvitationReplyView`（主催者・内容・候補・期限、選択肢、候補の帯、伝わる情報と変更可能の説明、時刻入りの参加OKボタン、目立たない見送りと通知されない説明）を作り、ホームと受信箱から開く。delegate を既存の `respondToInvitation` に変換し、成功時は画面を閉じ受信箱を自動で開かない。
  - 旧 `InvitationResponseCard` と `InvitationResponseSelection` を削除する。
  - 完了条件：Root の TestStore で delegate から既存 Action と operationID 再利用が検証でき、Simulator で返事・変更・取消を操作できる。
  - _Requirements: 7.1, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9_
  - _Depends: 4.2, 5.1_

- [x] 6. ホームを再構成する
- [x] 6.1 (P) ホーム投影を実装する
  - `HomeDashboard.make` で区分の順序（提案・決まった予定を含む）、空区分の非表示と暇の区分の常時表示、主操作の切替、自動提案オフの表示、お知らせ件数（未回答の提案を含む）を計算する。
  - 完了条件：友達0人、友達あり、提案あり、確定予定あり、届いたお誘いあり、返事待ち、参加OKあり、案内終了後の各 snapshot で区分と件数のテストが通り、出力に配信人数・未回答者・見送り・相手の許可の情報を含まない。
  - _Requirements: 2.1, 2.3, 2.4, 2.5, 2.6, 2.8, 3.6, 7.1, 8.6_
  - _Boundary: HomeDashboard_
  - _Depends: 2.1, 2.4_
- [x] 6.2 ホーム画面、カレンダー画面、登録前画面を作り直す
  - `HomeView` を投影の区分（友達申請、提案と決まった予定（`SchedulingProposalCard`）、届いたお誘い、案内カード（準備3項目の操作を含む）、自分のお誘いと候補の帯・参加者・全員そろう時間・連絡手段の案内・取消確認、時間候補、暇の一覧と「この時間で誘う」「暇を追加」）で描画し、主操作を友達の有無で切り替える。時間軸と選択バーを `AvailabilityCalendarView` へ移し、`HostingListView` を削除する。
  - 登録前画面を main の3段階（暇の登録・自動提案の許可・参加OKで予定が決まる）と非公開の説明のまま維持し自分で誘えることを併記、お知らせの入口に件数を出す。友達一覧の各行に「誘う」を置く。区分ごとの読み込み中・失敗・再試行を表示する。
  - 完了条件：Simulator のデモで友達0人と友達ありの両方のホームが要件の順序で表示され、時間軸画面で既存の登録・区間削除・範囲からの誘いが動作し、既存の HomeTimeline テストが回帰しない。
  - _Requirements: 1.1, 1.2, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.8, 3.1, 3.2, 3.3, 3.7, 3.8, 6.3, 6.4, 8.2, 8.3, 8.4, 8.6, 11.1, 11.2, 11.3, 11.4_
  - _Depends: 4.2, 5.2, 6.1_
- [x] 6.3 参加OKの受け取りと案内の記録を統合する
  - ホーム表示時と前面復帰時に `reloadHostings` を行い、新着の参加OKを一時表示（最新1件と他の件数）してお知らせ件数に加え、表示時・お知らせ表示時に既読キーを保存する。完了条件を満たしたら案内を完了として保存し、閉じる操作とコード共有の記録を保存する。アカウント削除受付時に記録を消す。
  - デモのホームに「デモ操作」としてデモ友達の申請と参加OKを表示する（DEBUG のみ）。
  - 完了条件：Root の TestStore で新着検出→バナーと件数→既読保存、時間変更の再通知、案内完了・閉じるの保存と非表示、削除時の記録消去が検証でき、デモで参加OKを受け取る経路が Simulator で通る。
  - _Requirements: 3.3, 3.4, 3.5, 8.1, 8.5, 10.3_
  - _Depends: 2.3, 2.4, 3, 6.2_

- [x] 7. アプリ内の文言を「お誘い」「返事」「会い方」へ統一する
  - `AppView`、`AppFeature`、`HomeView`、`HomeTimelineView`、`TimelineGridViews`、`AvailabilityFormatting`、`AvailabilityModels`、`SystemActionReviewView` のお誘いに関するアプリ内表示から「募集」「招待」「回答」「開催形態」を置き換える。友達追加の「招待コード」「友達を招待する」と Intent 名・`AppShortcuts.xcstrings` は変えない。
  - 完了条件：対象ファイルのユーザー表示文字列に置換対象の語が残らないことを検索で確認し、文言を検証している既存テストを更新して通る。
  - _Requirements: 9.1, 9.2, 9.3_
  - _Depends: 6.3_

- [x] 9. 自動提案を主軸に main と統合する
- [x] 9.1 DEBUG デモで自動提案を再現する
  - Prototype シナリオに自動提案の状態（全体設定・友達別許可・提案）と execute（設定・許可・回答・取消）、提案の到着と相手の参加OKの操作を加え、`DemoScenarioClient.scheduling` として公開する。Composition で所有者 `demo` だけをデモへ振り分け、デモのプロフィール保存で自動提案を起動する。デモのホームに提案と相手の参加OKの操作を表示する。
  - 完了条件：デモで許可→提案→参加OK→相手の参加OK→確定→案内完了の TestStore テスト、振り分けのテストが通り、Simulator で同じ経路を操作できる。
  - _Requirements: 10.1, 10.5, 10.6_
  - _Boundary: HimatchPrototypeScenario, DemoScenarioClient, AppCompositionRoot, AppFeature_
- [x] 9.2 ホームと案内を自動提案の主軸へ切り替える
  - 案内の段階・準備3項目の操作、提案と決まった予定の区分、主操作「暇を登録」、自動提案オフの表示、件数への提案の加算、カレンダー画面への確定提案の表示を実装する。手動のお誘いは「自分で誘う」と友達画面に残す。
  - 完了条件：投影・段階のテストが通り、Simulator のデモで案内の各段階とホームの区分順を確認できる。
  - _Requirements: 2.1, 2.3, 2.5, 2.6, 2.8, 3.1, 3.4, 3.7, 3.8, 8.6_
  - _Depends: 9.1_

- [x] 10. 独立レビューの指摘を直す
- [x] 10.1 アカウント境界で画面状態を破棄し、遅れた結果を照合する
  - 切替・サインアウト・失効・削除受付・デモ開始で作成・返事・送信結果・バナー・表示済みキー・案内記録・操作ID・表示中の画面を破棄し、作成・返事・取消の結果 Action に開始時の所有者を付けて照合する。
  - 完了条件：切替時の破棄と旧アカウントの結果の破棄の TestStore テストが通り、既存の境界テストが更新後に通る。
  - _Requirements: 12.1, 12.2, 12.3_
- [x] 10.2 (P) 引き下げ更新と送信中の閉じる操作を直す
  - 引き下げ更新で友達・暇・お誘い・自動提案を再取得し、送信中はお誘い作成を閉じられないようにする。
  - 完了条件：引き下げ更新で友達を再取得するテストと、送信中の close が無視され operationID が保たれるテストが通る。
  - _Requirements: 2.7, 5.12_
- [x] 10.3 (P) 参加OK後の返事変更・取消の 409 を直す
  - `hosting_respond_before_scheduling` を版一致時に変更・取消・再参加を受け付ける関数へ置き換える migration と pgTAP を追加する。
  - 完了条件：Supabase CLI 2.117.0 の `db lint` と `test db` が成功し、修正前の関数では同じテストが失敗する。
  - _Requirements: 7.8_
  - _Boundary: supabase/migrations, supabase/tests/hosting.test.sql_

- [x] 8. 検証と文書の同期を完了する
- [x] 8.1 デモ主要経路の統合テストと構成検査を追加する
  - Prototype シナリオで、友達なし開始→プロフィール保存→コード共有→デモ申請承認→候補から作成→デモ参加OK→受け取り表示、と友達あり開始→届いたお誘いへの返事、を通す統合テストを追加する。Release 構成がシナリオとデモ client を含まないことを検査する。
  - 完了条件：統合テストと構成検査が通る。
  - _Requirements: 10.1, 10.2, 10.3, 10.4_
  - _Depends: 6.3_
- [x] 8.2 ビルド・テスト・Simulator での確認を行う
  - Debug と Release のビルド、全 Swift Testing、Simulator でのデモ一巡（友達0人→参加OK受け取り、返事・変更・取消、取消確認）を行い、最大の Dynamic Type と VoiceOver の読み上げ文言（候補の帯、状態の文字表示）を確認する。
  - 完了条件：ビルドとテストの結果、各画面のスクリーンショット、未実施の確認（実機・実 Backend の複数アカウント）を記録する。
  - _Requirements: 2.1, 5.1, 7.6, 8.2, 11.1, 11.2, 11.3_
  - _Depends: 7, 8.1, 9.2, 10.1, 10.2_
- [x] 8.3 製品・設計文書と仕様状態を同期する
  - `docs/product/overview.md` と `docs/architecture/ios-architecture.md` にホーム構成（自動提案を主軸）、子機能、端末内記録、アカウント境界、デモ境界を反映する。roadmap に仕様を加える。この仕様と影響を受けた仕様の freshness と完了状態を sync で更新し、リポジトリ外の資料を参照しない。
  - 完了条件：コミット単体で `okf.py check` がリポジトリ全体で問題を出さず、実装と文書の記述が一致する。
  - _Requirements: 9.1, 10.4_
  - _Depends: 8.2_
