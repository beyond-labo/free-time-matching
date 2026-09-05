# 開発手順

## 現在の検証

Node.js を用意して、リポジトリルートで実行します。

```sh
node scripts/verify.mjs
```

外部依存のインストールは不要です。
JSON、workspace の登録、ローカル文書リンクを確認します。
アプリのテスト、ビルド、API 互換性は検証しません。
`pnpm-lock.yaml` はルートと Backend の空の依存一覧です。

## Backend の実装開始

1. 承認済み仕様と HTTP 実行基盤、スキーマ、テストツールを確認する。
2. Node.js、pnpm、TypeScript の版を決め、依存とコンパイラ設定を追加する。
3. 最初の機能に必要な Domain、Application、Presentation、Infrastructure を作成する。
4. 起動処理で機能の Handler を登録する。
5. HTTP スキーマから OpenAPI を生成し、実装との整合性を検証する。
6. 型チェック、テスト、ビルドが実行できた段階でアプリ CI を追加する。

## iOS の実装開始

1. 最低 iOS、Xcode / Swift、TCA の対応バージョン、Bundle ID を決める。
2. 実際の Xcode プロジェクトと Simulator で動く最小アプリを作る。
3. Swift Package Manager で固定した TCA 依存を導入し、解決結果を管理する。
4. 最初の機能の View、Reducer、State、Action を実装する。
5. Application の UseCase と Port、Infrastructure の Adapter を実装する。
6. 生成ツールと入力契約を固定し、DTO の変換を機能内へ閉じ込める。
7. Composition で依存を注入し、TestStore と Simulator で検証する。

TCA の導入方針は採用済みですが、ライブラリの互換性と実装は未検証です。
ソースがない状態で空のプロジェクト、生成設定、成功しないスクリプトを作りません。
