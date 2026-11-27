#!/usr/bin/env node
/**
 * Staff-oriented curriculum / marking operational checks.
 * Uses a staff JWT against admin_api views that never expose answer keys.
 *
 * Required env: LP_SUPABASE_URL, LP_SUPABASE_PUBLISHABLE_KEY, LP_STAFF_ACCESS_TOKEN
 * Optional: LP_EXPECTED_SANITISATION_VERSION (default lp.strip.v1)
 */
import { readFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const env = (name, fallback = "") => String(process.env[name] || fallback).trim();
const result = (id, passed, message, severity = "error", details = null) => ({
  id, passed: Boolean(passed), severity, message, details
});

async function adminSelect(path, { url, key, token, query = "" }) {
  const response = await fetch(`${url}/rest/v1/${path}${query}`, {
    headers: {
      apikey: key,
      Authorization: `Bearer ${token}`,
      "Accept-Profile": "admin_api",
      "Content-Profile": "admin_api",
      Accept: "application/json"
    }
  });
  const text = await response.text();
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  if (!response.ok) {
    const error = new Error(`admin_api.${path} failed (HTTP ${response.status})`);
    error.status = response.status;
    error.body = body;
    throw error;
  }
  return body;
}

async function anonCurriculum(hubCode, courseKey, { url, key }) {
  const response = await fetch(`${url}/rest/v1/rpc/published_curriculum_package`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Profile": "api",
      "Accept-Profile": "api",
      "Content-Type": "application/json",
      Accept: "application/json"
    },
    body: JSON.stringify({ p_hub_code: hubCode, p_course_key: courseKey })
  });
  const text = await response.text();
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  return { ok: response.ok, status: response.status, body, text };
}

const firstRow = (payload) => Array.isArray(payload)
  ? (payload[0] || null)
  : (payload && typeof payload === "object" ? payload : null);

async function main() {
  const url = env("LP_SUPABASE_URL", env("SUPABASE_URL")).replace(/\/+$/, "");
  const key = env("LP_SUPABASE_PUBLISHABLE_KEY", env("SUPABASE_PUBLISHABLE_KEY"));
  const token = env("LP_STAFF_ACCESS_TOKEN");
  const expectedSanitisation = env("LP_EXPECTED_SANITISATION_VERSION", "lp.strip.v1");
  const asJson = process.argv.includes("--json");
  if (!url || !key) {
    process.stderr.write("Set LP_SUPABASE_URL and LP_SUPABASE_PUBLISHABLE_KEY.\n");
    process.exitCode = 2;
    return;
  }
  if (!token) {
    process.stderr.write("Set LP_STAFF_ACCESS_TOKEN for staff-only admin_api diagnostics.\n");
    process.exitCode = 2;
    return;
  }

  const results = [];
  const auth = { url, key, token };

  try {
    const missingPackages = await adminSelect("publications_missing_learner_packages", {
      ...auth,
      query: "?select=hub_code,course_key,package_version,status,learner_package_sanitisation_version,expected_sanitisation_version"
    });
    results.push(result(
      "learner-packages.missing-or-outdated",
      Array.isArray(missingPackages) && missingPackages.length === 0,
      Array.isArray(missingPackages) && missingPackages.length === 0
        ? "No publications missing a current learner_package."
        : `${missingPackages.length} publication(s) missing or outdated learner_package.`,
      "error",
      { rows: missingPackages }
    ));
  } catch (error) {
    results.push(result(
      "learner-packages.missing-or-outdated",
      false,
      error.message,
      error.status === 401 || error.status === 403 ? "error" : "warning",
      error.body || null
    ));
  }

  try {
    const publications = await adminSelect("curriculum_publications", {
      ...auth,
      query: "?status=eq.published&select=hub_code,course_key,package_version,has_learner_package,learner_package_sanitisation_version"
    });
    const outdated = (publications || []).filter((row) => (
      !row.has_learner_package
      || String(row.learner_package_sanitisation_version || "") !== expectedSanitisation
    ));
    results.push(result(
      "learner-packages.sanitisation-version",
      outdated.length === 0,
      outdated.length === 0
        ? `Published rows use sanitisation ${expectedSanitisation}.`
        : `${outdated.length} published row(s) missing package or not on ${expectedSanitisation}.`,
      "error",
      { expectedSanitisation, outdated }
    ));
  } catch (error) {
    results.push(result(
      "learner-packages.sanitisation-version",
      false,
      error.message,
      "warning",
      error.body || null
    ));
  }

  try {
    const gaps = await adminSelect("published_marking_coverage_gaps", {
      ...auth,
      query: "?select=hub_code,course_key,package_version,activity_key,question_key,question_type,has_own_marking,unresolved"
    });
    results.push(result(
      "marking.coverage-gaps",
      Array.isArray(gaps) && gaps.length === 0,
      Array.isArray(gaps) && gaps.length === 0
        ? "No unresolved published marking coverage gaps."
        : `${gaps.length} published question(s) lack resolvable marking specs (includes fingerprint/unresolved failures).`,
      "error",
      { sample: (gaps || []).slice(0, 25) }
    ));
  } catch (error) {
    results.push(result(
      "marking.coverage-gaps",
      false,
      error.message,
      "warning",
      error.body || null
    ));
  }

  try {
    const summary = await adminSelect("published_marking_coverage_summary", {
      ...auth,
      query: "?marking_mode=eq.language-variants&select=hub_code,course_key,activity_key,question_key,has_language_variants,unresolved"
    });
    const invalidLanguage = (summary || []).filter((row) => row.unresolved || row.has_language_variants === false);
    results.push(result(
      "marking.language-variants",
      invalidLanguage.length === 0,
      invalidLanguage.length === 0
        ? "language-variants rows report configured variants."
        : `${invalidLanguage.length} language-variants row(s) unresolved or missing variants.`,
      "error",
      { sample: invalidLanguage.slice(0, 25) }
    ));
  } catch (error) {
    results.push(result(
      "marking.language-variants",
      false,
      error.message,
      "warning",
      error.body || null
    ));
  }

  const targets = JSON.parse(
    await readFile(resolve(__dirname, "pages-health-targets.json"), "utf8")
  ).targets.filter((target) => target.kind === "learner-hub");

  for (const target of targets) {
    const hubCode = target.curriculum?.hubCode;
    const courseKey = target.curriculum?.courseKey;
    if (!hubCode || !courseKey) continue;
    const probe = await anonCurriculum(hubCode, courseKey, { url, key });
    if (!probe.ok) {
      const timeout = /57014|statement timeout/i.test(probe.text || "");
      results.push(result(
        `curriculum.retrieval.${hubCode}`,
        false,
        timeout
          ? `${hubCode}: curriculum RPC timed out (leave anon statement timeout unchanged; inspect learner packages).`
          : `${hubCode}: curriculum RPC failed (HTTP ${probe.status}).`
      ));
      continue;
    }
    const row = firstRow(probe.body);
    if (!row?.package) {
      results.push(result(
        `curriculum.retrieval.${hubCode}`,
        false,
        `${hubCode}: empty published curriculum package.`
      ));
      continue;
    }
    const version = row.package_version || row.package?.version || "";
    const expectedEnv = target.curriculum?.expectedPackageVersionEnv;
    const expected = expectedEnv ? env(expectedEnv) : "";
    if (expected && version !== expected) {
      results.push(result(
        `curriculum.version.${hubCode}`,
        false,
        `${hubCode}: got ${version}, expected ${expected}.`
      ));
    } else {
      results.push(result(
        `curriculum.retrieval.${hubCode}`,
        true,
        `${hubCode}: published package ${version} retrieved.`,
        "info"
      ));
    }
  }

  const errors = results.filter((item) => !item.passed && item.severity === "error");
  const report = {
    passed: errors.length === 0,
    errors: errors.length,
    warnings: results.filter((item) => !item.passed && item.severity === "warning").length,
    results
  };
  if (asJson) {
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  } else {
    process.stdout.write(`Curriculum/marking ops health — ${report.passed ? "PASS" : "FAIL"}\n`);
    for (const item of results) {
      const mark = item.passed ? "OK" : item.severity === "warning" ? "WARN" : "FAIL";
      process.stdout.write(`  [${mark}] ${item.id}: ${item.message}\n`);
    }
  }
  process.exitCode = report.passed ? 0 : 1;
}

main().catch((error) => {
  process.stderr.write(`${error?.stack || error}\n`);
  process.exitCode = 1;
});
