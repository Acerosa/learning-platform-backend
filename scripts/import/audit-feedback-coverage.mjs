#!/usr/bin/env node
/**
 * Cross-hub server-feedback coverage audit.
 * Compares browser/runtime formative contracts against hosted catalogue inventory.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendRoot = path.resolve(__dirname, "../..");
const projectsRoot = path.resolve(backendRoot, "..");

const HOSTED_PATH = path.join(
  backendRoot,
  "supabase/data/manifests/feedback-coverage/hosted-inventory.json"
);

const REVIEW_TYPES = new Set(["short-response", "reflection", "text"]);
const SCORABLE_TYPES = new Set([
  "single-choice",
  "option-cards",
  "classification",
  "drag-drop",
  "ordering",
  "sequence",
  "fill-gap",
  "phrase-completion",
  "matching"
]);

const HUBS = [
  {
    name: "Unit 3",
    moduleKey: "unit-3-cyber-security",
    activitiesPath: path.join(projectsRoot, "unit-3-Cyber-Security-Hub/content/unit-3-cyber-security/activities.json"),
    mapping: "unit3"
  },
  {
    name: "T Level",
    moduleKey: "tlevel-software-development",
    activitiesPath: path.join(projectsRoot, "tlevel-software-development-hub/content/tlevel-software-development/activities.json"),
    mapping: "passthrough"
  },
  {
    name: "Unit 14",
    moduleKey: "unit-14-software-engineering-for-business",
    activitiesPath: path.join(projectsRoot, "unit-14-software-engineering-for-business-hub/content/unit-14/activities.json"),
    mapping: "passthrough"
  },
  {
    name: "L2E",
    moduleKey: "l2e-exploring-emerging-digital-technologies",
    activitiesPath: path.join(projectsRoot, "Emerging-Digital-Technologies-Hub/content/l2e-exploring-emerging-digital-technologies/activities.json"),
    mapping: "passthrough"
  }
];

function resolveFormativeRpcQuestionId(map, activityKey, questionId) {
  const raw = String(questionId || "").trim();
  if (!raw) return raw;
  const colon = raw.lastIndexOf(":");
  if (colon >= 0) {
    const suffix = raw.slice(colon + 1);
    if (suffix) return map.normaliseQuestionKey(suffix, activityKey);
  }
  return map.normaliseQuestionKey(raw, activityKey);
}

function loadUnit3Mapper() {
  const root = path.join(projectsRoot, "unit-3-Cyber-Security-Hub");
  const sandbox = { window: {}, console };
  vm.runInContext(fs.readFileSync(path.join(root, "js/core/question-key-aliases.js"), "utf8"), vm.createContext(sandbox));
  vm.runInContext(fs.readFileSync(path.join(root, "js/core/activity-key-map.js"), "utf8"), vm.createContext(sandbox));
  const map = sandbox.window.Unit3ActivityKeyMap;
  return {
    activityVersion(activityKey, packageVersion) {
      return map.catalogueVersionFor(activityKey) || map.normaliseActivityVersion(packageVersion, activityKey);
    },
    questionId(activityKey, block) {
      const content = block.content || {};
      const hosted = String(content.questionId || block.id || "").trim();
      const source = String(content.sourceQuestionId || "").trim();
      let local = source;
      if (!local && hosted.includes(":")) {
        local = hosted.slice(hosted.indexOf(":") + 1);
      } else if (!local) {
        local = hosted;
      }
      const blockType = String(block.type || "").toLowerCase();
      if (blockType === "classification") {
        return map.normaliseQuestionKey(local, activityKey);
      }
      return resolveFormativeRpcQuestionId(map, activityKey, hosted || local);
    }
  };
}

function questionIdFor(block) {
  return String(block?.content?.questionId || block?.id || "").trim();
}

function resolveActivityVersion(activity) {
  const raw = String(activity?.version || activity?.activityVersion || "").trim();
  if (!raw || raw === "latest") return "";
  if (/^\d+\.\d+$/.test(raw)) return `${raw}.0`;
  if (/^\d+\.\d+\.\d+$/.test(raw)) return raw;
  return "";
}

function isFormativeBlock(block) {
  return Boolean(block?.content?.formative);
}

function isReviewBlock(block) {
  const type = String(block.type || "").toLowerCase();
  return REVIEW_TYPES.has(type);
}

function loadActivities(filePath) {
  if (!fs.existsSync(filePath)) {
    return { activities: [], missing: true };
  }
  const doc = JSON.parse(fs.readFileSync(filePath, "utf8"));
  const activities = Array.isArray(doc) ? doc : doc.activities || [];
  return { activities, missing: false };
}

function buildHostedIndex(rows, moduleKey) {
  const byModule = rows.filter((row) => row.module_key === moduleKey || !row.module_key);
  const index = new Map();
  for (const row of byModule) {
    const key = `${row.activity_key}\0${row.activity_version}\0${row.question_key}`;
    index.set(key, row);
    if (!index.has(`${row.activity_key}\0*\0${row.question_key}`)) {
      index.set(`${row.activity_key}\0*\0${row.question_key}`, row);
    }
  }
  return { index, rows: byModule };
}

function lookupHosted(index, activityKey, activityVersion, questionKey) {
  return (
    index.get(`${activityKey}\0${activityVersion}\0${questionKey}`) ||
    index.get(`${activityKey}\0*\0${questionKey}`)
  );
}

function hostedVersionsForActivity(rows, activityKey) {
  return [...new Set(rows.filter((r) => r.activity_key === activityKey).map((r) => r.activity_version))];
}

const SERVER_MARKING_SKIP = {
  "Unit 3": (activityKey) => activityKey.startsWith("u3-w01-")
};

function isFoundationsClassicActivity(activityKey) {
  return String(activityKey || "").startsWith("foundations-");
}

const UNPUBLISHED_TLEVEL_PREFIXES = [
  /^week-[4-9]-/,
  /^week-1[0-9]-/,
  /^week-2[0-9]-/
];

function classifyRow({ hub, activity, block, runtimeQuestionId, canonicalQuestionId, runtimeVersion, blockType, hostedRows, hosted }) {
  if (!isFormativeBlock(block)) return null;
  if (isReviewBlock(block)) {
    return { status: "REVIEW", reason: "INTENTIONAL_REVIEW", hub, activityKey: activity.id, runtimeVersion, blockType, runtimeQuestionId, canonicalQuestionId };
  }

  const versions = hostedVersionsForActivity(hostedRows, activity.id);
  if (!versions.length) {
    if (hub === "T Level" && UNPUBLISHED_TLEVEL_PREFIXES.some((re) => re.test(activity.id))) {
      return {
        status: "PUBLICATION_ALIGNMENT_REQUIRED",
        reason: "ACTIVITY_NOT_PUBLISHED",
        hub,
        activityKey: activity.id,
        runtimeVersion,
        blockType,
        runtimeQuestionId,
        canonicalQuestionId
      };
    }
    if (hub === "L2E") {
      return {
        status: "PUBLICATION_ALIGNMENT_REQUIRED",
        reason: "ACTIVITY_NOT_PUBLISHED",
        hub,
        activityKey: activity.id,
        runtimeVersion,
        blockType,
        runtimeQuestionId,
        canonicalQuestionId
      };
    }
    return { status: "BROKEN", reason: "ACTIVITY_MISSING", hub, activityKey: activity.id, runtimeVersion, blockType, runtimeQuestionId, canonicalQuestionId };
  }

  const hostedExact = lookupHosted(hosted.index, activity.id, runtimeVersion, canonicalQuestionId);
  const hostedAnyVersion = lookupHosted(hosted.index, activity.id, "*", canonicalQuestionId);

  if (!hostedExact && hostedAnyVersion && hostedAnyVersion.activity_version !== runtimeVersion) {
    return { status: "BROKEN", reason: "VERSION_MISMATCH", hub, activityKey: activity.id, runtimeVersion, expectedVersion: hostedAnyVersion.activity_version, blockType, runtimeQuestionId, canonicalQuestionId };
  }

  if (!hostedExact && !hostedAnyVersion) {
    const wrongVersion = hostedRows.find((r) => r.activity_key === activity.id && r.question_key.toLowerCase() === canonicalQuestionId.toLowerCase() && r.question_key !== canonicalQuestionId);
    if (wrongVersion) {
      return { status: "BROKEN", reason: "QUESTION_KEY_DRIFT", hub, activityKey: activity.id, runtimeVersion, blockType, runtimeQuestionId, canonicalQuestionId, hostedKey: wrongVersion.question_key };
    }
    return { status: "BROKEN", reason: "QUESTION_MISSING", hub, activityKey: activity.id, runtimeVersion, blockType, runtimeQuestionId, canonicalQuestionId };
  }

  const row = hostedExact || hostedAnyVersion;
  if (row && !row.has_marking_spec) {
    if (row.marking_mode === "requires_review" || row.question_type === "text") {
      return { status: "REVIEW", reason: "HOSTED_REQUIRES_REVIEW", hub, activityKey: activity.id, runtimeVersion, blockType, runtimeQuestionId, canonicalQuestionId };
    }
    return { status: "BROKEN", reason: "BACKEND_SPEC_MISSING", hub, activityKey: activity.id, runtimeVersion, blockType, runtimeQuestionId, canonicalQuestionId };
  }

  return { status: "PASS", hub, activityKey: activity.id, runtimeVersion, blockType, runtimeQuestionId, canonicalQuestionId };
}

function auditHub(hubConfig, hostedRows, unit3Mapper) {
  const { activities, missing } = loadActivities(hubConfig.activitiesPath);
  if (missing) {
    return { hub: hubConfig.name, missingRepo: true, rows: [], summary: { PASS: 0, REVIEW: 0, BROKEN: 0, PUBLICATION_ALIGNMENT_REQUIRED: 0 } };
  }

  const { index, rows } = buildHostedIndex(hostedRows, hubConfig.moduleKey);
  const results = [];

  for (const activity of activities) {
    const activityKey = String(activity.id || "").trim();
    const packageVersion = resolveActivityVersion(activity);
    const runtimeVersion = hubConfig.mapping === "unit3"
      ? unit3Mapper.activityVersion(activityKey, packageVersion)
      : packageVersion;

    for (const block of activity.blocks || []) {
      if (!isFormativeBlock(block)) continue;
      if (SERVER_MARKING_SKIP[hubConfig.name]?.(activityKey)) continue;
      if (hubConfig.name === "T Level" && isFoundationsClassicActivity(activityKey)) {
        results.push({
          status: "REVIEW",
          reason: "FOUNDATIONS_CLASSIC_PATH",
          hub: hubConfig.name,
          activityKey,
          runtimeVersion: packageVersion,
          blockType: String(block.type || "").toLowerCase(),
          runtimeQuestionId: questionIdFor(block),
          canonicalQuestionId: questionIdFor(block)
        });
        continue;
      }
      const blockType = String(block.type || "").toLowerCase();
      const runtimeQuestionId = questionIdFor(block);
      let canonicalQuestionId = runtimeQuestionId;
      if (hubConfig.mapping === "unit3") {
        try {
          canonicalQuestionId = unit3Mapper.questionId(activityKey, block);
        } catch (error) {
          results.push({
            status: "BROKEN",
            reason: "RUNTIME_MAPPING_MISSING",
            hub: hubConfig.name,
            activityKey,
            runtimeVersion,
            blockType,
            runtimeQuestionId,
            canonicalQuestionId: null,
            detail: String(error?.message || error)
          });
          continue;
        }
      }

      if (blockType === "classification") {
        const items = Array.isArray(block.content?.items) ? block.content.items : [];
        if (!items.length) {
          results.push(classifyRow({ hub: hubConfig.name, activity, block, runtimeQuestionId, canonicalQuestionId, runtimeVersion, blockType, hosted: { index }, hostedRows: rows }));
          continue;
        }
        for (const item of items) {
          const itemId = String(item.id || "").trim();
          const composite = `${runtimeQuestionId}:${itemId}`;
          let canonical = composite;
          if (hubConfig.mapping === "unit3") {
            canonical = unit3Mapper.questionId(activityKey, { ...block, content: { ...block.content, sourceQuestionId: itemId } });
          }
          results.push(classifyRow({
            hub: hubConfig.name,
            activity,
            block,
            runtimeQuestionId: composite,
            canonicalQuestionId: canonical,
            runtimeVersion,
            blockType,
            hosted: { index },
            hostedRows: rows
          }));
        }
        continue;
      }

      results.push(classifyRow({ hub: hubConfig.name, activity, block, runtimeQuestionId, canonicalQuestionId, runtimeVersion, blockType, hosted: { index }, hostedRows: rows }));
    }
  }

  const summary = { PASS: 0, REVIEW: 0, BROKEN: 0, PUBLICATION_ALIGNMENT_REQUIRED: 0 };
  for (const row of results) summary[row.status] += 1;
  return { hub: hubConfig.name, missingRepo: false, rows: results, summary };
}

function main() {
  if (!fs.existsSync(HOSTED_PATH)) {
    console.error("Missing hosted inventory:", HOSTED_PATH);
    process.exit(1);
  }
  const hostedRows = JSON.parse(fs.readFileSync(HOSTED_PATH, "utf8"));
  const unit3Mapper = loadUnit3Mapper();

  console.log("CROSS-HUB SERVER-FEEDBACK COVERAGE AUDIT");
  console.log("======================================");

  let total = { PASS: 0, REVIEW: 0, BROKEN: 0, PUBLICATION_ALIGNMENT_REQUIRED: 0 };
  const hubReports = [];
  const allBroken = [];

  for (const hub of HUBS) {
    const report = auditHub(hub, hostedRows, unit3Mapper);
    hubReports.push(report);
    if (report.missingRepo) {
      console.log(`\nHub: ${report.hub}`);
      console.log("  MISSING REPO — skipped");
      continue;
    }
    console.log(`\nHub: ${report.hub}`);
    console.log(`  PASS: ${report.summary.PASS}`);
    console.log(`  REVIEW: ${report.summary.REVIEW}`);
    console.log(`  BROKEN: ${report.summary.BROKEN}`);
    if (report.summary.PUBLICATION_ALIGNMENT_REQUIRED) {
      console.log(`  PUBLICATION_ALIGNMENT_REQUIRED: ${report.summary.PUBLICATION_ALIGNMENT_REQUIRED}`);
    }
    total.PASS += report.summary.PASS;
    total.REVIEW += report.summary.REVIEW;
    total.BROKEN += report.summary.BROKEN;
    total.PUBLICATION_ALIGNMENT_REQUIRED += report.summary.PUBLICATION_ALIGNMENT_REQUIRED;
    allBroken.push(...report.rows.filter((r) => r.status === "BROKEN"));
  }

  console.log("\nOverall");
  console.log(`  PASS: ${total.PASS}`);
  console.log(`  REVIEW: ${total.REVIEW}`);
  console.log(`  BROKEN: ${total.BROKEN}`);
  console.log(`  PUBLICATION_ALIGNMENT_REQUIRED: ${total.PUBLICATION_ALIGNMENT_REQUIRED}`);

  if (allBroken.length) {
    console.log("\nBroken items (first 40):");
    for (const row of allBroken.slice(0, 40)) {
      console.log(`  [${row.reason}] ${row.hub} ${row.activityKey} v${row.runtimeVersion} ${row.runtimeQuestionId} -> ${row.canonicalQuestionId}`);
    }
  }

  const outPath = path.join(backendRoot, "supabase/data/manifests/feedback-coverage/audit-report.json");
  fs.writeFileSync(outPath, JSON.stringify({
    generatedAt: new Date().toISOString(),
    total,
    hubs: hubReports.map((report) => ({
      name: report.hub,
      summary: report.summary,
      missingRepo: report.missingRepo
    })),
    broken: allBroken,
    publicationAlignment: hubReports.flatMap((report) => report.rows.filter((r) => r.status === "PUBLICATION_ALIGNMENT_REQUIRED"))
  }, null, 2));
  process.exit(total.BROKEN > 0 ? 1 : 0);
}

main();
