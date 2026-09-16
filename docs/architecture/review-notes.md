# 構成の見直し結果

2026-09-06 に追加指示を反映しました。

| 論点 | 決定 |
| --- | --- |
| 機能を束ねる中間階層 | 作らない |
| HTTP の層名 | Presentation。HTTP は通信方式として区別 |
| Port / Gateway | 層名ではなく契約と接続の役割 |
| iOS の実装方式 | TCA＋Clean Architecture。ViewModel を重ねない |
| API DTO の変換 | 各機能の Infrastructure が所有 |
| 共有クライアント | 必要になったら Platform/Networking。機能モデルには依存しない |
| 予約ファイルと空ディレクトリ | 削除。実装時に追加 |
| 検証の入口 | `node scripts/verify.mjs` に統一 |
| CI の表示 | 実態に合わせリポジトリ検証とする |

[技術方針](technology.md)と[iOS の設計](ios-architecture.md)を現在の決定とします。
生成 DTO を Core 内だけに閉じ込める旧案は、機能の API Adapter も生成型を利用できる境界へ更新しました。

未決事項は、各ツールのバージョン、HTTP 基盤、契約生成ツール、最低 iOS、インフラと公開先です。
実装前に空の型や層を増やさず、最初の機能を通して境界を検証します。
