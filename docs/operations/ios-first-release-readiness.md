# iOS初版の実装・リリース判定

## 現在の判定

第一段階の完成条件は、手動募集中心から [自動提案・双方OKでの予定成立](../../.kiro/specs/automatic-friend-scheduling/requirements.md) へ変更しました。
認証・友達・本人暇・手動募集には既存の実Backendがあります。新しい自動提案・予定・通知・安全機能の実装と検証は [調査・検証記録](../../.kiro/specs/automatic-friend-scheduling/research.md) を参照してください。
コードの追加、ローカル試験、STGでの実機E2E、外部TestFlightの配布判定を区別します。実環境・実配信の証拠が揃うまでは外部配布可能な製品完成状態と扱いません。

## 既存実装から再利用する範囲

- 初回説明、Sign in with Appleボタン、DEBUGデモ導線、プロフィール、ホーム・友達・設定の3タブ。
- 非公開の暇時間の登録・削除、15分境界、14日上限、OR統合・区間減算。
- 招待コード表示、受信申請の承認、友達プロフィール、解除、通報、ブロック。
- 手動のオンライン／オフライン募集、定型カテゴリ、友達選択、招待への部分回答。手動Hostingの確定予定fixtureは実Backendの確定証拠にしません。
- Push非依存の受信箱、通知設定UI、削除受付番号。UIだけでは配信・安全機能の保存証拠になりません。
- TCA 1.26.1の固定、Sign in with Apple entitlement、Swift Testing専用検査、Simulator build/test。

新しい自動提案では、本人・友達別の双方許可、各自の明示OK、頻度・日時・安全の再検証を条件にします。旧Prototypeの表示とチェックだけでこれらを合格としません。

## リリース前に未完了の項目

- Apple DeveloperとSupabase Dashboardの実環境設定、GitHub EnvironmentへのSupabase／Worker設定登録、実資格情報によるstaging E2E。
- 新しい自動提案のSTGでのoperation ID、version conflict、同時操作、二重送信、7日/14日制限、暇変更・許可失効との整合性。
- APNs capabilityと資格情報、端末登録、sandbox/productionの実配送、失敗後再送、通知本文の実機確認。
- staging migrationと2アカウントでの自動検出、片側OK、双方OK確定、見送り・期限・取消・ブロック・退会のE2E。
- 運営の通報受付・是正・利用停止、公開問い合わせ先、コミュニティルール。
- actionRequiredとなった削除の運用再試行、将来の業務データ削除、バックアップ復元対策。
- 実Bundle IDとTeam ID、capability対応profile、審査用アクセス、Privacy Label、年齢レーティング、外部TestFlight審査。
- VoiceOver、Dynamic Type、タイムゾーン変更、IPv6-only、2台以上の実機によるリリース判定。

これらをプロトタイプの画面表示やfixtureテストで代替せず、Backend・運用・実機の証拠が揃った時点でリリース可否を再判定します。

新機能の設定・検証順・評価項目は [運用手順](automatic-scheduling.md) にまとめています。自動提案の上限や共有初期値は、配布前の設定作業で勝手に緩和しません。
