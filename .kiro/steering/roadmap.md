---
type: Roadmap
title: "自動提案・予定成立の第一段階ロードマップ"
description: "既存基盤を再利用し4週間の仮説検証単位で2人の遊びを成立させる"
status: stable
sources:
  - id: user-stage-one
    resource: conversation://2026-10-29/automatic-friend-scheduling
    title: ホストなしの自動提案と双方OKでの予定確定
kiro:
  depends_on:
    - docs/product/overview.md
    - .kiro/specs/automatic-friend-scheduling/requirements.md
---

# 第一段階ロードマップ

## Overview

手動の暇登録を起点に、許可された承認済み友達2人の共通時間をシステムが検出し、一つの提案へ各自が参加OK／見送りで回答する。双方OKで自動確定し、通知・取消・安全機能まで実Backendで成立させる。[^user-stage-one]
4週間は小規模開発の計画仮説とし、5〜20人の既知の友達で検証する。機能の生成、承認、実装、実環境検証は区別する。

## Approach Decision

既存の認証・友達・本人暇を再利用し、ホストなしの提案・予定ライフサイクルを `automatic-friend-scheduling` にまとめる。
手動Hostingのホスト権限・複数招待・部分回答へ名前だけ置換して流用しない。手動募集は既存API互換性として保持し、第一段階の必須導線から外す。

## Scope

- 15分単位・未来14日の非公開手動暇登録、承認済み友達2人のオンラインの遊び。
- 初期オフの自動提案、友達別の相互許可、共通時間検出、一つの日時の提案。
- ワンタップ回答、双方OKで自動確定、取消、通知、受信箱、通報・ブロック・退会の整合。
- 週1件までと同一ペア連続抑制、成立・煩わしさ・プライバシーの小規模評価。

次段階は3人以上、パーソナライズ、定期暇学習、カレンダー連携、自動再調整。当面はLLM交渉、位置推定、店舗検索・予約、チャット、未知の人を対象外とする。

## Constraints

- 暇登録、自動提案許可、参加OK、予定確定は別の意思と状態。
- 相手の生の暇は公開しない。名前と参加OKの共有は本人が選択し初期オフ。双方OK後は互いの名前と予定を表示する。本人限定RLSを広げず内部照合の権限を分ける。
- サーバーで許可・安全・暇・競合・頻度を再検証し、通知失敗でも確定状態を二重化しない。
- Pushを利用条件にしない。Prototypeの成功を認可・並行性・実配信の証拠にしない。
- iOS17以降、SwiftUI/TCA、Swift Testing、既存Clean Architectureの依存方向を維持する。

## Boundary Strategy

- `backend-user-account-management`: 認証・プロフィール・削除受付の既存正本。
- `backend-availability` / `ios-availability`: 本人の正確な暇と入力。自動参加を所有しない。
- `backend-friendship` / `ios-friendship`: 承認済み関係と友達操作。自動提案許可を友達承認へ混ぜない。
- `automatic-friend-scheduling`: 相互許可、内部照合、提案、回答、自動確定、取消、頻度、通知・安全との整合を縦に所有する。
- `ios-app-integration`: 新機能のCompositionとHome/Inboxへの投影を接続する。
- `ios-safety-settings`: 通報・ブロック・退会の入口と最新の影響表示。
- `backend-hosting` / `ios-hosting`: 既存の手動招待・部分回答の互換性。自動提案の代わりとして使わない。

## Specs (dependency order)

- [x] automatic-friend-scheduling -- ホストなしの2人提案・合意・確定・取消・頻度・通知・安全。Dependencies: backend-user-account-management, backend-friendship, backend-availability
- [x] ios-first-match-flow -- 自動提案を主軸にした初回の予定までの案内とホーム構成、手動のお誘いの作成・返事の簡略化、アカウント境界、DEBUGデモ、返事変更の409修正。実装・Simulator検証済み、改訂後の要件・設計・タスクは2026-11-10に承認済み、実機・STG未確認。工程承認の正本は spec.json。Dependencies: ios-app-foundation, ios-availability, ios-friendship, ios-hosting, ios-app-integration, automatic-friend-scheduling

このチェックは仕様生成の完了を示し、実装完了を意味しない。工程承認と実装準備状態の正本は各 `spec.json`。

## Existing Spec Updates

| 仕様 | 更新対象と再検証 |
| --- | --- |
| ios-app-foundation | 要件1.1: 主催者前提の初回説明を、非公開暇・初期オフ・明示回答・自動確定へ置換 |
| ios-availability | 要件1.2/1.8/1.10、3、4.6、7: 非公開固定、Homeの提案・実確定予定投影、暇変更と提案の再検証。OR・15分入力は再利用 |
| backend-availability | 要件2/3.4/8.6: 本人API・RLSを維持し、内部照合・提案中の暇変更と旧shareOnHosting互換性を区別 |
| ios-friendship / backend-friendship | 友達追加・解除を再利用。友達別許可は新機能へ委譲し、解除・再追加で許可を復活させない |
| ios-safety-settings | 要件1/2/3/5/6: 提案・予定を通報対象へ追加、実ブロック・退会の関連状態無効化、提案・確定・取消通知 |
| ios-app-integration | 要件1/2/3: 実提案・予定の投影、実Adapter、セッション切替、2アカウント検証。DEBUG確定fixtureを実績としない |
| ios-siri-actions | 暇の登録・削除は再利用。手動募集の音声入口は既存互換性として区別し、暇登録を参加OKにしない |
| backend-hosting / ios-hosting | 旧手動募集として全現存成果物を位置付け直し、自動提案の要件や達成証拠として使わない |

認証・CI/CD・旧手動募集の既存成果を一律に未完了へ戻さない。変更した受け入れ条件を証明しない完了項目だけを再評価する。

## スプリント計画

| 週 | 実装する体験 | 検証仮説・受け入れ証拠 |
| --- | --- | --- |
| 1 | 友達と15分単位の非公開暇登録、初期オフ・友達別許可 | 登録負担、片側許可では提案されないこと |
| 2 | アプリ非起動時も共通時間を検出し一つの提案 | システム発の誘いへの反応、週上限・ペア抑制・開示境界 |
| 3 | 各自1回答で双方OKから自動確定 | 日程調整0回、片側OKでは未確定、同時操作・再送でも1予定 |
| 4 | 通知・取消・安全・TestFlight準備 | Push拒否時の成立、ブロック/退会、複数実機、実際の遊びの確認 |

## Direct Implementation Candidates

仕様と承認が揃った後、既存API互換性を維持しながら新機能とiOS導線を追加する。実装コードの変更は依頼範囲に含まれる。デプロイ・アップロード・外部配布はこの変更作成の実施済み事項としない。

## 成功の確認

提案から実際に遊べた割合を最優先にし、確定率、実際に遊べたかの未回答、各自の操作数、往復調整回数を分ける。煩わしさと意図しない暇公開の受け止めも確認する。

## 変更履歴

- 2026-11-08: `ios-first-match-flow` を自動提案主軸の初回体験として追加し、実装・Simulator検証済みと要件改訂の再承認待ち、実機・STG未確認を区別した。
- 2026-10-29: ユーザーの第一段階方針に従い、ホストが手動募集し最終確定とPushを後続に送る旧ロードマップを置換した。旧仕様の実装・検証履歴は各仕様に維持する。

[^user-stage-one]: 2026-10-29 の第一段階方針と実装コードを含める追加指示。
