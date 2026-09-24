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
- ホームは本人の暇と確定予定だけを集約し、友達の暇を導入しない。

## Design Decisions

### Decision: 半開区間を採用する

- **Selected Approach**: `[start, end)`。
- **Rationale**: 連続する枠を重複扱いせず、照合の共通部分を一貫して計算できる。

### Decision: 公開範囲の広い値を継承しない

- **Selected Approach**: 新規枠は常に `privateUntilAccepted`。
- **Rationale**: 操作回数より誤公開防止を優先する。

### Decision: ホーム時間軸を日表示と週表示のカレンダーにする

- **Selected Approach**: 要件1.1の縦時間軸を、24時間の日表示と7列の週表示で切り替える。週は今日を起点に7日×2ページとし、月曜始まりにしない。アクセシビリティ文字サイズでは週表示を日ごとの一覧に置き換える。
- **Rationale**: 空いている時間帯と既存枠の位置を一覧より速く把握できる。今日起点にすると14日範囲外の日を表示せずに済む。7列はアクセシビリティ文字サイズで判読できない。

### Decision: 時間軸の直接選択を主動線、編集シートを補助動線にする

- **Selected Approach**: 日表示のタップは15分を画面内で選択し、0.3秒の長押し成立後のドラッグは連続範囲を選択する。長押し前に10ptを超えて動けば選択を成立させずスクロールへ譲る。選択後は明示的な「非公開で登録」で保存でき、カテゴリや公開設定を変える場合だけ「詳細を調整」からシートを開く。編集シートでは±15分、長さプリセット、`UIDatePicker.minuteInterval = 15` を引き続き提供する。
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
- Home が Hosting データを所有する — 確定予定は表示用契約だけ受け取り、ライフサイクルは Hosting に残す。

## Change Log

- 2026-09-20: ユーザー提示の時間・公開ルールを新規仕様へ反映。
- 2026-09-24: ユーザー依頼（暇登録動線とデザイン品質の改善）に基づき、日／週カレンダー、15分入力、秒を含む境界判定、共通デザイン部品の判断を追加した。要件は変更せず、設計の Presentation 契約とファイル構成を実装に合わせて具体化した。根拠は `apps/ios/Himatch/Availability/` と `apps/ios/HimatchTests/` の実装、および Swift Testing 81件の成功。
- 2026-09-24: 追加のユーザー指示に基づき、時間軸タップと長押しドラッグを主動線へ変更した。スクロール競合は UIKit 認識器の所有権と0.3秒・10ptの成立条件で分離し、明示確認、無効理由、ハンドル、触覚、VoiceOver代替操作を追加した。根拠は直接選択の実装、補助テスト13件・Swift Testing 105件の成功、Simulator での通常スクロール非誤発火と長押し15分選択の確認。
