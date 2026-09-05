import assert from "node:assert/strict";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const readJSON = (path) => JSON.parse(readFileSync(join(root, path), "utf8"));
const rootPackage = readJSON("package.json");
const backendPackage = readJSON("apps/backend/package.json");
readJSON("apps/backend/tsconfig.json");
assert.equal(rootPackage.private, true);
assert.equal(backendPackage.private, true);
assert.equal(backendPackage.name, "@himatch/backend");
assert.equal(backendPackage.exports, undefined, "Backend を共有パッケージとして公開しないでください。");
assert.ok(!existsSync(join(root, "packages/contracts")), "API 契約は Backend が所有します。");

const requiredDirectories = [
  "apps/backend/src/auth/domain",
  "apps/backend/src/auth/application",
  "apps/backend/src/auth/infrastructure",
  "apps/backend/src/users/domain",
  "apps/backend/src/users/application",
  "apps/backend/src/users/infrastructure",
  "apps/backend/src/friendships/domain",
  "apps/backend/src/friendships/application",
  "apps/backend/src/friendships/infrastructure",
  "apps/backend/src/availability/domain",
  "apps/backend/src/availability/application",
  "apps/backend/src/availability/infrastructure",
  "apps/backend/src/hostings/domain",
  "apps/backend/src/hostings/application",
  "apps/backend/src/hostings/infrastructure",
  "apps/backend/src/notifications/domain",
  "apps/backend/src/notifications/application",
  "apps/backend/src/notifications/infrastructure",
  "apps/backend/src/account-deletion/domain",
  "apps/backend/src/account-deletion/application",
  "apps/backend/src/account-deletion/infrastructure",
  "apps/backend/src/interfaces/http/routes",
  "apps/backend/src/interfaces/http/schemas",
  "apps/backend/src/interfaces/http/presenters",
  "apps/backend/src/interfaces/http/errors",
  "apps/backend/src/infrastructure/database",
  "apps/backend/src/infrastructure/messaging",
  "apps/backend/src/infrastructure/notifications",
  "apps/backend/src/infrastructure/observability",
  "apps/backend/openapi/examples/authentication",
  "apps/backend/openapi/examples/availability",
  "apps/backend/openapi/examples/hostings",
  "apps/backend/test/unit",
  "apps/backend/test/integration",
  "apps/backend/test/contract",
  "apps/ios/Himatch/App",
  "apps/ios/Himatch/Core/API/Mappers",
  "apps/ios/Himatch/Core/API/Generated",
  "apps/ios/Himatch/Resources",
  "apps/ios/HimatchTests",
  "infra/bootstrap",
  "infra/modules",
  "infra/environments"
];
for (const directory of requiredDirectories) {
  assert.ok(existsSync(join(root, directory)), `配置がありません: ${directory}`);
}
const workspace = readFileSync(join(root, "pnpm-workspace.yaml"), "utf8");
assert.match(workspace, /- apps\/backend\s/);
assert.doesNotMatch(workspace, /apps\/ios/);
for (const directory of ["docs/product", "docs/architecture", "docs/operations"]) {
  assert.ok(readdirSync(join(root, directory)).some((file) => file.endsWith(".md")));
}
console.log("構成と JSON の検証に成功しました。アプリのテスト、ビルド、API 互換性は未検証です。");
