---
type: Research
title: "自動提案・予定成立への移行調査"
description: "既存実装の境界と第一段階の方針変更、未決事項、検証記録"
status: stable
sources:
  - id: stage-one
    resource: conversation://2026-10-29/automatic-friend-scheduling
    title: 第一段階方針と実装範囲
  - id: apns-send
    resource: https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
    title: APNs request contract
  - id: apns-response
    resource: https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns
    title: APNs response contract
  - id: supabase-keys
    resource: https://supabase.com/docs/guides/getting-started/api-keys
    title: Supabase API key headers
kiro:
  depends_on:
    - .kiro/specs/automatic-friend-scheduling/requirements.md
    - apps/backend/src/Composition/createApp.ts
    - apps/backend/src/Hosting/Domain/Hosting.ts
    - apps/ios/Himatch/App/Composition/AppRuntime.swift
    - supabase/migrations/202610300001_automatic_scheduling.sql
    - supabase/tests/automatic_scheduling.test.sql
    - apps/backend/src/Shared/Infrastructure/SupabaseRestClient.ts
    - apps/backend/src/EntryPoint/index.ts
    - apps/backend/wrangler.jsonc
    - apps/backend/test/automatic-scheduling.worker.test.ts
    - apps/backend/test/notification.worker.test.ts
    - apps/backend/test/supabase-rest-client.worker.test.ts
    - apps/ios/Himatch/App/Presentation/AppFeature.swift
    - apps/ios/Himatch/App/Presentation/AppView.swift
    - apps/ios/Himatch/Himatch.entitlements
    - apps/ios/HimatchTests/AutomaticScheduling/AutomaticSchedulingTests.swift
    - apps/backend/src/AutomaticScheduling/Application/Port/AutomaticSchedulingRepository.ts
    - apps/backend/src/AutomaticScheduling/Domain/Model/AutomaticScheduling.ts
    - apps/backend/src/AutomaticScheduling/Infrastructure/Adapter/SupabaseSchedulingTickAdapter.ts
    - apps/backend/src/AutomaticScheduling/Infrastructure/Repository/SupabaseAutomaticSchedulingRepository.ts
    - apps/backend/src/AutomaticScheduling/Presentation/Route/AutomaticSchedulingRoutes.ts
    - apps/backend/src/Notification/Application/Port/NotificationDeliveryPort.ts
    - apps/backend/src/Notification/Application/UseCase/DeliverSchedulingNotifications.ts
    - apps/backend/src/Notification/Composition/Factory/dispatchSchedulingNotifications.ts
    - apps/backend/src/Notification/Domain/Model/NotificationDelivery.ts
    - apps/backend/src/Notification/Infrastructure/Adapter/ApnsNotificationAdapter.ts
    - apps/backend/src/Notification/Infrastructure/Repository/SupabaseNotificationDeliveryRepository.ts
    - apps/ios/Himatch/AutomaticScheduling/Application/Port/AutomaticSchedulingRepository.swift
    - apps/ios/Himatch/AutomaticScheduling/Application/UseCase/AutomaticSchedulingUseCase.swift
    - apps/ios/Himatch/AutomaticScheduling/Domain/Model/AutomaticSchedulingModels.swift
    - apps/ios/Himatch/AutomaticScheduling/Infrastructure/Adapter/BackendAutomaticSchedulingAdapter.swift
    - apps/ios/Himatch/AutomaticScheduling/Infrastructure/Adapter/SchedulingPushAdapter.swift
    - apps/ios/Himatch/AutomaticScheduling/Presentation/Dependency/AutomaticSchedulingEffects.swift
    - apps/ios/Himatch/AutomaticScheduling/Presentation/Reducer/AutomaticSchedulingFeature.swift
    - apps/ios/Himatch/AutomaticScheduling/Presentation/View/AutomaticSchedulingView.swift
---

# 調査と決定

## 現行要約

最新リモートmainの146ad5bから専用ワークツリーを作成した。既存作業ディレクトリの未コミットiOS変更とHTMLを取り込んでいない。
認証・友達・本人暇・手動HostingのAPIとiOS Adapterを確認。Hostingはopen/cancelled/expired、部分区間のaccepted/declinedを扱い、ホストなし提案・確定は持たない。
iOSの実Business依存も提案・確定・安全のBackend契約を持たない。Prototype確定fixtureを実績としない。

## 採用判断

自動提案・予定成立を独立した機能とする。偽ホストをHostingへ足す方式は、ホスト権限・複数招待・部分回答を新体験へ持ち込むため採用しない。
友達と本人暇の正本・既存APIを再利用し、公開RLSを広げずに内部照合を追加する。
相互許可と個別回答を分け、初期オフ・週上限・ペア抑制・取消・安全を初期範囲に含める。

## 確定した製品条件

ユーザーは実装まで依頼し、具体条件への回答でOK共有の選択・最大24時間を指定し、直近7日間1件・同一ペア14日間隔・開始期限・再調整なしを了承した。最小15分と参加OK共有の初期offを採用する。
匿名でも許可対象が一人なら推測可能なため、API上の非開示と推測限界の説明を分ける。友達解除だけで確定予定を消さず、ブロック/退会時に未来予定を取り消す。
この依頼範囲の要件・設計・タスクを品質確認後に承認へ反映し、実装へ進む。外部公開の実行は含まない。

## 技術契約の調査

既存RPC/SECURITY DEFINER/固定search_pathを踏襲する。小規模の並行処理はglobal lockから既存owner/pair lockへ統一する。後段でglobalを取るrow hookだけではデッドロックし得るため、既存RPC入口のwrapperで順序を揃える。
CronはCloudflare scheduled handlerと環境別triggers.cronsを使用する（2026-10-30公式確認）。
- https://developers.cloudflare.com/workers/configuration/cron-triggers/
- https://developers.cloudflare.com/workers/runtime-apis/handlers/scheduled/
APNsとjoseの署名契約は通知Adapter実装時に一次資料で確認する。

## 意味の変更と影響先

- ios-app-foundation要件1.1: 主催者前提の説明を変更。
- ios-availability要件1/3/4/7: 非公開固定、提案と実確定予定の表示へ変更。
- backend-availability要件2/3/8: 本人境界を維持し内部照合と編集整合を拡張。
- Friendship: 友達承認を自動提案許可にしない。解除で許可失効。
- Safety/Integration: 実Backendの通知・ブロック・退会・予定投影と横断整合を追加。
- Siri/Hosting: 手動招待の既存互換性を区別。暇登録のみで参加承諾しない原則を維持。

## レビューと検証

独立調査でAppRuntime、HimatchClient、AppFeature、Home、Inboxの接続点と既存完了証拠の限界を確認した。
構造検査、仕様レビュー、アプリ検証、実DB、STG・実機・配布の証拠は、実施後に個別記録する。

## 変更記録

- 2026-10-29: ユーザーの方針に基づいてホスト主導のMVPを自動提案・双方OKによる確定へ置換。実装コードも依頼範囲に含む追加指示を受領。既存仕様の影響工程の承認を失効し、再同期対象をspec.jsonへ記録した。

## 実装・独立レビュー・ローカル検証の最終記録（2026-11-03）

### 実装した契約

非公開の暇と承認済み友達を再利用し、相互許可・最早15分〜24時間・7日間1件・同一ペア14日間隔・個別OK共有・双方OKによる確定・取消・通知・通報・ブロック・任意評価を実装した。提案に架空のホストを作らず、本人向けAPIとサービス用RPCを分離した。
友達プロフィールの実確定予定も所有機能へ委譲し、片側OKの撤回は回答の上書きでなくcancelを使う。通報の受付番号は成功したoperationIDをDBのreport行へ一意に保存する。

### レビューで修正した境界

- 許可友達が一人なら匿名でも推測できるため、直接返す情報の制限と推測限界の説明を分けた。
- global lockの後で実時刻を読み、transaction開始後に期限/上限が変わっても古い時刻で確定しない。7日/14日は168h/336hで比較する。
- quota receiptを相手の退会で消さず、過去confirmedの相手profileが消えても予定とfeedbackを表示できる。
- 申請当事者と解除済み友達からの通報、端末tokenの所有者移転、旧sessionの遅延無効化を検証した。
- APNsは再送とstable collapse IDで重複を抑える。外部配送のexactly-onceは保証しない。
- Supabaseの非JWTキーはapikeyへ送り、利用者JWTのBearerと分ける。旧service_role JWTの互換性は維持する。
- iOSはlogoutを含めて更新世代を維持し、古いHTTP応答と通知登録の競合で別sessionの状態を表示しない。
- 旧Prototypeの安全preview/影響IDを匿名2人の実契約へ持ち込まず、固定効果を確認後にサーバーで最新状態へ適用する。旧仕様本文も置換し、履歴へ説明を残した。

### 検証証拠

| 対象 | 実施内容 | 結果と限界 |
| --- | --- | --- |
| Backend | pnpm --dir apps/backend test | Vitest 57成功、補助health smokeテスト3成功、失敗0 |
| 型/生成物 | pnpm --dir apps/backend typecheck / build | 成功。buildはWrangler dry-runで実配備なし。未指定環境の既存warningあり |
| DB | 専用ローカルSupabase Postgresへ全migrationを順次適用、pgTAP全5ファイル | 成功。auth schemaは構造のみ複製し、既存利用データとリモートDBを変更していない |
| 並行DB | 2つのpsql接続から同時OK、許可off対OK、暇減算対OK、同時tickのquota、実時刻境界 | 5ケース成功。後続の通報受付列追加はこの処理経路を変えないため証拠を再利用 |
| iOS | XcodeBuildMCP test_sim | 186成功、0失敗、0skip、warning/errorなし |
| iOS生成物 | XcodeBuildMCP Release build_sim | 成功、warning/errorなし |
| iOS起動 | MCP install/launch/snapshot | 最終Release生成物の登録前説明まで成功。実認証後の主要フローE2Eは未実施 |
| 構造 | node scripts/verify.mjs / git diff --check / CD run block bash -n | 成功。OKFの確認済み入力は最終同期時に更新する |

DB実行ログは `/private/tmp/himatch-himatch_auto_20261103021142-*.log`、並行試験ログは `/private/tmp/himatch-himatch_auto_20261102111210-*.log` に保存した。専用fixtureのみを扱った。
MCPの最終xcresultは `/Users/hiiragi589/Library/Developer/XcodeBuildMCP/workspaces/free-time-matching-e32e602ac1d7/result-bundles/test_sim_2026-11-03T02-12-36-381Z_pid68017_ebad167f.xcresult`、詳細な実行記録は `/private/tmp/himatch-scheduling-ios-evidence.md` を参照する。

### 判定と残る実環境検証

実装タスク1〜5のローカル受け入れはVERIFIED。独立レビューのImportant指摘は修正し、関連の失敗再現と回帰検証を終えた。
製品全体のFEATURE_GOはMANUAL_VERIFY_REQUIREDとする。STG migration/2アカウント実機E2E、実APNs、TestFlight配布、5〜20人の実施率・煩わしさ・プライバシーの評価は未実施であり、ユーザーから外部公開の実行許可を受けたとは扱わない。
署名なしSimulatorで既存KeychainDeletionStatusTokenStoreの警告を確認した。本体に今回差分はなく、原因を署名と断定しない。警告を閉じた登録前画面までを起動smokeの範囲とし、実認証後の安全な保存は実機で確認する。

### 一次資料の確認

- Apple APNs: https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns （2026-10-31確認、署名・header・汎用payloadの契約）
- APNs応答: https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns （2026-10-31確認、無効tokenと一時失敗の区別）
- Supabase API keys: https://supabase.com/docs/guides/getting-started/api-keys （2026-11-03確認、非JWTキーのapikeyと利用者JWTのAuthorizationの区別）


## 2026-11-03 PR準備とバージョン更新

ユーザーのバージョン更新・PR作成依頼に従い、iOSのDebug/Release表示バージョンを0.1.7から0.1.8へ更新した。ビルド番号は既存の配布時採番契約を維持する。表示バージョンのみの変更で業務契約は不変のため、承認と既存のロジック検証証拠を維持する。
XcodeBuildMCPのRelease build_simが成功（警告/エラー0）し、生成物Info.plistのCFBundleShortVersionStringが0.1.8であることを確認した。ビルドログは `~/Library/Developer/XcodeBuildMCP/workspaces/free-time-matching-9ece3e2707da/logs/build_sim_2026-11-03T04-16-52-330Z_pid52414_1b752bbf.log`。STG・実APNs・実機E2E・配布の未実施状態は変わらない。
