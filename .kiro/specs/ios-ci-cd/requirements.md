---
type: Requirements
title: "iOS CI/CD 要件"
description: "iOS アプリを継続的に検証し、承認された実行から TestFlight へ安全に配布する要件"
status: stable
sources:
  - id: user-request
    resource: https://qiita.com/k-kayaba/items/e7da8828eb8fb085ec4d
    title: GitHub ActionsでiOSアプリを自動ビルド＆App Storeへ自動アップロードする完全ガイド
kiro:
  depends_on:
    - docs/operations/ios-ci-cd.md
    - docs/architecture/technology.md
---

# Requirements Document

## Introduction

GitHub Actions 上で iOS アプリのビルドとテストを再現可能にし、配布用資格情報を pull request から隔離したうえで、明示的なリリース操作から同じ検証済みソースを TestFlight へアップロードする。

## Boundary Context

- **In scope**: 最小の実行可能 iOS ターゲット、Simulator 向け CI、署名付き archive、TestFlight アップロード、資格情報の境界、運用手順。
- **Out of scope**: 製品機能、TCA 導入、Backend 契約生成、App Store 審査提出・公開、Apple/GitHub 上の外部設定の代行。
- **Adjacent expectations**: Backend と iOS は独立リリースとし、将来の OpenAPI 生成検証は公開契約が実装された時点で追加する。

## Requirements

### Requirement 1: 継続的な iOS 検証

**Objective:** As a 開発者, I want iOS の変更を pull request と main で自動検証したい, so that 壊れた変更を配布前に検出できる

#### Acceptance Criteria

1. When iOS のソース、プロジェクト、検証スクリプトまたは iOS CI 定義が変更された, the iOS CI shall 固定した Xcode で共有 scheme の署名なし Simulator ビルドとテストを実行する
2. If ビルドまたはテストが失敗した, the iOS CI shall 非ゼロ終了して後続の配布を許可しない
3. The iOS CI shall pull request で Apple の配布資格情報を参照しない
4. The repository verification shall iOS CI/CD に必要な追跡対象ファイルと非機密設定の欠落を検出する
5. The iOS tests shall Swift Testing を使用し、iOS のテストコードで XCTest を import または XCTestCase を継承しない

### Requirement 2: TestFlight 配布

**Objective:** As a リリース担当者, I want 明示的に指定したバージョンを TestFlight へ配布したい, so that ベータ版を再現可能かつ監査可能に提供できる

#### Acceptance Criteria

1. When `ios-vX.Y.Z` 形式のタグが push された、または手動実行でバージョンが指定された, the iOS CD shall CI と同じテストを通過した後だけ archive と upload を実行する
2. While TestFlight 配布ジョブが実行されている, the iOS CD shall GitHub の `testflight` Environment に保存された値だけから署名・アップロード資格情報を取得する
3. If 必須値、証明書、provisioning profile、Bundle ID、Team ID の対応が不正である, the iOS CD shall archive 前に失敗する
4. When archive が成功した, the iOS CD shall 一意な build number を設定し、同じジョブで生成した IPA を App Store Connect へ API key 認証でアップロードする
5. When upload が成功した, the iOS CD shall 配布した IPA を短期保持の GitHub Artifact として識別可能に保存する

### Requirement 3: 秘密情報と運用境界

**Objective:** As a リポジトリ管理者, I want 署名素材と配布権限を最小範囲で管理したい, so that pull request やコミットから漏えい・誤配布しない

#### Acceptance Criteria

1. The repository shall `.p8`、`.p12`、`.mobileprovision`、`.ipa`、`.xcarchive` を追跡対象から除外する
2. While 配布ジョブが資格情報を利用している, the iOS CD shall 一時 keychain と一時ファイルに展開し、成功・失敗にかかわらず削除する
3. The iOS CD shall GitHub token を read-only 権限で実行し、同一 ref の重複配布を直列化する
4. The operations documentation shall Apple Developer、App Store Connect、GitHub の各画面で人が設定する項目、登録先の名前、確認方法、失効時の復旧を記載する

### Requirement 4: 現行文書との整合

**Objective:** As a 保守担当者, I want 実装と文書が同じ現在状態を示してほしい, so that 未実装事項と利用可能な経路を誤認しない

#### Acceptance Criteria

1. When iOS CI/CD が追加された, the project documentation shall 実在する Xcode、scheme、検証コマンド、workflow、配布範囲を記載する
2. Where Backend OpenAPI と TCA が未実装である, the project documentation shall それらの検証を実装済みと表現しない
3. The project documentation shall App Store 審査提出と公開が自動化範囲外であることを明記する
