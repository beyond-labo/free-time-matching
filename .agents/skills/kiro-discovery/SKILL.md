---
name: kiro-discovery
description: Entry point for new work. Determines the best action path or work decomposition (update existing spec, create new spec, mixed decomposition, or no spec needed) and refines ideas through structured dialogue.
---

# 作業範囲の探索

依頼を既存仕様の更新、新規仕様、直接実装に振り分け、次の作業に必要な決定を保存する。

## 探索と判断

1. `.kiro/specs/*/spec.json`、roadmap、ディレクトリ構造から候補を絞り、関連する requirements・design・steering の本文を読む。メタデータの段階名やファイルの存在だけで既存仕様の有効性を判断しない。
2. [kiro-spec-sync](../kiro-spec-sync/SKILL.md) を読み、現在の依頼と古い前提の差分を確認する。依頼を既存仕様へ無理に合わせず、同じ責務の変更はその仕様の本文を更新する方針を優先する。
3. 次の作業経路を選ぶ。経路選択そのものへの定型的な確認は不要。
   - 既存仕様の範囲内なら、影響する要件・設計・タスクの更新。
   - 仕様上の振る舞いが変わらない小修正なら直接実装。ただし発見した古い関連記述は sync の対象とする。
   - 独立した新しい責務なら新規仕様。
   - 複数の責務なら複数仕様または既存更新との混合。タスク数の固定閾値で分割しない。
4. 誰の問題か、望む結果、対象外、依存先、制約を既存文脈から整理する。解決できない製品判断だけ質問し、許可された通常判断は進める。独立した大きなコード調査や技術調査は並列エージェントへ分担できるが、定型の実現可能性レビューを毎回必須にしない。
5. 選択に実質的な差があれば候補と理由を提示する。既存の採用判断を使える場合は再選択させない。製品範囲や互換性の新しい判断が必要なら、該当する確定だけ承認を待つ。

## 保存する内容

新規の単一仕様では `.kiro/specs/<feature>/brief.md` に以下を記録する。本文は仕様の言語を使い、後続工程が参照するラベルを維持する。

- `Problem`、`Current State`、`Desired Outcome`
- `Approach`（選択と理由）、`Scope`（In / Out）
- `Boundary Candidates`、`Out of Boundary`
- `Upstream / Downstream`
- `Existing Spec Touchpoints`（Extends / Adjacent）
- `Constraints`

複数仕様では `.kiro/steering/roadmap.md` に Overview、Approach Decision、Scope、Constraints、Boundary Strategy と次の一覧を保存する。

```markdown
## Specs (dependency order)
- [ ] feature-a -- 説明。Dependencies: none
- [ ] feature-b -- 説明。Dependencies: feature-a
```

混合の場合は `## Existing Spec Updates` と `## Direct Implementation Candidates` を分ける。`Specs (dependency order)` は新規仕様だけに使い、そこに列挙した各仕様に brief を作る。既存仕様更新は対象仕様と変更内容を明記し、別名の仕様を重複作成しない。

再入時は既存本文を読み、完了状態と判断根拠を保ちながら現行内容へ更新する。変更された前提に依存するチェックは sync で再評価する。過去の選択を現行判断と混在させず、理由と置き換え関係を記録する。未処理の既存仕様更新も消さない。

保存したファイルと参照を確認し、sync で整合状態と残件を反映する。会話のまとめだけで後続へ渡さない。

## 次工程

依頼が探索・検討までなら具体的な成果物と次のコマンドを示して終える。既に生成・実装まで依頼されているなら、その許可と各工程の承認条件に従って続ける。

- 既存仕様: 影響の最上流工程へ（要件変更なら `$kiro-spec-requirements <feature>`）。
- 新規単一仕様: `$kiro-spec-init` または許可された `$kiro-spec-quick`。
- 複数仕様: `$kiro-spec-batch`。この呼び出しの一括承認範囲を守る。
- 直接実装: 依頼範囲の変更と必要な文書同期。

各工程の最終反映では sync で現存文書の整合を確認し、`freshness.status` と未同期の `pending` を更新する。`current` は文書整合の状態であり、承認や実装 GO を意味しない。旧仕様に freshness がなくても一律に承認を消去せず、今回の対象から確認する。

## 文書形式

生成と更新には [OKF の共通手順](../kiro-spec-sync/references/okf-workflow.md) を使う。本文のIDと構造を保ち、工程終了時に対象文書と影響先を検査する。初期化だけの場合は未確認状態を維持し、未実施の意味検査を記録しない。
