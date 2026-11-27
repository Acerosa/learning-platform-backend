#!/usr/bin/env node
/**
 * Fleet GitHub Pages health runner.
 * Prefers a local sibling learning-platform-core checkout, otherwise clones the
 * pinned Core release that ships deployment-health.
 */
import { spawn } from "node:child_process";
import { access } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "../..");
const DEFAULT_CORE_REF = process.env.LP_CORE_HEALTH_REF || "v0.2.29";
const CONFIG = resolve(__dirname, "pages-health-targets.json");

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

function run(command, args, options = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, { stdio: "inherit", ...options });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolvePromise();
      else reject(new Error(`${command} ${args.join(" ")} exited ${code}`));
    });
  });
}

async function resolveCli() {
  const sibling = resolve(ROOT, "../learning-platform-core/dist/deployment-health.mjs");
  if (await exists(sibling)) return sibling;

  const vendored = resolve(ROOT, ".tmp/learning-platform-core");
  if (!(await exists(resolve(vendored, "dist/deployment-health.mjs")))) {
    await run("rm", ["-rf", vendored]);
    await run("git", [
      "clone",
      "--depth",
      "1",
      "--branch",
      DEFAULT_CORE_REF,
      "https://github.com/Acerosa/learning-platform-core.git",
      vendored
    ]);
  }
  return resolve(vendored, "dist/deployment-health.mjs");
}

async function main() {
  const args = process.argv.slice(2);
  const cli = await resolveCli();
  const forwarded = args.length ? args : ["--config", CONFIG, "--skip-browser"];
  if (!forwarded.includes("--config")) {
    forwarded.unshift("--config", CONFIG);
  }
  await run(process.execPath, [cli, ...forwarded], {
    env: {
      ...process.env,
      LP_SUPABASE_URL: process.env.LP_SUPABASE_URL || process.env.SUPABASE_URL || "https://hubwpkrqndorznwzvaer.supabase.co",
      LP_SUPABASE_PUBLISHABLE_KEY: process.env.LP_SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_PUBLISHABLE_KEY || ""
    }
  });
}

main().catch((error) => {
  process.stderr.write(`${error?.stack || error}\n`);
  process.exitCode = 1;
});
