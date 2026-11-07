# iOS CI/CDとTestFlight

`iOS CI`はすべてのpull request、`main` push、手動実行でXcode buildとSwift Testingを実行します。iOSのテストコードではXCTestを使用しません。
`iOS TestFlight`は`ios-v*` tagまたは手動実行から、署名済みIPAをApp Store Connectへuploadします。

## 実行環境

CIは`macos-26`と`/Applications/Xcode_26.6.app`を固定します。
同じimageのPython 3.14系とOpenSSL 3.6系をsigning preflightに使い、versionをworkflow logへ残します。

Appleは2026年時点のiOS build uploadにXcode 26以降を要求しています。
[Appleのupload要件](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)と[GitHub runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)を更新時に確認します。

## TestFlightへ配布する

運用上は、検証済みcommitへ`ios-vX.Y.Z`形式のannotated tagを付けます。

```sh
git tag -a ios-v0.1.0 -m "iOS 0.1.0"
git push origin ios-v0.1.0
```

workflowはtagが厳密な`ios-vX.Y.Z`形式のannotated tagであることと、対象commitが`origin/main`に含まれることを機械的に検査します。
testとreleaseはpreflightで確定した同一commitをcheckoutします。

手動実行ではGitHubの`Actions`から`iOS TestFlight`を選び、branchに現在の`main`を指定して、`marketing_version`へ`X.Y.Z`を入力します。
選択したcommitが現在の`origin/main`と一致しない場合はpreflightで停止します。
build numberはGitHubのrun numberとrun attemptから生成するため、再実行でも別番号になります。

配布jobは`testflight` Environmentの保護を通過してからsecretsを読みます。
archive前に、証明書と秘密鍵、証明書とprofile、有効期限、Team ID、Bundle ID、API private keyの形式を検査します。
Supabase URL、publishable key、Backend API URLも必須入力として検査し、Release archiveのInfo.plistへbuild setting経由で埋め込みます。
Supabase設定はAuthのsign-in／session更新だけに使います。プロフィールや削除などの業務リクエストはBackend API URLへ送り、iOSからSupabase PostgRESTやDBへ直接アクセスしません。
一時keychain、profile、API keyは終了時に削除し、成功したIPAはGitHub Artifactへ14日だけ保持します。

## 初回セットアップ

### 1. Apple Developer Program

[Apple Developer Account](https://developer.apple.com/account/)の`Membership details`を開きます。

1. Apple Developer Programが有効であることを確認する。
2. `Team ID`を控える。
3. 未同意の契約があればAccount Holderが同意する。

### 2. Explicit Bundle ID

Apple Developer Accountの`Certificates, Identifiers & Profiles`から`Identifiers`を開き、Explicit Bundle IDを登録します。
利用するcapabilityだけを有効にし、値をGitHub variable `IOS_BUNDLE_ID`へ登録します。

repository内の既定Bundle IDは`com.beyond-labo.aimano`です。
TestFlight archiveでも`IOS_BUNDLE_ID=com.beyond-labo.aimano`を設定します。

### 3. Apple Distribution証明書

Keychain AccessでCSRを作成し、Apple Developer Accountの`Certificates`から`Apple Distribution`証明書を発行します。
downloadした証明書をCSR作成時の秘密鍵と同じkeychainへ取り込みます。

Keychain Accessの`My Certificates`で証明書の配下に秘密鍵が表示されることを確認します。
証明書と秘密鍵を`.p12`としてexportし、強いpasswordを設定します。

```sh
base64 -i /path/to/distribution.p12 | pbcopy
```

Base64文字列を`IOS_DISTRIBUTION_CERTIFICATE_BASE64`、passwordを`IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`へ登録します。
[Appleの証明書概要](https://developer.apple.com/help/account/certificates/certificates-overview)、[CSRの作成手順](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)、[Keychain itemのexport手順](https://support.apple.com/guide/keychain-access/kyca35961/mac)を参照してください。

### 4. App Store provisioning profile

Apple Developer Accountの`Profiles`からDistribution用の`App Store Connect` profileを作成します。
登録済みBundle IDとApple Distribution証明書を選び、profileをdownloadします。

```sh
base64 -i Aimano_App_Store.mobileprovision | pbcopy
```

Base64文字列を`IOS_PROVISIONING_PROFILE_BASE64`へ登録します。

### 5. App Store Connectのアプリレコード

[App Store Connect](https://appstoreconnect.apple.com/)の`Apps`からアプリレコードを作成します。
名前、primary language、Bundle ID、一意なSKUを登録します。
binary uploadより先にアプリレコードが必要です。
[App Store Connectのアプリ作成手順](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)も確認してください。

### 6. App Store Connect API key

App Store Connectの`Users and Access`から`Integrations`を開き、Team Keyを発行します。
現在はuploadに必要な`Developer` roleを選び、`Key ID`と`Issuer ID`を控え、`.p8`を一度だけdownloadします。

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

GitHub variablesへ`APP_STORE_CONNECT_KEY_ID`と`APP_STORE_CONNECT_ISSUER_ID`を登録します。
GitHub secretへ`APP_STORE_CONNECT_PRIVATE_KEY_BASE64`を登録します。
不要になったkeyや漏えいしたkeyは同じ画面でrevokeします。

### 7. testflight Environment

GitHub repositoryの`Settings`から`testflight` Environmentを作成します。
配布元は`ios-v*` tagと許可した手動実行branchへ制限し、required reviewerを設定します。
現在のrequired reviewerは`hiiragi589`です。
本人によるリリースを許可するため`Prevent self-review`は無効、管理者による保護ルールのbypassは無効にします。

| 種類 | 名前 |
| --- | --- |
| Variable | `APPLE_TEAM_ID` |
| Variable | `IOS_BUNDLE_ID` |
| Variable | `APP_STORE_CONNECT_KEY_ID` |
| Variable | `APP_STORE_CONNECT_ISSUER_ID` |
| Variable | `SUPABASE_URL` |
| Variable | `SUPABASE_PUBLISHABLE_KEY` |
| Variable | `API_BASE_URL` |
| Secret | `IOS_DISTRIBUTION_CERTIFICATE_BASE64` |
| Secret | `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` |
| Secret | `IOS_PROVISIONING_PROFILE_BASE64` |
| Secret | `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` |

同名のrepositoryまたはorganization secretへ複製しません。
Environment secretを利用できない契約planでは、repository secretへ代替せず、承認付きの配布基盤を用意するまでworkflowを実行しません。

最初の内部TestFlightでは、3つのruntime Variableをstaging Projectと`https://api-staging.beyond-labo.com`へ向けます。
Supabase secret key、database password、Apple private keyをiOSのEnvironmentまたはarchiveへ渡しません。
詳しい値の取得元は[Supabase Auth・Database CI/CD](supabase-auth.md)を参照してください。

## TestFlightで確認する

workflow完了後、App Store Connectの対象アプリから`TestFlight`を開きます。

1. buildが`Processing`から利用可能になるまで待つ。
2. encryption complianceを確認する。
3. Internal Testing groupとtesterを登録する。
4. External Testingを使う場合はBeta App Reviewに必要な情報を登録する。

upload成功はApp Store公開を意味しません。

## アイマノのApp IDへ移行する

2026-11-07の承認により、表示名に加えてBundle IDも変更する。
iOSのBundle IDは`com.beyond-labo.aimano`、Apple DeveloperのApp IDのDescriptionは`アイマノ`とする。
App IDのapplication identifierは既存Teamのprefixと新Bundle IDから構成される。
App Store Connectの数値のApple IDは新しいアプリレコード作成時に自動採番される。
Xcode project／scheme／moduleと`HIMATCH_*`のbuild settingは既存のものを使う。

### 承認済みの移行条件

- 新Bundle IDは別アプリとして配布し、旧アプリの並行サポートを終了する。
- 端末内のログイン状態、未送信のSiri操作、削除状況確認情報、設定の自動移行は行わない。新アプリで再ログインし、通知許可を確認する。
- 既存のSupabase Project、Auth user、プロフィール、友達、暇、予定のサーバーデータを保持する。
- 新アプリから既存のSupabase user IDで再ログインできることを切替前に確認する。別user IDになった場合は切替を止め、既存データを再作成せずApple identity設定を調べる。

### AppleとGitHubを準備する

1. 本書の手順2と[Apple認証の設定手順](supabase-auth.md#aimanoへの識別子切替)に従い、既存Teamで`com.beyond-labo.aimano`のExplicit App IDを登録する。`Sign in with Apple`と`Push Notifications`を有効にする。
2. アカウント削除用Sign in with Apple KeyのPrimary App ID関連付けを確認する。新Primary App IDを使う場合は対応するKeyを作成し、既存Primaryにgroupingする場合はそのgroupとKeyの対応を確認する。
3. 新App IDと既存の有効なApple Distribution証明書を選び、`Aimano App Store`などのApp Store Connect profileを生成する。`application-identifier`、Sign in with Apple、`aps-environment=production`を確認する。本書の手順4に従いGitHub `testflight`の`IOS_PROVISIONING_PROFILE_BASE64`へ登録する。
4. App Store Connectの`Apps → ＋ → New App`から、名前`アイマノ`、日本語、新Bundle ID、一意なSKU（例 `aimano-ios`）でアプリレコードを作成する。Apple IDを控え、API keyの利用者が新アプリへアクセスできることを確認する。
5. 旧レコードが同じ名前を使用していて新規登録が拒否された場合は、Appleの名前変更手順に従って旧レコードの名前を変更する。公開状態によっては旧レコードの新バージョンと審査が必要となるため、新アプリの名称が保存できることを先に確認する。
6. GitHub `testflight` Environmentの`IOS_BUNDLE_ID`を`com.beyond-labo.aimano`へ設定する。SupabaseとBackendの接続先は既存の対象環境を使う。Backendの`APPLE_CLIENT_ID`と`APNS_TOPIC`、必要なKeyの設定は[認証切替手順](supabase-auth.md#aimanoへの識別子切替)に従う。
7. 既存アプリレコードのTestFlightグループは新レコードで作成し直し、テスターを招待する。旧buildへの配布を終了する。旧App IDとKeyの削除・失効は、処理中の削除受付と移行確認が完了した後に別途判断する。

[AppleのApp ID登録](https://developer.apple.com/help/account/identifiers/register-an-app-id/)、[アプリレコード作成](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)、[profile再生成](https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles)、[名前・Bundle ID・Apple IDの仕様](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)を参照する。

### 新識別子のビルドを配布する

1. 本変更を含むcommitを`main`へ反映し、本書の「TestFlightへ配布する」に従ってtagまたは現在の`main`への手動実行で配布する。失敗した旧commitの再実行は、そのcommitのコードをビルドする。
2. 生成IPAのInfo.plistで`CFBundleDisplayName=アイマノ`、`CFBundleIdentifier=com.beyond-labo.aimano`を確認する。
3. 新レコードのTestFlightからインストールし、ホーム画面、起動画面、新App IDでのAppleログイン、既存プロフィール・友達・予定の参照、Push許可と実通知を確認する。
4. 移行確認専用のアカウントで、Apple再認証とアカウント削除の完了・再送・状況照会を検証する。保持対象の利用者データを検証用に削除しない。
5. 実機で「アイマノで暇を登録」などSiri／ショートカットのフレーズを確認する。App Shortcutsは`\(.applicationName)`から表示名を参照する。旧アプリ向けショートカットは新アプリで作成し直す。

App Store Connectの名称保存、実環境の資格情報切替、TestFlight upload、実機検証、App Store審査と公開は、それぞれの実施証拠で確認する。

## 失敗時に復旧する

- 証明書またはprofileが期限切れの場合は、再発行して対応するEnvironment secretsを同時に更新する。
- API keyが漏えいした場合は、App Store Connectでrevokeし、新しいkeyとsecretへ置き換える。
- Bundle IDまたはTeam IDが一致しない場合は、workflowを再試行せず、profileとGitHub variablesの組合せを直す。
- runtime設定が不足している場合は、`testflight` Environmentの`SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`、`API_BASE_URL`を確認する。
- upload後に不具合が見つかった場合は、TestFlightのtester groupからbuildを外し、新しいbuild numberで修正版を配布する。
- App Store公開後の不具合はこのpipelineのrollback対象ではない。App Store Connectで販売停止またはphased releaseのpauseを判断する。

## 署名方式の選択

現在は単一アプリで外部依存を増やさないため、Appleのnative toolsとBase64化した証明書、profileを使います。
複数アプリ、extension、複数teamで署名資産を共有する段階では、[fastlane match](https://docs.fastlane.tools/actions/match/)への移行を再評価します。
