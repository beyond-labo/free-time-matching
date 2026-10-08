---
type: Implementation Plan
title: "iOS 暇時間実装計画"
description: "時間ポリシー、Repository、ホーム、編集、検証の実装計画"
status: stable
sources:
  - id: ios-availability-design
    resource: ./design.md
    title: iOS 暇時間設計
kiro:
  depends_on:
    - .kiro/specs/ios-availability/requirements.md
    - .kiro/specs/ios-availability/design.md
---

# Implementation Plan

- [ ] 1. 暇時間の Domain と Application 境界を実装する
  - 半開区間、15分境界、14日範囲、OR統合・区間差、公開設定、Repository / UseCase が純粋テストで検証できる。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.3, 5.1, 5.2_
  - _Boundary: AvailabilityDomain, AvailabilityApplication_

- [ ] 2. Prototype Adapter を実装する
  - 作成・更新・削除、version conflict、失敗を再現し、Reducer から直接保存状態へ触れない。
  - _Requirements: 4.1, 4.2, 4.3, 4.4_
  - _Boundary: PrototypeAvailabilityAdapter_
  - _Depends: 1_

- [ ] 3. ホーム時間軸を実装する
  - 本人暇と募集中候補、DEBUG fixture の確定予定、日時固定、新規登録、原因別の空状態を操作できる。
  - 進捗（2026-09-24）: 日／週カレンダー、14日の移動、タップで15分選択、長押しドラッグの15分範囲選択、スクロール競合回避、範囲ハンドル、直接確認、VoiceOver代替操作、暇なし表示、自分の暇と確定予定だけの表示を実装し、Reducer・選択純粋関数・AppFeature のテストで確認した。読み込み失敗の状態は `HimatchClient.load` が失敗を返さないため未実装。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.6, 2.7, 5.3, 5.4_
  - _Boundary: HomeTimelineFeature_
  - _Depends: 1, 2_

- [ ] 4. 暇時間編集シートを実装する
  - 初期2時間、15分調整、カテゴリ、公開説明、編集・削除、関連 Hosting 導線を操作できる。
  - 2026-09-23 の実装は重複時の既存枠への誘導とID単位削除であり、今回のOR統合・区間削除・Hosting導線の検証には使えない。既存枠の内容編集保存も別途未実装。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 4.1, 4.2, 4.3, 4.4_
  - _Boundary: AvailabilityEditorFeature_
  - _Depends: 2, 3_

- [ ] 5. 暇時間の統合検証を完了する
  - Domain/Application/Reducer テストと Simulator 上の登録・編集・削除が成功する。
  - 進捗（2026-09-24）: 補助テスト13件と Swift Testing 105件（直接選択、認識後のアンカー保持、正規化、日境界、閾値、即時・保存直前検証、直接登録、失敗保持、詳細引継ぎを含む）が成功した。Simulator で通常スワイプが選択を誤発火せずスクロールすることと、0.4秒長押しが15分選択になることを確認した。押下を保持したまま移動する実ドラッグと VoiceOver は手動確認待ち。
  - _Requirements: 1.1, 1.3, 1.5, 1.6, 1.7, 2.1, 2.2, 2.3, 2.4, 2.6, 2.7, 3.1, 3.4, 4.1, 4.4, 5.1, 5.2, 5.3, 5.4_
  - _Boundary: AvailabilityValidation_
  - _Depends: 1, 2, 3, 4_

- [ ] 6. Release の暇登録・再読込・削除を Backend へ接続する
  - 認証済み利用者JWTで本人の枠を登録・取得・削除し、再起動後の再読込と失敗時の入力保持を Adapter/Reducer テストで確認する。STGへの実通信は配備後に別途確認する。
  - _Requirements: 1.4, 4.4, 6.1, 6.2, 6.3, 6.4_
  - _Boundary: BackendAvailabilityAdapter, AppCompositionRoot, AppFeature_
  - _Depends: 3, backend-availability_

- [x] 7. 時間軸のOR登録・削除モード・募集中投影を実装する
  - 重複・接続した暇を属性確認後に統合し、選択範囲を複数枠から差し引く。募集中候補に触れた削除は止めて取消へ案内し、失敗時は選択を保持する。
  - _Requirements: 2.4, 2.7, 4.5, 4.6, 6.5, 7.1, 7.2, 7.3_
  - _Boundary: AvailabilityPolicy, HomeTimelineFeature, BackendAvailabilityAdapter_
  - _Depends: 3, 4, backend-availability, ios-hosting_

- [x] 8. 0.1.7 のホームリスト初期表示とカレンダー切替を実装する
  - 初期値 list、明示切替UI、日付別・開始時刻順・終了済み除外・種別ラベルを提供する。
  - 切替前後の選択日、未保存範囲、カレンダースクロール位置を保持し、リストから詳細・登録・招待へ遷移する。保存中は切替できない。
  - Release の本人暇・募集中候補、DEBUG の予定限定、Siri の日時引継ぎ、既存の日・週表示と直接選択を検証する。
  - _Requirements: 1.1, 1.2, 1.8, 1.9, 1.10, 1.11, 1.12, 7.1, 7.2, 7.3_
  - _Boundary: HomeTimelineFeature, HomeTimelineView, HomeView, AppFeature_
  - _Depends: 3, 7_

  - 検証（2026-10-04）: Swift Testing 168件成功・0失敗。初期リスト、カレンダー切替、翌日選択後の保持、リストからの詳細、友達プロフィールからの招待遷移を Simulator で確認した。長押し実ドラッグと VoiceOver の手動確認はタスク5の残件を維持する。2026-10-07のXcodeBuildMCP Debug/Releaseビルドも成功。
