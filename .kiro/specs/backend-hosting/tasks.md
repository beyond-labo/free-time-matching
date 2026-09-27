---
type: Implementation Plan
title: "Backend 友達招待実装計画"
description: "実招待、回答、取消、認可と検証"
status: stable
sources:
  - id: backend-hosting-design
    resource: ./design.md
    title: Backend 友達招待設計
kiro:
  depends_on:
    - .kiro/specs/backend-hosting/requirements.md
    - .kiro/specs/backend-hosting/design.md
---

# Implementation Plan

- [x] 1. 募集と受信者別回答のDB・RLS・RPCを追加する
  - 本人暇との原子的作成、承認済み友達全件検証、再送とversion、取消・期限をDBテストで確認する。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.2, 2.3, 2.4, 2.5, 4.4, 4.5, 5.1, 5.2, 5.3, 5.4_
  - _Boundary: HostingData, HostingPrivacy_
  - _Depends: backend-availability task 6_

- [x] 2. Worker APIと役割別投影を実装する
  - 作成、一覧、詳細、部分回答、辞退、取消の入力・応答・エラーを固定し、非公開情報がレスポンスとログへ出ないことを確認する。
  - _Requirements: 1.1, 2.1, 3.1, 3.2, 3.3, 3.4, 4.1, 4.2, 4.3, 4.4, 6.3_
  - _Boundary: HostingPresentation, HostingRepository_
  - _Depends: 1_

- [ ] 3. 実招待の縦断検証を行う
  - 別actor・非友達・同時再送・期限・取消・募集中削除と2アカウントの送受信を確認し、未実施環境検証を区別して記録する。
  - _Requirements: 1.3, 2.4, 2.5, 3.1, 4.4, 5.2, 6.1, 6.2_
  - _Boundary: HostingValidation_
  - _Depends: 1, 2_
