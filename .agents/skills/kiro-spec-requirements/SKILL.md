---
name: kiro-spec-requirements
description: Generate comprehensive requirements for a specification
metadata:
  shared-rules: "ears-format.md, requirements-review-gate.md"
---

# 要件の生成・更新

ユーザーから観測できる振る舞いと対象範囲を、検証できる受け入れ条件へ整理する。

## 文脈と同期

- `.kiro/specs/$1/` の `spec.json`、`requirements.md`、存在する `brief.md` を読む。更新時は関連する設計・タスク・research も確認する。
- steering の `product.md`、`tech.md`、`structure.md` と、今回の範囲に関係する追加文書を読む。
- [kiro-spec-sync](../kiro-spec-sync/SKILL.md) を読み、古い記述、今回の判断、実装上の事実を区別する。古い brief や既存承認を理由に最新の許可された判断を捨てない。
- `rules/ears-format.md`、`rules/requirements-review-gate.md` と `.kiro/settings/templates/specs/requirements.md` を使う。

## 生成とレビュー

1. 会話と既存の決定から WHAT を確定する。誰が何をでき、何を対象外とするか、隣接機能へ何を期待するかを記述する。HOW に属する内部構造は設計に委ねる。
2. EARS 形式の受け入れ条件と数値の要件 ID を使う。既存 ID は可能な限り維持し、改番が必要なら設計・タスク・検証側の参照も同期する。
3. 未知の既存機能や外部制約の調査が必要な場合だけ調べる。独立したコード調査・ドメイン調査は並列エージェントへ分担できる。文書を読むだけの分担は不要。
4. requirements-review-gate を一度のまとまったレビューとして実施する。局所的な不足は修正して影響箇所を再確認する。同じ問題で修正が進まない場合は根拠と未決定事項を整理する。
5. 製品範囲・振る舞い・公開契約に関する複数の選択肢が既存の許可から解決できない場合に限り、該当する要件の確定を保留して質問する。通常の記述整理や許可済み判断の反映を質問へ戻さない。

## 保存と状態

- 合格した現行本文を `requirements.md` に書き戻し、変更理由・根拠・影響先を sync の手順で記録する。変更履歴への追記だけで古い本文を残さない。
- `approvals.requirements.generated: true` と `updated_at` を更新する。要件の意味が変わったときは sync に従って要件および下流の承認・ready を無効化し、生成済みファイルの存在状態を維持する。影響する完了タスクも再評価する。
- 新規生成の `phase` は `requirements-generated`。既存更新の phase は sync の規約に従う。変更がない場合は承認を不用意にリセットしない。
- 品質レビュー合格は人間の承認ではない。既存の明示承認または上位 quick/batch の許可範囲だけを適用する。

変更点、同期したファイル、品質結果、未承認の工程を簡潔に報告する。独立呼び出しでは次工程の承認がなければ成果物を提示してレビューを待つ。上位ワークフローから許可された継続を、定型の確認質問で止めない。

各工程の最終反映では sync で現存文書の整合を確認し、`freshness.status` と未同期の `pending` を更新する。`current` は文書整合の状態であり、承認や実装 GO を意味しない。旧仕様に freshness がなくても一律に承認を消去せず、今回の対象から確認する。

## 文書形式

生成と更新には [OKF の共通手順](../kiro-spec-sync/references/okf-workflow.md) を使う。本文のIDと構造を保ち、工程終了時に対象文書と影響先を検査する。初期化だけの場合は未確認状態を維持し、未実施の意味検査を記録しない。
