# 開発手順

## 現在の検証

Node.js を用意して、リポジトリルートで実行します。

```sh
node scripts/verify.mjs
```

外部依存のインストールは不要です。
JSON、workspace の登録、ローカル文書リンク、iOS CI/CD 構成を確認します。
Backend のテスト、API 互換性はまだ検証しません。
`pnpm-lock.yaml` はルートと Backend の空の依存一覧です。

## iOS の build と test

Xcode 26.6、利用可能な iPhone Simulator、Python 3.9 以上、OpenSSL 3.4 以上を用意し、リポジトリルートで実行します。
CI の `macos-26` image では Python 3.14 系と OpenSSL 3.6 系を使用し、各 version は test log に出力されます。

```sh
bash scripts/ios/test.sh
```

スクリプトは最初に期限切れ、証明書・秘密鍵・profile の不一致、壊れた key、RSA/P-384 API key を扱う signing preflight の実 crypto fixture test を実行します。
続いて `apps/ios/Himatch.xcodeproj` の shared scheme `Himatch` を使い、署名なしで app と `HimatchTests` を build/test します。
最低 iOS は 17.0、Swift language mode は 6.0 です。
CI と App Store upload の build 環境は Xcode 26.6 に固定します。

## Backend の実装開始

1. 承認済み仕様と HTTP 実行基盤、スキーマ、テストツールを確認する。
2. Node.js、pnpm、TypeScript の版を決め、依存とコンパイラ設定を追加する。
3. 最初の機能に必要な Domain、Application、Presentation、Infrastructure を作成する。
4. 起動処理で機能の Handler を登録する。
5. HTTP スキーマから OpenAPI を生成し、実装との整合性を検証する。
6. 型チェック、テスト、ビルドが実行できた段階でアプリ CI を追加する。

## iOS の実装開始

1. TCA の Xcode 26.6 / Swift 6 / iOS 17 対応バージョンを確認する。
2. Swift Package Manager で固定した TCA 依存を導入し、解決結果を管理する。
3. 最初の機能の View、Reducer、State、Action を実装する。
4. Application の UseCase と Port、Infrastructure の Adapter を実装する。
5. 生成ツールと入力契約を固定し、DTO の変換を機能内へ閉じ込める。
6. Composition で依存を注入し、TestStore と Simulator で検証する。

TCA の導入方針は採用済みですが、ライブラリの互換性と実装は未検証です。
現在の SwiftUI 画面と AppIcon は CI/CD 経路を検証する最小成果物で、製品機能ではありません。
