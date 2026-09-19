---
type: Research
title: "Android CI/CD 調査"
description: "Android build、GitHub Actions、Play App Signing、Google Play配布方式の調査と採用判断"
status: stable
sources:
  - id: agp-94
    resource: https://developer.android.com/build/releases/agp-9-4-0-release-notes
    title: Android Gradle plugin 9.4.0 release notes
  - id: compose-bom
    resource: https://developer.android.com/develop/ui/compose/bom
    title: Use a Bill of Materials
  - id: android-jdk
    resource: https://developer.android.com/build/jdks
    title: Java versions in Android builds
  - id: built-in-kotlin
    resource: https://developer.android.com/build/migrate-to-built-in-kotlin
    title: Migrate to built-in Kotlin
  - id: gradle-java
    resource: https://docs.gradle.org/current/userguide/compatibility.html#java
    title: Gradle Java compatibility
  - id: target-api
    resource: https://developer.android.com/google/play/requirements/target-sdk
    title: Meet Google Play target API level requirement
  - id: app-signing
    resource: https://developer.android.com/studio/publish/app-signing
    title: Sign your app
  - id: play-api
    resource: https://developers.google.com/android-publisher/api-ref/rest
    title: Google Play Android Developer API
kiro:
  depends_on:
    - .kiro/specs/android-ci-cd/requirements.md
---

# 調査と設計判断

## Summary

- **Feature**: `android-ci-cd`
- **Discovery Scope**: Complex Integration
- **Key Findings**:
  - 2026年8月31日以降、新規appと更新はAndroid 16（API 36）以上がGoogle Play提出要件のためtargetSdk 36を採用する。
  - AGP 9.4.0のJDK下限は17だが、Gradle 9.6.0はLTSのJDK 21で正式に実行できる。build runtime/toolchainは21、Android向けbytecode targetは17に分離する。
  - Play App Signingではrepository側はupload keyだけを管理し、Googleが配布用app signing keyを管理できる。
  - Play Developer APIはedit作成、AAB upload、track更新、commitの順でinternal releaseを構成できる。

## Research Log

### Android build toolchain

- **Context**: 新規Android appの再現可能なbuild境界を決めた。
- **Sources Consulted**: Android Gradle Plugin 9.4.0 release notes、Android buildのJava version、Gradle Java compatibility、Compose BOM（2026-09-18確認）。
- **Findings**: AGP 9.4.0の最小Gradleは9.6.0、JDK下限は17。Gradleは8.5以降でJDK 21実行を正式サポートする。AGP 9はKotlin supportを内蔵し、AGP 9.4.0の既定KGPは2.2.10。Composeのstable BOMは2026.08.00。
- **Implications**: 外付けKotlin Android pluginを使わずAGP内蔵Kotlin 2.2.10へ揃える。Gradle WrapperとJDK 21をbuild入口にし、Android source/bytecodeは17へ固定する。

### Google Play提出条件

- **Context**: target SDKと配布成果物を決めた。
- **Sources Consulted**: Target API level requirement、App signing（2026-09-18確認）。
- **Findings**: 2026-08-31以降はphone/tabletの新規appと更新にAPI 36以上が必要。新規appはPlay App Signingを使い、AABはupload keyで署名してuploadする。
- **Implications**: Compose BOMのAAR要件に合わせてcompileSdk 37、Play提出要件としてtargetSdk 36を採用する。署名済みAABを使い、production公開とは分離したinternal trackだけを自動化する。

### Google Play Developer API

- **Context**: 追加のpackageや第三者upload actionを避けながら配布する方法を確認した。
- **Sources Consulted**: Google Play Android Developer API v3（2026-09-18確認）。
- **Findings**: service accountのOAuth access tokenを使い、edit作成、bundle upload、track update、commitをRESTで実行できる。
- **Implications**: Node.js標準のfetchとcryptoで限定的なupload clientを実装し、外部actionへのsecret委譲を避ける。

## Architecture Pattern Evaluation

| Option | Strengths | Risks / Limitations | Decision |
|---|---|---|---|
| Node.jsからPlay APIを直接利用 | 依存追加なし、API境界が明示的 | API変更の追従が必要 | 採用 |
| 第三者upload action | 設定が短い | secretを第三者actionへ渡し、更新監査が必要 | 不採用 |
| Gradle Play Publisher | release管理が豊富 | pluginと設定面が増える | 現時点では不採用 |

## Design Decisions

### Decision: CIと配布を別workflowにする

- **Context**: PRの検証では秘密を不要にし、配布だけをEnvironmentで保護する。
- **Selected Approach**: CIはlint/test/debug build、CDは同じ検証後に署名とinternal uploadを実行する。
- **Trade-offs**: CDで検証を再実行する費用と引き換えに、配布対象commitの検証結果を同一run内で保証する。

### Decision: 最小Compose appを実行可能な契約として追加する

- **Context**: workflowだけではbuild経路を検証できない。
- **Selected Approach**: Composeの最小画面とJVM単体テストを追加し、製品機能やarchitecture用の空ディレクトリは作らない。
- **Trade-offs**: 暫定UIは将来置換が必要だが、bundleと配布経路を先に検証できる。

## Risks & Mitigations

- 初回releaseはPlay Console側のapp作成、契約、Play App Signing設定、場合によって手動AAB uploadが必要 — runbookで明示する。
- upload keyまたはservice account keyの漏えい — Environmentに限定し、一時ファイルをcleanupし、失効手順を記載する。
- API/toolchain更新 — versionを固定し、変更時を再検証triggerにする。

## Change Log

### 2026-09-19

`play-internal` Environmentを作成し、`hiiragi589`の1名承認、self-review許可、管理者bypass禁止、`main` / `android-v*`のref制限を設定した。外部 contributor のpull request workflowは組織メンバー承認まで実行せず、main rulesetは同ユーザーだけの承認Teamを必須とする。本人にはpull request経由だけのbypassを設定した。要件とworkflow契約は変更しない。

GitHub Actionsの実行で `sdkmanager` がPATHに存在しないことを確認し、CI/CD両workflowのSDK導入を `ANDROID_HOME` 配下の明示パスへ変更した。Android SDK、build、配布の契約に変更はない。

### 2026-09-18

ユーザー依頼を起点にAndroidとGoogleの一次資料を確認し、API 36、AGP 9.4.0、Gradle 9.6.0、JDK 21 build runtime/toolchain、Java/Kotlin 17 target、AGP内蔵Kotlin 2.2.10、Compose BOM 2026.08.00、Play internal track配布を採用した。
