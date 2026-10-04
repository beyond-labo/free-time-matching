# Siri 操作の検証記録

2026-10-04に実施。実機の成立確認は未実施で、仕様タスク7は未完了です。
対象は暇の登録・区間削除、友達への募集、本人募集の取消です。

| 検証 | 結果 | 証拠 |
| --- | --- | --- |
| Swift Testing | 160件成功・失敗0 | XcodeBuildMCP test_sim、03:55 UTCのxcresult |
| Debug build-for-testing | 成功 | XcodeBuildMCP build_sim、03:55 UTC |
| Release build | 成功（最終修正後） | XcodeBuildMCP build_sim、03:56 UTC |
| 通常Simulator起動 | 成功・プロフィール設定画面表示 | XcodeBuildMCP build_run_sim、03:05 UTC、snapshot_ui |
| Apple metadata | 4操作・日本語nlu生成、各認証policy2・明示設定true・supportedModes9 | Debug/Release Himatch.app/Metadata.appintents/extract.actionsdata |
| DB再送契約 | availability29件・hosting42件、計71件成功 | Postgres17・pgTAP、transaction rollbackで検証 |
| Opus 5.5設計レビュー | 初回指摘を解消後GO | 共通実runtime、replay優先順とDB検証を反映 |
| Opus 5.5実装レビュー | 重要指摘修正後、コード準備GO | 読取専用、編集/外部ツールなし。実機受け入れは別 |
| 日本語Siri/ショートカット実機 | 未実施 | 下記手順を実機で記録する |

XcodeBuildMCP証拠ディレクトリは `~/Library/Developer/XcodeBuildMCP/workspaces/free-time-matching-e32e602ac1d7/`。
Swift Testingの最新result bundleは `result-bundles/test_sim_2026-10-04T03-55-48-776Z_pid54869_44e91654.xcresult`。
ビルド対象はHimatch、Debug/Release、iPhone17 Pro Max Simulator（iOS26.5）、deployment target iOS17。
iOS17実機の実行はこのコンパイル結果だけでは確認できません。
iOS17互換の確認APIは新SDKでdeprecated警告がありますが、18以降は新APIを分岐して使用します。

追加テストは共有設定の自動拡大防止・通信失敗時の本人束縛・開始/終了の個別修正案内・オンライン条件表示・破損記録隔離・認証失効を含め、15分境界・日跨ぎ・属性統合・明示nil、同名/失効対象、ロック、本人切替、退会送信ゲート、確認fingerprint、送信前保存失敗、送信中重複、結果不明の固定ID/payload再送を扱います。
DBテストは保存済みpayloadと募集日時を窓外へ変更して期限経過を再現し、再送が期限/version検査より先に判定される契約と異payload拒否を確認しています。
本番DBやBackendへのデプロイは行っていません。

## 実機で残る確認

iOS17とiOS26以降の日本語環境で、Siriとショートカットをそれぞれ入口にします。
実機OS・locale・操作・対話・Backend最終状態を記録します。

- 4操作が見つかり、日時を入力して成功する。開始/終了の日付とタイムゾーンを確認する。
- 募集作成で複数友達、同名候補、オンライン/オフライン、エリア、任意カテゴリを選べる。
- 作成と取消のまとめ確認で中止した場合、書込が起きない。
- ロック直後と時間経過後の両方で友達/募集の情報を表示せず、解除後に実行できる。complete保護とisProtectedDataAvailableの実機上の猶予も確認する。
- 未認証・プロフィール未設定から認証を完了し、受け取った入力を再入力せず続けられる。
- 属性不一致、募集中の区間削除、失効した友達、version競合を安全に解決する。
- 通信断の結果不明で同じID/payloadを再送し、二重招待や二重取消を発生させない。
- 実行後にアプリへ戻ると最新の暇・募集を取得する。別本人へ切り替えた場合は旧操作を送らない。

実機検証が済むまで、Siriの日本語フレーズ認識やApple対話UIの成立を検証済みと報告しません。

## 独立レビューの判定

Opus 5.5は初回実装レビューで共有範囲の暗黙拡大、プロフィール通信失敗時の本人識別消失、拒否理由・日時補完、オンラインエリア表記を重要指摘しました。
修正後の再レビューはコード準備GO、再現可能な新規ブロッカーなしです。
再レビューへ報告した時点は152件成功で、その後の追加Intentテスト3件も含め最終155件が成功しました。
送信前のセッション消失が汎用AuthenticationFailureの場合に安全側の結果不明になる点は、未解決の非ブロッキング改善事項です。
この場合も新しいIDを自動発行せず、同じ操作を保持します。
実機受け入れは未完了のため、全要件受け入れの判定はMANUAL_VERIFY_REQUIREDです。


## PR候補の分離検証（2026-10-04）

作業開始前から存在したproject.pbxproj、xcschemeのローカル設定変更とモックHTMLはPRへ含めない。
ステージしたファイルだけを `/private/tmp/himatch-siri-pr-checkout/` に取り出し、リモートmain由来のXcode設定で再検証した。
XcodeBuildMCPの最終Debug build-for-testingと160件のSwift Testingは成功、Releaseビルドも成功した。
`test_sim_2026-10-04T03-55-48-776Z_pid54869_44e91654.xcresult` と `build_sim_2026-10-04T03-56-12-523Z_pid54869_9372b72a.log` が証拠である。
Debug/Releaseの4操作の認証・実行モードmetadataを再照合し、`node scripts/verify.mjs`も成功した。
PRのchecked_inputsは、この分離した公開対象の入力へ更新する。未公開のローカルXcode設定は検証済みのPR入力と区別する。

Claude CLIのPR前レビューはドラフトGO。指摘された確定拒否後編集のID衝突と未送信失効の競合を修正し、修正差分の再レビューもGOだった。
追加5件は既知拒否・事前アクセス拒否後の新ID、初回失効競合、コールドunknown再送の失効競合、新記録保存失敗時の元入力保持を検証する。
実機受け入れは引き続き未実施で、ドラフト状態を維持する。


## バージョン0.1.6（2026-10-04）

XcodeBuildMCPで0.1.6のDebug/Releaseをビルドし、生成Info.plistのCFBundleShortVersionStringが双方0.1.6であることを確認した（build 1）。
ログは `build_sim_2026-10-04T04-13-30-297Z_pid54869_114ac352.log` と `build_sim_2026-10-04T04-13-55-302Z_pid54869_5c45da4b.log`。
設定画面の表示はBundleのバージョンを参照する。業務処理は変更していないため、上記160件の証拠を再利用する。
