---
type: Implementation Plan
title: "iOS 募集・招待実装計画"
description: "時間軸からの実招待、部分回答、取消と受信箱"
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

# Implementation Plan

- [x] 1. Hosting のドメインと Backend Adapter を実装する
  - 型付き招待先、候補半開区間、募集中・取消・期限切れ、回答の区間、operationID/version と役割別 DTO を扱う。
  - _Requirements: 1.2, 2.1, 2.2, 2.3, 2.4, 3.6, 5.1, 7.1, 7.3_
  - _Boundary: HostingDomain, BackendHostingAdapter_
  - _Depends: backend-hosting_

- [x] 2. 暇登録と共通の時間軸から募集を作る
  - 新規選択、既存暇の詳細、友達プロフィールから開き、選択範囲と友達・開催条件を保持して実Backendへ送る。未登録範囲は募集と原子的に暇へ登録する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 7.2_
  - _Boundary: HostingCreationFeature, TimelineSelection_
  - _Depends: 1, ios-availability_

- [x] 3. 招待受信・部分回答・辞退・取消を実装する
  - 受信箱で最新状態を取得し、15分単位の一部を参加OKまたは辞退する。ホストは参加OKだけを確認でき、募集中部分を一般の暇と区別する。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 5.1, 5.2, 5.3, 5.4, 5.5, 6.1, 6.2, 6.3, 6.4_
  - _Boundary: HostingDetailFeature, InboxFeature, HomeProjection_
  - _Depends: 1, 2_

- [ ] 4. 実Backend経路を検証する
  - Release CompositionがPlaceholderではなくBackendを注入すること、失敗時に入力を保持すること、2アカウントの送信・回答・取消を確認する。実STG未実施は成功と記録しない。
  - _Requirements: 1.5, 2.1, 2.3, 3.2, 3.7, 5.3, 6.2, 7.1, 7.2, 7.3, 7.4_
  - _Boundary: HostingValidation_
  - _Depends: 1, 2, 3_

旧タスクの予定確定・離脱は今回の実装完了条件から外す。現行Releaseで提供しているとは報告しない。
