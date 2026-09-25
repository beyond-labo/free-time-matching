---
type: Design
title: "iOS アプリ統合設計"
description: "Composition、横断読み取り投影、共有 Prototype scenario の設計"
status: stable
sources:
  - id: ios-app-integration-research
    resource: ./research.md
    title: iOS アプリ統合調査
kiro:
  depends_on:
    - .kiro/specs/ios-app-integration/requirements.md
    - .kiro/specs/ios-app-foundation/design.md
    - .kiro/specs/ios-availability/design.md
    - .kiro/specs/ios-friendship/design.md
    - .kiro/specs/ios-hosting/design.md
    - .kiro/specs/ios-safety-settings/design.md
---

# Design Document

## Overview

`AppCompositionRoot` が全機能のPort実装とTCA Storeを組み立てる。認証・プロフィール・削除・Friendship・本人の暇時間は実Backend Adapterを標準とし、最初の内部TestFlightではSTGへ接続する。`HimatchPrototypeScenario` actorはDEBUGの明示的なデモと未接続の業務機能だけに限定する。

起動時は削除受付状態とセッションを先に判定し、プロフィールの有無でメイン画面か初期設定画面を決める。プロフィール確定後はメイン画面を表示し、友達と本人の暇時間を独立した Effect で並行取得する。各取得状態は専用フラグで Home / Friends の領域に表示し、共通 `isLoading` の全面オーバーレイは読み取りに使わない。失敗時は各領域から再試行でき、片方の失敗で他方の表示を消さない。

## Boundary Commitments

### This Spec Owns

- Root Composition、横断 read model、共有 Prototype scenario、fixture reset、全機能統合テスト。

### Out of Boundary

- 個別機能の業務規則、暇の実BackendトランザクションとAPI自体、募集の実Backend、Push。暇AdapterのRelease注入は本仕様が所有する。

### Allowed Dependencies

- 新規5仕様の Domain / Application / Presentation 契約。Composition だけが Infrastructure 実装を参照できる。

### Revalidation Triggers

- 機能 Port、projection DTO、Root Navigation、fixture schema、TCA/Xcode の変更。

## Architecture

```mermaid
graph LR
    AppCompositionRoot --> RootStore
    AppCompositionRoot --> FeatureAdapters
    AppCompositionRoot --> ProductionAccountAdapters
    AppCompositionRoot --> BackendFriendshipAdapter
    AppCompositionRoot --> BackendAvailabilityAdapter
    FeatureAdapters --> PrototypeScenario
    ProjectionRepository --> PrototypeScenario
    Home --> ProjectionRepository
    UnifiedInbox --> ProjectionRepository
    FriendProfile --> ProjectionRepository
```

## File Structure Plan

```text
apps/ios/Himatch/App/Composition/AppCompositionRoot.swift
apps/ios/Himatch/App/Composition/AppProjectionRepository.swift
apps/ios/Himatch/App/Infrastructure/Prototype/HimatchPrototypeScenario.swift
apps/ios/Himatch/App/Presentation/Reducer/AppFeature.swift
apps/ios/Himatch/App/Presentation/View/AppView.swift
apps/ios/HimatchTests/AppIntegration/
```

## Contracts

`AppProjectionRepository` は `home()`、`inbox()`、`friendPlans(friendID)` の read-only async 操作だけを持つ。DTO は ownerFeature と entityID を持ち、変更操作は Root delegate が所有機能へ route する。

`HimatchPrototypeScenario` は actor 内で全 fixture を保持し、feature adapter factory と reset(seed) を提供する。block/delete は actor メソッド一回で関連状態と revision を更新する。各 Adapter は自機能 Port だけを実装する facade である。

## Requirements Traceability

| Requirement | Components | Validation |
|---|---|---|
| 1.1-1.4 | AppProjectionRepository, Root route | projection / navigation tests |
| 2.1-2.5 | HimatchPrototypeScenario, facets | actor / reset / cross-effect tests |
| 3.1-3.5 | AppCompositionRoot, integration tests | build / Swift Testing / Simulator smoke |
| 3.6-3.8 | ProductionAccountAdapters, BackendFriendshipAdapter, AppFeature | composition / staging config / restore / logout / deletion tests |

## Testing Strategy

- iOS テストは Swift Testing に統一し、repository verify で XCTest の再混入を拒否する。
- actor: reset、block/delete 原子的更新、revision。
- projection: owner ID、privacy-safe DTO、順序と区分。
- Root: delegate action が所有機能へ遷移する。
- Simulator: デモの主要経路。Backend安全性は MANUAL/BACKEND_REQUIRED として別判定する。
