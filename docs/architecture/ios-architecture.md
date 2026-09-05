# iOS の設計

## 採用方針

SwiftUI と TCA を Presentation に使用し、業務の処理と外部接続を Clean Architecture の依存方向で分離します。
これはこのプロジェクトの組み合わせ方であり、TCA 公式が要求するディレクトリ構成ではありません。
TCA の依存追加とアプリ実装はまだ行いません。

TCA は State、Action、Reducer、Effect、Store によって状態変化と副作用を扱います。
Store は状態と Action の処理を駆動し、Reducer が遷移と実行する Effect を定義します。
[公式 README](https://github.com/pointfreeco/swift-composable-architecture)

## MVVM との関係

MVVM の「描画と表示ロジックを分離する」という考え方を維持します。
独立した ObservableObject の ViewModel を TCA の上に重ねることはしません。

| MVVM で意識する責務 | 採用する実装 |
| --- | --- |
| View | SwiftUI View |
| 表示状態 | Reducer に属する State |
| ユーザー操作 | Action |
| 表示状態の更新と操作の調整 | Reducer |
| 状態の保持と実行 | Store |
| Model | Domain のモデルと Application の結果 |

Reducer は ViewModel と同一の型ではありません。
この表は責務の対応であり、MVVM のクラス構造を再現するものではありません。
画面を持つ機能では State と Action を Reducer と同じファイルにまとめ、分割の必要が出てから別ファイルにします。

## 実行時の流れと静的依存

```text
実行:
View が Action を送信
  → Store が Reducer を実行
  → Effect 内で UseCase を呼ぶ
  → UseCase が Port を通して API Adapter を呼ぶ
  → 内部モデルの結果を Action として返す
  → Reducer が State を更新
  → View が再描画

静的な依存:
Presentation → Application → Domain
Infrastructure → Application / Domain
Composition → Presentation / Application / Infrastructure
```

ローディング表示、画面遷移、選択状態、Effect のキャンセルは Presentation が所有します。
業務上の検証や複数操作の調整は UseCase、業務上の不変条件は Domain が所有します。
API SDK や生成 DTO を Reducer の State や Action に含めません。
親 Reducer は子機能の状態と Action を合成し、必要な結果を delegate Action 等の明示的な契約で受け取ります。
単一のアプリ全体 State に全機能の業務データを重複して持たせません。

## DTO 変換の所有者

DTO 変換のために独立した横断層は作成しません。
外部契約を知る各機能の Infrastructure が変換を所有します。

```text
API Response DTO
  → <Feature>APIMapper
  → Domain のモデルまたは Application の結果
  → UseCase
  → Reducer の State
```

たとえば `HostingAPIMapper` を `Himatch/Hosting/Infrastructure/Mappers/` に置きます。
同じ機能の `HostingAPIAdapter` が、通信と変換を組み合わせて Application の Port を実装します。
DB 変換なら `HostingRecordMapper`、表示向けの変換なら Presentation の `HostingViewDataMapper` のように境界を名前で表します。
`DTOMapper` のように対象が曖昧な共通型は作りません。

小さな変換が一か所だけで使われる場合は Adapter 内の private 関数で十分です。
変換の複雑化や独立した検証の必要が生じたら Mapper ファイルへ分離します。
Domain の型に生成 DTO を引数とする initializer を追加すると依存が逆転するため、変換関数は Infrastructure 側に置きます。
未知の enum、不正な日時、欠落した必須情報は、API Adapter の境界で扱いを決めます。
無条件に既定値へ置き換えず、Application が定義する失敗型などへ変換します。

共有の生成クライアントが必要なら `Himatch/Platform/Networking/Generated/` に配置します。
Platform は SwiftUI、TCA、各機能のモデルに依存しません。
生成型にアクセスできるのは通信基盤と各機能の API Adapter / Mapper だけです。
`Core/API` に機能固有の Mapper を集める構成は採用しません。

Domain モデルを State 内に保持することは許容します。
表示専用 DTO を毎回作ることは必須にしません。
整形済み文字列など UI 固有の形が必要になったときだけ、Presentation で変換します。

## TCA と依存注入の境界

Application の UseCase と Port は通常の Swift 型、async 関数、protocol またはクロージャの値型で表現します。
Application と Domain は `ComposableArchitecture` や `Dependencies` を import しません。
クロージャを選ぶ場合も、UseCase への明示的な初期化引数として渡します。

Presentation の `Dependencies/` に UseCase を呼ぶための薄い依存値と `DependencyValues` への登録を置きます。
Reducer は `@Dependency` でこの依存を受け取り、Effect 内で呼び出します。
その公開シグネチャには Application の入出力型だけを使います。
ネットワーク用 Client と、UseCase 呼び出し用の依存値を同じ名前や責務にしません。

App の Composition が生成クライアント、Adapter、UseCase を組み立て、Store の生成時に依存値を注入します。
Presentation 側の `liveValue` で Infrastructure を直接構築しません。
初期値を必要とする場合は未注入の検出に使い、本番接続を自動生成する抜け道にしません。
実装は選定した TCA と swift-dependencies の版で検証します。
[依存差し替えの公式資料](https://github.com/pointfreeco/swift-dependencies)

Cancellation は Effect と下位の非同期処理へ伝播させ、キャンセルを通信失敗の画面表示へ機械的に変換しません。
Swift の並行処理チェックに合わせ、境界の値とクロージャの Sendable 要件を確認します。
具体的な API や actor 構成はバージョンと実装に応じて決めます。

## 過剰な層分けを防ぐ

ViewModel、汎用 BaseReducer、全モデル用の変換プロトコルは作成しません。
UseCase は業務操作の単位で設け、各 HTTP エンドポイントと一対一に対応させません。
単なる処理の中継のために同じ protocol とラッパーを各層へ重ねません。
ディレクトリ分離だけでは import 制約は強制されないため、実装開始時には lint 等で依存方向を検証します。
Swift package への分割は、実際にビルド境界を強制する必要が出てから判断します。

## 検証方針

- Domain：業務上の不変条件。
- Application：差し替えた Port に対する処理と失敗の扱い。
- Infrastructure：DTO の変換、不正値、未知値、通信エラーの翻訳。
- Presentation：TestStore による Action、State、Effect の結果、キャンセル。
- Composition：本番依存を注入した Simulator 上の起動と主要操作。

TestStore は TCA の状態遷移と Effect の結果を検証するために使います。
[公式のテスト例](https://github.com/pointfreeco/swift-composable-architecture#testing)
