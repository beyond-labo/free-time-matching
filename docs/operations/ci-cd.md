# CI/CD

## 実装済みの経路

| Workflow | Trigger | 処理 | 秘密情報 |
|---|---|---|---|
| `Repository CI` | pull request、main push、手動 | JSON、workspace、文書リンク、iOS CI/CD 構成を検査 | 使用しない |
| `iOS CI` | すべての pull request、main push、手動 | Xcode 26.6 で signing preflight の単体テスト、Simulator build、XCTest | 使用しない |
| `iOS TestFlight` | `ios-vX.Y.Z` tag、手動 | 同じテスト後、署名、IPA export、App Store Connect upload | `testflight` Environment のみ |

iOS と Backend は独立してリリースします。
TestFlight への build upload までを自動化し、App Store の metadata 登録、審査提出、公開判断は自動化しません。
Backend OpenAPI、TCA、Mapper、UseCase は未実装のため、それらの生成差分やテストは現在の workflow に含めません。

CI は `macos-26` と `/Applications/Xcode_26.6.app` を固定します。
同 image に収録された Python 3.14 系と OpenSSL 3.6 系を signing preflight に使い、version を workflow log へ残します。
Apple は 2026 年時点の iOS build upload に Xcode 26 以降を要求し、GitHub の macOS 26 image は Xcode 26.6 を収録しています。
[Apple の upload 要件](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)、[GitHub runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)

## リリース方法

通常は検証済み commit に `ios-vX.Y.Z` 形式の annotated tag を作り、push します。

```sh
git tag -a ios-v0.1.0 -m "iOS 0.1.0"
git push origin ios-v0.1.0
```

緊急時や事前確認では GitHub の `Actions` → `iOS TestFlight` → `Run workflow` を開き、`marketing_version` に `X.Y.Z` を入力します。
build number は GitHub の run number と run attempt から生成するため、再実行でも別番号になります。

同一 ref の配布は `concurrency` で直列化します。
配布 job は `testflight` Environment の保護を通過してから、archive step だけで secrets を読みます。
archive の前に、証明書と秘密鍵、証明書と profile の対応、有効期限、Team/Bundle ID、API private key の形式と ES256 用 EC P-256 curve を検査し、一時 keychain と profile、API key を終了時に削除します。
成功した IPA は GitHub Artifact に 14 日だけ保持します。

## 初回セットアップで人が行う作業

リポジトリから Apple と GitHub の管理画面を変更することはありません。
以下は上から順に一度だけ実施します。

### 1. Apple Developer Program と契約

ページ: [Apple Developer Account](https://developer.apple.com/account/) の `Membership details`。

1. 有料の Apple Developer Program が有効であることを確認する。
2. `Team ID` を控える。後で GitHub variable `APPLE_TEAM_ID` に登録する。
3. Account Holder に未同意の契約が表示されていれば同意する。

### 2. Explicit Bundle ID

ページ: Apple Developer Account の `Certificates, Identifiers & Profiles` → `Identifiers` → `+` → `App IDs` → `App`。

1. `Description` に `Himatch` など管理しやすい名前を入力する。
2. `Bundle ID` は `Explicit` を選び、所有ドメインに基づく値を登録する。
3. 利用する capability だけを有効にする。現在の最小アプリには追加 capability は不要。
4. 値を GitHub variable `IOS_BUNDLE_ID` に登録する。

登録方法は [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id) を参照します。
リポジトリ内の `com.example.himatch` は署名不要 CI 専用の既定値で、配布時は `IOS_BUNDLE_ID` で上書きされます。

### 3. Apple Distribution 証明書

ページ: Apple Developer Account の `Certificates, Identifiers & Profiles` → `Certificates` → `+`。

この操作には Account Holder または Admin role が必要です。

1. Mac で Keychain Access を開き、`Keychain Access` → `Certificate Assistant` → `Request a Certificate From a Certificate Authority` を選ぶ。
2. `User Email Address` に Apple Developer Account のメールアドレス、`Common Name` に鍵を識別できる名前を入力し、`CA Email Address` は空欄のままにする。
3. `Saved to disk` を選び、CSR（`.certSigningRequest`）を保存する。
4. Apple Developer Account で `+` を押した直後の `Create a New Certificate` ページを開き、`Software` 欄の `Apple Distribution` を選んで `Continue` を押す。
   `iOS Distribution (App Store and Ad Hoc)` は Xcode 11 以前向けなので選ばない。
5. 次のページで `Choose File` を押し、手順 3 の `.certSigningRequest` を選んで `Continue` を押す。
6. 証明書の作成完了後に `Download` を押し、ダウンロードした `.cer` をダブルクリックして Keychain に取り込む。
7. Keychain Access の `My Certificates` で `Apple Distribution: <Team Name> (<Team ID>)` を開き、配下に秘密鍵が表示されることを確認する。
   秘密鍵がない場合は `.p12` を作成できないため、CSR を作成した Mac で export するか、この Mac で新しい CSR を作成して証明書を発行し直す。
8. 証明書と配下の秘密鍵を選び、`File` → `Export Items` から Personal Information Exchange（`.p12`）として export する。
9. `.p12` に強い password を設定し、password manager に保存する。
10. Terminal で `base64 -i /path/to/distribution.p12 | pbcopy` を実行する。

GitHub には Base64 文字列を `IOS_DISTRIBUTION_CERTIFICATE_BASE64`、password を `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` として登録します。
証明書と秘密鍵は本人性を示す機密資産です。
[Apple の証明書概要](https://developer.apple.com/help/account/certificates/certificates-overview)、[CSR の作成手順](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)、[Keychain item の export 手順](https://support.apple.com/guide/keychain-access/kyca35961/mac)

### 4. App Store provisioning profile

ページ: Apple Developer Account の `Certificates, Identifiers & Profiles` → `Profiles` → `+`。

1. Distribution の `App Store Connect` を選ぶ。
2. 手順 2 の Bundle ID と手順 3 の証明書を選ぶ。
3. `Himatch App Store` などの名前で生成し、`.mobileprovision` を download する。
4. Terminal で `base64 -i Himatch_App_Store.mobileprovision | pbcopy` を実行する。

GitHub secret `IOS_PROVISIONING_PROFILE_BASE64` に登録します。
配布スクリプトは profile 内の Team ID、application identifier、有効期限、選択した証明書との対応を GitHub variables と照合し、不一致なら archive 前に停止します。

### 5. App Store Connect のアプリレコード

ページ: [App Store Connect](https://appstoreconnect.apple.com/) の `Apps` → `+` → `New App`。

1. Platform に iOS、名前、primary language、手順 2 の Bundle ID、任意の一意な SKU を入力する。
2. 作成後、`App Information` で Bundle ID が正しいことを確認する。

binary upload より先にアプリレコードが必要です。[Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)

### 6. App Store Connect API key

ページ: App Store Connect の `Users and Access` → `Integrations` → `App Store Connect API` → `Team Keys`。

1. API access が未有効なら Account Holder が `Request Access` を完了する。
2. Account Holder または Admin が `Generate API Key` を選ぶ。
3. 名前を `GitHub Actions TestFlight` とし、最初は upload に必要な最小の `Developer` role を選ぶ。
4. `Key ID` と `Issuer ID` を控える。
5. `.p8` を一度だけ download し、password manager に保存する。
6. Terminal で `base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy` を実行する。

GitHub variables に `APP_STORE_CONNECT_KEY_ID` と `APP_STORE_CONNECT_ISSUER_ID`、secret に `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` を登録します。
Team Key はアプリ単位に制限されないため Admin role を避け、漏えい時は同じページで直ちに revoke します。
[App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)

### 7. GitHub Environment、variables、secrets

ページ: GitHub repository の `Settings` → `Environments` → `New environment`。

1. `testflight` という名前で Environment を作る。
2. `Deployment branches and tags` を設定できる場合は `ios-v*` tag に制限する。手動実行も使う場合は repository policy に合わせて対象 branch を許可する。
3. 利用プランで可能なら `Required reviewers` を設定し、`Prevent self-review` を有効にする。
4. 同じ Environment の `Environment variables` と `Environment secrets` に下表を登録する。

| 種類 | 名前 | 値 |
|---|---|---|
| Variable | `APPLE_TEAM_ID` | Membership details の 10 文字 Team ID |
| Variable | `IOS_BUNDLE_ID` | 登録した Explicit Bundle ID |
| Variable | `APP_STORE_CONNECT_KEY_ID` | Team Key の Key ID |
| Variable | `APP_STORE_CONNECT_ISSUER_ID` | Team Key の Issuer ID |
| Secret | `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | `.p12` の Base64 |
| Secret | `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | `.p12` export password |
| Secret | `IOS_PROVISIONING_PROFILE_BASE64` | `.mobileprovision` の Base64 |
| Secret | `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` | `.p8` の Base64 |

Environment secrets と required reviewer の利用可否は repository visibility と GitHub plan に依存します。
この workflow は `testflight` Environment だけを資格情報の正本にします。
repository または organization の secrets/variables に同名の値を作らず、既存の同名項目がないことをそれぞれの `Settings` → `Secrets and variables` → `Actions` で確認してください。
private repository の契約プランで Environment secrets を利用できない場合は repository secrets へ代替せず、利用可能なプランまたは別の承認付き配布基盤を用意するまで TestFlight workflow を実行しません。
[GitHub Environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)

### 8. main の Ruleset

ページ: GitHub repository の `Settings` → `Rules` → `Rulesets`。

1. main を対象とする branch ruleset を作成する。
2. pull request を必須にする。
3. status checks に `Repository validation` と `iOS build and test` を追加する。
4. workflow と `scripts/ios/` の変更に code review を要求する。

`iOS TestFlight` は配布操作であり、merge の required check にはしません。
`iOS CI` は path filter を使わずすべての pull request で起動するため、非 iOS 変更でも required check が Pending のまま残りません。
まず pull request で各 CI の成功と意図した失敗を確認してから required check にします。

### 9. TestFlight の確認

ページ: App Store Connect の `Apps` → 対象アプリ → `TestFlight`。

1. GitHub の `iOS TestFlight` workflow 完了後、build が `Processing` から利用可能になるまで待つ。
2. encryption compliance の状態を確認する。現在は non-exempt encryption を使わない設定だが、通信・暗号機能を追加した際は申告を再評価する。
3. Internal Testing group と tester を登録し、build を割り当てる。
4. External Testing を使う場合は What to Test、連絡先、review 情報を入力し、Beta App Review を受ける。

upload の成功は Apple 側の processing 完了や App Store 公開を意味しません。
[TestFlight](https://developer.apple.com/testflight/)

## 更新・失敗時の復旧

- **証明書または profile が期限切れ**: Apple Developer で再発行し、対応する Environment secrets を同時に更新する。古い証明書を revoke する前に他アプリへの影響を確認する。
- **API key が漏えい・紛失**: App Store Connect の `Users and Access` → `Integrations` で revoke し、新しい key/ID/secret に置き換える。
- **Bundle ID または Team ID 不一致**: workflow を再試行せず、profile と GitHub variables の組合せを修正する。
- **upload 後の build 不具合**: TestFlight で当該 build を tester group から外す。修正版は同じ marketing version と新しい build number で再配布する。upload 済み binary は上書きしない。
- **App Store 公開後の不具合**: この pipeline は公開ロールバックを所有しない。App Store Connect で販売停止または phased release の pause を判断し、修正版を新しい build として配布する。

資格情報をログや issue に貼らず、GitHub の secret scan だけに依存せず定期的に不要 key を削除・ローテーションします。

## 設計上の選択

参考にした Qiita 記事の P12/profile Base64 方式は、単一アプリで外部依存を増やさない点を採用しました。
一方、記事は Flutter、`macos-latest`、Apple ID の app-specific password、main push 自動配布、固定 keychain password、CI 内の `sed` による署名設定変更を前提にしているため、この repository では使いません。

fastlane `match` は複数アプリ、extension、複数チームで署名資産を共有する段階では有力です。
現時点では Ruby/fastlane、暗号化した別 repository、deploy key、`MATCH_PASSWORD` が追加されるため、Apple の native tools だけで構成します。
target が増えたときは [fastlane match](https://docs.fastlane.tools/actions/match/) への移行を再評価します。

## 変更履歴

### 2026-09-17

Apple Developer Account の現行 `Create a New Certificate` 画面に合わせ、`Apple Distribution` の選択、CSR の upload、証明書の download、Keychain での秘密鍵確認と `.p12` export を画面遷移順に更新しました。

### 2026-09-16

Qiita 記事と Apple/GitHub の一次資料を照合し、Xcode 26.6、App Store Connect API key、GitHub Environment、一時 keychain、TestFlight までの CI/CD を実装しました。
独立レビューを受け、required check が常に作成される trigger、Environment 限定、署名素材の対応・期限・形式を archive 前に検証する経路へ更新しました。
