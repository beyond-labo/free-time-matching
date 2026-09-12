---
name: kiro-steering-custom
description: API、テスト、セキュリティなど特定領域のプロジェクト方針を作成または更新する。
metadata:
  shared-rules: "steering-principles.md"
---

# 領域別の方針

[rules/steering-principles.md](rules/steering-principles.md) と [kiro-spec-sync](../kiro-spec-sync/SKILL.md) に従う。

1. 依頼から領域と目的を特定し、既存の core と custom steering を検索する。既存文書が同じ責務を持つ場合は更新する。
2. `.kiro/settings/templates/steering-custom/` に該当テンプレートがあれば使い、関連コード、設定、決定の根拠を調べる。
3. `.kiro/steering/{name}.md` の本文を現行の方針に合わせる。旧記述への追記だけで矛盾を残さない。
4. 影響する仕様と相互参照を sync で確認し、変更した意味と根拠を短く記録する。
5. 更新結果と未解決事項を報告する。

追加質問は、目的を左右する情報が既存文脈から得られない場合に限る。
独立した大きな調査は分担できるが、テンプレート読込だけの分担は不要。
読取専用の依頼では提案を返す。

## 文書形式

生成と更新には [OKF の共通手順](../kiro-spec-sync/references/okf-workflow.md) を使う。本文のIDと構造を保ち、工程終了時に対象文書と影響先を検査する。初期化だけの場合は未確認状態を維持し、未実施の意味検査を記録しない。
