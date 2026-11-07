# iOS

SwiftUI/TCA アプリ、Swift Testing、shared scheme を Xcode 26.6 で管理します。iOS テストでは XCTest を使用しません。
最低 iOS は 17.0、scheme と target は `Himatch`、テスト target は `HimatchTests` です。
Bundle ID は `com.beyond-labo.aimano` で、TestFlight archive では GitHub Environment の `IOS_BUNDLE_ID` に同じ値を指定します。

```sh
bash scripts/ios/test.sh
```

スクリプトは利用可能な iPhone Simulator を自動選択します。
特定の destination を使う場合は `IOS_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'` を指定します。

TCAを用い、認証・プロフィール・友達関係・暇時間・招待と回答・削除をBackend APIへ接続します。第一段階はホストなしの自動提案と双方OKによる予定確定へ移行しました。全体と友達別の許可は初期オフです。参加OK時は名前と回答を先に共有するか任意に選べます。最初の実環境検証先はstagingです。

自動提案・実予定・取消・定型通報・ブロックはAutomaticSchedulingの実Backendへ接続し、Push拒否でも受信箱から操作できます。APNsはDebugのsandboxとReleaseのproductionをビルド設定で区別し、配布時はPush capability付きの署名profileが必要です。[仕様](../../.kiro/specs/automatic-friend-scheduling/requirements.md) と [運用・検証手順](../../docs/operations/automatic-scheduling.md) を参照してください。実機・実配信・TestFlightの証拠はローカル試験と分けて扱います。
署名、TestFlight、Apple/GitHubの初回設定は[iOS CI/CD運用手順](../../docs/operations/ios-ci-cd.md)を参照してください。
