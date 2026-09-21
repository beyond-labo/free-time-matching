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

workflowが機械的に検査するのは`ios-v*`というtag名です。
annotated tagであることと`main`への包含はworkflow内では検査しないため、tag rulesetとリリース担当者の手順で保証します。

手動実行ではGitHubの`Actions`から`iOS TestFlight`を選び、`marketing_version`へ`X.Y.Z`を入力します。
build numberはGitHubのrun numberとrun attemptから生成するため、再実行でも別番号になります。

配布jobは`testflight` Environmentの保護を通過してからsecretsを読みます。
archive前に、証明書と秘密鍵、証明書とprofile、有効期限、Team ID、Bundle ID、API private keyの形式を検査します。
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

repository内の`com.example.himatch`は署名不要CI用の既定値です。
TestFlight archiveでは`IOS_BUNDLE_ID`で上書きします。

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
base64 -i Himatch_App_Store.mobileprovision | pbcopy
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
| Secret | `IOS_DISTRIBUTION_CERTIFICATE_BASE64` |
| Secret | `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` |
| Secret | `IOS_PROVISIONING_PROFILE_BASE64` |
| Secret | `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` |

同名のrepositoryまたはorganization secretへ複製しません。
Environment secretを利用できない契約planでは、repository secretへ代替せず、承認付きの配布基盤を用意するまでworkflowを実行しません。

## TestFlightで確認する

workflow完了後、App Store Connectの対象アプリから`TestFlight`を開きます。

1. buildが`Processing`から利用可能になるまで待つ。
2. encryption complianceを確認する。
3. Internal Testing groupとtesterを登録する。
4. External Testingを使う場合はBeta App Reviewに必要な情報を登録する。

upload成功はApp Store公開を意味しません。

## 失敗時に復旧する

- 証明書またはprofileが期限切れの場合は、再発行して対応するEnvironment secretsを同時に更新する。
- API keyが漏えいした場合は、App Store Connectでrevokeし、新しいkeyとsecretへ置き換える。
- Bundle IDまたはTeam IDが一致しない場合は、workflowを再試行せず、profileとGitHub variablesの組合せを直す。
- upload後に不具合が見つかった場合は、TestFlightのtester groupからbuildを外し、新しいbuild numberで修正版を配布する。
- App Store公開後の不具合はこのpipelineのrollback対象ではない。App Store Connectで販売停止またはphased releaseのpauseを判断する。

## 署名方式の選択

現在は単一アプリで外部依存を増やさないため、Appleのnative toolsとBase64化した証明書、profileを使います。
複数アプリ、extension、複数teamで署名資産を共有する段階では、[fastlane match](https://docs.fastlane.tools/actions/match/)への移行を再評価します。
