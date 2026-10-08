---
type: Research
title: "iOS アプリ統合調査"
description: "機能間依存、読み取り投影、プロトタイプ整合性の設計判断"
status: stable
sources:
  - id: ios-spec-cross-review
    resource: conversation://2026-09-20/ios-spec-cross-review
    title: iOS 初版仕様間レビュー
kiro:
  depends_on:
    - .kiro/steering/roadmap.md
---

# 調査と設計判断

## Summary

- Home / Inbox / FriendProfile は複数所有データを表示するため、単一機能へ吸収すると循環する。
- 読み取り投影と変更 UseCase を分けることで業務データの二重所有を避けられる。
- 共有 prototype は Composition のみに置き、各機能へ facet を注入する。

## Design Decisions

### Decision: App integration を独立仕様にする

- **Alternatives Considered**: Foundation へ全状態を集約、各機能が相互 import、別々の fixture。
- **Selected Approach**: read model と shared scenario を下流 Integration が所有する。
- **Rationale**: 依存循環と fixture 不整合を避け、Production Adapter 交換点を保つ。

## Risks & Mitigations

- prototype が巨大な本番モデルになる — デモ専用とし、本番では API projection を使用する。
- actor 一つが並行性挙動を隠す — 本番の競合・冪等性は Backend 検証対象として別扱いにする。

## Change Log

- 2026-09-27: Release に予定確定 Backend がないため、Home と友達プロフィールの確定予定投影、および確定フローの fixture 検証を DEBUG Prototype に限定した。根拠は今回の承認済み計画の「最終確定は対象外」と既存の実 API 契約。
- 2026-09-26: Release Composition の Hosting Placeholder を実Backend Adapterへ置き換え、受信箱の招待・部分回答を別アカウント間で扱う契約へ更新した。根拠はユーザーが承認した実招待計画と backend-hosting 要件。

### 2026-09-25

内部TestFlightのReleaseで暇登録が `HimatchClient.productionPlaceholder` から `PrototypeError.notFound` を返し、通信に到達しないことをコードで確認した。ユーザーの実接続依頼により、Release Compositionへ `BackendAvailabilityAdapter` を追加する。DEBUGデモのPrototypeは維持する。要件3.6、3.9と設計・タスク3を改訂し、旧タスク完了と工程承認は新しい契約の証拠にならないため再評価する。

2026-09-25: 初回起動の読み込みを再点検したところ、友達の GET がメイン画面遷移後も共通 `isLoading` の全面オーバーレイを出していた。ユーザーの部分読み込み要求に合わせ、友達と暇の取得状態を独立させ、画面内の進捗・失敗・再試行へ移した。セッションと削除受付状態、プロフィール有無の判定は遷移先とアクセス可否を決めるため先行する。根拠は `AppFeature.swift`、`AppView.swift`、`HomeView.swift` と Swift Testing の部分読み込みテスト。

### 2026-09-21

ユーザーのiOSテスト戦略に合わせ、単体・Reducer・統合テストをSwift Testingへ統一した。`xcodebuild test`と既存test targetは維持し、repository verifyとCIでXCTestのimport・継承の再混入とテスト0件を拒否する。

認証・プロフィール・削除とFriendshipは実Backend Adapterを標準とし、Release CompositionでPrototypeへフォールバックしない。最初の内部TestFlightはSTGへ接続する。共有Prototype scenarioはDEBUGデモと未接続の暇・募集へ限定する。

### 2026-09-23

Friendship の実 Backend 契約追加に合わせ、Release Composition が `BackendFriendshipAdapter` を注入する境界と STG-first の接続方針を同期した。DEBUG デモの再現可能な Friendship fixture は維持するが、Release の状態正本にはしない。

Root Composition と友達状態の統合を iPhone 17 Pro Max Simulator でビルドし、Swift Testing 33 件で確認した。STG 実アカウントを使う縦断 smoke は配備後の手動確認として残す。

削除状態の復元をRoot起動より先に判定し、Supabase SDKの初期session eventが保留中の削除を追い越して通常画面を復元しないようにした。

- 2026-09-20: 独立仕様間レビューの Critical 指摘を受けて新規作成。

### 2026-10-04: Siri操作の実装同期


共通実依存の組立てをAppRuntimeへ集約し、通常Debug/ReleaseとSiriは同じBackend構成、明示デモのみPrototypeにした。AppViewの起動・scene active・main遷移・通知からRootがFIFO引継ぎを検査し、本人変更/サインアウト/退会受付で旧本人操作を失効する。Siriの本人束縛Clientはmutation後GETを省略し、通常RootはGETを維持する。根拠はAppRuntime/AppCompositionRoot/AppFeature/AppView/SystemActionHandoffの現行実装とSwift Testingの確認済み結果。実装検証はios-siri-actionsタスクへ集約する。既存要件は維持し、旧承認falseと未完了タスクを今回の部分検証だけで全体承認・完了へ変更しない。

- 2026-10-04: 独立Siri実装レビューP1-2の修正方針を同期。プロフィール通信の失敗からnil-ownerへ落とさず、session本人の識別とプロフィールを含む実行gateを分離する。ログアウト時はentityOwnerの一致とnil-owner未送信記録も破棄する。修正後の実装・回帰照合はios-siri-actionsタスク2/5/6で行う。

## 0.1.7 の明示デモ依存修復（2026-10-07）

0.1.7 のホーム smoke で、明示DEBUGデモのプロフィール保存が実Backend Clientへ流れて失敗する既存不具合を発見した。Composition の `demoClient` 注入と `isDemo` 条件で修復し、要件3.6のデモ境界へ同期する。Release認可・通常Debug・Siri契約を変更せず、既存未完了タスクや未承認工程を今回の部分検証だけで完了へ変更しない。

`AppFeatureDemoDependencyTests` の明示デモ保存・通常実依存・プロフィール招待遷移を含むSwift Testing 168件成功（2026-10-04）の証拠を再利用し、2026-10-07にXcodeBuildMCPでDebug/Releaseビルド成功を確認した。ホーム両表示は同じ読み取りsnapshotを使い、最終予定確定や友達の暇を追加しない。全機能統合のタスク3/4は未完を維持する。
