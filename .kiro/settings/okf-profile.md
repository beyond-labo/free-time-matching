# Kiro の OKF プロファイル

対象バージョンは Open Knowledge Format 0.2。
この文書は kiro 固有の運用規則を定義する。
OKF の全文仕様や認証制度を置き換えるものではない。

## 対象範囲

- `.kiro/specs/` と `.kiro/steering/` を、それぞれ知識文書の bundle とする。
- `.agents/`、`.codex/`、AGENTS.md、`.kiro/settings/` のテンプレートは bundle に含めない。
- `spec.json` は kiro の制御ファイルとして保持し、承認や実装状態を Markdown に複製しない。
- 既存文書のパスと本文構造、数値要件ID、チェックリストを維持する。別の wiki へ本文を複製しない。
- 旧形式は対象の更新時に移行する。形式移行だけで意味上の承認を失効させないが、内容を点検するまで最新と扱わない。

## 文書メタデータ

`index.md` と `log.md` 以外の Markdown は YAML frontmatter を持つ。
`type` は空でない文字列とし、次の種類を使う。未知の種類や拡張フィールドは保持する。

| 文書 | type |
|---|---|
| brief.md | Brief |
| requirements.md | Requirements |
| design.md | Design |
| tasks.md | Implementation Plan |
| research.md | Research |
| 個別の重要判断 | Decision |
| steering の方針 | Project Policy |
| roadmap.md | Roadmap |

`title` と `description` は仕様所属文書なら `spec.json.language`、それ以外は指定された言語（指定なしは日本語）で短く記し、index 生成の材料にする。
`status` は明示的に `draft`、`stable`、`deprecated` を使う。
生成途中は draft、内容を確認して現行の説明として使える場合は stable、置換された文書は deprecated とする。
stable は実装許可を意味しない。

```yaml
---
type: Design
title: 予約の設計
description: 予約時間の制約と通知への契約
status: draft
sources:
  - id: booking-requirements
    resource: ./requirements.md
    title: 予約要件
kiro:
  depends_on:
    - .kiro/specs/booking/requirements.md
---
```

上記は形式例であり、実在しないファイルを生成文書へ転記しない。
`sources` は採用した根拠を示し、各項目に `resource` を記す。
必要な主張には `sources[].id` と一致する Markdown 脚注を付ける。
`kiro.depends_on` は変更時に再確認する契約や設定の実ファイルをリポジトリ相対で記す kiro 拡張であり、単なる参考資料と区別する。
依存の宣言は影響探索を補助するもので、未宣言の逆参照を `rg` で調べる作業も続ける。

`generated: {by, at}` は意味上の更新時に、実際の生成主体とタイムゾーン付き時刻を記録できる。
`verified` は実施した内容確認だけを記す。機械検査の成功を人間の確認として記録しない。
意味や根拠が変わって以前の確認が適用できなくなった場合は、旧 verified を履歴へ移し、現行本文に適用する確認だけを残す。
外部資料の更新日と文書の生成日を混同しない。
`stale_after` は期限が有用な外部仕様などに限定し、日付だけで整合や承認を判定しない。

## リンクと索引

- 通常の Markdown リンクを使う。ローカルリンクは文書相対を基本とする。
- `/` 始まりの OKF パスは各 bundle のルート相対であり、OS の絶対パスではない。
- 別 bundle やコードへの文書相対リンクは同じリポジトリ内に解決させる。単独 bundle として外部へ渡す際は必要な根拠を同梱するか、参照を解決可能なURLへ変換する。単独配布の可搬性を未検証で主張しない。
- `index.md` は各ディレクトリの概要で、制御状態を複製しない。ルートの frontmatter は `okf_version: "0.2"` のみ。子ディレクトリの index には frontmatter を付けない。
- `log.md` を使う場合は `## YYYY-MM-DD` の新しい日付から並べる。詳細な調査理由は research、重要な判断は Decision に置き、同じ全文を log に複製しない。
- 陳腐化した文書は置換先を示す。通常文書の現行本文は書き換えるが、決定記録は失効を明示して経緯を残す。

## 二段階の検証

1. 構造検査：frontmatter、参照、状態整合と確認済み入力のハッシュをスクリプトで確認する。
2. 意味の検査：要件から設計、タスクへの対応と実装の根拠を担当者が照合する。スクリプトの成功だけで意味の検査を省略しない。

ハッシュは変更検出に使い、承認の自動失効や自動付与に使わない。
変更を検出した場合は関連作業の開始と完了判定を保留し、sync の分類で表記修正か意味変更かを判断する。
表記修正なら承認を維持できる。意味変更なら該当工程と下流の承認を失効させ、影響先を同期する。

確認した文書とローカルの出典、依存先のハッシュは `spec.json.freshness.checked_inputs` に保存する。
同じファイルに複数の状態の正本を作らない。
JSON 自身、生成 index、log は入力ハッシュに含めず、自己参照や帳簿更新による無限の変更検出を避ける。
この記録は対象範囲の確認時点を表し、外部URLや動的サービスの現在の状態までは証明しない。
外部資料は確認日、対象バージョン、必要ならコミット固定URLを根拠として記録する。

並列担当は自分の spec だけの snapshot と index を更新する。
bundle ルートの index や共通方針への変更はコントローラーが直列に反映する。

## 重要判断の記録

MADR の問題、候補、選択理由、帰結の構成を必要な判断だけに使う。
OKF の `status` と衝突する MADR の承認状態は同じ frontmatter キーへ重ねず、本文で決定の採用や置換を記す。
単純な変更に Decision 文書を義務付けない。

## 根拠

- [OKF v0.2 公式仕様](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)（2026-09-07確認）。型、出典、来歴、状態、索引の基礎。
- [MADR](https://adr.github.io/madr/)（2026-09-07確認）。重要判断を構造化する本文の参考。
- `kiro.depends_on`、checked_inputs、承認の失効判定と二段階検証は、このプロジェクトの拡張。
