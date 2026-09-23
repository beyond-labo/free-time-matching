---
type: Implementation Plan
title: "Backend 友達関係実装計画"
description: "DB、API、iOS の STG 実接続、統合検証の実装計画"
status: stable
sources:
  - id: backend-friendship-design
    resource: ./design.md
    title: Backend 友達関係設計
kiro:
  depends_on:
    - .kiro/specs/backend-friendship/requirements.md
    - .kiro/specs/backend-friendship/design.md
---

# Implementation Plan

- [x] 1. 友達関係の DB schema と transactional RPC を実装する
  - code、申請、unordered friendship、version、operation ID の制約と actor 認可を migration・pgTAP で検証できる。
  - _Requirements: 1.2, 1.4, 1.5, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4, 3.5, 4.3, 4.4, 4.5_
  - _Boundary: FriendshipData_

- [x] 2. Backend Domain / UseCase / Repository を実装する
  - 初回コード自動発行、乱数と hash、snapshot、解決、申請遷移、競合、再送を単体検証できる。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5, 4.1, 4.2, 4.3, 4.4, 4.5_
  - _Boundary: FriendshipDomain, FriendshipApplication, FriendshipInfrastructure_
  - _Depends: 1_

- [x] 3. Friendship HTTP API と Composition を実装する
  - 全 endpoint が JWT actor、公開 DTO、共通 code error、409 conflict、既存 error envelope を route test で満たす。
  - _Requirements: 1.4, 1.5, 2.1, 2.2, 2.5, 3.1, 3.2, 3.3, 3.4, 4.1, 4.2, 4.3, 4.5_
  - _Boundary: FriendshipPresentation, BackendComposition_
  - _Depends: 2_

- [x] 4. iOS Friendship Adapter と友達操作 UI を STG 実接続する
  - STG 設定の認証後にコードが表示され、コード確認後の申請、承認・拒否・取消・解除・再発行と競合 reload を Adapter / Reducer test で検証できる。
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_
  - _Boundary: IOSFriendshipClient, IOSFriendshipPresentation, IOSComposition_
  - _Depends: 3_

- [x] 5. 公開契約・仕様同期と縦断検証を完了する
  - API 文書、iOS 仕様、roadmap が実装境界と一致し、Backend test/typecheck/build、iOS test/build、OKF check の証拠が揃う。
  - _Requirements: 1.1, 1.4, 2.1, 2.5, 3.1, 3.4, 4.1, 4.5, 5.1, 5.4, 5.5, 5.6_
  - _Boundary: FriendshipValidation_
  - _Depends: 1, 2, 3, 4_
