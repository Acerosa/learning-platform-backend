/**
 * Idempotent synthetic QA Auth + application provisioning.
 *
 * Admin/ops only. Not imported by learner hubs, Vite bundles, or browser code.
 * Never logs passwords, service-role keys, JWTs, or unmasked emails.
 */

import { PERSONAS, PURPOSE } from "./synthetic-qa-config.mjs";

export { PERSONAS, PURPOSE };

const PRIVILEGED_ROLES = new Set([
  "admin",
  "service_role",
  "supabase_admin",
  "staff",
  "platform_admin",
  "teacher"
]);

export class ProvisionError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = "ProvisionError";
    this.code = code;
    this.details = details;
  }
}

export function maskEmail(email) {
  const trimmed = String(email || "");
  const at = trimmed.indexOf("@");
  if (at <= 1) return "(redacted)";
  return `${trimmed.slice(0, 2)}…${trimmed.slice(at)}`;
}

export function maskId(id) {
  const value = String(id || "");
  if (value.length < 8) return "(redacted)";
  return `${value.slice(0, 4)}…${value.slice(-2)}`;
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

export function collectMissingEnv(env, personas = PERSONAS) {
  const missing = [];
  if (!envValue(env, "SUPABASE_URL")) missing.push("SUPABASE_URL");
  if (!envValue(env, "SUPABASE_SERVICE_ROLE_KEY")) missing.push("SUPABASE_SERVICE_ROLE_KEY");
  for (const persona of personas) {
    if (!firstPresent(env, persona.emailEnv)) missing.push(persona.emailEnv[0]);
    if (!firstPresent(env, persona.passwordEnv)) missing.push(persona.passwordEnv[0]);
  }
  return missing;
}

export function resolvePersonaSecrets(env, personas = PERSONAS) {
  const missing = collectMissingEnv(env, personas);
  if (missing.length) {
    throw new ProvisionError(
      "MISSING_REQUIRED_ENV",
      `MISSING_REQUIRED_ENV:\n${missing.join("\n")}`,
      { missing }
    );
  }

  const resolved = personas.map((persona) => ({
    ...persona,
    email: firstPresent(env, persona.emailEnv).value,
    password: firstPresent(env, persona.passwordEnv).value
  }));

  const emails = resolved.map((item) => item.email.toLowerCase());
  const unique = new Set(emails);
  if (unique.size !== emails.length) {
    throw new ProvisionError(
      "DUPLICATE_QA_EMAIL",
      "DUPLICATE_QA_EMAIL: each persona must use a distinct email address."
    );
  }

  return resolved;
}

export function isPrivilegedAppMetadata(appMetadata) {
  const meta = appMetadata && typeof appMetadata === "object" ? appMetadata : {};
  const role = String(meta.role || meta.app_role || "").toLowerCase();
  if (PRIVILEGED_ROLES.has(role)) return true;
  if (meta.platform_admin === true || meta.staff === true || meta.is_staff === true) {
    return true;
  }
  const roles = Array.isArray(meta.roles) ? meta.roles : [];
  return roles.some((value) => PRIVILEGED_ROLES.has(String(value || "").toLowerCase()));
}

export function inspectAuthMetadata(user, expectedPersona) {
  const userMeta = user?.user_metadata && typeof user.user_metadata === "object"
    ? user.user_metadata
    : {};
  const synthetic = userMeta.synthetic === true || userMeta.synthetic === "true";
  const purpose = String(userMeta.purpose || "");
  const persona = String(userMeta.persona || "");
  const confirmed = Boolean(
    user?.email_confirmed_at
    || user?.confirmed_at
    || user?.email_confirmed === true
  );
  const privileged = isPrivilegedAppMetadata(user?.app_metadata);

  if (privileged) {
    return { ok: false, code: "STAFF_ACCOUNT_FORBIDDEN", confirmed, synthetic, purpose, persona };
  }
  if (!synthetic) {
    return { ok: false, code: "NON_SYNTHETIC_ACCOUNT", confirmed, synthetic, purpose, persona };
  }
  if (purpose !== PURPOSE) {
    return { ok: false, code: "AUTH_METADATA_MISMATCH", confirmed, synthetic, purpose, persona };
  }
  if (persona !== expectedPersona) {
    return { ok: false, code: persona ? "PERSONA_COLLISION" : "AUTH_METADATA_MISMATCH", confirmed, synthetic, purpose, persona };
  }
  if (!confirmed) {
    return { ok: false, code: "EMAIL_NOT_CONFIRMED", confirmed, synthetic, purpose, persona };
  }
  return { ok: true, code: "PASS", confirmed, synthetic, purpose, persona };
}

function containsSecret(value, secrets) {
  const text = String(value || "");
  return secrets.some((secret) => secret && text.includes(secret));
}

export function assertSafeLog(args, secrets) {
  for (const arg of args) {
    if (typeof arg === "string" && containsSecret(arg, secrets)) {
      throw new ProvisionError("SECRET_LOG_BLOCKED", "Refusing to log a secret value.");
    }
    if (arg && typeof arg === "object") {
      const dumped = JSON.stringify(arg);
      if (containsSecret(dumped, secrets)) {
        throw new ProvisionError("SECRET_LOG_BLOCKED", "Refusing to log a secret value.");
      }
    }
  }
}

function safeLogger(log, secrets) {
  return (...args) => {
    assertSafeLog(args, secrets);
    log(...args);
  };
}

const WRITE_RPCS = new Set([
  "provision_synthetic_qa_learner",
  "ensure_synthetic_qa_groups",
  "set_synthetic_qa_learner_active"
]);

export function isWriteRpc(name) {
  return WRITE_RPCS.has(String(name || ""));
}

function rpcRows(body) {
  if (Array.isArray(body)) return body;
  if (body && typeof body === "object") return [body];
  return [];
}

async function inspectLearners(rest) {
  return rpcRows(await rest.rpc("inspect_synthetic_qa_learners", {}));
}

async function inspectAuthLink(rest, authUserId) {
  const rows = rpcRows(await rest.rpc("inspect_synthetic_qa_auth_user", {
    p_auth_user_id: authUserId
  }));
  return rows[0] || {
    auth_user_linked: false,
    student_number: null,
    is_synthetic: null,
    student_active: null,
    teacher_linked: false
  };
}

function fixtureRow(rows, persona) {
  return rows.find((row) => row?.persona === persona) || null;
}

function planForPersona({ existingUser, fixture, expected }) {
  const enrolmentCodes = Array.isArray(fixture?.enrolment_codes) ? fixture.enrolment_codes : [];
  const assignmentReady = fixture?.smoke_assigned === true;
  return {
    authAction: existingUser ? "AUTH REUSE" : "AUTH CREATE",
    studentAction: fixture?.student_present ? "STUDENT READY" : "STUDENT PROVISION",
    enrolmentAction: enrolmentCodes.includes(expected.groupCode)
      ? "ENROLMENT READY"
      : "ENROLMENT CREATE",
    assignmentAction: assignmentReady ? "ASSIGNMENT READY" : "ASSIGNMENT MISSING",
    enrolmentCodes,
    assignmentReady
  };
}

export async function inspectPersonaState({ admin, rest, personaConfig, fixtures }) {
  const existingUser = await admin.findUserByEmail(personaConfig.email);
  const rows = fixtures || await inspectLearners(rest);
  const fixture = fixtureRow(rows, personaConfig.persona);
  const authLink = existingUser ? await inspectAuthLink(rest, existingUser.id) : null;
  return { existingUser, fixture, authLink, enrolmentCodes: Array.isArray(fixture?.enrolment_codes) ? fixture.enrolment_codes : [] };
}

function assertSafeExistingAuth(state, expected) {
  if (!state.existingUser) return;
  const metadata = inspectAuthMetadata(state.existingUser, expected.persona);
  if (!metadata.ok) {
    throw new ProvisionError(
      metadata.code,
      `${expected.persona}: ${metadata.code} — existing Auth user will not be converted.`
    );
  }
  if (state.authLink?.teacher_linked) {
    throw new ProvisionError("STAFF_ACCOUNT_FORBIDDEN", `${expected.persona}: STAFF_ACCOUNT_FORBIDDEN`);
  }
  if (state.authLink?.auth_user_linked && state.authLink.is_synthetic === false) {
    throw new ProvisionError(
      "REAL_LEARNER_FORBIDDEN",
      `${expected.persona}: REAL_LEARNER_FORBIDDEN`
    );
  }
  if (
    state.authLink?.auth_user_linked
    && state.authLink.student_number
    && state.authLink.student_number !== expected.studentNumber
  ) {
    throw new ProvisionError(
      "AUTH_ACCOUNT_ALREADY_LINKED",
      `${expected.persona}: AUTH_ACCOUNT_ALREADY_LINKED`
    );
  }
}

export async function provisionPersona({ admin, rest, personaConfig, dryRun, log, fixtures }) {
  const expected = personaConfig;
  const state = await inspectPersonaState({ admin, rest, personaConfig, fixtures });
  if (!state.fixture) {
    throw new ProvisionError(
      "UNKNOWN_QA_PERSONA",
      `${expected.persona}: inspect_synthetic_qa_learners returned no fixture row.`
    );
  }
  const plan = planForPersona({ existingUser: state.existingUser, fixture: state.fixture, expected });

  assertSafeExistingAuth(state, expected);

  if (dryRun) {
    log(`${expected.persona}`);
    log(`  Auth: ${state.existingUser ? "REUSE" : "CREATE"}`);
    log(`  Student: ${state.fixture?.student_present ? "READY" : "PROVISION"}`);
    log(`  Enrolment: ${plan.enrolmentCodes.includes(expected.groupCode) ? "READY" : "PROVISION"}`);
    log(`  Assignment: ${plan.assignmentReady ? "READY" : "MISSING"}`);
    log("  Status: PLANNED");
    return {
      persona: expected.persona,
      auth: state.existingUser ? "AUTH_REUSED" : "AUTH_CREATE",
      metadata: state.existingUser ? "PASS" : "PENDING_CREATE",
      student: plan.studentAction,
      group: expected.groupCode,
      assignmentReady: plan.assignmentReady,
      dryRun: true
    };
  }

  let authUser = state.existingUser;
  let authStatus = "AUTH_REUSED";
  if (!authUser) {
    authUser = await admin.createUser({
      email: expected.email,
      password: expected.password,
      persona: expected.persona
    });
    authStatus = "AUTH_CREATED";
  }

  const metadata = inspectAuthMetadata(authUser, expected.persona);
  if (!metadata.ok) {
    throw new ProvisionError(
      metadata.code,
      `${expected.persona}: ${metadata.code} after Auth ${authStatus === "AUTH_CREATED" ? "create" : "reuse"}.`,
      { layer: authStatus === "AUTH_CREATED" ? "AUTH_CREATED" : "AUTH", partial: authStatus === "AUTH_CREATED" }
    );
  }

  let provisioned;
  try {
    provisioned = await rest.rpc("provision_synthetic_qa_learner", {
      p_auth_user_id: authUser.id,
      p_persona: expected.persona
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "application provisioning failed";
    throw new ProvisionError(
      "STUDENT_PROVISION_FAILURE",
      `${expected.persona}: PARTIAL_PROVISIONING application layer failed (${message}). Auth user was not deleted.`,
      { layer: "APPLICATION", partial: true, authStatus }
    );
  }

  const row = Array.isArray(provisioned) ? provisioned[0] : provisioned;
  const after = fixtureRow(await inspectLearners(rest), expected.persona);
  const enrolmentCodes = Array.isArray(after?.enrolment_codes) ? after.enrolment_codes : [];
  const assignmentReady = after?.smoke_assigned === true;
  const contactEmailCopied = after?.contact_email_copied === true;
  const ready = Boolean(
    after?.student_present
    && after?.is_synthetic
    && after?.student_active
    && contactEmailCopied === false
    && enrolmentCodes.length === 1
    && enrolmentCodes[0] === expected.groupCode
    && assignmentReady
  );

  log(`${expected.persona}`);
  log(`  Auth: ${authStatus === "AUTH_CREATED" ? "CREATED" : "REUSED"}`);
  log(`  Student: ${row?.idempotent ? "REUSED" : "PROVISIONED"}`);
  log(`  Group: ${row?.group_code || expected.groupCode}`);
  log(`  Enrolment: ${(row?.enrolment_status || "unknown").toUpperCase()}`);
  log(`  Assignment: ${assignmentReady ? "READY" : "MISSING"}`);
  log(`  Contact email copied: ${contactEmailCopied ? "YES" : "NO"}`);
  log(`  Status: ${ready ? "READY" : "NOT_READY"}`);

  return {
    persona: expected.persona,
    auth: authStatus,
    metadata: "PASS",
    student: row?.idempotent ? "REUSED" : "PROVISIONED",
    studentNumber: expected.studentNumber,
    group: row?.group_code || expected.groupCode,
    enrolment: row?.enrolment_status || null,
    enrolmentCodes,
    assignmentReady,
    contactEmailCopied,
    ready,
    authIdMasked: maskId(authUser.id)
  };
}

export async function runProvision({
  env,
  admin,
  rest,
  dryRun = false,
  checkOnly = false,
  log = console.log,
  error = console.error
}) {
  const secrets = [];
  const resolved = resolvePersonaSecrets(env);
  secrets.push(envValue(env, "SUPABASE_SERVICE_ROLE_KEY"));
  for (const item of resolved) {
    secrets.push(item.email, item.password);
  }
  const out = safeLogger(log, secrets);
  const writes = { authCreates: 0, authPasswordUpdates: 0, rpcCalls: [] };

  const wrappedAdmin = {
    findUserByEmail: (email) => admin.findUserByEmail(email),
    createUser: async (input) => {
      if (dryRun || checkOnly) {
        throw new ProvisionError("WRITE_BLOCKED", "Auth create attempted during dry-run/check.");
      }
      writes.authCreates += 1;
      return admin.createUser(input);
    },
    updatePassword: async () => {
      writes.authPasswordUpdates += 1;
      throw new ProvisionError("PASSWORD_RESET_FORBIDDEN", "Existing passwords must not be changed by this command.");
    }
  };

  const wrappedRest = {
    select: async (schema, table) => {
      throw new ProvisionError(
        "INTERNAL_SCHEMA_FORBIDDEN",
        `Direct REST read of ${schema}.${table} is not allowed.`
      );
    },
    rpc: async (name, args) => {
      if ((dryRun || checkOnly) && isWriteRpc(name)) {
        throw new ProvisionError("WRITE_BLOCKED", "RPC write attempted during dry-run/check.");
      }
      if (isWriteRpc(name)) writes.rpcCalls.push(name);
      return rest.rpc(name, args);
    }
  };

  if (!dryRun && !checkOnly) {
    await wrappedRest.rpc("ensure_synthetic_qa_groups", {});
  }

  const fixtures = await inspectLearners(wrappedRest);
  const results = [];
  const failures = [];
  for (const personaConfig of resolved) {
    try {
      if (checkOnly) {
        const state = await inspectPersonaState({
          admin: wrappedAdmin,
          rest: wrappedRest,
          personaConfig,
          fixtures
        });
        const metadata = state.existingUser
          ? inspectAuthMetadata(state.existingUser, personaConfig.persona)
          : { ok: false, code: "AUTH_MISSING" };
        const assignmentReady = state.fixture?.smoke_assigned === true;
        const ready = Boolean(
          metadata.ok
          && state.fixture?.student_present
          && state.fixture?.is_synthetic
          && state.fixture?.contact_email_copied === false
          && state.enrolmentCodes.length === 1
          && state.enrolmentCodes[0] === personaConfig.groupCode
          && assignmentReady
        );
        out(`${personaConfig.persona}`);
        out(`  Auth: ${state.existingUser ? "PRESENT" : "MISSING"}`);
        out(`  Metadata: ${metadata.ok ? "PASS" : metadata.code}`);
        out(`  Student: ${state.fixture?.student_present ? "PRESENT" : "MISSING"}`);
        out(`  Group: ${personaConfig.groupCode}`);
        out(`  Enrolment: ${state.enrolmentCodes[0] || "MISSING"}`);
        out(`  Assignment: ${assignmentReady ? "READY" : "MISSING"}`);
        out(`  Status: ${ready ? "READY_FOR_BROWSER_SMOKE" : "NOT_READY"}`);
        results.push({ persona: personaConfig.persona, ready, check: true });
        if (!ready) failures.push(personaConfig.persona);
        continue;
      }

      const result = await provisionPersona({
        admin: wrappedAdmin,
        rest: wrappedRest,
        personaConfig,
        dryRun,
        log: out,
        fixtures
      });
      results.push(result);
      if (!dryRun && result.ready === false) failures.push(personaConfig.persona);
    } catch (caught) {
      const code = caught instanceof ProvisionError ? caught.code : "OTHER_PROVEN";
      const message = caught instanceof Error ? caught.message : "Provisioning failed.";
      error(`${personaConfig.persona}: ${code}`);
      error(message);
      failures.push(personaConfig.persona);
      results.push({
        persona: personaConfig.persona,
        failed: true,
        code,
        partial: Boolean(caught instanceof ProvisionError && caught.details?.partial)
      });
    }
  }

  if (dryRun) out("Dry run complete. No Auth users or learner rows were written.");
  if (checkOnly) out("Read-only check complete. No writes were performed.");

  return {
    results,
    failures,
    writes,
    ok: failures.length === 0
  };
}
