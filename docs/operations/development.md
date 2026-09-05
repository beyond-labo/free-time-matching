# 開発手順

## 現在実行できること

```sh
make bootstrap
make verify
pnpm --filter @himatch/backend verify
```

`bootstrap` は Node.js と pnpm の存在、およびリポジトリの構成を確認します。
依存のインストール、Xcode 設定、クラウド作成は行いません。
`verify` は必要な配置と JSON の構文、パッケージ境界の基本設定を確認します。
業務テストやビルドの代替ではありません。

構成確認時に pnpm が生成した `pnpm-lock.yaml` を含めています。
ルートと Backend の登録のみで、外部依存はありません。
初めて依存を導入するときに Node.js と pnpm のバージョンを決め、`packageManager` とランタイム設定を追加し、ロックファイルを更新します。
以後、CI はロックファイルを更新しないインストールを使用します。

## Backend の実装開始

1. HTTP 実行基盤、HTTP スキーマライブラリ、テストツールを選定する。
2. TypeScript と必要な実行依存を `apps/backend/package.json` に追加する。
3. `app.ts` に依存の組み立て、`entrypoints/` に実行環境への接続を書く。
4. 承認済み仕様に従い、機能内に Domain、Application、Infrastructure を実装する。
5. HTTP スキーマとルートを追加し、OpenAPI エクスポートを実装する。
6. lint、型チェック、テスト、ビルドの正式なコマンドを追加する。

現在の TypeScript ファイルは予約位置を示す空のモジュールです。
HTTP、認可、通知のハンドラーとしてデプロイできません。

## iOS の実装開始

1. 最低 iOS、Xcode / Swift、Bundle ID、署名チームを決める。
2. `apps/ios/Himatch.xcodeproj/` 内の予約 README を除き、実際の Xcode プロジェクトを作る。
3. `Himatch/` と `HimatchTests/` をターゲットへ登録する。
4. OpenAPI クライアント生成ツールと依存ライブラリのバージョンを固定する。
5. `Config/` と `Scripts/` に再現可能な生成処理を実装する。
6. API Adapter と Mapper を実装し、機能の Port へ接続する。
7. Simulator 上のテストとビルドコマンドを決める。

現在の Swift ファイルはコメントのみです。
App の起動コード、生成クライアント、署名可能なターゲットはありません。

## 未実装の操作

`make export-openapi`、`make generate-api-client` は、現段階では説明を出して失敗します。
`tooling/openapi/check-breaking-change.sh` も同様です。
未実装の検証を成功として扱わないための動作です。
