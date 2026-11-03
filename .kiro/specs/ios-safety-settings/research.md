---
type: Research
title: "iOS 安全機能・設定調査"
description: "Apple審査、削除、Push、Privacy Label とクライアント境界の調査"
status: stable
sources:
  - id: apple-review-guidelines
    resource: https://developer.apple.com/app-store/review/guidelines/
    title: App Review Guidelines
  - id: apple-account-deletion
    resource: https://developer.apple.com/support/offering-account-deletion-in-your-app
    title: Offering account deletion in your app
  - id: apple-token-revoke
    resource: https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple
    title: Handling account deletions and revoking tokens
  - id: apple-app-privacy
    resource: https://developer.apple.com/app-store/app-privacy-details/
    title: App privacy details
kiro:
  depends_on:
    - docs/product/overview.md
    - docs/operations/ci-cd.md
---

# 調査と設計判断

## Summary

- UGC / social services はフィルタ、通報と適時対応、悪質ユーザーのブロック、公開連絡先が必要。
- アカウント作成を提供する場合、アプリ内削除開始が必要。受付と完了を分けられる。
- Push をアプリ利用の必須条件にできず、機密情報を通知へ含めない。
- social graph は端末 Contacts 権限を使わなくても Privacy Label の Contacts に含まれる。

## Design Decisions

### Decision: 通報とブロックを別コマンドにする

- **Rationale**: Apple 要件と利用者の即時安全を独立して満たし、一方を他方の必須条件にしない。

### Decision: 削除を長期状態として扱う

- **Selected Approach**: accepted 後にアクセス停止し、外部 token revoke と削除ジョブは再試行可能な status とする。
- **Rationale**: Apple 失効が一時失敗しても削除要求を履行し、受付と完了を誤認させない。

### Decision: Push は opaque hint に限定する

- **Rationale**: 受信箱を正本にし、通知拒否とロック画面露出を安全に扱う。

## Risks & Mitigations

- UIだけの block で安全を誤認 — block preview / confirm の Backend 契約を明記する。
- 仮の問い合わせ URL が審査へ出る — release 前に構成値を検証し、未設定を合格させない。
- 削除受付後の復帰 — client session を即時無効化し、status 参照だけを別契約にする。

## References

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app)
- [Sign in with Apple token revoke](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)

## Change Log

- 2026-09-21: アカウント削除をPrototype受付から、fresh Apple再認証、Backend token revoke、Supabase Auth hard deleteへ接続する方針へ更新。初版は同期処理とし、失敗はactionRequiredでアクセス停止を維持する。独立レビュー後、送信前operation IDのKeychain保存、曖昧結果の同一ID再送、accepted / processing表示、Keychain・sign-out失敗時の安全側遷移を追加した。
- 2026-09-20: ユーザー提示内容を Apple 公式資料と照合し、新規仕様へ反映。

## 2026-10-30 第一段階への同期

ユーザーの自動提案・双方OKによる確定への変更に基づき、自動提案・予定と友達プロフィールの定型通報/ブロックを実Backendへ接続する。匿名相手は提案IDから解決する。既存Prototypeの任意補足やblock一覧を実保存・実提供されたと表示しない。ブロック/退会でpendingと未来予定を停止する。通知許可・device登録とAPNs配送はAutomaticScheduling/Notificationへ委譲する。
新機能と関連受け入れ条件は [自動予定成立仕様](../automatic-friend-scheduling/requirements.md) を参照する。既存完了を新機能の証拠に流用せず、実装・検証証拠は同仕様のresearchへまとめる。

## 匿名2人契約の安全操作への移行（2026-11-03）

新しい第一段階は匿名の2人提案を含み、相手や影響予定IDを先に開示する旧Prototypeの件数/version previewを実APIへ移さない。固定の効果（関係解除・新規停止・pendingと未来予定取消）を確認し、その同じ効果をサーバーの最新状態へ原子的に適用する契約へ置換した。通報・ブロックは別操作とし、運営向け通報受付は成功したoperationIDをDB行へ一意保存して受付番号とする。これは新しい製品境界のプライバシー設計であり、旧Prototypeの状態を実Backendの証拠に使わない。
