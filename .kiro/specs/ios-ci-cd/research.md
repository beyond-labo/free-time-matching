---
type: Research
title: "iOS CI/CD 調査"
description: "GitHub Actions、Apple 署名、App Store Connect 配布方式の調査と採用判断"
status: stable
sources:
  - id: apple-upload
    resource: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
    title: Upload builds
  - id: apple-api-key
    resource: https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api
    title: App Store Connect API
  - id: github-environments
    resource: https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
    title: Deployments and environments
  - id: github-runner
    resource: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
    title: macOS 26 runner image
  - id: github-skip-workflow
    resource: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs
    title: Skipping workflow runs
  - id: apple-api-token
    resource: https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
    title: Generating tokens for API requests
  - id: apple-certificates
    resource: https://developer.apple.com/help/account/certificates/certificates-overview
    title: Certificates overview
  - id: apple-csr
    resource: https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request
    title: Create a certificate signing request
  - id: apple-keychain-export
    resource: https://support.apple.com/guide/keychain-access/kyca35961/mac
    title: Import and export keychain items using Keychain Access on Mac
  - id: openssl-pkcs12
    resource: https://docs.openssl.org/3.6/man1/openssl-pkcs12/
    title: openssl-pkcs12
kiro:
  depends_on:
    - .kiro/specs/ios-ci-cd/requirements.md
---

# 調査と設計判断

## Summary

- **Feature**: `ios-ci-cd`
- **Discovery Scope**: Complex Integration
- **Key Findings**:
  - Apple は 2026 年時点の iOS アップロードに Xcode 26 以降でのビルドを要求しているため、`macos-26` と Xcode 26.6 を固定する。
  - GitHub Environment は配布秘密をジョブ単位に隔離でき、保護ルールを設定した場合は承認前に secret を渡さない。
  - App Store Connect API key は Apple ID とアプリ用パスワードよりローテーションと権限管理が明確であり、アップロードには `altool` の API key 認証を使える。
  - 元記事の証明書・profile の Base64 管理は採用するが、main push 自動配布、Apple ID 認証、固定 keychain password、project.pbxproj の sed 書換えは採用しない。

## Research Log

### Apple のアップロード要件

- **Context**: 記事の `altool` と認証方式が現行か確認した。
- **Sources Consulted**: Apple の Upload builds、App Store Connect API、証明書ヘルプ（2026-09-16確認）。
- **Findings**: iOS build は Xcode 26 以降が必要。`altool` と Transporter は引き続き upload をサポートし、API key による JWT 認証が可能。build string はアップロードごとに一意でなければならない。
- **Implications**: Xcode 26.6 を固定し、workflow run number と attempt の組を build number にする。API private key は JWT の ES256 に対応する EC P-256 key であることを archive 前に検査する。App Store 公開は upload と分ける。

### Apple Distribution 証明書の発行 UI

- **Context**: Apple Developer Account の `Certificates` で `+` を押した後に表示される現行画面と、CI に読み込む `.p12` の作成手順を確認した。
- **Sources Consulted**: Apple の Certificates overview、Create a certificate signing request、Keychain Access User Guide（2026-09-17確認）。
- **Findings**: `Create a New Certificate` ページでは `Software` 欄の `Apple Distribution` を選んでから CSR を upload する。配布証明書を作成できるのは Account Holder または Admin である。CSR を作成した Mac の Keychain には対応する秘密鍵が保存され、証明書の取り込み後に証明書と秘密鍵を `.p12` として export できる。
- **Implications**: 運用手順を現行画面の順序へ合わせ、CSR の入力項目、旧 `iOS Distribution` との区別、Keychain で秘密鍵を確認する失敗時の判断を明記する。CI の秘密情報名と署名方式は変更しない。

### GitHub の秘密と承認境界

- **Context**: pull request と配布資格情報を分離する必要がある。
- **Sources Consulted**: GitHub Deployments and environments、Secure use reference（2026-09-16確認）。
- **Findings**: Environment secret はその Environment を参照する job だけが利用でき、required reviewer 設定時は承認前に利用できない。プランと private repository の組合せにより required reviewer が利用できない場合がある。
- **Implications**: `testflight` Environment を必須の登録先にする。required reviewer は `hiiragi589` に限定し、本人によるリリースのため self-review は許可する一方、管理者 bypass は禁止する。許可 ref は `main` と `ios-v*` に限定し、workflow 自体も tag/manual trigger と concurrency で誤配布を抑える。

### GitHub required check と path filter

- **Source**: [GitHub Docs — Skipping workflow runs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs)
- **Findings**: path filter で workflow 自体が skip されると、required check は Pending のまま残り pull request を block する。
- **Implications**: `iOS build and test` を required check にできるよう、iOS CI はすべての pull request と main push で起動する。秘密を使わない Simulator 検証なので、常時起動しても資格情報境界は変わらない。

### GitHub macOS runner

- **Context**: `macos-latest` の移動で再現性が失われないようにする。
- **Sources Consulted**: actions/runner-images の macOS 26 image（2026-09-16確認）。
- **Findings**: `macos-26` は Xcode 26.6 を `/Applications/Xcode_26.6.app` に含み、Python 3.14 系と OpenSSL 3.6 系も収録する。
- **Implications**: runner と `DEVELOPER_DIR` の両方を固定し、Xcode、Python、OpenSSL の version をログへ残す。runner image 更新時は signing preflight の実 crypto fixture を再実行する。

### Keychain export の legacy PKCS#12 互換性

- **Context**: Keychain Access から export した配布証明書を OpenSSL 3.6 で展開した際、`RC2-40-CBC` を取得できず TestFlight workflow が archive 前に失敗した。
- **Sources Consulted**: OpenSSL 3.6 の `openssl-pkcs12` マニュアル（2026-09-18確認）。
- **Findings**: OpenSSL 3 は legacy provider を既定で読み込まず、RC2で暗号化された旧形式の PKCS#12 を読み込む場合は `-legacy` が必要である。
- **Implications**: `release.sh` の証明書と秘密鍵の両方の展開で `-legacy` を指定する。RC2形式の fixture を実際に生成し、展開後の署名素材検証まで到達する回帰テストを維持する。

## Architecture Pattern Evaluation

| Option | Strengths | Risks / Limitations | Decision |
|---|---|---|---|
| Base64 certificate/profile + runner 同梱 tools | 追加 install が不要で、単一アプリの構成が明示的 | 更新時に secret の差替えと Python/OpenSSL 互換性確認が必要 | 採用 |
| fastlane match | 複数アプリ・複数人で証明書共有に強い | Ruby と別の暗号化 repository、復号 secret が増える | 現時点では不採用 |
| Xcode Cloud | Apple 側で署名・CI を統合 | GitHub Actions から運用が分散し、今回の依頼範囲と異なる | 不採用 |

## Design Decisions

### Decision: CI と配布を別 workflow にする

- **Context**: PR の検証では秘密を不要にし、配布だけを Environment で保護する。
- **Selected Approach**: CI は Simulator の署名なし test、CD は同じ test 後に manual signing と upload を実行する。
- **Trade-offs**: CD で test を再実行する費用と引き換えに、配布対象 commit の検証結果を同一 run 内で保証する。

### Decision: 最小アプリを実行可能な契約として追加する

- **Context**: 現状は Xcode project がなく、空 workflow は既存方針に反する。
- **Selected Approach**: SwiftUI の最小画面、shared scheme、Swift Testing、AppIcon を追加する。iOS テストでは XCTest を使用しない。TCA と製品機能は別仕様で追加する。
- **Trade-offs**: 暫定 UI とアイコンは将来置換が必要だが、build・archive・upload の実経路を今から検証できる。

## Risks & Mitigations

- Apple/GitHub の外部設定は repository だけでは完了できない — ページ単位の runbook と preflight error を用意する。
- 証明書または profile の失効 — expiry を確認し、同名 secret を更新して再実行する。
- App Store Connect の処理後エラー — workflow の upload 成功を公開成功と扱わず、App Store Connect の Processing 状態を確認する。
- API key は team 全アプリへ広い権限を持ち得る — Developer 相当の最小 role を選び、Environment secret に限定する。
- Python/OpenSSL の runner 同梱版が更新される — version をログへ残し、期限切れ、鍵不一致、RSA/P-384、壊れた key の実 fixture test で archive 前検査を再確認する。

## Change Log

### 2026-09-21

ユーザーの iOS 戦略決定により、iOS の単体・Reducer・統合テストを Swift Testing に統一し、XCTest の import と XCTestCase 継承を禁止した。`xcodebuild test` と既存 test target は実行経路として維持し、テスト記述フレームワークだけを置換した。

### 2026-09-19

GitHub の実設定を確認し、外部 collaborator が存在しないこと、外部 contributor の pull request workflow が組織メンバー承認まで実行されないことを確認した。`testflight` は `hiiragi589` の1名承認、self-review許可、管理者bypass禁止、`main` / `ios-v*` のref制限へ更新した。main rulesetは同ユーザーだけの承認Teamを必須とし、本人にはpull request経由だけのbypassを設定した。要件とworkflow契約は変更しない。

### 2026-09-18

Keychain Access が export した legacy PKCS#12 と OpenSSL 3.6 の互換性問題を修正し、RC2形式の実 fixture による回帰テストを追加した。CI/CD の要件、設計責務、秘密情報の契約に変更はない。

### 2026-09-17

Apple Developer Account の現行証明書発行 UI と Keychain Access の一次資料を確認し、運用手順の画面遷移と `.p12` export 前の秘密鍵確認を更新した。CI/CD の要件、設計、秘密情報の契約に変更はない。

### 2026-09-16

Qiita 記事を起点に Apple と GitHub の一次資料を再確認し、Xcode 26.6、API key upload、Environment 分離を採用した。影響先は iOS project、GitHub workflows、運用・技術文書。
