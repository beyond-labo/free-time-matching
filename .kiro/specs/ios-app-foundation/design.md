---
type: Design
title: "iOS アプリ基盤設計"
description: "TCA と Clean Architecture による起動・認証・プロフィール・3タブの設計"
status: stable
sources:
  - id: ios-app-foundation-research
    resource: ./research.md
    title: iOS アプリ基盤の調査
kiro:
  depends_on:
    - .kiro/specs/ios-app-foundation/requirements.md
    - docs/architecture/ios-architecture.md
    - docs/architecture/technology.md
---

# Design Document

## Overview

TCA の `AppFeature` と `AppView` に、起動時セッション復元、native Apple認証、プロフィールAPIを接続する。Applicationは認証・プロフィールのPortを所有し、CompositionがSupabase/Auth API AdapterまたはDEBUG Prototype Adapterを明示的に注入する。

### Goals

- 登録前説明から3タブまでを状態として一貫して表す。
- Apple 認証 UI、Application Port、プロトタイプ Adapter を分離する。
- 後続機能が Root Store に業務データを重複させず合成できる入口を作る。

### Non-Goals

- 暇、友達、募集、安全機能の業務実装。
- APNs capability と通知許可。

## Boundary Commitments

### This Spec Owns

- アプリ起動状態、Onboarding、ProfileSetup、3タブとルート Composition。
- `AuthenticationPort`、`ProfileRepository`、セッション状態、入力・失敗型。
- TCA 1.26.1 と filesystem-synchronized Xcode group の導入。

### Out of Boundary

- 各タブの業務状態、Apple token revokeとAuth user削除。

### Allowed Dependencies

- SwiftUI / AuthenticationServices / TCA 1.26.1 / supabase-swift固定版。
- iOS 17、Swift 6.3、Xcode 26.6。

### Revalidation Triggers

- 認証 API、TCA、Xcode、対応 OS、タブ構成、Backend session 契約の変更。

## Architecture

```mermaid
graph LR
    AppView --> AppFeature
    AppFeature --> AuthUseCase
    AppFeature --> ProfileUseCase
    AuthUseCase --> AuthenticationPort
    ProfileUseCase --> ProfileRepository
    SupabaseAuthAdapter --> AuthenticationPort
    ProfileAPIAdapter --> ProfileRepository
    DebugPrototypeAdapters --> AuthenticationPort
    DebugPrototypeAdapters --> ProfileRepository
    Composition --> AppFeature
    Composition --> PrototypeAdapters
```

静的依存は Presentation → Application → Domain、Infrastructure → Application / Domain、Composition → 全層とする。SignInWithAppleButton の結果は Presentation で Apple 型から Application 入力へ変換する。

### Technology Stack

| Layer | Choice / Version | Role | Notes |
|---|---|---|---|
| UI | SwiftUI / iOS 17 | View と Navigation | Dynamic Type / VoiceOver |
| State | TCA 1.26.1 | Reducer、Store、Effect | 1.26.2 は Swift 6.4 要求のため不採用 |
| Auth UI | AuthenticationServices | Apple 標準ボタン、nonce | identity tokenとauthorization codeを取得 |
| Auth SDK | supabase-swift 固定版 | session発行・保存・更新 | native `signInWithIdToken` |
| Build/Test | Xcode 26.6 / Swift 6.3 / Swift Testing | app と test | TCA Package.resolved を固定し、XCTest は使用しない |

## File Structure Plan

```text
apps/ios/Himatch/
├── App/Presentation/Reducer/AppFeature.swift
├── App/Presentation/View/AppView.swift
├── App/Composition/AppCompositionRoot.swift
├── Authentication/Application/{Port,UseCase}/
├── Authentication/Infrastructure/Adapter/{Supabase,Prototype}AuthenticationAdapter.swift
├── Authentication/Presentation/{Reducer,View}/
├── Profile/Application/{Port,UseCase}/
├── Profile/Domain/Model/UserProfile.swift
├── Profile/Infrastructure/Adapter/{API,Prototype}ProfileAdapter.swift
├── Profile/Presentation/{Reducer,View}/
├── MainTab/Presentation/{Reducer,View}/
└── Himatch.entitlements
apps/ios/HimatchTests/AppFoundation/
```

既存 `ContentView.swift` は `AppView` の互換入口へ置換し、`HimatchApp.swift` は Composition が作る Store のみ保持する。Xcode project は app/test フォルダ同期と TCA package product を登録する。

## State and Contracts

`AppFeature.State` は `onboarding`、`profileSetup`、`mainTab` の排他的 route と共通 suspension 状態だけを持つ。各子機能は delegate action で完了を親へ通知する。

```swift
struct AppleAuthorizationInput: Equatable, Sendable {
    let identityToken: String
    let authorizationCode: String?
    let rawNonce: String
}

protocol AuthenticationPort: Sendable {
    func authenticate(_ input: AppleAuthorizationInput) async throws -> SessionSummary
    func currentSession() async throws -> SessionSummary?
    func signOut() async throws
}
```

Apple requestにはraw nonceのSHA-256を設定し、Supabaseにはidentity tokenとraw nonceを渡す。失敗は`cancelled`、`unavailable`、`rejected(message)`、`transport`へ正規化し、キャンセルを通信失敗として表示しない。起動時はsession復元後に`GET /v1/me`でrouteを決める。Prototype Adapterは`DEBUG`でのみデモセッションを返し、Release Compositionは構成値不足を明示的に失敗させる。

## Requirements Traceability

| Requirement | Components | Validation |
|---|---|---|
| 1.1-1.5 | OnboardingFeature, AuthenticationPort | Reducer / View tests |
| 2.1-2.4 | ProfileSetupFeature, ProfileRepository | validation / UseCase tests |
| 3.1-3.3 | AppFeature, MainTabFeature | route transition tests |
| 4.1-4.5 | CommonUiState, reusable views | state and accessibility inspection |
| 5.1-5.5 | AuthenticationPort, AppFeature, Composition | restore / refresh / invalidation tests |

## Testing Strategy

- すべての iOS テストは Swift Testing で記述し、XCTest を import しない。
- Domain/Application: 表示名、Port 成功・失敗、キャンセルの翻訳。
- Presentation: TestStore で onboarding → profile → tabs、失敗・再試行、logout。
- Integration: Simulator で起動し DEBUG デモ導線から3タブへ到達。
- Project: TCA resolve、全 Swift ファイルの target membership、既存 CI/CD test。

## Security Considerations

- identity token、authorization code、raw nonce、access token、暇時間をログへ出さない。
- 生のApple credentialを永続化せず、Supabase SDKの安全なsession storageを利用する。
- Sign in with Apple entitlement 追加時は配布 profile の再作成を必要条件として文書化する。
