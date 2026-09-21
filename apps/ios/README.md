# iOS

SwiftUI/TCA アプリ、Swift Testing、shared scheme を Xcode 26.6 で管理します。iOS テストでは XCTest を使用しません。
最低 iOS は 17.0、scheme と target は `Himatch`、テスト target は `HimatchTests` です。
署名不要 CI の既定 Bundle ID は `com.example.himatch` で、TestFlight archive では GitHub Environment の `IOS_BUNDLE_ID` を指定します。

```sh
bash scripts/ios/test.sh
```

スクリプトは利用可能な iPhone Simulator を自動選択します。
特定の destination を使う場合は `IOS_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'` を指定します。

現在の画面は初版の主要経路を確認するプロトタイプです。TCA を導入済みですが、Backend API client と本番認証・認可はまだ導入していません。
署名、TestFlight、Apple/GitHubの初回設定は[iOS CI/CD運用手順](../../docs/operations/ios-ci-cd.md)を参照してください。
