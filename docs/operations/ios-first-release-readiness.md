# iOS初版の実装・リリース判定

## 現在の判定

現時点の成果物は、認証・プロフィール・削除をSupabase/Backendへ接続し、それ以外の画面と状態遷移をPrototypeで確認する段階です。
外部Apple/Supabase設定と実機E2Eが未完了のため、外部TestFlightへ配布できる製品完成状態ではありません。

## 実装済みの検証範囲

- 初回説明、Sign in with Appleボタン、DEBUGデモ導線、プロフィール、ホーム・友達・設定の3タブ。
- 非公開を初期値とする暇時間の登録・削除、15分境界、14日上限、重複拒否。
- 招待コード表示、受信申請の承認、友達プロフィール、解除、通報、ブロック。
- オンライン／オフライン募集、定型カテゴリ、必要時間、友達選択、招待への参加OK、回答済み募集の確定。
- Push非依存の受信箱、確定予定、通知設定UI、削除受付番号。
- TCA 1.26.1の固定、Sign in with Apple entitlement、Swift Testing専用検査、Simulator build/test。

プロトタイプは、配信人数や非公開ユーザーの登録状況をホストへ表示しません。
また、暇登録だけでは参加者を生成せず、参加OK回答のない募集は確定できません。

## リリース前に未完了の項目

- Apple DeveloperとSupabase Dashboardの実環境設定、GitHub EnvironmentへのSupabase／Worker設定登録、実資格情報によるstaging E2E。
- operation ID、version conflict、同時操作、二重送信、募集頻度制限を含む整合性制御。
- APNs、アプリ内受信箱の永続化、通知設定の保存、通知本文の本番確認。
- 友達コードの解決・申請・拒否・取消、募集回答の変更・撤回・見送り、予定の取消・離脱の本番フロー。
- 運営の通報受付・是正・利用停止、公開問い合わせ先、コミュニティルール。
- actionRequiredとなった削除の運用再試行、将来の業務データ削除、バックアップ復元対策。
- 実Bundle IDとTeam ID、capability対応profile、審査用アクセス、Privacy Label、年齢レーティング、外部TestFlight審査。
- VoiceOver、Dynamic Type、タイムゾーン変更、IPv6-only、2台以上の実機によるリリース判定。

これらをプロトタイプの画面表示やfixtureテストで代替せず、Backend・運用・実機の証拠が揃った時点でリリース可否を再判定します。
