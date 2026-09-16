---
name: kiro-spec-tasks
description: Generate implementation tasks for a specification
metadata:
  shared-rules: "tasks-generation.md, tasks-parallel-analysis.md"
---

# 実装タスクの生成・更新

要件と設計を、責務・依存関係・検証できる成果で区切った実行単位へ変換する。

## 準備

- `.kiro/specs/$1/` の `spec.json`、`requirements.md`、`design.md`、存在する `tasks.md` と関連 research を読む。steering は基本3文書と関連文書に限定する。
- [kiro-spec-sync](../kiro-spec-sync/SKILL.md) に従って、変更の影響と承認の有効性を確認する。
- 要件と設計の承認を確認する。`-y` は今回の許可範囲で要件・設計・生成後のタスクを自動承認する。未解決の製品判断や品質不合格を承認で飛び越えない。
- `rules/tasks-generation.md`、`.kiro/settings/templates/specs/tasks.md` を読む。`--sequential` がなければ `rules/tasks-parallel-analysis.md` も使う。ファイル読込だけのエージェント分担はしない。

## 生成とレビュー

1. 数値要件 ID、設計の責務・契約、実際に不足する前提設定と検証項目をタスクへ対応させる。記述は spec.json.language に従う。
2. 各実行タスクに観測可能な完了条件を書く。時間や詳細行数で固定せず、独立して検証できる成果と責務で分割する。子が1つなら親に昇格してよい。実行対象は番号の深さではなく、子を持たない実行可能な末端タスクである。
3. `_Requirements:_` に数値 ID、必要な `_Depends:_` と `_Boundary:_` を付ける。`(P)` は依存と共有ファイルの競合がない場合だけ使う。
4. 既存の完了チェックを無条件に複写しない。意味変更の影響を受ける成果は sync に従って再オープンし、無関係な完了状態と参照可能な ID を維持する。
5. tasks-generation の Task Plan Review Gate で網羅性と依存グラフを一度に確認する。独立した sanity review を重複して必須化しない。複数境界・複雑な並列化・重要な契約変更がある場合は独立レビュアーへこのゲートを任せる。単純な計画は主担当が確認する。
6. 局所的な計画不足を直して影響部分を再確認する。上流の矛盾は sync で要件・設計の本文へ戻って修正する。新しい製品判断が必要な部分だけ質問し、架空のタスクで穴埋めしない。

## 保存・承認

- 合格した `tasks.md` を保存し、`approvals.tasks.generated: true`、`updated_at` を更新する。新規生成は `phase: tasks-generated`、既存更新は sync の phase 規約に従う。
- 意味変更時の承認失効、ready の無効化、完了タスクの扱いは sync に従う。生成しただけで要件・設計を承認済みに変更しない。
- `-y` または上位 quick/batch の明示許可があれば、その範囲の品質合格したタスクを承認する。それ以外は成果物を提示してタスク承認を待つ。既に承認された同一内容への再確認は不要。
- 最終同期と承認反映後に sync の条件で `ready_for_implementation` を必ず再計算する。
- タスク承認は実装開始、commit、push などの外部操作の許可を意味しない。実装はユーザーの依頼範囲に従う。

変更したタスク、再オープンした範囲、検証結果、未承認工程と次の `$kiro-impl $1` を簡潔に伝える。

各工程の最終反映では sync で現存文書の整合を確認し、`freshness.status` と未同期の `pending` を更新する。`current` は文書整合の状態であり、承認や実装 GO を意味しない。旧仕様に freshness がなくても一律に承認を消去せず、今回の対象から確認する。

## 文書形式

生成と更新には [OKF の共通手順](../kiro-spec-sync/references/okf-workflow.md) を使う。本文のIDと構造を保ち、工程終了時に対象文書と影響先を検査する。初期化だけの場合は未確認状態を維持し、未実施の意味検査を記録しない。
