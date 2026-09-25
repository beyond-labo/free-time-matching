import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, dirname, resolve, extname } from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const ignored = new Set([".git", ".agents", ".codex", ".kiro", ".terraform", "node_modules", ".pnpm-store"]);
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
  "apps/backend/src/Friendship/Application/UseCase/ManageFriendships.ts",
  "apps/backend/src/Friendship/Infrastructure/Repository/SupabaseFriendshipRepository.ts",
  "apps/backend/src/Friendship/Presentation/FriendshipRoutes.ts",
  "apps/backend/src/Health/Presentation/healthRoute.ts",
  "apps/backend/test/friendship.worker.test.ts",
  "apps/backend/test/health.worker.test.ts",
  "apps/backend/tsconfig.json",
  "apps/backend/vitest.config.ts",
  "apps/backend/wrangler.jsonc",
  "apps/backend/worker-configuration.d.ts",
  "scripts/backend/smoke-health.mjs",
  "scripts/backend/smoke-health.test.mjs",
  "scripts/terraform/init-r2-backend.sh",
  ".github/workflows/ci-backend.yml",
  ".github/workflows/ci-supabase.yml",
  ".github/workflows/cd-backend-staging.yml",
  ".github/workflows/cd-backend-production.yml",
  "supabase/config.toml",
  "supabase/migrations/202609210001_auth_profile_and_deletion.sql",
  "supabase/migrations/202609230001_friendship.sql",
  "supabase/tests/auth_profile_and_deletion.test.sql",
  "supabase/tests/friendship.test.sql",
  "infra/cloudflare/README.md",
];
for (const path of requiredBackendFiles) {
  assert.ok(existsSync(join(root, path)), `Backend の必須ファイルがありません: ${path}`);
}

const migrationRoot = join(root, "supabase/migrations");
const destructiveMigrationPatterns = [
  /\bdrop\s+(?:table|schema|type)\b/i,
  /\balter\s+table\b[\s\S]*?\bdrop\s+column\b/i,
  /\balter\s+table\b[\s\S]*?\brename\s+(?:column\b|to\b)/i,
  /\btruncate(?:\s+table)?\b/i,
  /\bdelete\s+from\b/i,
  /\balter\s+table\b[\s\S]*?\balter\s+column\b[\s\S]*?\bset\s+not\s+null\b/i,
];
for (const path of filesIn(migrationRoot)) {
  if (extname(path) !== ".sql") continue;
  const source = readFileSync(path, "utf8");
  const reviewedMarker = /^\s*--\s*himatch: destructive-migration-reviewed\s*$/m;
  if (reviewedMarker.test(source)) continue;
  const executableSQL = source
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/--[^\n]*/g, " ")
    .replace(/'(?:''|[^'])*'/gs, "''");
  for (const pattern of destructiveMigrationPatterns) {
    assert.doesNotMatch(
      executableSQL,
      pattern,
      `破壊的なmigration候補です。expand / contractの承認後だけマーカーを付けてください: ${path}`,
    );
  }
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

const supabaseCI = readFileSync(join(root, ".github/workflows/ci-supabase.yml"), "utf8");
assert.match(supabaseCI, /^\s*workflow_call:/m);
assert.match(supabaseCI, /runs-on: ubuntu-24\.04/);
assert.match(supabaseCI, /version: 2\.117\.0/);
assert.match(supabaseCI, /supabase db start/);
assert.match(supabaseCI, /supabase db lint --local/);
assert.match(supabaseCI, /supabase test db --local/);
assert.doesNotMatch(supabaseCI, /pull_request_target/);
assert.doesNotMatch(supabaseCI, /secrets\./, "Supabase pull request CI はsecretを参照できません");
assert.doesNotMatch(supabaseCI, /vars\./, "Supabase pull request CI はEnvironment variableを参照できません");
assert.doesNotMatch(supabaseCI, /^\s+environment:/m, "Supabase pull request CI はprotected Environmentを参照できません");

const backendStagingCD = readFileSync(join(root, ".github/workflows/cd-backend-staging.yml"), "utf8");
assert.match(backendStagingCD, /group: backend-staging/);
assert.match(backendStagingCD, /environment: staging/);
assert.match(backendStagingCD, /verify-supabase/);
assert.match(backendStagingCD, /supabase db push --linked --dry-run --skip-vault/);
assert.match(backendStagingCD, /supabase db push --linked --skip-vault --yes/);
assert.match(backendStagingCD, /supabase migration list --linked/);
assert.match(backendStagingCD, /wrangler deploy --env staging/);
assert.match(backendStagingCD, /--secrets-file/);
assert.match(backendStagingCD, /SUPABASE_URL/);
assert.match(backendStagingCD, /smoke-health\.mjs/);
assert.match(backendStagingCD, /BACKEND_HEALTH_MAX_ATTEMPTS/);
assert.ok(
  backendStagingCD.indexOf("Apply Terraform changes") <
    backendStagingCD.indexOf("Apply Supabase migrations to staging") &&
    backendStagingCD.indexOf("Apply Supabase migrations to staging") <
      backendStagingCD.indexOf("Deploy Worker to staging"),
  "stagingはTerraform、DB migration、Workerの順で配備してください",
);
assert.match(backendStagingCD, /Partial release requires attention/);
assert.match(backendStagingCD, /steps\.database-migration\.outcome != 'skipped'/);
assert.ok(
  backendStagingCD.split("supabase migration list --linked").length - 1 >= 2,
  "stagingは通常適用後と失敗時復旧の両方でlinked migration履歴を確認してください",
);
for (const setting of [
  "SUPABASE_PROJECT_REF",
  "SUPABASE_URL",
  "SUPABASE_PUBLISHABLE_KEY",
  "SUPABASE_SECRET_KEY",
  "APPLE_CLIENT_ID",
  "APPLE_TEAM_ID",
  "APPLE_KEY_ID",
  "APPLE_PRIVATE_KEY",
  "ACCOUNT_DELETION_STATUS_SECRET",
]) {
  assert.match(backendStagingCD, new RegExp(`\\b${setting}\\b`), `staging CDに${setting}がありません`);
}

const backendProductionCD = readFileSync(join(root, ".github/workflows/cd-backend-production.yml"), "utf8");
assert.match(backendProductionCD, /group: backend-production/);
assert.match(backendProductionCD, /environment: production-plan/);
assert.match(backendProductionCD, /environment: production/);
assert.match(backendProductionCD, /verify-supabase/);
assert.match(backendProductionCD, /git merge-base --is-ancestor/);
assert.match(backendProductionCD, /terraform plan -lock=false -detailed-exitcode/);
assert.match(backendProductionCD, /supabase db push --linked --dry-run --skip-vault/);
assert.match(backendProductionCD, /supabase db push --linked --skip-vault --yes/);
assert.match(backendProductionCD, /supabase migration list --linked/);
assert.match(backendProductionCD, /wrangler deploy --env production/);
assert.match(backendProductionCD, /--secrets-file/);
assert.match(backendProductionCD, /BACKEND_HEALTH_MAX_ATTEMPTS/);
assert.ok(
  backendProductionCD.indexOf("Recalculate and apply Terraform changes") <
    backendProductionCD.indexOf("Apply Supabase migrations to production") &&
    backendProductionCD.indexOf("Apply Supabase migrations to production") <
      backendProductionCD.indexOf("Deploy Worker to production"),
  "productionはTerraform、DB migration、Workerの順で配備してください",
);
assert.match(backendProductionCD, /Partial release requires attention/);
assert.match(backendProductionCD, /steps\.database-migration\.outcome != 'skipped'/);
assert.ok(
  backendProductionCD.split("supabase migration list --linked").length - 1 >= 2,
  "productionは通常適用後と失敗時復旧の両方でlinked migration履歴を確認してください",
);
for (const setting of [
  "SUPABASE_PROJECT_REF",
  "SUPABASE_URL",
  "SUPABASE_PUBLISHABLE_KEY",
  "SUPABASE_SECRET_KEY",
  "APPLE_CLIENT_ID",
  "APPLE_TEAM_ID",
  "APPLE_KEY_ID",
  "APPLE_PRIVATE_KEY",
  "ACCOUNT_DELETION_STATUS_SECRET",
]) {
  assert.match(backendProductionCD, new RegExp(`\\b${setting}\\b`), `production CDに${setting}がありません`);
}
const productionPlanJob = backendProductionCD.match(
  /\n  production-plan:[\s\S]*?\n  apply-and-deploy:/,
)?.[0];
assert.ok(productionPlanJob, "production-plan jobを検出できません");
assert.doesNotMatch(
  productionPlanJob,
  /BACKEND_HEALTH_URL/,
  "production-planへBACKEND_HEALTH_URLを登録しないでください",
);
assert.doesNotMatch(
  productionPlanJob,
  /SUPABASE_(ACCESS_TOKEN|DB_PASSWORD)/,
  "production-planへSupabaseの変更資格情報を登録しないでください",
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

const backendWorkflows = [backendCI, supabaseCI, backendStagingCD, backendProductionCD];
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
  "apps/ios/Himatch/Friendship/Application/Port/FriendshipClient.swift",
  "apps/ios/Himatch/Friendship/Infrastructure/Adapter/BackendFriendshipAdapter.swift",
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
const iosTestRoot = join(root, "apps/ios/HimatchTests");
const iosTestSources = [...filesIn(iosTestRoot)].filter((path) => extname(path) === ".swift");
assert.ok(iosTestSources.length > 0, "Swift Testing のテストがありません");
for (const path of iosTestSources) {
  const content = readFileSync(path, "utf8");
  assert.doesNotMatch(content, /\bimport\s+XCTest\b/, `iOS テストで XCTest を import しています: ${path}`);
  assert.doesNotMatch(content, /\bXCTestCase\b/, `iOS テストで XCTestCase を使用しています: ${path}`);
  assert.match(content, /\bimport\s+Testing\b/, `iOS テストは Swift Testing を import してください: ${path}`);
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
assert.match(iosCD, /SUPABASE_URL/);
assert.match(iosCD, /SUPABASE_PUBLISHABLE_KEY/);
assert.match(iosCD, /API_BASE_URL/);
assert.match(iosCD, /git merge-base --is-ancestor/);
assert.match(iosCD, /release tag must be annotated/);
assert.match(iosCD, /\^ios-v\[0-9\]\+\\\.\[0-9\]\+\\\.\[0-9\]\+\$/);
assert.ok(
  iosCD.split("ref: ${{ needs.preflight.outputs.commit_sha }}").length - 1 >= 2,
  "iOS testとreleaseはpreflightで確定したcommitをcheckoutしてください",
);
const iosRelease = readFileSync(join(root, "scripts/ios/release.sh"), "utf8");
for (const setting of ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "API_BASE_URL"]) {
  assert.match(iosRelease, new RegExp(`\\b${setting}\\b`), `iOS release scriptに${setting}がありません`);
}

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
  "supabase/.branches/",
  "supabase/.temp/",
]) {
  assert.ok(gitignore.split("\n").includes(pattern), `秘密・配布成果物の ignore がありません: ${pattern}`);
}
console.log(`JSON ${jsonCount} 件、ローカル文書リンク ${linkCount} 件、workspace 登録: OK`);
console.log("Backend Worker 構成: OK");
console.log("Backend / Cloudflare CI/CD 構成: OK");
console.log("iOS CI/CD 構成: OK");
console.log(`iOS Swift Testing ${iosTestSources.length} ファイル: OK`);
console.log("Android CI/CD 構成: OK");
console.log("アプリの build/test は scripts/ios/test.sh と scripts/android/test.sh、API 互換性は公開契約実装後に検証します。");
