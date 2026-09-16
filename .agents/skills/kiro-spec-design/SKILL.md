---
name: kiro-spec-design
description: Create comprehensive technical design for a specification
metadata:
  shared-rules: "design-principles.md, design-discovery-full.md, design-discovery-light.md, design-synthesis.md, design-review-gate.md"
---

# 設計の生成・更新

承認された要件を実装可能な責務・契約・検証方針へ落とし込む。

## 文脈と承認

- `.kiro/specs/$1/` の `spec.json`、`requirements.md`、存在する `design.md`、`research.md`、関連タスクを読む。steering は基本3文書と対象に関係する追加文書を読む。
- [kiro-spec-sync](../kiro-spec-sync/SKILL.md) で前提の陳腐化と影響範囲を確認する。古い設計を現行実装の事実と混同しない。
- 要件の承認を確認する。`-y` は今回の許可された範囲の要件を承認して進める指定であり、未決定の製品判断を新しく決める許可ではない。品質確認を省略しない。
- `.kiro/settings/templates/specs/design.md`、`research.md` と `rules/design-principles.md` を読む。

## 調査と設計

1. 変更の不確実性に合わせて調査する。既知パターンの小変更はコードと契約の確認で十分。既存機能拡張は `rules/design-discovery-light.md`、新規境界や複雑な統合は `rules/design-discovery-full.md` の該当項目を使う。
2. 外部 API・依存ライブラリの契約など変化する情報は一次資料で確認する。未決定の選択に影響しない網羅的な調査は加えない。独立したコード調査と外部調査は並列エージェントに分担できる。
3. `rules/design-synthesis.md` を使って調査結果を統合する。採用理由、棄却した選択肢、確認した契約と出典を `research.md` に残す。
4. テンプレートに沿い、所有する責務、対象外、依存方向、公開契約、下流の再検証条件を明示する。File Structure Plan には作成・変更する具体的パスと責務を書く。要件 ID を正確に参照し、検証方針は受け入れ条件と重要な利用フローから導く。
5. `rules/design-review-gate.md` で要件の対応、契約の整合、実行可能性を確認する。局所的な設計不足は修正する。上流の誤りは sync に従い許可範囲内で本文から直し、その影響を再評価する。未許可の製品判断だけ質問し、その判断に依存する確定を保留する。

## 保存と状態

- 合格した `design.md` と根拠を記した `research.md` を保存する。同期対象の古い記述も更新し、履歴だけを追加して矛盾を温存しない。
- `approvals.design.generated: true` と `updated_at` を更新する。意味変更の承認失効、下流タスクの再オープン、ready の無効化は sync に従う。要件の承認を設計生成だけで true に書き換えない。
- 新規生成の `phase` は `design-generated`。既存更新の phase は sync の規約に従う。既存承認は内容が有効な範囲で維持する。
- 品質合格と承認を別々に報告する。次のタスク生成へ進むのは設計の明示承認または許可済み fast-track がある場合。

不足ファイルや未決定事項は具体的に示す。既存 ID の機械的な修正は参照先と一緒に行い、ユーザーに手編集を要求しない。

各工程の最終反映では sync で現存文書の整合を確認し、`freshness.status` と未同期の `pending` を更新する。`current` は文書整合の状態であり、承認や実装 GO を意味しない。旧仕様に freshness がなくても一律に承認を消去せず、今回の対象から確認する。

## 文書形式

生成と更新には [OKF の共通手順](../kiro-spec-sync/references/okf-workflow.md) を使う。本文のIDと構造を保ち、工程終了時に対象文書と影響先を検査する。初期化だけの場合は未確認状態を維持し、未実施の意味検査を記録しない。
