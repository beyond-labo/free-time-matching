---
type: Requirements
title: "Android CI/CD 要件"
description: "Androidアプリを継続的に検証し、承認された実行からGoogle Play internal trackへ安全に配布する要件"
status: stable
sources:
  - id: user-request
    resource: user-request://2026-09-18/android-and-cicd
    title: AndroidアプリとCI/CDの整備依頼
kiro:
  depends_on:
    - docs/operations/android-ci-cd.md
    - docs/architecture/technology.md
---

# Requirements Document

## Introduction

GitHub Actions上でAndroidアプリのビルド、lint、単体テストを再現可能にし、配布資格情報をpull requestから隔離したうえで、明示的なリリース操作から同じ検証済みソースをGoogle Play internal trackへ配布する。

## Boundary Context

- **In scope**: 最小の実行可能Androidアプリ、CI、署名済みAndroid App Bundle、Google Play internal track配布、資格情報境界、運用手順。
- **Out of scope**: 製品機能、外部API接続、端末UIテスト、production公開、ストア掲載情報の自動更新、Google/GitHub上の外部設定代行。
- **Adjacent expectations**: Backend、iOS、Androidは独立リリースとし、将来のOpenAPI生成検証は公開契約の実装後に追加する。

## Requirements

### Requirement 1: 継続的なAndroid検証

**Objective:** As a 開発者, I want Androidの変更をpull requestとmainで自動検証したい, so that 壊れた変更を配布前に検出できる

#### Acceptance Criteria

1. When pull requestまたはmainへのpushが発生した, the Android CI shall 固定したJDK 21、Gradle、Android SDKでlint、単体テスト、debug buildを実行する
2. If いずれかの検証が失敗した, the Android CI shall 非ゼロ終了して後続の配布を許可しない
3. The Android CI shall pull requestで署名鍵またはGoogle Play資格情報を参照しない
4. The repository verification shall Android CI/CDに必要な追跡対象ファイルと非機密設定の欠落を検出する

### Requirement 2: Google Play internal track配布

**Objective:** As a リリース担当者, I want 明示的に指定したバージョンをinternal trackへ配布したい, so that テスターへ再現可能かつ監査可能に提供できる

#### Acceptance Criteria

1. When `android-vX.Y.Z`形式のtagがpushされた、または手動実行でversionが指定された, the Android CD shall CIと同じ検証を通過した後だけ署名とuploadを実行する
2. While 配布jobが実行されている, the Android CD shall GitHubの`play-internal` Environmentに保存された値だけから署名・upload資格情報を取得する
3. If 必須値、keystore、alias、password、package nameが不正である, the Android CD shall upload前に失敗する
4. When buildが成功した, the Android CD shall 一意なversionCodeを設定し、同じjobで生成した署名済みAABをGoogle Play internal trackへcommitする
5. When uploadが成功した, the Android CD shall 配布したAABを短期保持のGitHub Artifactとして保存する

### Requirement 3: 秘密情報と運用境界

**Objective:** As a リポジトリ管理者, I want 署名素材と配布権限を最小範囲で管理したい, so that pull requestやcommitから漏えい・誤配布しない

#### Acceptance Criteria

1. The repository shall keystore、service account key、APK、AABを追跡対象から除外する
2. While 配布jobが資格情報を利用している, the Android CD shall 一時ファイルに展開し、成功・失敗にかかわらず削除する
3. The Android CD shall GitHub tokenをread-only権限で実行し、同一refの重複配布を直列化する
4. The operations documentation shall Play Console、Google Cloud、GitHubで人が設定する項目、登録名、確認方法、失効時の復旧を記載する

### Requirement 4: 現行文書との整合

**Objective:** As a 保守担当者, I want 実装と文書が同じ現在状態を示してほしい, so that 未実装事項と利用可能な経路を誤認しない

#### Acceptance Criteria

1. When Android CI/CDが追加された, the project documentation shall 実在するGradle構成、検証コマンド、workflow、配布範囲を記載する
2. Where Androidの製品機能とOpenAPI clientが未実装である, the project documentation shall それらを実装済みと表現しない
3. The project documentation shall production公開とストア掲載情報の自動化が範囲外であることを明記する
