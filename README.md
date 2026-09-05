# ひまっち（仮）

iOS と Backend を独立して開発、リリースするモノレポです。
Backend は公開 OpenAPI を所有し、iOS は TCA＋Clean Architecture を採用する方針です。

[ドキュメント一覧](docs/README.md)に、製品範囲、技術方針、将来の配置、開発と運用の手順をまとめています。

## 現在の状態

現時点で存在するのは文書、workspace の登録、リポジトリ検証です。
アプリ、Xcode プロジェクト、OpenAPI、生成ツール、インフラ、アプリの CI/CD は未実装です。
未実装の層やツールのための予約ファイルは作成しません。

## 検証

Node.js が利用できる環境で実行します。
外部依存のインストールは不要です。

```sh
node scripts/verify.mjs
```

JSON、workspace 登録、文書のローカルリンクを検証します。
アプリのテストやビルドは行いません。
