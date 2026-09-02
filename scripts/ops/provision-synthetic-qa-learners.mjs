#!/usr/bin/env node
/**
 * Admin/ops CLI for permanent synthetic QA Auth users and learner mapping.
 *
 * Never import this module from learner hubs, Vite bundles, or browser code.
 * Does not insert into auth.users through SQL.
 */

import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createClient } from "@supabase/supabase-js";
import { ProvisionError, runProvision } from "./synthetic-qa-provision.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../..");

function loadLocalEnv(env) {
  const path = join(ROOT, ".env");
  if (!existsSync(path)) return env;
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

function fail(message) {
  console.error(message);
  process.exit(1);
}

function toQuery(params) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params || {})) {
    search.set(key, String(value));
  }
  return search.toString();
}

function createAdmin(url, serviceRoleKey) {
  const supabase = createClient(url, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false
    }
  });

  return {
    async findUserByEmail(email) {
      const needle = String(email || "").toLowerCase();
      let page = 1;
      while (page <= 10) {
        const { data, error } = await supabase.auth.admin.listUsers({
          page,
          perPage: 200
        });
        if (error) {
          throw new ProvisionError("AUTH_LOOKUP_FAILED", "Auth Admin lookup failed.");
        }
        const users = Array.isArray(data?.users) ? data.users : [];
        const match = users.find((user) => String(user?.email || "").toLowerCase() === needle);
        if (match) return match;
        if (users.length < 200) return null;
        page += 1;
      }
      return null;
    },

    async createUser({ email, password, persona }) {
      const { data, error } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          synthetic: true,
          purpose: "formative-smoke-test",
          persona
        }
      });
      if (error || !data?.user?.id) {
        throw new ProvisionError(
          "AUTH_CREATE_FAILED",
          `Auth Admin create failed for ${persona}.`
        );
      }
      return data.user;
    }
  };
}

function createRest(url, serviceRoleKey) {
  const headers = {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json"
  };

  async function readJson(response) {
    const text = await response.text();
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch {
      return { parseError: true };
    }
  }

  return {
    async select(schema, table, query) {
      const response = await fetch(`${url}/rest/v1/${table}?${toQuery(query)}`, {
        headers: {
          ...headers,
          "Accept-Profile": schema,
          "Content-Profile": schema
        }
      });
      const body = await readJson(response);
      if (!response.ok) {
        throw new ProvisionError(
          "REST_SELECT_FAILED",
          `Read of ${schema}.${table} failed.`
        );
      }
      return body;
    },

    async rpc(name, args) {
      const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
          ...headers,
          "Content-Profile": "admin_api",
          "Accept-Profile": "admin_api"
        },
        body: JSON.stringify(args || {})
      });
      const body = await readJson(response);
      if (!response.ok) {
        const code = body?.code || body?.message || `HTTP ${response.status}`;
        throw new ProvisionError("RPC_FAILED", `RPC ${name} failed: ${code}`);
      }
      return body;
    }
  };
}

async function main() {
  const env = loadLocalEnv(process.env);
  const dryRun = process.argv.includes("--dry-run");
  const checkOnly = process.argv.includes("--check");
  const url = String(env.SUPABASE_URL || "").replace(/\/$/, "");
  const serviceRoleKey = String(env.SUPABASE_SERVICE_ROLE_KEY || "").trim();

  let admin = null;
  let rest = null;
  if (url && serviceRoleKey) {
    admin = createAdmin(url, serviceRoleKey);
    rest = createRest(url, serviceRoleKey);
  } else {
    admin = {
      findUserByEmail: async () => null,
      createUser: async () => {
        throw new ProvisionError("MISSING_REQUIRED_ENV", "MISSING_REQUIRED_ENV:\nSUPABASE_URL\nSUPABASE_SERVICE_ROLE_KEY");
      }
    };
    rest = {
      select: async () => [],
      rpc: async () => {
        throw new ProvisionError("MISSING_REQUIRED_ENV", "MISSING_REQUIRED_ENV:\nSUPABASE_URL\nSUPABASE_SERVICE_ROLE_KEY");
      }
    };
  }

  const outcome = await runProvision({
    env: { ...env, SUPABASE_URL: url },
    admin,
    rest,
    dryRun,
    checkOnly,
    log: console.log,
    error: console.error
  });

  if (!outcome.ok) process.exit(1);
}

main().catch((error) => {
  if (error instanceof ProvisionError && error.code === "MISSING_REQUIRED_ENV") {
    fail(error.message);
  }
  fail(error instanceof Error ? error.message : "Provisioning failed.");
});
