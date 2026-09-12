# OKF 文書の取り扱い

プロファイルの正本は [okf-profile.md](../../../../.kiro/settings/okf-profile.md)。
以下のコマンドはリポジトリルートから実行する。
Python 3 と `scripts/requirements.txt` に記した PyYAML が必要。既存環境を使い、依存追加が必要なら実行環境の許可手順に従う。

```sh
python3 .agents/skills/kiro-spec-sync/scripts/okf.py check --root . --feature FEATURE
```

`check` は読み取り専用。
`--feature` を省略すると specs と steering を棚卸しする。
ハッシュ変更は意味変更の確定ではないので、結果を読んで同期スキルの分類を行う。
検査対象がまだ存在しない場合は、検査できた文書がないことを報告する。

## 制御ファイルがない場合

brief のみの探索段階は `check` と `index --feature FEATURE` だけを使い、snapshot のために spec.json を新設しない。
steering 単独更新では全体の check と index を使い、feature のない snapshot を要求しない。
関連する既存仕様の入力を変えた場合だけ、所有者と調整してそれらの snapshot を更新する。
旧形式の無関係な文書まで移行する必要はない。棚卸しの指摘と今回の完了範囲を分けて報告する。

## 生成と移行

1. テンプレートの TITLE、DESCRIPTION を実際の内容で埋め、出典と契約依存を確認して `sources` と `kiro.depends_on` に記す。無いものは空リストとし、捏造しない。
2. 新規 brief と roadmap にも profile の type を付ける。既存文書は内容とIDを維持して frontmatter を追加し、メタデータの未知フィールドは保持する。
3. 意味変更があれば sync の失効処理を先に行う。古い内容確認を現在の verified として残さない。
4. 構造検査の問題を直し、本文と影響先の意味を照合する。必要な承認を既存の許可範囲で確認する。
5. 確認を終えた対象だけに次を実行し、確認済み入力のハッシュを記録する。

```sh
python3 .agents/skills/kiro-spec-sync/scripts/okf.py snapshot --root . --feature FEATURE --reviewed
python3 .agents/skills/kiro-spec-sync/scripts/okf.py index --root . --feature FEATURE
```

snapshot は確認済み入力の記録のみを更新する。承認を付与せず、ready や同期状態の判断も代行しない。
`--reviewed` は人間の承認を意味せず、実施済みの意味の検査を表す。コマンドを通すためだけに付けない。
タスクの完了チェックや共通 roadmap の更新も先に済ませ、変更した入力に依存する仕様の確認記録を最後に更新する。完了チェックだけの変更なら、その意味が不変であることを確認して既存の検証結果を再利用する。
記録後に sync の手順で freshness と ready を更新し、check を再実行して一致を確認する。
判定に無関係な変更まで再テストしない。

生成 index は再作成可能な索引であり、詳細や承認の正本にしない。
`index --root .` の共有索引更新はコントローラーだけが行う。
新しい文書を読んだときは、既存のハッシュが一致していても未宣言の影響先や外部根拠を必要に応じて確認する。

## 限界

構造検査は OKF 全規定の認証でも意味上の正しさの保証でもない。
外部URLは自動取得しない。URLの到達性と資料内容の更新は別に確認する。
ハッシュのない旧仕様は未確認として点検し、承認を一括削除しない。

## ツール自体の検証

スクリプトを変更した場合は、依存の入った Python 環境で次を実行する。

```sh
python3 -m unittest discover -s .agents/skills/kiro-spec-sync/tests -v
```
