import assert from "node:assert/strict";
import test from "node:test";
import {
  browserChecklist,
  collectAcceptanceEnv,
  evaluateLearnerIsolation,
  runAcceptance
} from "../authenticated-qa-acceptance.mjs";
import { maskEmail } from "../synthetic-qa-provision.mjs";

test("collectAcceptanceEnv reports missing learner and staff secrets without values", () => {
  const plan = collectAcceptanceEnv({
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_PUBLISHABLE_KEY: "publishable"
  });
  assert.equal(plan.learners.length, 0);
  assert.ok(plan.missingLearners.length >= 5);
  assert.equal(plan.staff, null);
  assert.ok(plan.staffMissing.includes("STAFF_QA_EMAIL"));
});

test("collectAcceptanceEnv accepts alternate SYNTHETIC_QA_* names", () => {
  const plan = collectAcceptanceEnv({
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_PUBLISHABLE_KEY: "publishable",
    SYNTHETIC_QA_EMAIL_UNIT3: "unit3@example.test",
    SYNTHETIC_QA_PASSWORD_UNIT3: "not-a-real-secret",
    STAFF_QA_EMAIL: "staff@example.test",
    STAFF_QA_PASSWORD: "not-a-real-secret"
  });
  assert.equal(plan.learners.length, 1);
  assert.equal(plan.learners[0].persona, "UNIT3_TEST_LEARNER");
  assert.equal(plan.learners[0].emailEnv, "SYNTHETIC_QA_EMAIL_UNIT3");
  assert.ok(plan.staff);
});

test("evaluateLearnerIsolation fails closed on unexpected active groups", () => {
  const result = evaluateLearnerIsolation(
    { groupCode: "CYBER-TEST-QA" },
    {
      enrolments: [
        { group_code: "CYBER-TEST-QA", status: "active" },
        { group_code: "TLEVEL-DSD-Y2", status: "active" }
      ]
    }
  );
  assert.equal(result.ok, false);
  assert.deepEqual(result.extras, ["TLEVEL-DSD-Y2"]);
});

test("runAcceptance skips without printing credential material", async () => {
  const lines = [];
  const results = await runAcceptance({
    env: { PATH: "/usr/bin" },
    loadDotEnv: false,
    log: (line) => lines.push(String(line))
  });
  assert.equal(results.status, "SKIPPED");
  assert.ok(results.blockers.length >= 1);
  assert.ok(browserChecklist().length >= 8);
  const joined = lines.join("\n");
  assert.match(joined, /SKIPPED/);
  assert.doesNotMatch(joined, /service_role|eyJ[A-Za-z0-9_-]{10,}/i);
  assert.doesNotMatch(joined, /@[a-z0-9.-]+\.[a-z]{2,}/i);
});

test("maskEmail never echoes a full mailbox", () => {
  assert.equal(maskEmail("qa.unit3@example.test"), "qa…@example.test");
});
