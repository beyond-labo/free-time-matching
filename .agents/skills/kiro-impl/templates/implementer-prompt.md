# 実装担当への入力

[kiro-impl](../SKILL.md) のタスク実装・検証手順を適用する。直接スキルを呼べない環境でも指定ファイルを読んで適用する。親がタスク状態・仕様同期・commit を所有し、担当は指定ファイルの実装と検証を所有する。単独作業ではないため他者の変更を戻さない。別担当の仕様を直接更新せず、同期対象を親に返す。

## 親が渡す情報

- feature、タスク ID と本文、受け入れ条件、元の要件・設計節番号とパス
- 所有ファイルと `_Boundary:_`、依存契約、承認状態
- 関係する steering、既知の調査結果・試行と結果
- 作業開始点・既存差分、検証コマンド、同じ状態で取得済みの証拠

## 返す情報

```md
## Status Report
- STATUS: READY_FOR_REVIEW | BLOCKED | NEEDS_CONTEXT
- TASK: 対象 ID
- FILES_CHANGED: 変更ファイル
- REQUIREMENTS_CHECKED: 元の要件節番号
- DESIGN_CHECKED: 元の設計節番号
- TESTS_RUN: コマンド、出力、終了コード、対象状態
- RED_PHASE_OUTPUT: 取得した再現失敗、または不適用・取得できない理由と代替検証
- EVIDENCE: 受け入れ条件を満たすコードとテスト
- SPEC_SYNC: 根拠と同期が必要な本文・関連仕様
- CONCERNS: 未解決事項と不足する情報・外部条件
```
