---
type: Research
title: "iOS 暇時間調査"
description: "日時表現、重複、ホーム表示境界の設計判断"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
kiro:
  depends_on:
    - docs/architecture/api-contracts.md
    - docs/architecture/ios-architecture.md
---

# 調査と設計判断

## Summary

- 絶対時刻の半開区間と表示タイムゾーンを分ける。
- 15分の離散マスを永続表現にせず、区間を Domain の正本とする。
- ホームは本人の暇と募集中候補を区別して表示する。確定予定は Prototype の旧表示に限り、Release で実 Backend から提供される状態とは扱わない。友達の暇は導入しない。

## Design Decisions

### Decision: 0.1.7 はリスト初期表示と明示的なカレンダー切替にする

- **Selected Approach**: 日付別・開始時刻順のリストを初期表示し、上部の「リスト／カレンダー」で既存の日・週カレンダーへ切り替える。選択日、未保存範囲、スクロール位置をセッション内で保持する。
- **Rationale**: 関係する予定候補を素早く確認する入口をリストにし、日時選択にカレンダーを使う。縦方向に両方を並べると項目増加でカレンダーへ到達しにくくなる。
- **Boundary**: モックの友達の暇一覧へデータ契約を拡大しない。Release は本人暇と募集中候補、確定予定は DEBUG fixture に限定する。設定永続化と最終確定は追加しない。
- **Superseded**: 下記2026-09-24のカレンダー設計はカレンダー内部の契約として保持し、ホーム初期表示については本決定へ置換する。

### Decision: 半開区間を採用する

- **Selected Approach**: `[start, end)`。
- **Rationale**: 連続する枠を重複扱いせず、照合の共通部分を一貫して計算できる。

### Decision: 公開範囲の広い値を継承しない

- **Selected Approach**: 新規枠は常に `privateUntilAccepted`。
- **Rationale**: 操作回数より誤公開防止を優先する。

### Decision: カレンダーを日表示と週表示で提供する

- **Selected Approach**: 要件1.1のカレンダー内の縦時間軸を、24時間の日表示と7列の週表示で切り替える。週は今日を起点に7日×2ページとし、月曜始まりにしない。アクセシビリティ文字サイズでは週表示を日ごとの一覧に置き換える。
- **Rationale**: カレンダーでは空いている時間帯と既存枠の位置を把握できる。今日起点にすると14日範囲外の日を表示せずに済む。7列はアクセシビリティ文字サイズで判読できない。

### Decision: 時間軸の直接選択を主動線、編集シートを補助動線にする

- **Selected Approach**: 日表示のタップは15分を画面内で選択し、0.3秒の長押し成立後のドラッグは連続範囲を選択する。長押し前に10ptを超えて動けば選択を成立させずスクロールへ譲る。同じ選択を「暇を登録」「友達を誘う」「暇を削除」の各モードで使い、属性衝突がある登録は統合後の値を確認する。編集シートでは±15分、長さプリセット、`UIDatePicker.minuteInterval = 15` を引き続き提供する。
- **Rationale**: 15分だけの登録はタップと確認、任意範囲は長押しドラッグと確認の2操作で完結する。選択と保存を分離することで、直接操作の速さを得ながら誤登録を防ぐ。初回の SwiftUI `LongPressGesture.sequenced(before: DragGesture())` は子認識器が縦スクロールを遮ったため、透明な `UIViewRepresentable` 上の tap / long-press と祖先 `UIScrollView` の pan が「先に成立した認識器」を所有する構成へ置き換えた。
- **Fool-proof / Affordance**: 未選択時に操作ヒントを出し、長押し成立と15分境界の変更を触覚で返す。選択範囲、時刻、長さ、ハンドルを表示し、無効状態は色だけでなく破線・アイコン・理由で示す。VoiceOver には15分選択、端点調整、登録、詳細、取消の代替操作を提供する。
- **Superseded**: 2026-09-24 初回実装の「長押しドラッグを採用しない」という判断は、最小操作という製品価値を満たさないため本決定で置き換える。

### Decision: 15分境界の判定に秒とナノ秒を含める

- **Selected Approach**: `AvailabilityPolicy.isQuarterHourAligned` で分・秒・ナノ秒を判定し、`validate` もこれを使う。
- **Rationale**: 分だけの判定では 10:15:30 のような値が通っていた。15分境界の意味は変えず、判定を正確にするだけである。

### Decision: 共通デザイン部品は App の Presentation に置く

- **Selected Approach**: 色、余白、角丸、最小タップ領域、ボタンやカードの部品を `App/Presentation/DesignSystem/` に置く。
- **Rationale**: `Platform` は SwiftUI に依存しない方針であり、共通UIは ios-app-foundation の Presentation が所有する。

## Risks & Mitigations

- DST / timezone 変更 — Calendar で表示だけ変換し、保存は絶対時刻。
- Home が Hosting データを所有する — 募集中候補は Hosting から表示用投影だけを受け取り、ライフサイクルは Hosting に残す。

## Change Log

- 2026-10-04: ホームUI相談結果とユーザーの0.1.7対応指示を根拠に、要件1.1、1.2、1.8–1.12、設計、タスク8を改訂した。今回の改訂範囲は仕様生成・実装の許可対象とし、既存の未承認工程全体への承認は付与しない。タスク8の検証結果は下記の0.1.7検証記録を参照する。

- 2026-09-27: 時間軸の3操作を同じ選択範囲から開始し、募集中候補を投影する実装に合わせて現行判断を修正した。旧確定予定の表示は Prototype 限定の履歴として扱う。
- 2026-09-27: OR統合時の属性明示確認、選択区間の減算、募集中削除時の取消導線を実装し、iPhone Simulator の Swift Testing 121件で関連 Reducer と区間選択を確認した。STG反映後の複数アカウント操作は未実施。
- 2026-09-26: ユーザーが暇のOR統合、選択範囲の複数枠からの減算、募集中候補の削除禁止とその範囲だけの状態表示を確定した。旧「重複は保存不可・既存枠へ誘導」は現行要件では失効し、区間APIと時間軸操作へ置き換える。根拠は会話の計画承認と `ios-availability` 要件2.4、4.5–4.6、7。
- 2026-09-25: 初回起動時の友達・暇 GET を各領域の読み込み状態で表示する方針に同期した。暇 GET の失敗時は空枠と区別して再試行を表示し、全面オーバーレイを使わない。根拠は `AppFeature.swift`、`HomeView.swift`、`ios-app-integration` 要件3.10。
- 2026-09-25: Release の本人枠 GET が失敗した場合の空一覧への握り潰しと、保存中に古い GET が返る競合を修正した。利用者 ID と更新番号で反映を制限し、HTTP 区間の signpost と安全な request ID 記録を追加した。登録・削除後の GET は現行 snapshot 契約の整合性を保つため継続し、遅延分析上の直列通信として記録した。根拠は `AppCompositionRoot.swift`、`AppFeature.swift`、`BackendAvailabilityAdapter.swift`、`docs/operations/availability-latency.md`。
- 2026-09-25: 内部TestFlightのReleaseで暇登録が `productionPlaceholder` の固定エラーに終わり、Workerへ到達しないことをコードで確認。ユーザー指示により本人限定の登録・参照・削除をBackendへ接続する要件6とタスク6を追加した。既存の編集・version契約は将来の課題として残し、初回APIのPUTは新規作成と同内容再送だけに限定する。根拠は `AppCompositionRoot.swift`、`HimatchClient.swift`、`docs/architecture/api-contracts.md`。

- 2026-09-20: ユーザー提示の時間・公開ルールを新規仕様へ反映。
- 2026-09-24: ユーザー依頼（暇登録動線とデザイン品質の改善）に基づき、日／週カレンダー、15分入力、秒を含む境界判定、共通デザイン部品の判断を追加した。要件は変更せず、設計の Presentation 契約とファイル構成を実装に合わせて具体化した。根拠は `apps/ios/Himatch/Availability/` と `apps/ios/HimatchTests/` の実装、および Swift Testing 81件の成功。
- 2026-09-24: 追加のユーザー指示に基づき、時間軸タップと長押しドラッグを主動線へ変更した。スクロール競合は UIKit 認識器の所有権と0.3秒・10ptの成立条件で分離し、明示確認、無効理由、ハンドル、触覚、VoiceOver代替操作を追加した。根拠は直接選択の実装、補助テスト13件・Swift Testing 105件の成功、Simulator での通常スクロール非誤発火と長押し15分選択の確認。

## 0.1.7 の仕様同期と検証（2026-10-07）

ユーザーのホームリスト初期表示・カレンダー切替の依頼とClaude CLI Opus 5.5の相談を根拠に、要件1.1、1.2、1.8–1.12と設計・タスク8を同期した。モックの友達との予定を実Backend機能として拡張せず、本人暇・募集中候補とDEBUG fixtureの境界を維持した。

変更後コードに対する2026-10-04のSwift Testing 168件成功・0失敗（`test_sim_2026-10-04T12-18-59-707Z_pid86946_de41bb08.xcresult`）とSimulator確認を再利用した。HomeTimelineFeatureTestsは初期リスト・切替時入力保持・保存中の切替禁止、TimelineLayoutTestsは終了済み除外・順序・日付境界、AppFeatureDemoDependencyTestsはデモと実依存の分離・招待時カレンダー遷移を確認する。Simulatorでは初期リスト、切替、翌日選択の保持、リスト詳細とプロフィール招待導線を確認済み。長押し実ドラッグとVoiceOverの手動検証、既存編集機能の未実装は今回の完了範囲に含めない。

XcodeBuildMCPのDebugビルド（`build_sim_2026-10-06T23-52-10-758Z_pid23618_378275e8.log`）とReleaseビルド（`build_sim_2026-10-06T23-53-40-257Z_pid23618_1f2340dd.log`）が成功した。既存のSiri確認APIの非推奨警告1件が残る。

逆参照を照合し、Hostingの候補区間・回答・認可、Siriの日時引継ぎ・本人束縛・通常実依存、Backend Availabilityの15分境界・OR・区間減算・非公開契約には意味変更がないと判断した。これらの承認と既存タスク状態は維持する。roadmapの時間軸所有境界も維持する。
