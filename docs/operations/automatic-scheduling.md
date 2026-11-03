# 自動提案・予定成立の運用

製品契約と受け入れ条件は [自動予定成立仕様](../../.kiro/specs/automatic-friend-scheduling/requirements.md)、責務とRPCは [設計](../../.kiro/specs/automatic-friend-scheduling/design.md) を参照します。

## 接続と初期設定

既存のSupabase認証・友達・暇APIに追加migrationを適用した環境で利用します。既存利用者と新規利用者の自動提案は初期オフです。設定の全体許可と、友達プロフィールの個別許可を両者が有効にして初めて対象になります。
本人の通常APIは利用者JWTを使います。定期処理と通知配送だけがサービス資格情報を使います。サービス用RPCをクライアントから呼ばないでください。

Cloudflareのstaging/production別Cronは15分ごとです。許可と暇の変更も検出の契機です。Cronは共通時間の検出・期限と条件の再評価後、通知配送を試みます。tickが失敗した場合も、既存通知の配送処理は独立して試みます。

## 通知配信の準備

Backendの環境に次を4つまとめて設定します。ローカルは無視対象の `.dev.vars`、配備時はGitHub EnvironmentのSecretsとVariablesからWorkerへ渡します。

| 値 | 保存先 | 用途 |
| --- | --- | --- |
| APNS_TEAM_ID | Secret | APNs署名のissuer |
| APNS_KEY_ID | Secret | APNs署名キーID |
| APNS_PRIVATE_KEY | Secret | ES256のp8鍵。ログへ出さない |
| APNS_TOPIC | Variable | 配信対象のBundle ID |

4つとも未設定ならPush配送を保留し、アプリ内通知は引き続き利用できます。一部だけ設定すると設定エラーとして扱います。設定がない状態をPush配信成功とは扱いません。
既存Workerから配信を停止する場合、GitHub側の値を空にするだけで既存WorkerのSecretが削除されるとは限りません。明示的にWorker側の設定を停止し、アプリ内通知の利用と切り分けて確認します。

iOSのAPNs capability、署名profile、Bundle ID、環境が一致する必要があります。Debugはsandbox、配布構成はproductionの端末tokenを登録します。通知の明示許可で登録し、拒否しても受信箱から回答できます。通知本文に相手名・暇時間を入れません。

通知は業務transactionで保存し、端末登録後の通知だけを配送キューへ入れます。leaseの期限切れで再試行し、同じ配送IDをAPNs collapse IDに使います。送信後に完了保存が失敗した場合の再送があり得るため、Pushの受信を業務状態の正本にはしません。

## ローカルと実環境の検証

```sh
node scripts/verify.mjs
pnpm --dir apps/backend typecheck
pnpm --dir apps/backend test
pnpm --dir apps/backend build
```

DBは専用のローカルDBへ全migrationを順に適用し、`supabase/tests/` の認可・暇・友達・Hostingと新しい自動予定成立試験を実行します。共有DBの初期化やリモートへのmigration適用をローカル検証の代わりに行いません。
iOSはXcodeBuildMCPでSimulator build/testを優先し、非応答や機能制限がある場合だけ理由を記録してCLIで補います。

STGでは別々の2アカウントで以下を確認します。

1. 初期オフ・片側のみ許可では提案が生まれない。
2. 双方の全体・友達別許可と共通暇で一つの匿名提案が生まれる。
3. 参加OK共有のオン・オフが相手表示に反映され、生の暇は返らない。
4. 片側OKでは未確定、双方OKで一つだけ確定し、両者の通知・予定に反映される。
5. 見送り・期限・許可オフ・暇削除・ブロック・退会・取消・再送の後も安全な状態になる。
6. 各人7日間1件、同じ2人14日間隔を、取消や端末変更で回避できない。
7. Push拒否時も完了し、許可時はsandbox/productionの実APNsをそれぞれ検証する。

STGへの配備、実APNs、複数実機、TestFlightへのアップロード、5〜20人での利用は別の実行証拠が必要です。ローカル試験の成功だけで実施済みとはしません。

## 評価

最重要KPIは、提案から実際の遊びが成立した割合です。任意回答の実施結果を使い、提案総数、確定数、遊べた回答数、未回答を別々に示します。2人の回答が食い違った場合を含め、回答数をそのまま遊び件数へ足しません。
提案後1回答・往復調整0回は設計目標です。実際の利用で操作数・調整の発生、煩わしさ・意図しない暇公開の受け止めを確認します。本文・token・個人の暇を一般の観測ログへ追加しません。

## 通報対応

通報は当事者確認後に定型理由を保存し、ブロックとは独立して受け付けます。管理画面・運営SLAはこの変更の対象外です。小規模利用前に権限を限定した通報確認担当と連絡先を決め、運営による非表示・利用停止が必要な場合の手順を準備します。
