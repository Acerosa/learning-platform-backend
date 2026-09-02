#!/usr/bin/env node
/**
 * Provision permanent synthetic QA Auth users, then map them through
 * admin_api.provision_synthetic_qa_learner.
 *
 * Does not insert into auth.users through SQL. Does not log passwords,
 * emails, service-role keys, or JWTs.
 */

const PERSONAS = [
  { persona: "UNIT3_TEST_LEARNER", emailEnv: "SYNTHETIC_QA_EMAIL_UNIT3", passwordEnv: "SYNTHETIC_QA_PASSWORD_UNIT3" },
  { persona: "TLEVEL_TEST_LEARNER", emailEnv: "SYNTHETIC_QA_EMAIL_TLEVEL", passwordEnv: "SYNTHETIC_QA_PASSWORD_TLEVEL" },
  { persona: "UNIT14_TEST_LEARNER", emailEnv: "SYNTHETIC_QA_EMAIL_UNIT14", passwordEnv: "SYNTHETIC_QA_PASSWORD_UNIT14" },
  { persona: "L2E_TEST_LEARNER", emailEnv: "SYNTHETIC_QA_EMAIL_L2E", passwordEnv: "SYNTHETIC_QA_PASSWORD_L2E" }
];

function fail(message) {
  console.error(message);
  process.exit(1);
}

function requiredEnv(name) {
  const value = String(process.env[name] || "").trim();
  if (!value) fail(`Missing required environment variable ${name}.`);
  return value;
}

function isDryRun() {
  return process.argv.includes("--dry-run");
}

function headers(serviceRoleKey) {
  return {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json"
  };
}

function maskEmail(email) {
  const trimmed = String(email || "");
  const at = trimmed.indexOf("@");
  if (at <= 1) return "(redacted)";
  return `${trimmed.slice(0, 2)}…${trimmed.slice(at)}`;
}

async function readJson(response) {
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return { parseError: true };
  }
}

async function findUserIdByEmail(url, serviceRoleKey, email) {
  const encoded = encodeURIComponent(email);
  const response = await fetch(`${url}/auth/v1/admin/users?page=1&per_page=200`, {
    headers: headers(serviceRoleKey)
  });
  const body = await readJson(response);
  if (!response.ok) {
    fail(`Auth Admin lookup failed with HTTP ${response.status}.`);
  }
  const users = Array.isArray(body?.users) ? body.users : [];
  const match = users.find((user) => String(user?.email || "").toLowerCase() === email.toLowerCase());
  return match?.id || null;
}

async function createOrFindAuthUser({ url, serviceRoleKey, email, password, persona }) {
  const response = await fetch(`${url}/auth/v1/admin/users`, {
    method: "POST",
    headers: headers(serviceRoleKey),
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        synthetic: true,
        purpose: "formative-smoke-test",
        persona
      }
    })
  });
  const body = await readJson(response);
  if (response.ok && body?.id) {
    return { id: body.id, created: true };
  }

  const alreadyExists = response.status === 422
    || /already been registered|already exists|email_exists/i.test(JSON.stringify(body || {}));
  if (!alreadyExists) {
    fail(`Auth Admin create failed for ${persona} with HTTP ${response.status}.`);
  }

  const existingId = await findUserIdByEmail(url, serviceRoleKey, email);
  if (!existingId) fail(`Auth user for ${persona} already exists but could not be resolved safely.`);
  return { id: existingId, created: false };
}

async function rpc(url, serviceRoleKey, name, args) {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      ...headers(serviceRoleKey),
      "Content-Profile": "admin_api",
      "Accept-Profile": "admin_api"
    },
    body: JSON.stringify(args)
  });
  const body = await readJson(response);
  if (!response.ok) {
    const code = body?.code || body?.message || `HTTP ${response.status}`;
    fail(`RPC ${name} failed: ${code}`);
  }
  return body;
}

async function main() {
  const url = requiredEnv("SUPABASE_URL").replace(/\/$/, "");
  const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");

  if (isDryRun()) {
    for (const item of PERSONAS) {
      requiredEnv(item.emailEnv);
      requiredEnv(item.passwordEnv);
      console.log(`${item.persona}: env present (email ${maskEmail(process.env[item.emailEnv])})`);
    }
    console.log("Dry run complete. No Auth users or learner rows were written.");
    return;
  }

  console.log("Refreshing synthetic QA groups…");
  const groups = await rpc(url, serviceRoleKey, "ensure_synthetic_qa_groups", {});
  const groupRows = Array.isArray(groups) ? groups : [groups];
  for (const row of groupRows) {
    const status = row?.skipped_reason || row?.created_or_reused || "unknown";
    console.log(`${row?.persona || "unknown"} group ${row?.group_code || "?"}: ${status}; assignments=${row?.assignment_count ?? 0}`);
  }

  for (const item of PERSONAS) {
    const email = requiredEnv(item.emailEnv);
    const password = requiredEnv(item.passwordEnv);
    const authUser = await createOrFindAuthUser({
      url,
      serviceRoleKey,
      email,
      password,
      persona: item.persona
    });
    const provisioned = await rpc(url, serviceRoleKey, "provision_synthetic_qa_learner", {
      p_auth_user_id: authUser.id,
      p_persona: item.persona
    });
    const row = Array.isArray(provisioned) ? provisioned[0] : provisioned;
    console.log(
      `${item.persona}: auth ${authUser.created ? "created" : "reused"}; learner ${row?.idempotent ? "reused" : "created"}; group ${row?.group_code || "?"}`
    );
  }

  console.log("Synthetic QA provisioning complete.");
}

main().catch((error) => {
  fail(error instanceof Error ? error.message : "Provisioning failed.");
});
