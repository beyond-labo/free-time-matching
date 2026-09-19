# Androidの設計

## 現在の境界

`apps/android`はCI/CD経路を実行可能にする最小Jetpack Composeアプリです。
`MainActivity`、最小Composable、JVM単体テストだけを持ち、製品機能、Backend client、DI frameworkはまだ実装しません。

## 採用方針

- UIはJetpack Composeを使う。
- 機能実装は`Domain / Application / Presentation / Infrastructure`に分け、内側の層からAndroid、Compose、通信SDKを参照しない。
- PresentationはComposableと状態管理を所有する。具体的な状態管理libraryは最初の製品機能の仕様で選定する。
- Backendの公開OpenAPIから生成するclientは共通の通信基盤に置き、機能固有DTOからDomainへの変換は各機能に閉じ込める。
- App起動部が依存を組み立てる。利用責務がない空packageは作らない。

## 実装時の配置例

```text
app/src/main/java/com/example/himatch/hosting/
├── domain/
├── application/
├── presentation/
└── infrastructure/
```

Java/Kotlin packageは通常のAndroid規約に従ってlowercaseにし、型名はPascalCaseにします。
具体的なpackage name `com.example.himatch` は署名不要CI用の既定値で、配布時はEnvironment variableから上書きします。

## テスト

- Domain/Applicationの判断はJVM単体テストで確認する。
- Compose UI testと端末testは、検証する製品UIが生じた時点で追加する。
- pull requestではlint、JVM単体テスト、debug buildを秘密なしで実行する。
