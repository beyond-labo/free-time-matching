# Supabase Auth・Database CI/CD

この文書は、iOSのnative Sign in with Apple、Supabase Auth/Postgres、Cloudflare Workerを、未設定の状態からstaging・productionへ接続する手順です。
秘密値はリポジトリ、issue、pull request、チャットへ保存しません。

## 構成と自動化範囲

環境ごとにSupabase Projectを分離します。

| 用途 | Supabase | Worker | iOS |
| --- | --- | --- | --- |
| ローカル・Pull Request | Docker上の一時Postgres | mock／dry-run | Simulator |
| staging | staging Project | `himatch-backend-staging` | 最初の内部TestFlight |
| production | production Project | `himatch-backend-production` | App Store配布用の後続pipeline |

iOSがSupabaseへ直接行うのはAuthのsign-in、session refresh、sign-outです。
プロフィールや削除などの業務APIは`API_BASE_URL`のCloudflare Workerへ送り、iOSからSupabase PostgRESTやDBへ直接アクセスしません。
WorkerはSupabase access tokenを検証し、プロフィール操作では同じ利用者JWTをPostgRESTへ渡してRLSを適用します。
特権secretはアカウント削除Adapterだけが使います。

自動化済みの流れは次のとおりです。

```text
Pull Request
  └─ Supabase CI
       ├─ ローカルPostgres起動
       ├─ 全migration適用
       ├─ DB lint
       └─ pgTAP

main push
  └─ staging CD
       ├─ Supabase CI
       ├─ Terraform apply
       ├─ staging DB migration
       ├─ Worker vars/secretsを含むdeploy
       └─ /healthz

backend-vX.Y.Z tag またはmainからの手動実行
  └─ production CD
       ├─ source・Supabase CI・Terraform plan
       ├─ production Environment承認
       ├─ Terraform apply
       ├─ production DB migration
       ├─ Worker vars/secretsを含むdeploy
       └─ /healthz
```

Terraform applyを先に完了し、DB migrationはWorkerより先に適用されます。
本番migrationは旧Workerと新Workerのどちらから呼ばれても壊れないadditiveな変更にし、削除・rename・NOT NULL化は複数releaseのexpand / contractで行います。

## 作業前に用意するもの

- Supabase organizationでProjectを作成・設定できる権限。
- Apple Developer ProgramでIdentifier、Key、Profileを設定できる権限。
- GitHubの`staging`、`production-plan`、`production`、`testflight` Environmentを編集できる権限。
- Cloudflare Workerを配備できる既存の資格情報。
- 秘密値を保存するpassword manager。
- ローカル確認用のDockerとSupabase CLI 2.117.0。

Supabase CLIのバージョンを確認します。

```sh
npx -y supabase@2.117.0 --version
```

## 初回セットアップ

### 1. OrganizationとProjectを準備する

#### 1.1 完成形と再開位置を確認する

初期構築の完成形は次のとおりです。

| アプリ環境 | Supabase Organization | Supabase Project | 初期構築中のPlan |
| --- | --- | --- | --- |
| staging | `beyond-labo-staging` | `himatch-staging` | Free |
| production | `beyond-labo-production` | `himatch-production` | Free |

各Organizationには対応するProjectを1つだけ置きます。
同じOrganizationに2 Projectを置いた状態は、Project自体が分かれていてもCI権限の分離が完了していません。

作業を再開するときは、[Supabase Organizations](https://supabase.com/dashboard/organizations)で現在の状態を確認し、次の表から進む節を決めます。

| 確認結果 | 次に進む節 |
| --- | --- |
| 2つのOrganizationがない | 1.2 Organizationを作成する |
| 対応するProjectがない | 1.3または1.4で不足するProjectだけを作成する |
| 2 Projectが同じOrganizationにある | 1.5 既存Projectを別Organizationへ移動する |
| 各Organizationに対応Projectが1つずつある | 1.6 構成を確認し、完了後に「2. CI identityを準備する」へ進む |

SupabaseのPlanはOrganization単位です。
productionだけを後からProへ変更できるように、初期構築時点からOrganizationを分けます。

別Organizationはclassic personal access tokenの到達範囲を分ける境界でもあります。
Proへ変更してもProject-scoped roleは追加されないため、Plan変更でCI権限の分離を代用できません。

#### 1.2 Organizationを作成する

存在しないOrganizationだけを作成します。
すでに同名のOrganizationが表示される場合は作り直しません。

1. 左上のorganization selectorを開き、`New organization`を選びます。
2. `Create a new organization`画面を次の値で入力します。

   | 項目 | staging | production |
   | --- | --- | --- |
   | `Name` | `beyond-labo-staging` | `beyond-labo-production` |
   | `Type` | `Personal` | `Personal` |
   | `Plan` | `Free - $0/month` | `Free - $0/month` |

3. `Create organization`を選びます。
4. もう一方のOrganizationが存在しない場合は、同じ手順で作成します。
5. organization selectorに`beyond-labo-staging FREE`と`beyond-labo-production FREE`が表示されることを確認します。

#### 1.3 `himatch-staging`を作成する

`beyond-labo-staging`に`himatch-staging`がない場合だけ作成します。

1. [Supabase Dashboard](https://supabase.com/dashboard/projects)を開きます。
2. 左上のorganization selectorで`beyond-labo-staging`を選びます。
3. `New project`を選びます。
4. `Create a new project`画面の`Organization`が`beyond-labo-staging`になっていることを確認します。
5. `GitHub (optional)`は未選択のままにします。
6. `Project name`へ`himatch-staging`を入力します。
7. `Database password`へpassword managerで生成したstaging専用passwordを入力します。
8. `Region`で`Northeast Asia (Tokyo)`を選び、region codeが`ap-northeast-1`であることを確認します。
9. `Security`で`Enable Data API`をONにします。
10. `Automatically expose new tables`をOFFにします。
11. `Enable automatic RLS`をONにします。
12. 入力値を確認し、`Create new project`を選びます。
13. Project Overviewの`STATUS`が`Healthy`になるまで待ちます。

Database passwordは`himatch / Supabase / staging / database password`としてpassword managerへ保存します。
Dashboardの`Generate a password`を使う場合は、Project作成を確定する前に保存します。

#### 1.4 `himatch-production`を作成する

`beyond-labo-production`に`himatch-production`がない場合だけ作成します。
1.3と同じ操作を次の値で実行します。

| 項目 | productionの値 |
| --- | --- |
| `Organization` | `beyond-labo-production` |
| `Project name` | `himatch-production` |
| `Database password` | production専用の別password |
| `Region` | `Northeast Asia (Tokyo)` `ap-northeast-1` |
| `Enable Data API` | ON |
| `Automatically expose new tables` | OFF |
| `Enable automatic RLS` | ON |

Database passwordは`himatch / Supabase / production / database password`としてpassword managerへ保存します。
stagingのpasswordをproductionへ流用しません。

#### 1.5 既存Projectを別Organizationへ移動する

この節は、既存の1 Organizationに`himatch-staging`と`himatch-production`が同居している場合の補正手順です。
最初から完成形どおりに作成した場合は実行しません。

1. 2 Projectが入っているOrganizationの`Organization Settings`、`General`を開きます。
2. `Organization name`を`beyond-labo-production`へ変更して`Save`を選びます。
3. `beyond-labo-staging`がなければ、1.2の値で作成します。
4. `beyond-labo-production`から`himatch-staging`を開きます。
5. 左メニュー最下部の`Project Settings`を選び、`General`の`Transfer project`まで移動します。
6. `Transfer project`を選び、dialogの見出しが`Transfer project himatch-staging`であることを確認します。
7. `Select Target Organization`で`beyond-labo-staging`を選びます。
8. source、target、対象Projectを照合し、`Transfer Project`を選びます。
9. 両方のProject Overviewで`STATUS`が`Healthy`へ戻ったことを確認します。

source OrganizationではOwner、target Organizationでは少なくともmemberである必要があります。
transfer前に対象ProjectのGitHub integration、Log Drain、Project-scoped roleを解除します。
paid OrganizationからFree Organizationへのtransferでは1分から2分の停止が起こる可能性があります。

#### 1.6 OrganizationとProjectの構成を確認する

organization selectorを切り替え、次の結果になることを確認します。

1. `beyond-labo-staging FREE`の`Projects`に`himatch-staging`だけが表示される。
2. `beyond-labo-production FREE`の`Projects`に`himatch-production`だけが表示される。
3. 両Projectの`STATUS`が`Healthy`である。
4. `Primary Database`に`Northeast Asia (Tokyo)`と`ap-northeast-1`が表示される。
5. `RECENT BRANCH`が`No branches`である。
6. `Integrations`、`Data API`、`Settings`で`Automatically expose new tables`がOFFである。
7. `Data API`が`Installed`である。

画面上部の`main PRODUCTION`はSupabase Project内のroot branchを示します。
`himatch-staging`に表示される`PRODUCTION`は、アプリのproduction環境を意味しません。

#### 1.7 Supabase Branchingは初版で使わない

初版では次の構成を使います。

- 環境分離：`himatch-staging`と`himatch-production`の別Project。
- 開発：ローカルSupabase CLIとDocker。
- Pull Request：secretless Supabase CI。
- remote反映：GitHub Environmentで分離したCLI migration。
- Supabase Branching：無効。

productionをProへ変更してもBranchingは有効化しません。
Pull Requestごとの実環境E2Eが必要になった場合だけ、短命なPreview Branchを別途設計します。

#### 1.8 Project値を取得する

各Projectについて次をpassword managerの環境別項目へ記録します。

| 値 | Dashboard上の取得元 | 登録先 | 公開可否 |
| --- | --- | --- | --- |
| Project ref | `Project Settings`、`General`、`Project ID` | GitHub Environment variable `SUPABASE_PROJECT_REF` | 公開設定 |
| Project URL | Project Overviewまたは画面上部の`Connect` | GitHub Environment variable `SUPABASE_URL` | 公開設定 |
| Publishable key | `Project Settings`、`API Keys`、`Publishable key` | GitHub Environment variable `SUPABASE_PUBLISHABLE_KEY` | iOSとWorkerへ埋め込み可能 |
| Secret key | `Project Settings`、`API Keys`、`Secret keys` | GitHub Environment secret `SUPABASE_SECRET_KEY` | server専用secret |
| Database password | Project作成時に保存した値 | GitHub Environment secret `SUPABASE_DB_PASSWORD` | migration専用secret |

`API Keys`画面では`Publishable and secret API keys`タブを使います。
`Legacy anon, service_role API keys`タブの長いJWT形式の値は使用しません。

Secret keyとDatabase passwordをiOSへ渡しません。
secret keyはRLSを迂回できるため、Cloudflare Workerのアカウント削除Adapter以外へ配布しません。
legacyの`service_role` keyしか表示されないProjectでは、`New secret key`で新方式のsecret keyを用意します。

### 2. CI identityを準備する

classic personal access tokenは、発行accountが参加するすべてのOrganizationとProjectへ到達します。
同じaccountから名前だけ違うtokenを2つ発行しても、環境間の到達範囲は分離されません。

staging用とproduction用に、異なるメールアドレスを持つ別々のSupabase accountを使います。
各accountは対応するOrganizationだけへDeveloperとして参加させます。

#### 2.1 CI専用accountを招待する

1. Owner accountでorganization selectorから`beyond-labo-staging`を選びます。
2. 左メニューの`Team`を開き、`Invite members`を選びます。
3. `Invite team members`で`Role`を`Developer`にします。
4. `Email addresses`へstaging専用accountのメールアドレスだけを入力し、`Send invitation`を選びます。
5. staging専用accountで24時間以内に招待を承認します。
6. staging専用accountでDashboardへloginし、`beyond-labo-staging`と`himatch-staging`だけが表示されることを確認します。
7. `beyond-labo-production`でも同じ操作を行い、production専用accountだけをDeveloperとして招待します。
8. production専用accountで、`beyond-labo-production`と`himatch-production`だけが表示されることを確認します。

DeveloperはProject内容を変更でき、データやAuth userの削除も可能ですが、Project設定の変更やProject自体の削除はできません。
CI専用accountを日常作業へ使わず、MFAを有効にします。

#### 2.2 classic tokenを発行する

`Generate New Token` dialogに`Name`と`Expires in`だけが表示される場合はclassic tokenです。
Projectやpermissionを選ぶ欄が表示される場合だけ、Organization分離を維持したままscoped tokenで権限をさらに狭めます。

1. staging専用accountで[Supabase Account Tokens](https://supabase.com/dashboard/account/tokens)を開きます。
2. `Generate new token`を選びます。
3. `Name`へ`himatch-github-actions-staging`を入力します。
4. `Expires in`で`30 days`を選び、失効日の7日前を運用カレンダーへ登録します。
5. `Generate token`を選びます。
6. 一度だけ表示されるtokenをpassword managerの`himatch / Supabase / staging / GitHub Actions token`へ保存します。
7. token一覧にtoken名と期限が表示されることを確認します。
8. production専用accountで`himatch-github-actions-production`を発行し、production用の別項目へ保存します。

Owner個人accountからtokenを発行しません。
Proへ変更してもclassic tokenの到達範囲は変わりません。

#### 2.3 CI identityの完成条件を確認する

次のすべてを満たしたら「3. AuthとSign in with Appleを設定する」へ進みます。

- staging用accountからproduction用OrganizationとProjectが見えない。
- production用accountからstaging用OrganizationとProjectが見えない。
- 各Organizationの`Team`に、Ownerと対応するDeveloper CI accountだけが表示される。
- 2つのCI accountが別々のtokenを持ち、token値をpassword manager以外へ保存していない。

### 3. AuthとSign in with Appleを設定する

先にTestFlightで使用する実Bundle IDを決めます。
Repository内の`com.example.himatch`は署名不要CI用の値であり、Apple DeveloperとSupabaseへ登録しません。
実Bundle IDはGitHub `testflight` Environment variableの`IOS_BUNDLE_ID`と同じ値にします。

#### 3.1 Apple DeveloperでApp IDを登録する

1. [Apple DeveloperのIdentifiers](https://developer.apple.com/account/resources/identifiers/list)を開きます。
2. `Identifiers`一覧左上の追加ボタン`+`を選びます。
3. `App IDs`を選び、`Continue`を選びます。
4. typeで`App`を選び、`Continue`を選びます。
5. `Description`へ`Himatch`など識別できる名前を入力します。
6. `Bundle ID`で`Explicit`を選び、実Bundle IDを入力します。
7. `Capabilities`で`Sign in with Apple`をONにします。
8. `Configure`が表示された場合は`Enable as a primary App ID`を選びます。
9. `Server-to-Server Notification Endpoint`は空欄にします。
   初版の削除処理はアプリ内再認証とBackend処理で完結し、このendpointを実装していません。
10. `Continue`で内容を確認し、`Register`を選びます。

既存App IDを使う場合は、そのApp IDを開いて`Sign in with Apple`、`Configure`、`Enable as a primary App ID`、`Save`の順で有効化します。
Capability変更後は既存provisioning profileが無効になるため、profileを再生成します。

#### 3.2 XcodeのCapabilityとprovisioning profileを確認する

1. Xcodeで`apps/ios/Himatch.xcodeproj`を開きます。
2. `Himatch` target、`Signing & Capabilities`を開きます。
3. `Bundle Identifier`が実Bundle IDになっていることを確認します。
4. `Sign in with Apple` capabilityが表示されることを確認します。
5. 自動署名を使う場合は`Automatically manage signing`をONにし、正しいTeamを選びます。
6. 手動署名またはCI用profileを使う場合は、[Apple DeveloperのProfiles](https://developer.apple.com/account/resources/profiles/list)でdevelopment／App Store distribution profileを再生成します。

TestFlight用証明書とprofileのGitHub登録は[「iOS CI/CD」](ios-ci-cd.md)の手順に従います。

#### 3.3 アカウント削除用のSign in with Apple Keyを作成する

このKeyは、Cloudflare WorkerがApple tokenを失効するときだけ使います。
native iOSログインだけを使うSupabaseの`Secret Key (for OAuth)`へは入力しません。

1. [Apple DeveloperのKeys](https://developer.apple.com/account/resources/authkeys/list)を開きます。
2. 一覧左上の追加ボタン`+`を選びます。
3. `Key Name`へ`himatch-account-deletion`など用途が分かる名前を入力します。
4. `Sign in with Apple`をONにし、`Configure`を選びます。
5. `Primary App ID`で3.1のApp IDを選び、`Save`を選びます。
6. `Continue`、`Register`の順で確定します。
7. `.p8`を一度だけdownloadします。
8. Team ID、Key ID、`.p8`をpassword managerの環境共通Apple資格情報へ保存します。

`.p8`は再downloadできません。
紛失または漏えい時は新しいKeyへ移行した後で古いKeyをrevokeし、GitHub Environmentの`APPLE_KEY_ID`と`APPLE_PRIVATE_KEY`を更新します。

#### 3.4 SupabaseでApple providerだけを有効にする

stagingとproductionの両方で次を行います。

1. 対象Projectを開きます。
2. 左メニューの`Authentication`を選びます。
3. Authentication内の`CONFIGURATION`、`Sign In / Providers`を開きます。
4. `User Signups`で`Allow new users to sign up`をONにします。
5. `Allow manual linking`をOFFにします。
6. `Allow anonymous sign-ins`をOFFにします。
7. `Auth Providers`の`Email`を開きます。
8. `Enable email provider`をOFFにし、`Save`を選びます。
9. `Phone`が`Disabled`であることを確認します。
10. `Apple`を開きます。
11. `Enable Sign in with Apple`をONにします。
12. `Client IDs`へ実Bundle IDを入力します。
    native `signInWithIdToken`では、ここに登録したBundle IDがApple identity tokenのaudienceとして許可されます。
13. `Secret Key (for OAuth)`は空欄のままにします。
    Web OAuthを使わない初版ではServices IDと6か月ごとのOAuth secret更新は不要です。
14. `Allow users without an email`はOFFのままにします。
15. `Save`を選びます。

Supabaseの`Callback URL (for OAuth)`はnative iOSログインでは使用しません。
将来Webログインを追加するときは、Services ID、Callback URL、OAuth secretのローテーションを別仕様として追加します。

#### 3.5 Session設定を確認する

1. `Authentication`、`CONFIGURATION`、`Sessions`を開きます。
2. `Access Tokens`の`Access token expiry time`を確認します。
3. 値が`3600` secondsなら変更しません。
4. 異なる場合は`3600`へ変更し、同じsectionの`Save changes`を選びます。
5. `Refresh Tokens`の`Detect and revoke potentially compromised refresh tokens`をONにします。
6. `Refresh token reuse interval`は推奨値の`10` secondsを維持します。

初版ではFree Planでも設定できるaccess token expiryだけを必須にします。
`Enforce single session per user`、`Time-box user sessions`、`Inactivity timeout`はPro Plan向けのため変更しません。

Appleの氏名は初回認証時にしか返らないため、本アプリのプロフィール正本には使いません。
ニックネームは`user_profiles`で別途管理します。

### 4. JWT Signing Keysを確認する

各ProjectのJWT Signing Keyを非対称鍵へ設定します。
Workerは`ES256`または`RS256`のJWKSだけを受け入れます。

#### 4.1 現在のKeyを確認する

stagingとproductionの両方で次を行います。

1. 対象Projectを開きます。
2. 左メニューの`Project Settings`を選びます。
3. Settings内の`JWT Keys`を開きます。
4. `JWT Signing Keys`タブを開きます。
5. `CURRENT KEY`の`TYPE`を確認します。
6. `ECC (P-256)`なら、Dashboard上の追加操作は不要です。
   `ECC (P-256)`はJWTの`ES256`に対応します。
7. `Legacy HS256 (Shared Secret)`がCURRENT KEYなら、4.2の移行を行います。

`Legacy JWT Secret`タブのsecretをGitHubやWorkerへコピーしません。

#### 4.2 Legacy HS256からES256へ移行する

この操作はまずstagingで実施し、staging E2Eの成功後にproductionで繰り返します。

1. `JWT Signing Keys`画面の`Create Standby Key`を選びます。
2. `Choose signing algorithm`で既定の`ES256 (ECC) RECOMMENDED`を選びます。
3. `Import an existing private key`はOFFのままにします。
4. `Create standby key`を選びます。
5. 新しいSTANDBY KEYの公開鍵がJWKSへ出るまで待ちます。
   Supabaseとアプリ側のcacheを考慮し、最大20分を見込みます。
6. 下記のJWKS確認で、新しいKeyの`kid`と`alg: ES256`が取得できることを確認します。
7. Dashboardへ戻り、STANDBY KEYのactionから`Rotate keys`を実行します。
8. `CURRENT KEY`が`ECC (P-256)`になったことを確認します。
9. Sign in with AppleとWorkerの認証付きAPIを確認します。
10. access token expiryが3600秒なら、少なくとも1時間15分待ってから旧Keyのrevokeを検討します。

初回構築では、旧Keyの即時revokeを完了条件にしません。
publishable／secret API keyへの移行、実機E2E、新旧tokenの検証を終える前に旧Keyをrevokeしません。

#### 4.3 JWKSを確認する

ブラウザまたはcurlで次を確認します。

```sh
curl --fail --silent --show-error \
  "https://PROJECT_REF.supabase.co/auth/v1/.well-known/jwks.json"
```

確認事項は次のとおりです。

- `keys`が空でない。
- 使用中の鍵に`kid`がある。
- `alg`が`ES256`または`RS256`である。
- ローテーション中は新旧の検証鍵が取得できる。

legacyの共有JWT secretをWorkerのResource Server検証へ使用しません。

### 5. GitHub Environmentを設定する

[`beyond-labo/free-time-matching`のEnvironments設定](https://github.com/beyond-labo/free-time-matching/settings/environments)を開きます。
値はenvironmentごとに登録し、同名のrepository secretへ複製しません。

#### 5.1 Environmentを作成する

Environmentが未作成の場合は次の順で作成します。

1. Repositoryの`Settings`を開きます。
2. 左メニューの`Environments`を開きます。
3. `New environment`を選びます。
4. `staging`と入力し、`Configure environment`を選びます。
5. 同じ操作で`production-plan`、`production`、`testflight`を作成します。

`production`では`Deployment protection rules`の`Required reviewers`へ本番承認者を追加します。
利用中のGitHub planで表示される場合は`Prevent self-review`もONにします。
`production-plan`にはread-onlyのTerraform planに必要な設定だけを置き、Supabase access token、Database password、Worker secretを置きません。

Environment内では、公開値を`Environment variables`の`Add variable`、秘密値を`Environment secrets`の`Add secret`から登録します。
値を登録した後は名前だけが一覧に揃っていることを確認し、secret値を画面共有しません。

#### 5.2 Environment valuesとsecretsを登録する

環境別CI accountの招待とclassic tokenの発行は、手順2で完了しています。
password managerに保存したtokenを、ここで対応するGitHub Environmentの`SUPABASE_ACCESS_TOKEN`へ登録します。
同じEnvironmentへProject値、Database password、server secret、Apple設定も追加します。

tokenをまだ発行していない場合は、2.2へ戻ります。
漏えい、担当者変更、または有効期限到来時は該当環境の旧tokenだけをrevokeし、そのEnvironment secretを更新してから対象環境を再実行します。

##### `staging`

GitHubの`staging` Environmentを開き、次を1行ずつ登録します。

| 種類 | 名前 | 内容 |
| --- | --- | --- |
| Variable | `SUPABASE_PROJECT_REF` | staging Project ref |
| Variable | `SUPABASE_URL` | staging Project URL |
| Variable | `SUPABASE_PUBLISHABLE_KEY` | staging publishable key |
| Variable | `APPLE_CLIENT_ID` | native App ID／Bundle ID |
| Secret | `SUPABASE_ACCESS_TOKEN` | stagingだけに到達できるCI identityのaccess token |
| Secret | `SUPABASE_DB_PASSWORD` | staging database password |
| Secret | `SUPABASE_SECRET_KEY` | staging secret key |
| Secret | `APPLE_TEAM_ID` | Apple Team ID |
| Secret | `APPLE_KEY_ID` | Sign in with Apple Key ID |
| Secret | `APPLE_PRIVATE_KEY` | `.p8`のPEM全文 |
| Secret | `ACCOUNT_DELETION_STATUS_SECRET` | 32 byte以上のランダム値 |

既存のCloudflare、R2、health URL設定も維持します。
`ACCOUNT_DELETION_STATUS_SECRET`は環境ごとに別値を生成します。

```sh
openssl rand -hex 32
```

##### `production`

`staging`と同じ名前を、production Projectとproduction用Apple設定の値で登録します。
`SUPABASE_ACCESS_TOKEN`の値はproductionだけに到達できる別identityのtokenにします。
`production`にはrequired reviewerと配布元branch／tag制限を設定します。
`production-plan`へSupabase access token、DB password、Worker secretを登録しません。

##### `testflight`

既存の署名設定に次のVariableを追加します。

| 名前 | 最初の内部TestFlightで設定する値 |
| --- | --- |
| `SUPABASE_URL` | staging Project URL |
| `SUPABASE_PUBLISHABLE_KEY` | staging publishable key |
| `API_BASE_URL` | `https://api-staging.beyond-labo.com` |

TestFlight workflowはこれらをRelease archiveへ埋め込みます。
値はアプリから取得できる公開設定であり、secretとして扱いません。
`SUPABASE_URL`とpublishable keyはSupabase Authのsign-in／session更新だけに使い、プロフィールDB操作は`API_BASE_URL`のWorker経由です。
production接続版が必要になった場合は値を都度切り替えず、production配布用のEnvironmentとworkflowを別に作ります。

#### 5.3 GitHubで登録結果を確認する

各Environmentを開き、次を確認します。

- `staging`にはSupabase／Apple variable 4件、Supabase／Apple／削除用secret 7件がある。
- `production`には同名の設定がproduction値である。
- `production-plan`にはSupabase secretがない。
- `testflight`にはstagingの`SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`、staging Workerの`API_BASE_URL`がある。
- Repository-level secretsに同名のSupabase secretを複製していない。
- secret値そのものではなく、Environment名と設定名だけをレビュー記録へ残している。

## Pull Request CIを確認する

[`Supabase CI`](../../.github/workflows/ci-supabase.yml)は外部Projectへ接続せず、Docker上の一時DBだけを使います。

GitHub上では[Supabase CI workflow](https://github.com/beyond-labo/free-time-matching/actions/workflows/ci-supabase.yml)から実行履歴を確認できます。

ローカルでも同じ順序で確認できます。

```sh
npx -y supabase@2.117.0 db start
npx -y supabase@2.117.0 db lint --local --schema public --level error --fail-on error
npx -y supabase@2.117.0 test db --local
npx -y supabase@2.117.0 stop --no-backup
```

Pull Requestでは次の順で確認します。

1. Pull Requestの`Checks`タブを開きます。
2. `Supabase CI`を開きます。
3. `Verify Supabase migrations and RLS`が成功していることを確認します。
4. job logで`Start local Supabase database`、`Lint database schema`、`Run pgTAP tests`、`Stop local Supabase database`が順に成功していることを確認します。
5. secretやremote Projectへの接続がないことを確認します。
6. 初回成功後に[Repository Rulesets](https://github.com/beyond-labo/free-time-matching/settings/rules)を開きます。
7. main用rulesetのrequired status checksへ`Verify Supabase migrations and RLS`を追加します。

初回実行より前にcheck名を推測して登録しません。

## stagingへ初回反映する

GitHub Environmentの設定を終えてからmainへmergeします。
`Backend CD (staging)`が次を自動実行します。

1. Backend CIとSupabase CIを実行する。
2. Terraformをplanしてapplyする。
3. staging Projectへlinkする。
4. `supabase db push --dry-run`で対象migrationを確認する。
5. `supabase db push --yes`で未適用migrationだけを非対話で反映する。
6. `supabase migration list`でlinked Projectの履歴を表示する。
7. Worker variablesとsecretsを同じWorker versionへ渡してdeployする。
8. `/healthz`を確認する。

反映状況は[Backend CD (staging) workflow](https://github.com/beyond-labo/free-time-matching/actions/workflows/cd-backend-staging.yml)で確認します。

1. GitHubの`Actions`、`Backend CD (staging)`を開きます。
2. mainへmergeしたcommitに対応するrunを開きます。
3. `Database, Terraform and Worker deploy (staging)` jobを開きます。
4. `Apply Supabase migrations to staging`が成功していることを確認します。
5. job summaryの`Staging Supabase migration`でProject refとmigration履歴確認の表示を確認します。
6. `Deploy Worker to staging`と`Verify staging health endpoint`が成功していることを確認します。
7. Supabaseの`himatch-staging`を開きます。
8. 左メニューの`Database`から`Migrations`を開き、GitHub Actionsが適用したmigrationを確認します。

成功後、Supabase Dashboardのmigration historyとGitHub Actions summaryに同じmigrationが記録されていることを確認します。
DashboardのSQL EditorやTable Editorで本番schemaを直接変更しません。

## staging実機E2E

内部TestFlightまたはdevelopment署名した実機で確認します。

内部TestFlightを使う場合は、先に[「iOS CI/CD」](ios-ci-cd.md)の`testflight` Environment設定とarchive手順を完了します。
TestFlight buildがstagingへ接続していることは、GitHub Actionsのrelease summaryと`API_BASE_URL`の環境名で確認します。

1. 未認証の`GET /v1/me`が401になる。
2. Sign in with AppleからSupabase sessionを取得できる。
3. 初回はプロフィール設定へ進む。
4. 再起動後はsessionを復元してメインへ進む。
5. nicknameと4種類のpreset iconだけを保存できる。
6. 別利用者のprofileを取得・更新できない。
7. ログアウト後は保護APIを呼べない。
8. 削除時にApple再認証が要求される。
9. 削除完了後はsessionを復元できない。
10. Supabase Auth userとprofileが削除され、status tokenでは結果だけを照会できる。

実資格情報を使うE2EをPull Request CIへ入れません。
実施日、build、利用した環境、結果、削除受付referenceを秘密値を含めず運用記録へ残します。

## App Store公開前にproductionだけをProへ変更する

この手順は、実ユーザーを受け入れるApp Store公開の準備時に実行します。
初期構築や内部TestFlightのためには実行せず、それまでは両OrganizationをFreeのまま維持します。

1. [Supabase Organizations](https://supabase.com/dashboard/organizations)を開きます。
2. `beyond-labo-production`を選び、`Billing`を開きます。
3. 現在のPlanがFreeであることを確認し、`Change subscription plan`を選びます。
4. `Pro`を選び、Compute Sizeは`Micro`のままにします。
5. `Charge today`、`Monthly invoice estimate`、支払方法、billing情報を確認します。
6. 金額と対象Organizationを照合して、`Confirm upgrade`を選びます。
7. `beyond-labo-production`が`PRO`、`beyond-labo-staging`が`FREE`と表示されることを確認します。
8. productionの`Spend Cap`がONであることを確認します。
9. productionで非アクティブによるpauseがなく、日次backupと7日間のlog保持、Email supportが利用できることを確認します。

2026年9月22日時点のPro Plan基本料金は月額25 USDです。
Computeや追加機能による課金は別に確認します。

Plan変更後も、classic personal access tokenの到達範囲は発行accountのOrganization membershipで決まります。
Proへの変更をCI権限分離の代わりにせず、別Organizationと別CI accountを維持します。

## productionへ初回反映する

staging E2Eが完了したcommitをmainへ含め、既存のBackend release手順でannotated tagを作成します。

```sh
git tag -a backend-v0.1.0 -m "Backend 0.1.0"
git push origin backend-v0.1.0
```

`Backend CD (production)`は、production Environmentの承認後にTerraform apply、DB migration、Worker配備の順で実行します。
productionのDBだけを先に手動変更しません。

反映状況は[Backend CD (production) workflow](https://github.com/beyond-labo/free-time-matching/actions/workflows/cd-backend-production.yml)で確認します。

1. GitHubの`Actions`、`Backend CD (production)`を開きます。
2. 作成したannotated tagに対応するrunを開きます。
3. `Validate release ref`、Backend CI、Supabase CIの成功を確認します。
4. `Production Terraform preflight plan`のsummaryを確認します。
5. `Apply and deploy production`が`production` Environmentの承認待ちになったら、tag、commit、plan summary、staging E2E記録を照合します。
6. 承認者が`Review deployments`から`production`を選び、承認します。
7. `Apply Supabase migrations to production`、Worker deploy、`/healthz`の順に成功したことを確認します。
8. Supabaseの`himatch-production`、`Database`、`Migrations`で適用履歴を確認します。
9. migration履歴とGitHub Actions summaryの対象commitが一致することを確認します。

## Schema変更の通常手順

1つの変更を1つの新規migrationへ記録します。

```sh
npx -y supabase@2.117.0 migration new CHANGE_NAME
```

SQLを編集後、ローカルDBを作り直してmigrationの初期適用を確認します。

```sh
npx -y supabase@2.117.0 db reset --local
npx -y supabase@2.117.0 db lint --local --schema public --level error --fail-on error
npx -y supabase@2.117.0 test db --local
npx -y supabase@2.117.0 stop --no-backup
```

- 適用済みmigrationを編集・削除しない。
- Dashboardで先にschemaを変更しない。
- RLS、GRANT、REVOKE、関連pgTAPを同じPull Requestへ含める。
- destructive変更は旧アプリと旧Workerの利用がなくなった後のcontract migrationへ分離する。
- CIは`DROP`、`TRUNCATE`、`DELETE FROM`、rename、`SET NOT NULL`などを破壊的変更候補として停止する。承認済みのcontract migrationだけ、SQLコメント`-- himatch: destructive-migration-reviewed`を付ける。
- `migration repair`は通常操作に使わず、履歴不整合の原因と是正内容を記録したincident対応に限定する。

DB migrationは原則forward-onlyです。
失敗時は適用済みSQLを巻き戻そうとせず、互換性を回復する新しいcorrective migrationを作成します。

## 鍵とsecretのローテーション

- Supabase access tokenは環境別CI identity専用とし、担当者変更、漏えい、有効期限の前に該当環境だけ再発行する。
- Database password変更時はGitHub Environmentを同時に更新し、stagingでmigration dry-runを確認する。
- Supabase secret key変更時はWorker配備を再実行する。
- アカウント削除用Apple Key変更時は`APPLE_KEY_ID`、`APPLE_PRIVATE_KEY`を同じ作業で更新し、Workerを再配備する。native-only構成ではSupabaseの`Secret Key (for OAuth)`を変更しない。
- Bundle IDを変更する場合はApple App ID、provisioning profile、SupabaseのApple `Client IDs`、`APPLE_CLIENT_ID`、`IOS_BUNDLE_ID`を同じ変更として扱う。
- `ACCOUNT_DELETION_STATUS_SECRET`を変更すると既存status tokenを再構成できなくなるため、削除受付が残っていないことを確認してから変更する。

## 失敗時の切り分け

| 症状 | 最初に確認するもの |
| --- | --- |
| `supabase link`失敗 | Project ref、access token、DB password、Project停止状態 |
| migration history不一致 | `supabase migration list`。Dashboard直接変更の有無 |
| pgTAP失敗 | RLS、GRANT/REVOKE、test plan件数、migration初期適用 |
| Workerが起動しない | GitHub Environmentの8つのruntime設定、Worker deployment log |
| JWTが401 | `SUPABASE_URL`、JWKS、issuer、audience、Signing Key方式 |
| Apple認証失敗 | Bundle ID、Client ID、Capability、nonce、Supabase Apple provider |
| 削除が`actionRequired` | Apple revokeとSupabase Auth user削除を個別確認 |

削除結果が`actionRequired`の場合、受付済みaccountの通常API拒否を維持します。
Apple token失効とSupabase Auth user削除の失敗した側だけを管理経路で是正し、完了証拠を運用記録へ残します。

DB migration後にWorker deployまたはsmokeが失敗した場合、job summaryの`Partial release requires attention`を確認します。
適用済みmigrationは削除せず、後方互換が保たれていれば失敗原因を直して同じcommitを再実行します。
互換性に問題があれば、旧Workerでも動くcorrective migrationを追加してから再配備します。

## 完了チェックリスト

### 初回セットアップとstaging検証

- [ ] `himatch-staging`／`himatch-production`を東京regionの別Projectとして作成した。
- [ ] 両Projectを`beyond-labo-staging`／`beyond-labo-production`の別Organizationへ配置した。
- [ ] 初期構築中はstaging用とproduction用の両OrganizationをFreeにした。
- [ ] 両ProjectでData API ON、自動table公開OFF、自動RLS ONにした。
- [ ] Supabase Branchingを有効化していない。
- [ ] stagingとproductionへ別CI accountをDeveloperとして招待し、各accountに対応外Organizationが表示されないことを確認した。
- [ ] 各CI accountから別々のclassic tokenを発行し、`staging`と`production`のEnvironment secret `SUPABASE_ACCESS_TOKEN`へ登録した。
- [ ] 両ProjectでApple providerと非対称Signing Keyを設定した。
- [ ] `staging`／`production-plan`／`production`／`testflight`のGitHub設定を登録した。
- [ ] Pull RequestでSupabase CIが成功した。
- [ ] main merge後にstaging migration、Worker deploy、health smokeが成功した。
- [ ] main rulesetへSupabase checkを追加した。
- [ ] 内部TestFlightでstaging実機E2Eを完了した。

### App Store公開前

- [ ] production用OrganizationだけをProへ変更した。
- [ ] Pro変更後のproduction用OrganizationでSpend CapがONになっている。
- [ ] staging用OrganizationがFreeのままであることを確認した。
- [ ] production承認者、tag、復旧担当を確認した。

## 参照

- [Supabase Managing Environments](https://supabase.com/docs/guides/deployment/managing-environments)
- [Supabase Available Regions](https://supabase.com/docs/guides/platform/regions)
- [Supabase Branching](https://supabase.com/docs/guides/deployment/branching)
- [Supabase Access Control](https://supabase.com/docs/guides/platform/access-control)
- [Supabase Personal Access Tokens](https://supabase.com/docs/guides/platform/personal-access-tokens)
- [Supabase Project Transfers](https://supabase.com/docs/guides/platform/project-transfer)
- [Supabase Pricing](https://supabase.com/pricing)
- [Supabase Billing](https://supabase.com/docs/guides/platform/billing-on-supabase)
- [Supabase Billing FAQ](https://supabase.com/docs/guides/platform/billing-faq)
- [Supabase Database Backups](https://supabase.com/docs/guides/platform/backups)
- [Supabase Cost Control](https://supabase.com/docs/guides/platform/cost-control)
- [Supabase CLI Personal Access Tokens](https://supabase.com/docs/guides/cli/getting-started#access-token)
- [Supabase Database Migrations](https://supabase.com/docs/guides/deployment/database-migrations)
- [Supabase Database Testing](https://supabase.com/docs/guides/database/testing)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)
- [Supabase Sign in with Apple](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [Supabase Swift native ID token sign-in](https://supabase.com/docs/reference/swift/auth-signinwithidtoken)
- [Supabase JWT](https://supabase.com/docs/guides/auth/jwts)
- [Supabase JWT Signing Keys](https://supabase.com/docs/guides/auth/signing-keys)
- [Supabase User Sessions](https://supabase.com/docs/guides/auth/sessions)
- [Supabase user deletion](https://supabase.com/docs/guides/auth/managing-user-data)
- [Apple Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id)
- [Apple Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)
- [Apple Create a Sign in with Apple private key](https://developer.apple.com/help/account/capabilities/create-a-sign-in-with-apple-private-key)
- [Apple Create a development provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile)
- [Apple account deletion and token revocation](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
- [GitHub Managing environments for deployment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
