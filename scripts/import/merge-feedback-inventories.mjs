#!/usr/bin/env node
/**
 * Merge supplemental hosted inventory snapshots into hosted-inventory.json.
 * Run after exporting module slices (e.g. l2e-hosted-inventory.json).
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dir = path.join(__dirname, "../../supabase/data/manifests/feedback-coverage");
const mainPath = path.join(dir, "hosted-inventory.json");

const main = JSON.parse(fs.readFileSync(mainPath, "utf8"));
const extras = fs.readdirSync(dir)
  .filter((name) => name.endsWith("-hosted-inventory.json"))
  .map((name) => JSON.parse(fs.readFileSync(path.join(dir, name), "utf8")));

const key = (row) => `${row.module_key}\0${row.activity_key}\0${row.activity_version}\0${row.question_key}`;
const merged = new Map(main.map((row) => [key(row), row]));
for (const rows of extras) {
  for (const row of rows) merged.set(key(row), row);
}

const out = [...merged.values()].sort((a, b) => {
  const left = `${a.module_key}:${a.activity_key}:${a.activity_version}:${a.question_key}`;
  const right = `${b.module_key}:${b.activity_key}:${b.activity_version}:${b.question_key}`;
  return left.localeCompare(right);
});

fs.writeFileSync(mainPath, `${JSON.stringify(out, null, 2)}\n`);
console.log(`Merged ${out.length} rows (${extras.flat().length} supplemental).`);
