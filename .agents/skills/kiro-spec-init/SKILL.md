---
name: kiro-spec-init
description: Initialize a new specification with detailed project description
---

# 仕様の初期化

説明または feature 名から仕様の置き場所を確定し、初期ファイルを作る。

1. `.kiro/specs/` の既存仕様、対象の `brief.md`、関連する steering を確認する。同じ責務の仕様があればその仕様を再利用する。既存の `spec.json` や本文を初期テンプレートで上書きしない。
2. 既存仕様の更新なら [kiro-spec-sync](../kiro-spec-sync/SKILL.md) を読み、更新範囲を特定する。初期化は不要と報告し、許可された後続工程へ進む。単なる名前の衝突を理由に `-2` を作らない。別の責務であることが確認できた新規仕様だけ別名にする。
3. 新規仕様では誰の問題か、現状、望む変化を会話・brief・既存文書からまとめる。製品の振る舞いや範囲が未決定で、既存文脈から解決できないときだけ質問する。通常の命名や記述上の判断は自律的に行う。
4. `.kiro/settings/templates/specs/init.json` と `requirements-init.md` を読み、feature 名・ISO 8601 時刻・説明を置換して `.kiro/specs/<feature>/spec.json` と `requirements.md` を作る。`brief.md` だけの既存ディレクトリはそのまま利用する。言語は明示された指定、既存プロジェクト設定、ユーザー入力の順で決め、不明なら `ja` とする。
5. 書き戻した JSON と本文を確認する。初期化では要件本体・設計・タスクを生成しない。

テンプレートがない場合は不足パスを報告し、既存メタデータを推測で置換しない。結果は feature 名、作成または再利用したファイル、次の `$kiro-spec-requirements <feature>` を簡潔に伝える。上位ワークフローが後続生成を許可している場合はそこで継続する。

## 文書形式

生成と更新には [OKF の共通手順](../kiro-spec-sync/references/okf-workflow.md) を使う。本文のIDと構造を保ち、工程終了時に対象文書と影響先を検査する。初期化だけの場合は未確認状態を維持し、未実施の意味検査を記録しない。
