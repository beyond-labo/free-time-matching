---
type: Implementation Plan
title: "iOS 募集・招待実装計画"
description: "手動のお誘い作成、選択肢からの返事、取消と受信箱"
status: stable
sources:
  - id: ios-hosting-design
    resource: ./design.md
    title: iOS 募集・招待設計
kiro:
  depends_on:
    - .kiro/specs/ios-hosting/requirements.md
    - .kiro/specs/ios-hosting/design.md
---

> 適用範囲（2026-10-29）: この文書は既存の手動募集・招待・部分回答の互換性契約を記録する。第一段階の中心は [自動提案・予定成立](../automatic-friend-scheduling/requirements.md) へ置換した。本文の「対象外」は手動Hosting境界の対象外を意味し、製品全体の自動確定・通知を後続へ送る判断には使わない。既存タスクの完了は自動提案の達成証拠ではない。


# Implementation Plan

- [x] 1. Hosting のドメインと Backend Adapter を実装する
  - 型付き招待先、候補半開区間、募集中・取消・期限切れ、回答の区間、operationID/version と役割別 DTO を扱う。
  - _Requirements: 1.2, 2.1, 2.2, 2.3, 2.4, 3.6, 5.1, 7.1, 7.3_
  - _Boundary: HostingDomain, BackendHostingAdapter_
  - _Depends: backend-hosting_

- [x] 2. ホームの各入口から手動のお誘いを作る
  - 「自分で誘う」、時間候補、既存暇の詳細、カレンダーの選択範囲、友達プロフィールから `InvitationComposerFeature` を開き、引き継いだ範囲または友達と会い方を保持して実Backendへ送る。未登録範囲はお誘い作成と原子的に暇へ登録する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 7.2_
  - _Boundary: InvitationComposerFeature, InvitationComposerView, InvitationStart, AppFeature_
  - _Depends: 1, ios-availability_

- [x] 3. お誘い受信・選択肢からの返事・見送り・取消を実装する
  - Home / Inbox で最新状態を取得し、候補全体・前半・後半・15分単位の時間指定から1つを選んで参加OKまたは見送りを送る。ホストは参加OKだけを確認でき、お誘い中の部分を一般の暇と区別する。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 5.1, 5.2, 5.3, 5.4, 5.5, 6.1, 6.2, 6.3, 6.4_
  - _Boundary: InvitationReplyFeature, InvitationReplyView, ReplyChoicePolicy, HomeDashboard, AppFeature_
  - _Depends: 1, 2_

- [ ] 4. 実Backend経路を検証する
  - Release CompositionがPlaceholderではなくBackendを注入すること、失敗時に入力を保持すること、2アカウントの送信・回答・取消を確認する。実STG未実施は成功と記録しない。
  - _Requirements: 1.5, 2.1, 2.3, 3.2, 3.7, 5.3, 6.2, 7.1, 7.2, 7.3, 7.4_
  - _Boundary: HostingValidation_
  - _Depends: 1, 2, 3_

旧タスクの予定確定・離脱は今回の実装完了条件から外す。現行Releaseで提供しているとは報告しない。
