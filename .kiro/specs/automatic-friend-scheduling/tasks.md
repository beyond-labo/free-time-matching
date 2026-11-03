---
type: Implementation Plan
title: "自動提案・予定成立の実装計画"
description: "DB、Backend、iOS、通知を契約で分けて統合検証する"
status: stable
sources:
  - id: user-stage-one
    resource: conversation://2026-10-29/automatic-friend-scheduling
    title: 第一段階方針と具体条件の回答
kiro:
  depends_on:
    - .kiro/specs/automatic-friend-scheduling/requirements.md
    - .kiro/specs/automatic-friend-scheduling/design.md
---

# Implementation Plan

- [x] 1. 永続化とサーバー業務契約を追加する
  - private table、RPC、相互許可、最早15分〜24h区間、頻度、匿名/OK共有投影、原子的な確定、取消、feedbackを追加する。
  - 既存暇・友達・退会とのwrapper/trigger、ブロック・通報・通知/配送leaseを接続する。
  - 実DBで他者参照、片側許可・片側OK、双方OK、期限、上限、再送、安全変更と旧API互換性を検証する。
  - _Requirements: 1.1–1.6, 2.1–2.5, 3.1–3.5, 4.1–4.6, 5.1–5.6, 6.1, 7.1–7.3, 8.2, 8.5–8.6_
  - _Boundary: Supabase migration/RPC/tests_
- [x] 2. (P) 認証済みBackend APIと自動実行を追加する
  - 型付きPort/Adapter/Route、入力検証、公開DTO、安定エラー、本人JWTを接続する。
  - Cronを設定し非起動時の生成と通知dispatchを実行する。個人情報をログへ出さない。
  - Route/Adapter/型検査/buildでHTTPとRPC契約を検証する。
  - _Requirements: 1.1–1.6, 2.5, 3.1–3.5, 4.1–4.6, 5.1–5.6, 6.1–6.3, 7.1–7.3, 8.2, 8.5–8.6_
  - _Boundary: apps/backend/AutomaticScheduling, Composition, EntryPoint, wrangler_
- [x] 3. (P) iOSの主要体験と安全・通知の入口を接続する
  - 独立Featureのモデル/Port/UseCase/Adapter/Reducer/Viewを追加し、Home/Inbox/友達/設定へ統合する。
  - 初期off・友達別許可、任意のOK共有、1回回答、実確定予定/取消/feedback、非公開登録と安全APIを接続する。
  - APNs許可/登録/無効化、失敗時再試行、session/revision、Swift Testingを検証する。
  - _Requirements: 1.1–1.6, 2.1, 3.1–3.5, 4.1–4.6, 5.1–5.6, 6.1–6.5, 8.1–8.6_
  - _Boundary: apps/ios_
- [x] 4. (P) 永続配送キューからAPNsへ通知する
  - leaseした配送をES256認証で送り、成功・無効token・一時失敗を分ける。未設定で成功扱いにしない。
  - 通知本文とログに相手名・暇を含めず、二重実行や障害でも業務状態を失わない。
  - Fake HTTPと配送RPCで署名・宛先・再送・無効tokenを検証する。
  - _Requirements: 6.1–6.3, 8.6_
  - _Boundary: apps/backend/Notification_
- [x] 5. 統合、独立レビュー、仕様同期とローカル受け入れを完了する
  - DB/Backend/iOSの契約を照合し、独立レビューの重要指摘を修正する。
  - 構造検査、Backend test/typecheck/build、DB test、iOS Simulator test/buildを実施し、旧Home/Siri/手動契約の回帰を確認する。
  - 関連仕様と実装証拠を同期する。実APNs/実機/STG/配布と小規模ユーザー検証は未実施として引き継ぐ。
  - _Requirements: 1.1–1.6, 2.1–2.5, 3.1–3.5, 4.1–4.6, 5.1–5.6, 6.1–6.5, 7.1–7.3, 8.1–8.6_
  - _Boundary: integration/spec sync/evidence_
  - _Depends: 1, 2, 3, 4_
