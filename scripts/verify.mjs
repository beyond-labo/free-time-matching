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
console.log(`JSON ${jsonCount} 件、ローカル文書リンク ${linkCount} 件、workspace 登録: OK`);
console.log("アプリのビルド、テスト、API 互換性は未検証です。");
