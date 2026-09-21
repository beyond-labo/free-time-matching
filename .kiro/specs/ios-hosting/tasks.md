---
type: Implementation Plan
title: "iOS 募集・招待・予定実装計画"
description: "Domain、Repository、募集、詳細、受信箱、統合検証の計画"
status: stable
sources:
  - id: ios-hosting-design
    resource: ./design.md
    title: iOS 募集・招待・予定設計
kiro:
  depends_on:
    - .kiro/specs/ios-hosting/requirements.md
    - .kiro/specs/ios-hosting/design.md
---

# Implementation Plan

- [ ] 1. Hosting Domain と時間・遷移ポリシーを実装する
  - 募集、回答、予定を別モデルにし、共通時間、必要時間、期限、取消・離脱を純粋テストできる。
  - _Requirements: 1.2, 1.3, 3.4, 3.6, 4.1, 4.2, 4.6, 5.1, 5.2, 5.4, 5.5_
  - _Boundary: HostingDomain_

- [ ] 2. Privacy-safe Repository と Prototype Adapter を実装する
  - operationID / version、配信人数を返さない create、回答者だけの host detail、本人候補だけの invitee detail、競合を再現する。
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 4.4, 4.5, 7.1, 7.3, 7.4_
  - _Boundary: HostingApplication, PrototypeHostingAdapter_
  - _Depends: 1_

- [ ] 3. 募集作成フローを実装する
  - 3段階入力、暇未登録導線、確認文、開始結果、取消して作り直す制約を操作できる。
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.1, 2.2, 2.5, 7.2_
  - _Boundary: HostingCreationFeature_
  - _Depends: 2_

- [ ] 4. 役割・状態別の共通詳細を実装する
  - 招待回答、回答変更・撤回、見送り、共通候補、確定、取消、離脱、期限切れを一画面契約で扱う。
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 7.1, 7.2, 7.3_
  - _Boundary: HostingDetailFeature_
  - _Depends: 2, 3_

- [ ] 5. Push 非依存の受信箱を実装する
  - 要対応・進行中・終了、最新状態再取得、権限喪失・期限切れを表示し、Pushなしで回答・確定へ進める。
  - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - _Boundary: InboxFeature_
  - _Depends: 2, 4_

- [ ] 6. Hosting の統合検証を完了する
  - Domain/Application/Reducer と Simulator の募集→回答→確定→取消・離脱を検証し、Backend未検証範囲を明記する。
  - _Requirements: 1.1, 2.1, 2.3, 3.2, 3.5, 4.1, 4.4, 4.5, 5.3, 5.4, 6.2, 6.4, 7.1, 7.2, 7.3, 7.4_
  - _Boundary: HostingValidation_
  - _Depends: 1, 2, 3, 4, 5_
