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
assert.equal(
  workspace.trim(),
  "packages:\n  - apps/backend\nallowBuilds:\n  esbuild: true\n  workerd: true",
);
assert.ok(statSync(join(root, "apps/backend")).isDirectory());

const backendPackage = readJSON("apps/backend/package.json");
const requiredBackendScripts = {
  dev: "wrangler dev",
  types: "wrangler types && node scripts/normalize-generated-types.mjs",
  typecheck: "tsc --noEmit",
  test: "vitest run && node --test ../../scripts/backend/smoke-health.test.mjs",
  build: "wrangler deploy --dry-run --outdir dist",
};
for (const [name, command] of Object.entries(requiredBackendScripts)) {
  assert.equal(
    backendPackage.scripts?.[name],
    command,
    `Backend script がありません、または契約と異なります: ${name}`,
  );
}
assert.equal(backendPackage.dependencies?.hono, "4.13.7");
assert.equal(backendPackage.devDependencies?.["@cloudflare/vitest-plugin"], "1.1.13");
assert.equal(backendPackage.devDependencies?.typescript, "7.0.2");
assert.equal(backendPackage.devDependencies?.wrangler, "4.129.1");
const requiredBackendFiles = [
  "apps/backend/README.md",
  "apps/backend/scripts/normalize-generated-types.mjs",
  "apps/backend/src/EntryPoint/index.ts",
  "apps/backend/src/Composition/createApp.ts",
  "apps/backend/src/Health/Presentation/healthRoute.ts",
  "apps/backend/test/health.worker.test.ts",
  "apps/backend/tsconfig.json",
  "apps/backend/vitest.config.ts",
  "apps/backend/wrangler.jsonc",
  "apps/backend/worker-configuration.d.ts",
  "scripts/backend/smoke-health.mjs",
  "scripts/backend/smoke-health.test.mjs",
  "scripts/terraform/init-r2-backend.sh",
  ".github/workflows/ci-backend.yml",
  ".github/workflows/cd-backend-staging.yml",
  ".github/workflows/cd-backend-production.yml",
  "infra/cloudflare/README.md",
];
for (const path of requiredBackendFiles) {
  assert.ok(existsSync(join(root, path)), `Backend の必須ファイルがありません: ${path}`);
}
const backendWrangler = readFileSync(join(root, "apps/backend/wrangler.jsonc"), "utf8");
const backendWranglerConfig = JSON.parse(backendWrangler);
assert.match(backendWrangler, /"main"\s*:\s*"src\/EntryPoint\/index\.ts"/);
assert.match(backendWrangler, /"staging"\s*:\s*\{/);
assert.match(backendWrangler, /"name"\s*:\s*"himatch-backend-staging"/);
assert.match(backendWrangler, /"production"\s*:\s*\{/);
assert.match(backendWrangler, /"name"\s*:\s*"himatch-backend-production"/);
assert.match(backendWrangler, /"workers_dev"\s*:\s*false/);
assert.match(backendWrangler, /"pattern"\s*:\s*"api-staging\.beyond-labo\.com"/);
assert.match(backendWrangler, /"pattern"\s*:\s*"api\.beyond-labo\.com"/);
assert.equal(
  (backendWrangler.match(/"custom_domain"\s*:\s*true/g) ?? []).length,
  2,
  "stagingとproductionのCustom DomainをWranglerだけで定義してください",
);
assert.equal(backendWranglerConfig.workers_dev, false);
assert.deepEqual(backendWranglerConfig.env.staging, {
  name: "himatch-backend-staging",
  workers_dev: false,
  routes: [{ pattern: "api-staging.beyond-labo.com", custom_domain: true }],
});
assert.deepEqual(backendWranglerConfig.env.production, {
  name: "himatch-backend-production",
  workers_dev: false,
  routes: [{ pattern: "api.beyond-labo.com", custom_domain: true }],
});

const terraformEnvironments = ["staging", "production"];
for (const environment of terraformEnvironments) {
  const terraformRoot = `infra/cloudflare/environments/${environment}`;
  for (const file of [
    ".terraform.lock.hcl",
    "backend.tf",
    "main.tf",
    "outputs.tf",
    "providers.tf",
    "variables.tf",
    "versions.tf",
  ]) {
    assert.ok(existsSync(join(root, terraformRoot, file)), `Terraform の必須ファイルがありません: ${terraformRoot}/${file}`);
  }

  const backendConfiguration = readFileSync(join(root, terraformRoot, "backend.tf"), "utf8");
  assert.match(backendConfiguration, /backend\s+"s3"/);
  assert.doesNotMatch(backendConfiguration, /use_lockfile/, "R2 native lock は実環境検証後にだけ有効化します");

  const providerVersions = readFileSync(join(root, terraformRoot, "versions.tf"), "utf8");
  assert.match(providerVersions, /version\s*=\s*"5\.23\.0"/);
}

const backendCI = readFileSync(join(root, ".github/workflows/ci-backend.yml"), "utf8");
assert.match(backendCI, /^\s*workflow_call:/m);
assert.match(backendCI, /runs-on: ubuntu-24\.04/);
assert.doesNotMatch(backendCI, /pull_request_target/);
assert.doesNotMatch(backendCI, /secrets\./, "Backend pull request CI はsecretを参照できません");
assert.doesNotMatch(backendCI, /vars\./, "Backend pull request CI はEnvironment variableを参照できません");
assert.doesNotMatch(backendCI, /^\s+environment:/m, "Backend pull request CI はprotected Environmentを参照できません");

const backendStagingCD = readFileSync(join(root, ".github/workflows/cd-backend-staging.yml"), "utf8");
assert.match(backendStagingCD, /group: backend-staging/);
assert.match(backendStagingCD, /environment: staging/);
assert.match(backendStagingCD, /needs: verify/);
assert.match(backendStagingCD, /wrangler deploy --env staging/);
assert.match(backendStagingCD, /smoke-health\.mjs/);
assert.match(backendStagingCD, /BACKEND_HEALTH_MAX_ATTEMPTS/);

const backendProductionCD = readFileSync(join(root, ".github/workflows/cd-backend-production.yml"), "utf8");
assert.match(backendProductionCD, /group: backend-production/);
assert.match(backendProductionCD, /environment: production-plan/);
assert.match(backendProductionCD, /environment: production/);
assert.match(backendProductionCD, /git merge-base --is-ancestor/);
assert.match(backendProductionCD, /terraform plan -lock=false -detailed-exitcode/);
assert.match(backendProductionCD, /wrangler deploy --env production/);
assert.match(backendProductionCD, /BACKEND_HEALTH_MAX_ATTEMPTS/);
const productionPlanJob = backendProductionCD.match(
  /\n  production-plan:[\s\S]*?\n  apply-and-deploy:/,
)?.[0];
assert.ok(productionPlanJob, "production-plan jobを検出できません");
assert.doesNotMatch(
  productionPlanJob,
  /BACKEND_HEALTH_URL/,
  "production-planへBACKEND_HEALTH_URLを登録しないでください",
);

for (const terraformRoot of [
  "infra/cloudflare",
  "infra/cloudflare/environments/staging",
  "infra/cloudflare/environments/production",
]) {
  for (const path of filesIn(join(root, terraformRoot))) {
    if (extname(path) !== ".tf") continue;
    const terraformSource = readFileSync(path, "utf8");
    assert.doesNotMatch(
      terraformSource,
      /cloudflare_(record|dns_record|workers_route|workers_custom_domain)/,
      "DNS、Route、Custom DomainはWranglerだけで管理してください",
    );
  }
}

const backendWorkflows = [backendCI, backendStagingCD, backendProductionCD];
for (const workflow of backendWorkflows) {
  assert.doesNotMatch(workflow, /pull_request_target/);
  assert.doesNotMatch(workflow, /actions\/upload-artifact/);
  assert.doesNotMatch(workflow, /use_lockfile/);
  for (const [, action] of workflow.matchAll(/^\s*-?\s*uses:\s*([^\s#]+)/gm)) {
    if (action.startsWith("./")) continue;
    assert.match(action, /@[0-9a-f]{40}$/, `Action は完全な commit SHA に固定してください: ${action}`);
  }
}

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
for (const pattern of [
  "*.ipa",
  "*.xcarchive",
  "*.p12",
  "*.mobileprovision",
  "*.p8",
  "*.apk",
  "*.aab",
  "*.jks",
  "*.keystore",
  ".terraform/",
  "*.tfstate",
  "*.tfstate.*",
  "*.tfplan",
  "*.tfvars",
  "*.tfvars.json",
]) {
  assert.ok(gitignore.split("\n").includes(pattern), `秘密・配布成果物の ignore がありません: ${pattern}`);
}
console.log(`JSON ${jsonCount} 件、ローカル文書リンク ${linkCount} 件、workspace 登録: OK`);
console.log("Backend Worker 構成: OK");
console.log("Backend / Cloudflare CI/CD 構成: OK");
console.log("iOS CI/CD 構成: OK");
console.log("Android CI/CD 構成: OK");
console.log("アプリの build/test は scripts/ios/test.sh と scripts/android/test.sh、API 互換性は公開契約実装後に検証します。");
