/**
 * Authenticated QA acceptance harness for synthetic learners (and optional staff).
 *
 * - Uses gitignored env credentials only.
 * - Never logs passwords, tokens, service-role keys, or full emails.
 * - Skips cleanly when approved secrets are absent.
 * - Does not create Auth users (provision:synthetic-qa owns that, after approval).
 */

import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createClient } from "@supabase/supabase-js";
import { PERSONAS } from "./synthetic-qa-config.mjs";
import { maskEmail, maskId } from "./synthetic-qa-provision.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../..");

export const STAFF_EMAIL_ENV = ["STAFF_QA_EMAIL", "ADMIN_QA_EMAIL"];
export const STAFF_PASSWORD_ENV = ["STAFF_QA_PASSWORD", "ADMIN_QA_PASSWORD"];

function loadLocalEnv(env) {
  const path = join(ROOT, ".env");
  if (!existsSync(path)) return { ...env };
  const next = { ...env };
  for (const raw of readFileSync(path, "utf8").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq <= 0) continue;
    const name = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (
      (value.startsWith("\"") && value.endsWith("\""))
      || (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!String(next[name] || "").trim()) next[name] = value;
  }
  return next;
}

function envValue(env, name) {
  return String(env[name] || "").trim();
}

function firstPresent(env, names) {
  for (const name of names) {
    const value = envValue(env, name);
    if (value) return { name, value };
  }
  return null;
}

export function collectAcceptanceEnv(env, personas = PERSONAS) {
  const present = [];
  const missingLearners = [];
  for (const persona of personas) {
    const email = firstPresent(env, persona.emailEnv);
    const password = firstPresent(env, persona.passwordEnv);
    if (email && password) {
      present.push({
        persona: persona.persona,
        groupCode: persona.groupCode,
        smokeActivityKey: persona.smokeActivityKey,
        studentNumber: persona.studentNumber,
        emailEnv: email.name,
        passwordEnv: password.name,
        email: email.value,
        password: password.value
      });
    } else {
      missingLearners.push({
        persona: persona.persona,
        missing: [
          ...(email ? [] : [persona.emailEnv[0]]),
          ...(password ? [] : [persona.passwordEnv[0]])
        ]
      });
    }
  }

  const staffEmail = firstPresent(env, STAFF_EMAIL_ENV);
  const staffPassword = firstPresent(env, STAFF_PASSWORD_ENV);
  const staff = staffEmail && staffPassword
    ? {
      emailEnv: staffEmail.name,
      passwordEnv: staffPassword.name,
      email: staffEmail.value,
      password: staffPassword.value
    }
    : null;

  return {
    supabaseUrl: envValue(env, "SUPABASE_URL") || envValue(env, "NEXT_PUBLIC_SUPABASE_URL"),
    publishableKey:
      envValue(env, "SUPABASE_PUBLISHABLE_KEY")
      || envValue(env, "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY")
      || envValue(env, "SUPABASE_ANON_KEY"),
    learners: present,
    missingLearners,
    staff,
    staffMissing: staff
      ? []
      : [STAFF_EMAIL_ENV[0], STAFF_PASSWORD_ENV[0]]
  };
}

export function browserChecklist() {
  return [
    "Learner sign-in on each published hub",
    "Enrolment recognition for the intended group only",
    "Correct-answer feedback visible in the browser",
    "Incorrect-answer feedback visible in the browser",
    "Foundations language-aware marking (Python / JavaScript / C#)",
    "Progress persistence across refresh",
    "Session restoration after reload",
    "Sign-out",
    "Staff sign-in on Admin Portal",
    "Dashboard / student / enrolment / curriculum / assignment views",
    "Progress and assessment reporting (filter is_synthetic)",
    "Marking coverage diagnostics",
    "Group Generator: create session, QR/join, publish, close (isolated records)"
  ];
}

export async function signInLearner(client, { email, password }) {
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error || !data?.session?.access_token) {
    return { ok: false, code: "AUTH_FAILED", userId: null };
  }
  return {
    ok: true,
    code: "AUTH_OK",
    userId: data.user?.id || null
  };
}

export async function fetchLearnerContext(client) {
  const profile = await client.schema("api").from("my_profile").select("*").maybeSingle();
  const enrolments = await client.schema("api").from("my_enrolments").select("group_code,status,hub_code");
  return {
    profileError: profile.error?.message || null,
    enrolmentsError: enrolments.error?.message || null,
    profile: profile.data || null,
    enrolments: Array.isArray(enrolments.data) ? enrolments.data : []
  };
}

export function evaluateLearnerIsolation(persona, context) {
  const active = (context.enrolments || []).filter((row) => String(row.status || "") === "active");
  const codes = active.map((row) => String(row.group_code || "").trim()).filter(Boolean);
  const intended = persona.groupCode;
  const hasIntended = codes.includes(intended);
  const extras = codes.filter((code) => code !== intended);
  return {
    hasIntended,
    extras,
    ok: hasIntended && extras.length === 0,
    codes
  };
}

export async function runAcceptance({
  env = process.env,
  createClientFn = createClient,
  log = console.log,
  requireCredentials = false,
  loadDotEnv = true
} = {}) {
  const merged = loadDotEnv ? loadLocalEnv(env) : { ...env };
  const plan = collectAcceptanceEnv(merged);
  const results = {
    status: "SKIPPED",
    learners: [],
    staff: null,
    blockers: [],
    checklist: browserChecklist()
  };

  if (!plan.learners.length) {
    results.blockers.push(
      "Approved synthetic learner credentials are not configured in the local environment."
    );
  }
  if (!plan.staff) {
    results.blockers.push(
      "Approved staff QA credentials are not configured (STAFF_QA_EMAIL / STAFF_QA_* secret)."
    );
  }
  if (!plan.supabaseUrl || !plan.publishableKey) {
    results.blockers.push(
      "SUPABASE_URL and a publishable/anon key are required for authenticated acceptance sign-in."
    );
  }

  if (results.blockers.length) {
    log("Authenticated QA acceptance: SKIPPED");
    for (const blocker of results.blockers) log(`  - ${blocker}`);
    log("  Configure gitignored .env per docs/audits/qa-acceptance/AUTHENTICATED_QA_PLAN.md");
    log("  Browser checklist:");
    for (const item of results.checklist) log(`    • ${item}`);
    if (requireCredentials) {
      const err = new Error("AUTHENTICATED_QA_CREDENTIALS_REQUIRED");
      err.code = "AUTHENTICATED_QA_CREDENTIALS_REQUIRED";
      throw err;
    }
    return results;
  }

  const client = createClientFn(plan.supabaseUrl, plan.publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
  });

  results.status = "RAN";
  for (const learner of plan.learners) {
    const signed = await signInLearner(client, learner);
    const entry = {
      persona: learner.persona,
      email: maskEmail(learner.email),
      auth: signed.code,
      userId: maskId(signed.userId),
      isolation: null,
      notes: []
    };
    if (!signed.ok) {
      entry.notes.push("Sign-in failed; password may be wrong or Auth user missing.");
      results.learners.push(entry);
      await client.auth.signOut().catch(() => {});
      continue;
    }
    const context = await fetchLearnerContext(client);
    if (context.profileError || context.enrolmentsError) {
      entry.notes.push("Profile/enrolment read failed under learner JWT.");
    }
    const isolation = evaluateLearnerIsolation(learner, context);
    entry.isolation = isolation.ok ? "PASS" : "FAIL";
    if (!isolation.hasIntended) {
      entry.notes.push(`Missing intended group ${learner.groupCode}.`);
    }
    if (isolation.extras.length) {
      entry.notes.push(`Unexpected active groups: ${isolation.extras.join(", ")}`);
    }
    results.learners.push(entry);
    await client.auth.signOut().catch(() => {});
  }

  if (plan.staff) {
    const signed = await signInLearner(client, plan.staff);
    results.staff = {
      email: maskEmail(plan.staff.email),
      auth: signed.code,
      userId: maskId(signed.userId),
      notes: signed.ok
        ? ["Staff Auth OK — complete Admin Portal / Group Generator browser checklist."]
        : ["Staff sign-in failed."]
    };
    await client.auth.signOut().catch(() => {});
  }

  log("Authenticated QA acceptance:");
  for (const row of results.learners) {
    log(`  ${row.persona}: auth=${row.auth} isolation=${row.isolation || "n/a"} user=${row.userId}`);
    for (const note of row.notes) log(`    - ${note}`);
  }
  if (results.staff) {
    log(`  STAFF: auth=${results.staff.auth} user=${results.staff.userId}`);
    for (const note of results.staff.notes) log(`    - ${note}`);
  }
  log("  Browser checklist remains mandatory for feedback visibility:");
  for (const item of results.checklist) log(`    • ${item}`);
  return results;
}

function isMain() {
  const entry = process.argv[1] ? String(process.argv[1]) : "";
  return entry.endsWith("authenticated-qa-acceptance.mjs");
}

if (isMain()) {
  const requireCredentials = process.argv.includes("--require");
  runAcceptance({ requireCredentials })
    .then((results) => {
      if (results.status === "SKIPPED") process.exitCode = requireCredentials ? 1 : 0;
      else {
        const learnerFail = results.learners.some((row) => row.auth !== "AUTH_OK" || row.isolation === "FAIL");
        const staffFail = results.staff && results.staff.auth !== "AUTH_OK";
        process.exitCode = learnerFail || staffFail ? 1 : 0;
      }
    })
    .catch((error) => {
      console.error(error?.code || error?.message || "AUTHENTICATED_QA_FAILED");
      process.exitCode = 1;
    });
}
