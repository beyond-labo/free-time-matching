# CI/CD

Backend、iOS、Androidは、検証とリリースを独立して実行します。
この文書は各手順への索引と、リポジトリ全体に共通する保護ルールだけを扱います。

## 運用手順

| 対象 | 文書 | 配布先 |
| --- | --- | --- |
| Backend | [Backend CI/CDとCloudflare](backend-ci-cd.md) | Cloudflare Workers staging / production |
| Supabase | [Supabase Auth・Database CI/CD](supabase-auth.md) | Supabase Postgres staging / production |
| iOS | [iOS CI/CDとTestFlight](ios-ci-cd.md) | App Store Connect TestFlight |
| Android | [Android CI/CDとGoogle Play](android-ci-cd.md) | Google Play internal track |

## 実装済みのWorkflow

| Workflow | Trigger | 処理 | 秘密情報 |
| --- | --- | --- | --- |
| `Repository CI` | pull request、`main` push、手動 | JSON、workspace、文書リンク、CI/CD構成を検査 | 使用しない |
| `Backend CI` | pull request、`main` push、手動、再利用呼び出し | BackendとTerraformを検証 | 使用しない |
| `Supabase CI` | pull request、`main` push、手動、再利用呼び出し | migration初期適用、DB lint、pgTAP | 使用しない |
| `Backend CD (staging)` | `main` push | Terraform apply、Supabase migration、Worker設定・deploy、health smoke | `staging` Environmentのみ |
| `Backend CD (production)` | `backend-vX.Y.Z` tag、手動 | preflight、承認、Terraform apply、Supabase migration、Worker設定・deploy、health smoke | `production-plan`と`production` Environment |
| `iOS CI` | pull request、`main` push、手動 | signing preflight、Simulator build、Swift Testing | 使用しない |
| `iOS TestFlight` | `ios-vX.Y.Z` annotated tag、`main`からの手動実行 | release ref検証、同じcommitのtest、署名、IPA export、App Store Connect upload | `testflight` Environmentのみ |
| `Android CI` | pull request、`main` push、手動 | lint、JVM単体テスト、debug build | 使用しない |
| `Android Google Play` | `android-vX.Y.Z` tag、手動 | AAB署名、internal track upload | `play-internal` Environmentのみ |

## mainの保護

GitHub repositoryの`Settings`から、`main`を対象とするbranch rulesetを作成します。
pull requestと承認を必須にし、次のstatus checksをrequired checksへ登録します。

- `Repository validation`
- `Verify backend and Cloudflare configuration`
- `Verify Supabase migrations and RLS`
- `iOS build and test`
- `Android build and test`

各CIはすべてのpull requestで起動するため、path filterによってrequired checkが待機状態のまま残る構成にはしません。
required checkへ追加する前に、pull requestで成功と意図した失敗の両方を確認します。

現在の承認者は`free-time-matching-approvers` Teamに所属する`hiiragi589`です。
`hiiragi589`のbypassを許可する場合もpull request経由に限定し、直接pushへ切り替えない設定にします。

## 公開リポジトリの境界

pull requestのCIは秘密情報を参照しません。
配布資格情報はGitHub Environmentだけに登録し、repositoryまたはorganizationの同名secretへ複製しません。
外部forkのworkflowへEnvironment secretは渡さず、`pull_request_target`で外部コードを実行しません。
`beyond-labo`外のcollaboratorは登録せず、外部forkからのpull request workflowは組織メンバーが承認してから実行します。

workflowの権限はjobごとに最小化し、外部actionは完全なcommit SHAへ固定します。
同じ配布先への実行は`concurrency`で直列化し、secret、state、詳細なplanをlog、artifact、pull request commentへ保存しません。

workflow、配布スクリプト、`infra/`の変更には、CODEOWNERSまたはbranch rulesetで管理者レビューを要求します。
release tagの作成、更新、削除はtag rulesetでリリース担当者だけに許可し、force updateを禁止します。
Environmentでは配布元のbranchまたはtagを制限し、production相当の配布にはrequired reviewerを設定します。

公開状態そのものより、workflowを未レビューで変更できること、保護されていないrelease tagを作れること、Environment secretへ承認なしで到達できることが主要なリスクです。
