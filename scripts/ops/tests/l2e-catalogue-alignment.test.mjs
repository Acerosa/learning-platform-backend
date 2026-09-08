/**
 * Contract: curriculum packages must be able to produce an authoritative
 * marking-spec manifest matching catalogue projection rules
 * (classification → questionId:itemId).
 *
 * Fixture mirrors the L2E expanded Weeks 2–3 failure mode without hosting state.
 */

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const PKG_PATH = join(
  ROOT,
  "supabase/data/generated/l2e-expanded-weeks-0.3.13.package.json"
);

const SERVER_MARKED = new Set([
  "single-choice",
  "classification",
  "short-response",
  "reflection",
  "code-editor",
  "python-exercise",
  "drag-drop"
]);

function markingManifest(pkg) {
  const issues = [];
  const keys = new Set();
  const activityPairs = new Set();
  for (const activity of pkg.activities || []) {
    const pair = `${activity.id}@${activity.version}`;
    if (activityPairs.has(pair)) issues.push(`duplicate ${pair}`);
    activityPairs.add(pair);
    for (const block of activity.blocks || []) {
      if (!SERVER_MARKED.has(block.type)) continue;
      const content = block.content || {};
      const qid = String(content.questionId || "").trim();
      if (!qid) {
        issues.push(`${pair} missing questionId for ${block.type}`);
        continue;
      }
      if (block.type === "classification" || block.type === "drag-drop") {
        for (const item of content.items || []) {
          const key = `${qid}:${item.id}`;
          if (keys.has(key)) issues.push(`duplicate key ${key}`);
          keys.add(key);
        }
      } else {
        if (keys.has(qid)) issues.push(`duplicate key ${qid}`);
        keys.add(qid);
      }
    }
  }
  return { issues, keys, activityPairs };
}

test("generated L2E 0.3.13 package produces a coherent marking manifest", () => {
  const pkg = JSON.parse(readFileSync(PKG_PATH, "utf8"));
  const { issues, keys, activityPairs } = markingManifest(pkg);
  assert.equal(issues.length, 0, issues.join("\n"));
  assert.equal(activityPairs.size, 39);
  assert.ok(keys.has("week-1-digital-match:d-iot"));
  assert.ok(keys.has("week-2-iot-sectors-q:s1"));
  assert.ok(keys.has("week-2-starter-q1"));
  assert.ok(keys.has("week-3-local-q:l1"));
  assert.ok(keys.has("week-3-models-q:m1"));
  assert.ok(keys.has("week-3-starter-q1"));
  assert.ok(activityPairs.has("week-2-reflection@0.1.1"));
  assert.ok(activityPairs.has("week-2-starter@0.1.0"));
  assert.ok(activityPairs.has("week-3-local-vs-cloud@0.1.0"));
});

test("generated L2E package excludes stale Weeks 2–3 catalogue ids", () => {
  const pkg = JSON.parse(readFileSync(PKG_PATH, "utf8"));
  const ids = new Set(pkg.activities.map((a) => a.id));
  for (const stale of [
    "week-2-classify",
    "week-2-outline",
    "week-2-retrieval",
    "week-3-classify",
    "week-3-outline",
    "week-3-retrieval"
  ]) {
    assert.equal(ids.has(stale), false, stale);
  }
});

test("publication rejects package/catalogue mismatch signals in fixture", () => {
  const pkg = JSON.parse(readFileSync(PKG_PATH, "utf8"));
  const broken = structuredClone(pkg);
  const activity = broken.activities.find((a) => a.id === "week-2-starter");
  const block = activity.blocks.find((b) => b.type === "single-choice");
  delete block.content.questionId;
  const { issues } = markingManifest(broken);
  assert.ok(issues.some((i) => i.includes("missing questionId")));
});
