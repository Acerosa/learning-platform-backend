import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const content = require("../../../../learning-platform-content/dist/learning-platform-content.cjs.js");
const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");

function load(relative) {
  return JSON.parse(readFileSync(join(root, "..", relative), "utf8"));
}

test("converted Unit 3 and T Level packages validate against lp.content", () => {
  const unit3 = load("unit-3-Cyber-Security-Hub/content/unit-3-cyber-security/package.json");
  const tlevel = load("tlevel-software-development-hub/content/tlevel-software-development/package.json");
  const unit3Result = content.validatePackage(unit3);
  const tlevelResult = content.validatePackage(tlevel);
  assert.equal(unit3Result.valid, true, content.formatIssues?.(unit3Result.issues) || JSON.stringify(unit3Result.issues));
  assert.equal(tlevelResult.valid, true, content.formatIssues?.(tlevelResult.issues) || JSON.stringify(tlevelResult.issues));
  assert.equal(unit3.hub.id, "unit-3-cyber-security");
  assert.equal(tlevel.curriculum.metadata.course, "t-level-digital-software-development");
  assert.equal(unit3.version, "0.2.0");
  assert.equal(tlevel.version, "0.2.0");
});
