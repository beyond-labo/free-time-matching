---
type: Brief
title: "友達との自動提案・予定成立"
description: "非公開の暇を起点に、ホストなしで2人の合意と予定確定をつなぐ"
status: stable
sources:
  - id: user-stage-one
    resource: conversation://2026-10-29/automatic-friend-scheduling
    title: 第一段階を暇から予定への自動化へ変更する指示
kiro:
  depends_on:
    - .kiro/steering/product.md
    - .kiro/steering/roadmap.md
    - docs/product/overview.md
---

# 友達との自動提案・予定成立 Brief

## Problem

手動募集が必要な現行フローでは、誰かが誘い始める心理的負担と日程を選ぶ負担が残る。
第一段階では、ユーザーが預けた正確な暇を予定に変える自動化を検証する。[^user-stage-one]

## Current State

最新リモート main の `146ad5b` を起点に確認した。認証、友達関係、本人の暇のOR統合・区間削除、手動募集・部分回答の実APIとiOS Adapterがある。
ホストなしの検出、提案、双方OKによる自動確定、実Push、Backendのブロック・通報処理は未実装。既存の確定予定fixtureは実Backendの証拠ではない。

## Desired Outcome

非公開の暇登録 → 相互に許可した友達との共通時間検出 → 2人へ1件の提案 → 各自が参加OK／見送り → 双方OKで自動確定、という体験を作る。
提案後は各ユーザー1回の回答、日時の往復調整0回をUX設計目標とする。実績は別途測定する。

## Approach

新しい自動提案・予定ライフサイクルをこの仕様に集約する。既存Hostingのホスト・複数招待・部分回答契約へ偽のシステムホストを追加して流用しない。
本人の暇、友達承認、認証は既存所有境界を使い、提案に必要な内部照合と外部表示の権限を分ける。
既存の手動募集API・保存済みデータは今回削除しない。第一段階の主要導線から外す移行と旧クライアント互換性を設計で扱う。

## Scope

### In

- 既知の友達5〜20人、2人のオンライン通話・ゲーム等。
- 15分単位・今後14日の手動暇登録、共通時間検出、日時を一つに絞った提案。
- 初期オフの本人設定と友達ごとの相互許可、週1件までの頻度制限、同じ組み合わせの連続抑制。
- 参加OK／見送り、双方OKでの自動確定、取消、通知、受信箱、ブロック・通報・退会との整合。
- 実際に遊べたか、煩わしさ、意図しない暇公開の受け止めを確認する小規模検証。

### Out

- 次段階: 3人以上、活動のパーソナライズ、定期暇の学習、カレンダー連携、再調整の自動化。
- 当面対象外: LLM交渉、位置情報での暇推定、店舗検索・予約、チャット、知らない人とのマッチング。
- デプロイ、外部配布、既存データの削除。実装コードの変更は追加指示で対象に含まれた。

## Boundary Candidates

- Automatic Scheduling: 自動提案の許可、内部照合、頻度制限、提案・回答・確定・取消、評価用の最小イベント。
- Availability / Friendship / Safety: 本人暇、承認済み関係、安全制約の正本をそれぞれ維持する。
- Notification: 確定済みの業務状態を通知し、受信箱をPush非依存の入口とする。
- iOS: 提案カード、ワンタップ回答、確定予定、許可設定、取消・安全操作。状態の最終判定はBackend。

## Out of Boundary

認証・友達追加・本人暇のAPIを別実装へ複製しない。通知成功を予定成立の条件にしない。推定した暇を登録しない。

## Upstream / Downstream

- Upstream: backend-user-account-management、backend-friendship、backend-availability。
- Adjacent: ios-availability、ios-friendship、ios-safety-settings、ios-app-foundation。
- Downstream: ios-app-integration、ios-siri-actions、通知・TestFlightでの検証。

## Existing Spec Touchpoints

既存仕様の更新対象と受け入れ条件は [ロードマップ](../../steering/roadmap.md) の Existing Spec Updates を参照する。
手動Hostingの仕様は既存契約の記録として維持し、自動提案の完成条件へ読み替えない。
意味の変わる既存仕様は `spec.json` に再同期箇所を記録し、旧設計・完了チェックを新要件の達成証拠に使わない。

## Constraints

暇登録は誘いを受け取ってよい意思であり、参加OKではない。自動提案許可も個別参加への承諾ではない。
提案日時から共通時間を推測でき、友達が一人なら匿名でも相手を推測できる。生の暇と登録属性を返さず、この限界を許可時に説明する。名前と参加OKの共有は回答時に本人が選択し、双方OK後は互いの名前と予定を表示する。
最早の共通区間を15分〜24時間で提案し、回答期限は開始時刻、各人の直近7日間1件・同一ペア14日間隔を採用する。見送り・期限切れでは自動再調整しない。

[^user-stage-one]: 2026-10-29 の第一段階方針。外部のDeep Research本文は提供されていないため、競合サービスの調査結果を検証済みの事実として採用していない。
