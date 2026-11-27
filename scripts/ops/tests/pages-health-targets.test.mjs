import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));

test("pages health fleet config lists hubs and admin, excludes docs-only", async () => {
  const raw = await readFile(resolve(root, "../pages-health-targets.json"), "utf8");
  const config = JSON.parse(raw);
  assert.ok(Array.isArray(config.targets));
  const names = config.targets.map((target) => target.name);
  assert.ok(names.includes("tlevel-software-development-hub"));
  assert.ok(names.includes("unit-3-Cyber-Security-Hub"));
  assert.ok(names.includes("Emerging-Digital-Technologies-Hub"));
  assert.ok(names.includes("unit-14-software-engineering-for-business-hub"));
  assert.ok(names.includes("learning-platform-admin"));
  assert.equal(config.targets.every((target) => target.kind !== "docs-only"), true);
  assert.equal(
    config.targets.every((target) => target.pages?.expectedSource === "workflow"),
    true
  );
});
