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
