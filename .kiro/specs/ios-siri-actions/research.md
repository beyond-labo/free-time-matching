---
type: Research
title: "Siri 操作公開の調査記録"
description: "採用する公開経路と現行製品契約の境界"
status: stable
sources:
  - id: user-siri-low-effort
    resource: conversation://2026-10-04/siri-low-effort
    title: Siri 操作公開と予定調整の負荷最小化の依頼
kiro:
  depends_on:
    - .kiro/steering/product.md
    - .kiro/specs/ios-availability/requirements.md
    - .kiro/specs/ios-hosting/requirements.md
    - .kiro/specs/ios-friendship/requirements.md
---

# 調査記録

## 現行の要約
Apple の App Intents はアプリの操作とパラメータを Siri とショートカットへ公開する経路を提供する。4つのIntent、本人限定のEntity Query、共通操作サービス、保護された再送記録を実装した。任意の自然文が必ず解釈されるとは扱わない。

## 根拠
- [Apple AppIntent](https://developer.apple.com/documentation/appintents/appintent)（2026-10-04 確認）: 操作とパラメータ、認証ポリシーの公開経路。
- `apps/ios/Himatch/Hosting/Domain/HostingModels.swift`: 開催形態、定義済みエリア、募集状態と version の既存モデル。
- `ios-availability` と `ios-hosting` の要件: OR統合、削除制約、承認済み友達への招待、予定確定を後続工程へ置く契約。

## 要件レビュー
主要操作、必須項目不足、対象の曖昧さ、認証、期限、競合、通信結果不明、非公開情報、既存機能への責務分離を照合した。既存契約を変更せず、未実装の予定確定を公開範囲へ含めていない。品質確認は要件承認と区別する。独立レビューで指摘された結果不明時のpayload維持と競合後の新規操作を分離し、既存 Availability の絶対時刻・タイムゾーン・日付またぎ契約を登録と募集の両方へ追加した。

## 変更記録
- 2026-10-04: Siri 対応を独立のシステム連携仕様として追加。負荷低減は再入力・再選択を除去する方針とし、募集送信・取消の意思確認は保持する。当初は要件承認待ちだった。現在の工程状態は spec.json と tasks.md、検証不足は下記の実装同期を参照する。

## 設計調査（2026-10-04）

### 既存の操作境界
- Production Client の組立ては `AppRuntime.productionBusiness` に集約した。Debug/Release の通常起動と Siri は実Adapterを共有し、明示的にデモを開始した場合だけPrototypeへ切り替える。
- `BackendAvailabilityAdapter.put` は slot.id を union の operationId として送る。Intent の再送は同じ slot.id・payload を維持する。
- 通常 Root の `createHosting` と `cancelHosting` は mutation 後に暇の一覧を読む。Siri の本人束縛 Client は後続GETを省略し、mutation 成功だけで完了を判定する。表示更新は Root の独立した再取得へ委譲する。
- Entity Query は Intent の perform より前に呼ばれ得るため、保護データ可用性と認証済み本人の検査を Query にも置く。

### Apple API と最低版
以下の Apple 公式資料とローカル iPhoneOS SDK の AppIntents.swiftinterface を照合した。
- [AppIntent](https://developer.apple.com/documentation/appintents/appintent): パラメータ、認証、実行経路。
- [IntentAuthenticationPolicy](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy): `requiresLocalDeviceAuthentication` は SDK で iOS 16 以降の enum case と確認した。
- [IntentParameterContext](https://developer.apple.com/documentation/appintents/intentparametercontext): 値要求、曖昧性解消、確認。
- [Foreground 継続](https://developer.apple.com/documentation/appintents/foregroundcontinuableintent/requesttocontinueinforeground(_:continuation:)): iOS 16.4 以降。iOS 26 では `supportedModes` の動的 foreground が置換先。

ローカル SDK の supportedModes は iOS 26 以降。dialogを取る新しい requestConfirmation は iOS 18 以降であり、iOS 17 では従来の result を取る確認 API を互換ブリッジで使用する。非推奨と利用不可を区別し、最低版を勝手に上げない。API宣言確認は Intent のビルド・Siriの実機成功の証拠ではない。

## Design Decisions

### 本体ターゲットと共通 runtime
Intent専用extensionとApp Groupを追加せず本体へ含める。既存実依存を共有することで二重の認証構成とデモへの誤書込を避ける。システム連携の型はInfrastructureに隔離し、ServiceはTCA Storeを参照しない。

### 条件付き foreground
常時アプリを開く方式はユーザー負荷低減の目的を損なうため採用しない。通常は音声で完了し、認証・属性選択・競合・再試行時だけ確定済み入力を引き継ぐ。

### 最小限の保護された操作記録
メモリだけではプロセス中断後にoperationIDを失うため、送信前に完全保護ファイルへ操作を記録する。日時・対象IDは復帰に必要な範囲だけ保持し、token・音声原文・表示名・応答本文は保持しない。結果不明時は同じpayloadで再送し、競合後の別操作と分ける。

## 設計レビューの対象
要件IDごとの実現箇所、認証前Query、本人と対象の再検証、最低iOS版の互換API、operationIDとpayloadの保存、認証後の画面引継ぎ、書込後読込の失敗、既存機能への責務委譲を確認する。独立レビューの結果と修正は以下の変更記録に残す。

## 設計の変更記録
- 2026-10-04: 要件から設計を生成。実装・ビルド・実機確認は未実施。App Integration の契約反映はこの設計の承認後に行うため、現在の統合仕様を新しい案との差だけで未同期扱いにしない。

### 独立設計レビューと反映
- 指摘: 現行 Hosting Adapter の `availabilityCategory ?? draft.category` は明示未選択を表現できない。設計に明示 metadata の追加、Adapter の nil保持、画面とSiriの双方の移行、回帰検証を反映した。
- 指摘: AccessGate 後に Client がセッションを再復元すると別本人への誤送信が可能。本人束縛 Client の生成と各クロージャ内での一致確認、送信済み不明結果のアカウント別隔離、並行切替のテストを追加した。
- 更新対象を HimatchClient、Hosting Adapter、BackendAdapterTests へ拡張した。これは既存の属性・認可契約を守るための設計補足であり、要件の変更ではない。

- 独立レビューの修正箇所再確認で、指摘した2点の重大な残件なし。実装・ビルド・実機検証は未実施。

## Opus 5.5 の独立レビュー（2026-10-04）
Claude CLIでモデル `claude-opus-5-5` を明示し、編集・実行ツールを無効化して設計をレビューした。初回はNO-GOで、DebugのStoreとSiriの依存分離、サーバーの再生判定順序の未固定を指摘。通常のDebug/Releaseは共通実依存、デモだけ明示切替とし、supabase migrationsのcreate/cancel/union/subtractを直接読んで同一payloadの再生がstatus/version/新規日時検証より先であることを確認した。結果不明からの409で自動新規作成しない経路も明記した。
追加指摘のapplicationNameトークン、日本語カタログ、解決済みDate、複合Entity ID、foreground復帰の再取得、複数友達の実機表、ロック中の保存失敗、未完了操作のFIFOを設計へ統合した。実機成立は引き続き未検証。
Appleの[Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)本文も公式markdown配信から取得し、AppIntent/@Parameterとシステムによる必要パラメータの解決、用途に合うprotocolの採用を照合した。用途に合わないApple Intelligence schemaを無理に付与しない。

- Opus 5.5 再レビュー: 設計GO、重要残件なし。タスクのDB再送検証・Debug実依存検証・Entity単体検証を追加して計画へ反映。ユーザーの「問題なければそのまま進める」許可を設計・タスク・実装へ適用する。

## 実装同期（2026-10-04）

- `AppRuntime.swift`、`AppCompositionRoot.swift` と明示 metadata を実装し、画面と Siri の本人暇属性を募集カテゴリから分離した。本人束縛クロージャでセッション本人一致と削除受付停止を再検証する。
- `AppView.swift` の lifecycle・通知と `AppFeature.swift` の本人変更・サインアウト処理を接続した。Journal の createdAt 順で一件ずつ復帰し、完了後に次へ進む。別本人へ未送信入力や結果不明操作を渡さない。
- 初回の既知HTTP拒否は失敗として保存し、画面で入力を保持して再準備する。元送信の結果不明時は同じ operationID・入力・expectedVersion を保持し、再送後409だけで新規操作を自動生成しない。承認要件の競合後新規操作は、元操作の未適用が確定した場合に限る。
- コントローラーが確認した Swift Testing 146件と DB pgTAP 71件の成功証拠を、タスク1–5の受け入れ確認へ利用した。Releaseビルド・Simulator・独立実装レビューは進行中のためタスク6を未完、実機の日本語Siri/Shortcutsは未実施のためタスク7を未完に保つ。最終の検証詳細は `docs/testing/ios-siri-actions.md` を参照する。
- 業務要件は変更せず、共通構成と失敗境界を実装の根拠に合わせて具体化した。設計・タスクの承認を一度失効させ、既存の「問題なければそのまま進める」許可の範囲で意味照合後に再反映する。未実施検証と文書の未同期を別に判定する。

### メタデータ抽出の修正

共通protocol extensionに置いたauthenticationPolicy/supportedModesが、Appleのmetadata extractionでは具体Intentへ反映されずdefault値(0,8)となることをコントローラーが生成物で確認した。4つの具体Intent型へ宣言を移し、MCP build成功と4型すべてのauthenticationPolicy=2、isAuthPolExplicit=true、supportedModes=9を確認した。端末認証と条件付きforegroundの承認要件を守る実装バグ修正であり、要件は変更しない。修正前Release buildの成功は最終コードの証拠として再利用せず、最終Release確認を残す。Simulator build/run成功とプロフィール設定画面表示は確認済みだが、デモ操作・実機Siri成功の証拠として扱わない。

## Opus 5.5 初回実装レビュー: NO-GO（2026-10-04）

独立実装レビューは `/private/tmp/siri-opus-impl-review.json` に保存した。初回はNO-GOで、次の4件を既存要件充足のバグ修正として対応し、下記の修正後確認へ進んだ。新しい製品判断や要件変更は行わない。

- P1-1: 一つの共有暇枠へ接する新規範囲で共有を暗黙継承していた。既存枠が覆わない範囲があれば非公開・未選択の既定属性を候補へ加え、既存属性との差を本人に選ばせる。登録と募集の双方を修正・回帰検証する。
- P1-2: プロフィール通信失敗を本人不明と扱い、nil-ownerの引継ぎが別アカウントへ残り得た。session-onlyのrestoredOwnerIDとプロフィールを含む実行gateを分離する。引継ぎは復元sessionの本人、代替としてentityOwnerに束縛し、logoutでは旧本人または同entityOwnerの記録とnil-ownerの未送信記録を失効する。
- P1-3: 準備のinvalidInput理由を捨てて一律に画面へ移っていた。日時不正はAppleの当該パラメータneedsValueErrorで不足項目だけを補い、他の拒否は理由を説明して入力保持のhandoffへ進む。
- P1-4: オンライン開催でエリアnilを「あとで相談」と表示していた。確認と募集候補のエリア表記はオフラインだけに限定する。

修正前の146件成功証拠は上記経路の解消を証明しないため、影響するタスク2/4/5を再評価して未完へ戻した。タスク6の修正後全件テストと独立再レビューは未完、タスク7の実機Siriは未実施を維持する。レビューが言及したfixture修正中のテスト失敗は最終146件成功の報告より前の状態であり、現在の成功と矛盾する主張には使わない。修正後コード・テストの証拠を受け取ってからタスク完了を再判定する。

### P1-1〜4修正後の意味照合と回帰確認

`SystemActionService.mergedMetadata` が要求範囲の未被覆部分を計算して既定の非公開・未選択を統合候補へ加えることを確認した。`restoredOwnerID` はAppRuntimeのsession復元だけを用い、`saveHandoff` は復元本人とentityOwnerの不一致を拒否し、profile通信失敗でも本人束縛を保持する。`invalidate` はowner/entityOwner一致とnil-owner記録を扱う。Intentは新規入力の日時不正だけを当該開始/終了パラメータのneedsValueErrorへ渡し、結果不明の保存済みpayloadは日時再解釈せず再送する。他のinvalidInput理由はdialogに保持する。確認・Entity候補の開催条件は共通conditionsを用い、オンラインにエリアを含めない。

コントローラーが最終MCP build（03:04:22）とSwift Testing 155件成功・0件失敗を確認した。xcresultは `test_sim_2026-10-04T03-04-35-976Z_pid54869_9af3cb04.xcresult`。追加のService 5件、Intent 3件、Root認証失効1件を含む修正後証拠として利用し、タスク2/4/5を再完了とした。最終Release確認とOpus再レビューは進行中のためタスク6を未完に維持する。実機の日本語Siri/Shortcuts成立は依然未実施であり、タスク7を完了にしない。


## 最終実装レビューと検証（2026-10-04）

Opus 5.5の再レビューでP1-1〜5は解消、コード準備GO、新規の再現可能なブロッカーなしとなった。
レビューは提供したコード・証拠に基づく読取専用で、別途XcodeBuildMCPによる実行証拠を照合した。
最終155件成功・0失敗（`test_sim_2026-10-04T03-04-35-976Z_pid54869_9af3cb04.xcresult`）、03:05 UTCのReleaseビルド成功、最終Simulator起動成功を確認した。
Debug/Release双方で4操作のauthenticationPolicy=2、isAuthPolExplicit=true、supportedModes=9を確認した。
DBのavailability29件・hosting42件の再送契約検証は業務コード・SQLの追加変更がないため再利用する。
タスク6を完了とし、実機日本語Siri/ショートカットのタスク7は未実施のまま残す。
送信前の汎用AuthenticationFailureが結果不明になる安全側の分類は、非ブロッキング改善事項として記録する。
検証手順と不足は[検証記録](../../../docs/testing/ios-siri-actions.md)へ集約した。


## PR前のClaude CLIレビューと追検証（2026-10-04）

ユーザー指定でClaude CLI `--model claude-opus-5-5` に最終差分を読取専用でレビューさせた。
初回CLI応答エラーはレビュー証拠に採用せず、再実行の実モデル `claude-opus-5-5` と成功応答を確認した。
ドラフトPRとしてGOだったが、既知拒否後の編集で旧payloadとIDが衝突し続ける問題、未送信保存と失効の競合でunknown記録が復活する問題を修正した。
前者は新IDをdurable保存してから旧IDを整理し、保存失敗時に元入力を残す。後者は初回未送信と過去のunknownの再送を区別する。
修正差分のOpus 5.5再レビューはGOで、追加5件を含む160件のSwift TestingがXcodeBuildMCPで全件成功した。
公開対象だけを取り出したPR候補で、リモートmain由来のXcode設定のDebug/Releaseを検証した。
xcresultは `test_sim_2026-10-04T03-55-48-776Z_pid54869_44e91654.xcresult`、Releaseログは `build_sim_2026-10-04T03-56-12-523Z_pid54869_9372b72a.log`。
旧Preparedのexecuteは既存のinvalidated検査で保存前に停止すること、送信前の失効検査からmutationStarted登録までawaitがないことをコードで再照合した。
新ID保存後に旧記録削除だけがIO失敗すると新旧draftが残り得る点、プロセス内追跡集合の整理は非ブロッキング改善事項として残る。
タスク2/6を修正・回帰結果により再完了化し、実機のタスク7は未完了で維持する。
