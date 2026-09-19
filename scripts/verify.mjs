import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, dirname, resolve, extname } from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const ignored = new Set([".git", ".agents", ".codex", ".kiro", "node_modules", ".pnpm-store"]);
function* filesIn(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (ignored.has(entry.name)) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) yield* filesIn(path);
    else if (entry.isFile()) yield path;
  }
}
let jsonCount = 0;
let linkCount = 0;
for (const path of filesIn(root)) {
  const extension = extname(path);
  if (extension === ".json") {
    JSON.parse(readFileSync(path, "utf8"));
    jsonCount++;
  }
  if (extension !== ".md") continue;
  const content = readFileSync(path, "utf8").replace(/```[\s\S]*?```/g, "");
  for (const [, rawTarget] of content.matchAll(/\]\(([^)]+)\)/g)) {
    const target = rawTarget.trim().replace(/^<|>$/g, "");
    if (/^[a-z][a-z0-9+.-]*:/i.test(target) || target.startsWith("#")) continue;
    const localPath = decodeURIComponent(target.split("#")[0]);
    assert.ok(existsSync(resolve(dirname(path), localPath)), `リンク先がありません: ${path} → ${target}`);
    linkCount++;
  }
}
const readJSON = (path) => JSON.parse(readFileSync(join(root, path), "utf8"));
assert.equal(readJSON("package.json").private, true);
assert.equal(readJSON("apps/backend/package.json").private, true);
assert.equal(readJSON("apps/backend/package.json").name, "@himatch/backend");
// この小さな workspace 設定で登録したディレクトリが実在することを確認する。
const workspace = readFileSync(join(root, "pnpm-workspace.yaml"), "utf8");
assert.equal(workspace.trim(), "packages:\n  - apps/backend");
assert.ok(statSync(join(root, "apps/backend")).isDirectory());

const requiredIOSFiles = [
  "apps/ios/Himatch.xcodeproj/project.pbxproj",
  "apps/ios/Himatch.xcodeproj/xcshareddata/xcschemes/Himatch.xcscheme",
  "apps/ios/Himatch/HimatchApp.swift",
  "apps/ios/HimatchTests/HimatchTests.swift",
  "scripts/ios/test.sh",
  "scripts/ios/release.sh",
  "scripts/ios/validate_signing_assets.py",
  "scripts/ios/tests/test_validate_signing_assets.py",
  ".github/workflows/ci-ios.yml",
  ".github/workflows/cd-ios-testflight.yml",
];
for (const path of requiredIOSFiles) {
  assert.ok(existsSync(join(root, path)), `iOS CI/CD の必須ファイルがありません: ${path}`);
}

const requiredAndroidFiles = [
  "apps/android/settings.gradle.kts",
  "apps/android/build.gradle.kts",
  "apps/android/gradlew",
  "apps/android/gradle/wrapper/gradle-wrapper.jar",
  "apps/android/gradle/wrapper/gradle-wrapper.properties",
  "apps/android/app/build.gradle.kts",
  "apps/android/app/src/main/AndroidManifest.xml",
  "apps/android/app/src/main/java/com/example/himatch/MainActivity.kt",
  "apps/android/app/src/test/java/com/example/himatch/MainActivityTest.kt",
  "scripts/android/test.sh",
  "scripts/android/release.sh",
  "scripts/android/upload-play.mjs",
  ".github/workflows/ci-android.yml",
  ".github/workflows/cd-android-play.yml",
];
for (const path of requiredAndroidFiles) {
  assert.ok(existsSync(join(root, path)), `Android CI/CD の必須ファイルがありません: ${path}`);
}

const iosCI = readFileSync(join(root, ".github/workflows/ci-ios.yml"), "utf8");
assert.match(iosCI, /runs-on: macos-26/);
assert.doesNotMatch(iosCI, /secrets\./, "pull request CI は配布 secret を参照できません");
assert.doesNotMatch(iosCI, /^\s+paths:/m, "required iOS check は path filter で skip できません");
const iosCD = readFileSync(join(root, ".github/workflows/cd-ios-testflight.yml"), "utf8");
assert.match(iosCD, /environment: testflight/);
assert.match(iosCD, /APP_STORE_CONNECT_PRIVATE_KEY_BASE64/);
assert.match(iosCD, /needs: test/);

const androidBuild = readFileSync(join(root, "apps/android/app/build.gradle.kts"), "utf8");
assert.match(androidBuild, /compileSdk = 37/);
assert.match(androidBuild, /targetSdk = 36/);
assert.match(androidBuild, /jvmToolchain\(21\)/);
const androidWrapper = readFileSync(join(root, "apps/android/gradle/wrapper/gradle-wrapper.properties"), "utf8");
assert.match(androidWrapper, /gradle-9\.6\.0-bin\.zip/);
assert.match(androidWrapper, /distributionSha256Sum=/);
const androidCI = readFileSync(join(root, ".github/workflows/ci-android.yml"), "utf8");
assert.doesNotMatch(androidCI, /secrets\./, "pull request CI はAndroid配布secretを参照できません");
assert.doesNotMatch(androidCI, /^\s+paths:/m, "required Android check はpath filterでskipできません");
assert.match(androidCI, /java-version: "21"/);
const androidCD = readFileSync(join(root, ".github/workflows/cd-android-play.yml"), "utf8");
assert.match(androidCD, /environment: play-internal/);
assert.match(androidCD, /ANDROID_PLAY_SERVICE_ACCOUNT_JSON_BASE64/);
assert.match(androidCD, /needs: test/);

const gitignore = readFileSync(join(root, ".gitignore"), "utf8");
for (const pattern of ["*.ipa", "*.xcarchive", "*.p12", "*.mobileprovision", "*.p8", "*.apk", "*.aab", "*.jks", "*.keystore"]) {
  assert.ok(gitignore.split("\n").includes(pattern), `秘密・配布成果物の ignore がありません: ${pattern}`);
}
console.log(`JSON ${jsonCount} 件、ローカル文書リンク ${linkCount} 件、workspace 登録: OK`);
console.log("iOS CI/CD 構成: OK");
console.log("Android CI/CD 構成: OK");
console.log("アプリの build/test は scripts/ios/test.sh と scripts/android/test.sh、API 互換性は公開契約実装後に検証します。");
