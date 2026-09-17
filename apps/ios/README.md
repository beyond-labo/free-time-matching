# iOS

SwiftUI の最小アプリ、XCTest、shared scheme を Xcode 26.6 で管理します。
最低 iOS は 17.0、scheme と target は `Himatch`、テスト target は `HimatchTests` です。
署名不要 CI の既定 Bundle ID は `com.example.himatch` で、TestFlight archive では GitHub Environment の `IOS_BUNDLE_ID` を指定します。

```sh
bash scripts/ios/test.sh
```

スクリプトは利用可能な iPhone Simulator を自動選択します。
特定の destination を使う場合は `IOS_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'` を指定します。

現在の画面と AppIcon は CI/CD の実経路を成立させる暫定成果物です。
製品機能、TCA、Backend API client はまだ導入していません。
署名、TestFlight、Apple/GitHub の初回設定は [CI/CD 手順](../../docs/operations/ci-cd.md)を参照してください。
