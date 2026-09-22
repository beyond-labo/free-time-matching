---
type: Brief
title: "iOS アプリ基盤"
description: "初回説明、認証境界、プロフィール、3タブと共通状態を成立させる"
status: stable
sources:
  - id: user-ios-first-release
    resource: conversation://2026-09-20/ios-first-release
    title: iOS 初版の必要要件・画面仕様案
kiro:
  depends_on:
    - .kiro/steering/roadmap.md
    - docs/architecture/ios-architecture.md
---

# iOS アプリ基盤 Brief

## Problem

現行 iOS は CI/CD 用の暫定画面だけで、利用者が非公開共有の前提を理解し、認証、プロフィール設定、主要機能へ移動できない。

## Current State

TCA 1.26.1 と Swift Testing を使う iOS 初版があり、DEBUG のプロトタイプ画面と状態遷移を確認できる。認証・プロフィールは native Sign in with Apple、Supabase Auth、Backend API の Production Adapter へ接続し、外部設定がない Release 構成は設定エラーとして扱う。

## Desired Outcome

登録前に共有条件を理解し、Sign in with Apple のクライアント境界を通り、仮名とプリセットアイコンを設定して、ホーム・友達・設定の3タブへ進める。通信失敗、権限喪失、利用停止も安全な画面状態として扱える。

## Approach

TCA 1.26.1 と SwiftUI を Presentation に置き、Application の認証・プロフィール Port へ Production / DEBUG Prototype Adapter を Composition から明示的に注入する。Apple request の nonce と identity token は Supabase Auth へ渡し、Backend は Supabase access token を検証して本人プロフィールを提供する。

## Scope

### In

- 利用説明、規約・プライバシー・問い合わせ導線。
- Sign in with Apple ボタンと認証 Port。
- 1〜20文字の表示名、生成仮名、プリセットアイコン。
- 3タブ、共通 Navigation、読み込み・失敗・権限喪失・利用停止。
- Production Composition と、DEBUG に限定したプロトタイプ依存の入口。

### Out

- メール・パスワード認証、Android、友達・暇・募集の本番 Backend 接続。
- 各タブの業務機能、Push 許可要求、App Store 外部設定。

## Boundary Candidates

- AppFeature / AppView、OnboardingFeature、ProfileSetupFeature。
- AuthenticationPort、ProfileRepository と Supabase / Backend / Prototype Adapter。
- AppCompositionRoot。

## Out of Boundary

暇時間、友達、募集、安全操作の業務規則を基盤へ取り込まない。

## Upstream / Downstream

- Upstream: SwiftUI、AuthenticationServices、TCA、既存 iOS アーキテクチャ。
- Downstream: ios-availability、ios-friendship、ios-hosting、ios-safety-settings。

## Existing Spec Touchpoints

- Extends: `ios-ci-cd` の app target と test target。
- Adjacent: `docs/architecture/ios-architecture.md`。

## Constraints

- Domain / Application は SwiftUI、TCA、AuthenticationServices を import しない。
- 通知許可をログインや主要機能利用の条件にしない。
- プロトタイプ認証を実 Sign in with Apple 完了と表示しない。
