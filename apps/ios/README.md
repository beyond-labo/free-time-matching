# iOS

SwiftUI/TCA アプリ、Swift Testing、shared scheme を Xcode 26.6 で管理します。iOS テストでは XCTest を使用しません。
最低 iOS は 17.0、scheme と target は `Himatch`、テスト target は `HimatchTests` です。
署名不要 CI の既定 Bundle ID は `com.example.himatch` で、TestFlight archive では GitHub Environment の `IOS_BUNDLE_ID` を指定します。

```sh
bash scripts/ios/test.sh
```

スクリプトは利用可能な iPhone Simulator を自動選択します。
特定の destination を使う場合は `IOS_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'` を指定します。

現在の画面は初版の主要経路を確認するアプリです。TCAを導入し、認証・プロフィール・友達関係・削除はBackend APIへ接続します。最初の内部TestFlightはstaging設定を使い、暇・募集はDEBUG Prototypeで検証します。
署名、TestFlight、Apple/GitHubの初回設定は[iOS CI/CD運用手順](../../docs/operations/ios-ci-cd.md)を参照してください。
