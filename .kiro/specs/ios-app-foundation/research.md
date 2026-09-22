---
type: Research
title: "iOS アプリ基盤調査"
description: "現行 iOS 構造、TCA 互換性、Apple 認証境界の調査"
status: stable
sources:
  - id: tca-1-26-1-package
    resource: https://raw.githubusercontent.com/pointfreeco/swift-composable-architecture/1.26.1/Package.swift
    title: TCA 1.26.1 Package.swift
  - id: tca-1-26-2-package
    resource: https://raw.githubusercontent.com/pointfreeco/swift-composable-architecture/1.26.2/Package.swift
    title: TCA 1.26.2 Package.swift
  - id: apple-sign-in-button
    resource: https://developer.apple.com/documentation/authenticationservices/signinwithapplebutton
    title: SignInWithAppleButton
  - id: supabase-apple-native
    resource: https://supabase.com/docs/reference/swift/auth-signinwithidtoken
    title: Supabase Swift signInWithIdToken
kiro:
  depends_on:
    - apps/ios/Himatch.xcodeproj/project.pbxproj
    - docs/architecture/ios-architecture.md
    - docs/architecture/technology.md
---

# 調査と設計判断

## Summary

- **Feature**: `ios-app-foundation`
- **Discovery Scope**: Complex Integration
- **Key Findings**:
  - 現行 project は Swift ファイルを手動列挙し、TCA と entitlements は未導入。
  - Xcode 26.6 は Swift 6.3.3。TCA 1.26.2 は Swift tools 6.4 を要求する。
  - Apple identity tokenとraw nonceをsupabase-swiftへ渡し、Supabase sessionを発行・保存する。

## Research Log

### TCA の互換バージョン

- **Sources Consulted**: TCA 1.26.1 / 1.26.2 の公式 tag `Package.swift`。
- **Findings**: 1.26.1 は tools 6.1、1.26.2 は tools 6.4。現行 Swift 6.3 では 1.26.2 を解決できない。
- **Implications**: 1.26.1 を正確に固定し、Xcode 更新時に再評価する。

### Xcode project

- **Findings**: `PBXGroup` と Sources phase が個別ファイルを列挙し、大量追加に membership 漏れのリスクがある。
- **Implications**: Xcode 26 の filesystem-synchronized group へ移行し、build/test で構造移行を検証する。

### Package macro trust

- **Findings**: TCA と推移依存が提供する Swift macro は、対話操作のない `xcodebuild` では承認待ちになり得る。
- **Implications**: `Package.resolved` の固定版だけを使う `-onlyUsePackageVersionsFromResolvedFile` と、確認済み依存へ限定した `-skipMacroValidation` を CI・archive 経路で併用する。依存更新時は差分確認と再ビルドを必要とする。

### Sign in with Apple

- **Findings**: SwiftUI 標準 `SignInWithAppleButton` は request と completion を提供するが、credential のサービス認証は別責務。
- **Implications**: Presentation で Apple 型を終端し、Application Port へ最小入力を渡す。

### Supabase native Apple認証とsession

- **Sources Consulted**: SupabaseのApple provider guide、Swift `signInWithIdToken`、auth state change資料。
- **Findings**: native認証はApple requestへnonce hashを設定し、Supabaseへidentity tokenとraw nonceを渡す。SDKはsessionを永続化し、起動時復元とtoken refresh eventを提供する。
- **Implications**: 旧authorization code中心の認証契約をidentity token＋nonceへ置換し、authorization codeは削除時のBackend Apple revokeにだけ使う。

## Design Decisions

### Decision: TCA 1.26.1 を固定する

- **Alternatives Considered**: 1.26.2、TCA 非導入、Xcode 更新。
- **Selected Approach**: 1.26.1 を exact pin する。
- **Rationale**: 既存 Xcode 26.6 と CI/CD を維持しながら最新の互換リリースを使える。
- **Trade-offs**: 最新 patch の修正は取り込めず、Swift 6.4 移行時に再評価が必要。

### Decision: Prototype Adapter を本番認証から区別する

- **Selected Approach**: DEBUG に明示したデモ導線を設け、Apple 認証の失敗を成功へフォールバックしない。
- **Rationale**: Backend 不在でも UI を検証しつつ、認証完了を偽らない。

## Risks & Mitigations

- filesystem group 移行で target membership が変わる — clean build/test と archive 設定検査を行う。
- Sign in with Apple capability と profile の不一致 — entitlement 追加後の外部設定を runbook へ記録する。
- TCA 初回解決で CI 時間が増える — Package.resolved を追跡し、CI timeout を実測で確認する。

## Change Log

### 2026-09-21

ユーザーのiOS戦略決定を受け、テスト記述をSwift Testingへ統一した。TCAのmacroを非対話CIで使うため、固定済み`Package.resolved`とmacro validation省略をセットにし、依存更新時の再レビューを必須とした。

最新mainのPrototype実装を確認し、Supabase native Apple認証、session復元、Production Compositionを現行設計へ変更した。旧Backend未実装判断は失効した。

独立レビューで401/403時にsessionを保持する問題とSDKエラー露出を確認し、認証拒否時はsession・画面snapshotを破棄する状態遷移、利用者向けエラー正規化、ReleaseのHTTPS限定へ修正した。

- 2026-09-20: ユーザーの初版依頼、現行コード、TCA 公式 tag、Apple 公式 API を根拠に新規作成。
