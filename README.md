# ひまっち（仮）

iOS、Android、Backend を独立して開発、リリースするモノレポです。
Backend は公開 OpenAPI を所有し、各モバイルアプリは Clean Architecture を採用する方針です。iOS は TCA、Android は Jetpack Compose をUIに使います。

[ドキュメント一覧](docs/README.md)に、製品範囲、技術方針、将来の配置、開発と運用の手順をまとめています。

## 現在の状態

iOS には SwiftUI/TCA アプリ、Swift Testing、Xcode プロジェクトがあります。
GitHub Actions は pull request の iOS build/test と、明示的な tag または手動実行による TestFlight upload を提供します。
Android には最小Composeアプリ、JVM単体テスト、Gradleプロジェクトがあり、pull requestのlint/test/buildと、明示的なtagまたは手動実行によるGoogle Play internal track配布を提供します。
Backendには最小Hono Worker、`GET /healthz`、Workers Runtimeテスト、Cloudflare向けCI/CDがあります。
Terraformにはstagingとproductionの環境別rootとR2 remote state境界がありますが、実Cloudflare resourceはまだ宣言していません。
OpenAPI、認証、DB、契約生成ツールは未実装です。iOS 製品機能は Backend 未接続のプロトタイプ実装です。
未実装の層やツールのための予約ファイルは作成しません。

## 検証

Node.js が利用できる環境で実行します。
外部依存のインストールは不要です。

```sh
node scripts/verify.mjs
```

JSON、workspace登録、文書のローカルリンク、Backend Worker、Terraform、iOS/Android/Backend CI/CD構成を検証します。

iOS の build/test には Xcode 26.6 と iPhone Simulator が必要です。

```sh
bash scripts/ios/test.sh
```

Androidのbuild/testにはJDK 21、Android SDK Platform 37、Build Tools 36.0.0が必要です。

```sh
bash scripts/android/test.sh
```

配布設定は[CI/CDの索引](docs/operations/ci-cd.md)から、[Backend](docs/operations/backend-ci-cd.md)、[iOS](docs/operations/ios-ci-cd.md)、[Android](docs/operations/android-ci-cd.md)の手順を参照してください。
