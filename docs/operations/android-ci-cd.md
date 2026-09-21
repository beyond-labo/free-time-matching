# Android CI/CDとGoogle Play

`Android CI`はすべてのpull request、`main` push、手動実行でlint、JVM単体テスト、debug buildを実行します。
`Android Google Play`は`android-v*` tagまたは手動実行から、署名済みAABをGoogle Play internal trackへuploadします。

## Google Playへ配布する

運用上は、検証済みcommitへ`android-vX.Y.Z`形式のannotated tagを付けます。

```sh
git tag -a android-v0.1.0 -m "Android 0.1.0"
git push origin android-v0.1.0
```

workflowが機械的に検査するのは`android-v*`というtag名です。
annotated tagであることと`main`への包含はworkflow内では検査しないため、tag rulesetとリリース担当者の手順で保証します。

手動実行ではGitHubの`Actions`から`Android Google Play`を選び、`version_name`へ`X.Y.Z`を入力します。
versionCodeは`run_number * 100 + run_attempt`から生成するため、再実行でも増加します。

配布jobは`play-internal` Environmentの保護を通過した後だけsecretsを読みます。
一時keystoreとservice account JSONを作成し、署名済みAABを生成してGoogle Play Developer APIからinternal trackへ反映します。
一時ファイルは終了時に削除し、成功したAABはGitHub Artifactへ14日だけ保持します。

## 初回セットアップ

### 1. Google Playのアプリ

[Google Play Console](https://play.google.com/console/)の`All apps`からアプリを作成します。
developer accountの本人確認、契約、支払い情報を先に完了します。

一意なpackage nameを決め、GitHub Environment variable `ANDROID_PACKAGE_NAME`へ登録します。
repository内の`com.example.himatch`は署名不要CI用の既定値です。
[Google Playのアプリ作成手順](https://support.google.com/googleplay/android-developer/answer/9859152)も確認してください。

### 2. upload key

JDK 21の`keytool`でPlay App Signing用のupload keyを作成します。

```sh
keytool -genkeypair -v \
  -keystore himatch-upload.jks \
  -alias himatch-upload \
  -keyalg RSA -keysize 4096 -validity 10000
```

keystore password、alias、key passwordをpassword managerへ保存します。
keystoreをBase64へ変換し、GitHub Environment secretへ登録します。

```sh
# macOS
base64 -i himatch-upload.jks | pbcopy

# Linux
base64 -w 0 himatch-upload.jks
```

| 種類 | 名前 |
| --- | --- |
| Secret | `ANDROID_KEYSTORE_BASE64` |
| Secret | `ANDROID_KEYSTORE_PASSWORD` |
| Secret | `ANDROID_KEY_ALIAS` |
| Secret | `ANDROID_KEY_PASSWORD` |

private keyをrepository、issue、workflow logへ保存しません。
[Play App Signing](https://developer.android.com/studio/publish/app-signing)を参照してください。

### 3. 初回internal release

Google Play Consoleの`Internal testing`から最初のreleaseを作成します。
Play App Signingの規約に同意し、Googleが生成するapp signing keyを使用します。

`ANDROID_PACKAGE_NAME`と同じapplication IDで署名したAABをuploadし、internal trackを初期化します。
最初のAPI uploadが拒否される場合は、この手順をConsoleで完了してからworkflowを実行します。
[internal releaseの作成手順](https://support.google.com/googleplay/android-developer/answer/9859348)も確認してください。

### 4. Google Play Developer API

専用Google Cloud projectで`Google Play Android Developer API`を有効化します。
配布専用service accountを作成し、JSON keyを一度だけdownloadします。

Play Consoleの`Users and permissions`でservice accountを招待し、対象アプリのtesting trackへreleaseする権限だけを付与します。
productionやfinancial権限は付与しません。

service account JSONをBase64へ変換し、`ANDROID_PLAY_SERVICE_ACCOUNT_JSON_BASE64`へ登録します。

```sh
# macOS
base64 -i service-account.json | pbcopy

# Linux
base64 -w 0 service-account.json
```

### 5. play-internal Environment

GitHub repositoryの`Settings`から`play-internal` Environmentを作成します。
配布元は`android-v*` tagと許可した手動実行branchへ制限し、required reviewerを設定します。
現在のrequired reviewerは`hiiragi589`です。
本人によるリリースを許可するため`Prevent self-review`は無効、管理者による保護ルールのbypassは無効にします。

| 種類 | 名前 |
| --- | --- |
| Variable | `ANDROID_PACKAGE_NAME` |
| Secret | `ANDROID_KEYSTORE_BASE64` |
| Secret | `ANDROID_KEYSTORE_PASSWORD` |
| Secret | `ANDROID_KEY_ALIAS` |
| Secret | `ANDROID_KEY_PASSWORD` |
| Secret | `ANDROID_PLAY_SERVICE_ACCOUNT_JSON_BASE64` |

同名のrepositoryまたはorganization secretへ複製しません。
`.github/workflows/`と`scripts/android/`の変更にはcode reviewを要求します。
Environment secretを利用できない契約planでは、repository secretへ代替せず、承認付きの配布基盤を用意するまでworkflowを実行しません。

## internal trackで確認する

workflow完了後、Google Play Consoleの`Internal testing`でversionCodeとrelease statusを確認します。
testerはopt-in linkから参加し、Google Play経由でinstallします。
internal testingはproduction公開ではなく、検索からは見つかりません。
[internal testingの設定手順](https://support.google.com/googleplay/android-developer/answer/9845334)も確認してください。

## 失敗時に復旧する

- upload keyを紛失または漏えいした場合は、Play Consoleの`App integrity`からupload key resetを申請する。
- service account keyが漏えいした場合は、Google Cloud IAMでkeyを無効化し、新しいEnvironment secretへ置き換える。
- package nameが一致しない場合は、workflowを再試行せず、Play Consoleのアプリと`ANDROID_PACKAGE_NAME`の組合せを直す。
- internal buildに不具合がある場合は、新しいversionCodeで修正版をinternal trackへ配布する。

Google管理のapp signing keyはupload keyとは別です。
このpipelineはGoogle Play production releaseのrollbackを所有しません。
