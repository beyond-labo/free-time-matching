# Android

Google Play internal track配布までの経路を検証する最小Jetpack Composeアプリです。
製品機能、Clean Architectureの機能層、Backend API clientはまだ実装していません。

JDK 21、Android SDK Platform 37、Build Tools 36.0.0を用意し、リポジトリルートから次を実行します。

```sh
bash scripts/android/test.sh
```

Gradle Wrapperは`apps/android/gradlew`にあり、AGP 9.4.0、Gradle 9.6.0、AGP内蔵Kotlin 2.2.10、Compose BOM 2026.08.00を固定しています。Gradleとcompiler toolchainはJDK 21で実行し、Android向けのJava/Kotlin bytecode targetは17に固定します。
