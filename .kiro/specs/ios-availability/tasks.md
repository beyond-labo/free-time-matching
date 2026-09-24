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
  - 半開区間、15分境界、14日範囲、重複、公開設定、Repository / UseCase が純粋テストで検証できる。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.3, 5.1, 5.2_
  - _Boundary: AvailabilityDomain, AvailabilityApplication_

- [ ] 2. Prototype Adapter を実装する
  - 作成・更新・削除、version conflict、失敗を再現し、Reducer から直接保存状態へ触れない。
  - _Requirements: 4.1, 4.2, 4.3, 4.4_
  - _Boundary: PrototypeAvailabilityAdapter_
  - _Depends: 1_

- [ ] 3. ホーム時間軸を実装する
  - 自分の暇と確定予定、日時固定、新規登録、原因別の空状態を操作できる。
  - 進捗（2026-09-24）: 日／週カレンダー、14日の移動、タップで15分選択、長押しドラッグの15分範囲選択、スクロール競合回避、範囲ハンドル、直接確認、VoiceOver代替操作、暇なし表示、自分の暇と確定予定だけの表示を実装し、Reducer・選択純粋関数・AppFeature のテストで確認した。読み込み失敗の状態は `HimatchClient.load` が失敗を返さないため未実装。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.6, 2.7, 5.3, 5.4_
  - _Boundary: HomeTimelineFeature_
  - _Depends: 1, 2_

- [ ] 4. 暇時間編集シートを実装する
  - 初期2時間、15分調整、カテゴリ、公開説明、編集・削除、関連 Hosting 導線を操作できる。
  - 進捗（2026-09-23）: 新規登録の初期2時間、開始・終了の15分調整とプリセット、日付またぎ、検証理由の表示、重複時の既存枠への誘導、カテゴリ、非公開初期値と公開説明、削除、保存失敗時の入力保持を実装し、TestStore で確認した。既存枠の編集保存と関連 Hosting 導線は未実装。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 4.1, 4.2, 4.3, 4.4_
  - _Boundary: AvailabilityEditorFeature_
  - _Depends: 2, 3_

- [ ] 5. 暇時間の統合検証を完了する
  - Domain/Application/Reducer テストと Simulator 上の登録・編集・削除が成功する。
  - 進捗（2026-09-24）: 補助テスト13件と Swift Testing 105件（直接選択、認識後のアンカー保持、正規化、日境界、閾値、即時・保存直前検証、直接登録、失敗保持、詳細引継ぎを含む）が成功した。Simulator で通常スワイプが選択を誤発火せずスクロールすることと、0.4秒長押しが15分選択になることを確認した。押下を保持したまま移動する実ドラッグと VoiceOver は手動確認待ち。
  - _Requirements: 1.1, 1.3, 1.5, 1.6, 1.7, 2.1, 2.2, 2.3, 2.4, 2.6, 2.7, 3.1, 3.4, 4.1, 4.4, 5.1, 5.2, 5.3, 5.4_
  - _Boundary: AvailabilityValidation_
  - _Depends: 1, 2, 3, 4_
