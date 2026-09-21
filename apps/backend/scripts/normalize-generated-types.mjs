import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const generatedTypesPath = fileURLToPath(
  new URL("../worker-configuration.d.ts", import.meta.url),
);
const generatedTypes = readFileSync(generatedTypesPath, "utf8");
const normalizedTypes = generatedTypes.replace(/[\t ]+$/gm, "");

if (normalizedTypes !== generatedTypes) {
  writeFileSync(generatedTypesPath, normalizedTypes);
}
