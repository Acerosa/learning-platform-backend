#!/usr/bin/env node
/**
 * Convert Git-owned Unit 3 / T Level teaching snapshots into lp.content packages.
 * Does not invent a second schema. Hosted publication still uses admin_api.publish_curriculum.
 */
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const require = createRequire(import.meta.url);
const content = require("../../../learning-platform-content/dist/learning-platform-content.cjs.js");
const validatePackage = content.validatePackage;

const ROOT = dirname(fileURLToPath(import.meta.url));
const BACKEND = join(ROOT, "../..");
const PROJECTS = join(BACKEND, "..");
const SCHEMA = "0.1.0";

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function envelope(schema, id, version, metadata, relationships, extra = {}) {
  return {
    schema,
    schemaVersion: SCHEMA,
    id,
    version,
    metadata: metadata || {},
    relationships: relationships || {},
    ...extra
  };
}

function block(id, type, content) {
  return envelope("lp.content.block", id, "0.1.0", {}, {}, { type, content });
}

function kebabActivityId(id) {
  return String(id || "")
    .trim()
    .toLowerCase()
    .replace(/_/g, "-");
}

function semver(value) {
  const raw = String(value || "1.0.0").trim();
  if (/^\d+\.\d+\.\d+$/.test(raw)) return raw;
  if (/^\d+\.\d+$/.test(raw)) return `${raw}.0`;
  if (/^\d+$/.test(raw)) return `${raw}.0.0`;
  return "1.0.0";
}

function optionId(index, option) {
  if (option && option.id) return String(option.id);
  if (option && option.value != null && String(option.value).length <= 12) return String(option.value);
  return String.fromCharCode(97 + index);
}

function namespacedQuestionId(activityId, item, index) {
  const original = String(item.id || `${activityId}-q${index + 1}`);
  return {
    questionId: `${activityId}:${original}`,
    sourceQuestionId: original
  };
}

function optionLabel(option) {
  if (typeof option === "string") return option;
  return option.label || option.text || option.prompt || String(option.value || "");
}

function loadScript(path, extras = {}) {
  const sandbox = {
    console,
    Object,
    Array,
    JSON,
    Number,
    String,
    Boolean,
    Math,
    Date,
    ...extras
  };
  sandbox.global = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.window = sandbox;
  vm.runInNewContext(readFileSync(path, "utf8"), sandbox, { filename: path });
  return sandbox;
}

function writePackage(directory, assembled) {
  mkdirSync(directory, { recursive: true });
  const index = envelope("lp.content.package", assembled.id, assembled.version, {
    title: assembled.curriculum.metadata.title
  }, {
    hub: "hub.json",
    curriculum: "curriculum.json",
    learningOutcomes: "learning-outcomes.json",
    assignments: "assignments.json",
    weeks: "weeks.json",
    sessions: "sessions.json",
    activities: "activities.json",
    questions: [],
    assets: []
  });
  writeFileSync(join(directory, "index.json"), JSON.stringify(index, null, 2) + "\n");
  writeFileSync(join(directory, "hub.json"), JSON.stringify(assembled.hub, null, 2) + "\n");
  writeFileSync(join(directory, "curriculum.json"), JSON.stringify(assembled.curriculum, null, 2) + "\n");
  writeFileSync(join(directory, "learning-outcomes.json"), JSON.stringify(assembled.learningOutcomes, null, 2) + "\n");
  writeFileSync(join(directory, "assignments.json"), JSON.stringify(assembled.assignments, null, 2) + "\n");
  writeFileSync(join(directory, "weeks.json"), JSON.stringify(assembled.weeks, null, 2) + "\n");
  writeFileSync(join(directory, "sessions.json"), JSON.stringify(assembled.sessions, null, 2) + "\n");
  writeFileSync(join(directory, "activities.json"), JSON.stringify(assembled.activities, null, 2) + "\n");
  writeFileSync(join(directory, "package.json"), JSON.stringify(assembled, null, 2) + "\n");
}

function remainderBlock(activityId, remainder) {
  if (!remainder || typeof remainder !== "object") return null;
  const json = JSON.stringify(remainder);
  if (json === "{}" || json === "[]") return null;
  return block(`${activityId}-source-remainder`, "markdown", {
    text: "```json\n" + JSON.stringify(remainder, null, 2) + "\n```",
    format: "application/json"
  });
}

function convertMcq(activityId, item, index) {
  const options = (item.options || []).map((option, optionIndex) => ({
    id: optionId(optionIndex, option),
    label: optionLabel(option)
  }));
  let correct = item.correctOptionId || item.answer || item.correct;
  if (Number.isInteger(item.correctIndex) && options[item.correctIndex]) {
    correct = options[item.correctIndex].id;
  }
  const feedback = item.feedback || {};
  const ids = namespacedQuestionId(activityId, item, index);
  return block(`${activityId}-q-${index + 1}-${ids.sourceQuestionId}`, "single-choice", {
    formative: true,
    questionId: ids.questionId,
    sourceQuestionId: ids.sourceQuestionId,
    prompt: item.prompt || item.text || item.question || "",
    options,
    correctOptionId: correct == null ? "" : String(correct),
    feedback: {
      correct: feedback.correct || item.explanation || item.feedbackCorrect || "",
      incorrect: feedback.incorrect || item.feedbackIncorrect || item.explanation || ""
    },
    commandWord: item.commandWord,
    marks: item.marks,
    scenario: item.scenario,
    skill: item.skill,
    sourceType: item.type || "single"
  });
}

function convertQuestion(activityId, item, index) {
  const type = item.type || (item.correctIndex != null || item.options ? "single" : "text");
  if (type === "single" || type === "mcq" || type === "multiple" || item.options) {
    if (type === "matching") {
      const options = item.options || [];
      const rows = item.rows || [];
      const answers = item.answer || item.answers || {};
      return block(`${activityId}-q-${index + 1}-${item.id}`, "classification", {
        formative: true,
        questionId: namespacedQuestionId(activityId, item, index).questionId,
        sourceQuestionId: namespacedQuestionId(activityId, item, index).sourceQuestionId,
        prompt: item.prompt || "",
        categories: options.map((option) => ({
          id: String(option.value || option.id),
          label: option.label || option.text || String(option.value || option.id)
        })),
        items: rows.map((row) => ({
          id: String(row.id),
          text: row.label || row.text || row.id,
          correctCategoryId: String(answers[row.id] || "")
        })),
        feedback: item.feedback || {},
        skill: item.skill,
        sourceType: "matching",
        rows,
        options,
        answer: answers
      });
    }
    if (type === "order") {
      return block(`${activityId}-q-${index + 1}-${item.id}`, "short-response", {
        formative: true,
        questionId: namespacedQuestionId(activityId, item, index).questionId,
        sourceQuestionId: namespacedQuestionId(activityId, item, index).sourceQuestionId,
        prompt: item.prompt || "",
        items: item.items || item.options || [],
        answer: item.answer || item.answers,
        feedback: item.feedback || {},
        skill: item.skill,
        sourceType: "order"
      });
    }
    if (type === "multiple") {
      return convertMcq(activityId, { ...item, type: "single" }, index);
    }
    if (["predict-output", "code-gap", "line-select", "code-order", "code-editor"].includes(type)) {
      return block(`${activityId}-q-${item.id || index + 1}`, "code-editor", {
        formative: true,
        questionId: namespacedQuestionId(activityId, item, index).questionId,
    sourceQuestionId: namespacedQuestionId(activityId, item, index).sourceQuestionId,
        prompt: item.prompt || "",
        languages: item.languages,
        feedback: item.feedback || {},
        skill: item.skill,
        sourceType: type,
        starterCode: item.starterCode,
        code: item.code,
        accepted: item.accepted,
        rules: item.rules,
        items: item.items,
        editorRows: item.editorRows,
        hints: item.hints
      });
    }
    if (type === "text") {
      return block(`${activityId}-q-${item.id || index + 1}`, "short-response", {
        formative: true,
        questionId: namespacedQuestionId(activityId, item, index).questionId,
    sourceQuestionId: namespacedQuestionId(activityId, item, index).sourceQuestionId,
        prompt: item.prompt || "",
        accepted: item.accepted || item.answer,
        feedback: item.feedback || {},
        skill: item.skill,
        sourceType: "text",
        answerLabel: item.answerLabel
      });
    }
    return convertMcq(activityId, item, index);
  }
  if (item.correctType && item.text) {
    return null;
  }
  return convertMcq(activityId, item, index);
}

function convertCards(activityId, source) {
  const cards = source.cards || [];
  if (!cards.length) return [];
  const categories = [...new Set(cards.map((card) => card.correctType || card.category).filter(Boolean))]
    .map((id) => ({ id: String(id), label: String(id) }));
  return [block(`${activityId}-classification`, "classification", {
    formative: true,
    questionId: activityId,
    sourceQuestionId: activityId,
    prompt: source.title || source.activityName || "Classify each item",
    categories: categories.length ? categories : [
      { id: "a", label: "A" },
      { id: "b", label: "B" }
    ],
    items: cards.map((card) => ({
      id: String(card.id),
      text: card.text || card.prompt || "",
      correctCategoryId: String(card.correctType || card.category || ""),
      explanation: card.explanation || "",
      ambiguityNote: card.ambiguityNote,
      exploitPair: card.exploitPair
    }))
  })];
}

function convertSourceToBlocks(activityId, source) {
  const data = clone(source);
  const blocks = [];
  const title = data.title || data.activityName;
  if (title) blocks.push(block(`${activityId}-title`, "heading", { text: title, level: 2 }));
  if (data.description || data.purpose || data.intro || data.resultIntro) {
    blocks.push(block(`${activityId}-intro`, "paragraph", {
      text: data.description || data.purpose || data.intro || data.resultIntro
    }));
  }
  if (Array.isArray(data.sections)) {
    data.sections.forEach((section) => {
      blocks.push(block(`${activityId}-${section.id}-h`, "heading", { text: section.title || section.id, level: 3 }));
      if (section.intro) {
        blocks.push(block(`${activityId}-${section.id}-intro`, "paragraph", { text: section.intro }));
      }
      (section.questions || []).forEach((question, index) => {
        blocks.push(convertQuestion(activityId, question, index));
      });
    });
    delete data.sections;
  }
  const questionLists = ["questions", "knowledgeCheck", "items"];
  questionLists.forEach((key) => {
    if (!Array.isArray(data[key])) return;
    const looksLikeQuestions = data[key].some((item) => item && (item.prompt || item.options || item.type));
    if (!looksLikeQuestions) return;
    data[key].forEach((question, index) => {
      blocks.push(convertQuestion(activityId, question, index));
    });
    delete data[key];
  });
  if (Array.isArray(data.cards)) {
    blocks.push(...convertCards(activityId, data));
    delete data.cards;
  }
  ["activityId", "id", "title", "activityName", "activityVersion", "version", "total", "path"].forEach((key) => {
    delete data[key];
  });
  const remainder = remainderBlock(activityId, data);
  if (remainder) blocks.push(remainder);
  const interactive = new Set([
    "single-choice", "classification", "short-response", "reflection", "code-editor", "python-exercise"
  ]);
  if (!blocks.some((item) => interactive.has(item.type))) {
    blocks.push(block(`${activityId}-learner-note`, "reflection", {
      formative: true,
      questionId: `${activityId}:learner-note`,
      sourceQuestionId: "learner-note",
      prompt: "Complete this activity on the learner hub page, then write a short note to confirm you have finished."
    }));
  }
  return blocks.filter(Boolean);
}

function parseRemainder(activity) {
  const remainder = (activity.blocks || []).find((item) => item.id === `${activity.id}-source-remainder`);
  if (!remainder?.content?.text) return {};
  const match = String(remainder.content.text).match(/```json\n([\s\S]*?)\n```/);
  if (!match) return {};
  try {
    return JSON.parse(match[1]);
  } catch {
    return {};
  }
}

export function activityFromPackage(pkg, activityId) {
  const activity = (pkg.activities || []).find((item) => item.id === activityId);
  if (!activity) return null;
  const remainder = parseRemainder(activity);
  const restored = {
    id: activity.id,
    activityId: activity.id,
    version: activity.version,
    title: activity.metadata.title,
    ...remainder
  };
  const sections = [];
  let current = null;
  const questions = [];
  (activity.blocks || []).forEach((item) => {
    if (item.id?.endsWith("-source-remainder")) return;
    if (item.type === "heading" && item.content?.level === 3) {
      current = { id: item.id.replace(`${activity.id}-`, "").replace(/-h$/, ""), title: item.content.text, intro: "", questions: [] };
      sections.push(current);
      return;
    }
    if (item.type === "paragraph" && current && !current.intro) {
      current.intro = item.content?.text || "";
      return;
    }
    const content = item.content || {};
    if (!content.questionId && item.type !== "classification") return;
    if (content.sourceQuestionId === "learner-note") return;
    const question = {
      id: content.sourceQuestionId || String(content.questionId || item.id).split(":").pop(),
      type: content.sourceType || item.type,
      prompt: content.prompt || "",
      options: content.options,
      rows: content.rows,
      items: content.items,
      answer: content.answer || content.correctOptionId,
      answers: content.answers,
      accepted: content.accepted,
      feedback: content.feedback,
      skill: content.skill,
      languages: content.languages,
      commandWord: content.commandWord,
      marks: content.marks,
      scenario: content.scenario,
      explanation: content.feedback?.correct,
      correctIndex: Array.isArray(content.options)
        ? content.options.findIndex((option) => option.id === content.correctOptionId)
        : undefined,
      correctOptionId: content.correctOptionId,
      ...content
    };
    if (item.type === "classification" && content.sourceType !== "matching") {
      restored.cards = (content.items || []).map((card) => ({
        id: card.id,
        text: card.text,
        correctType: card.correctCategoryId,
        explanation: card.explanation,
        ambiguityNote: card.ambiguityNote,
        exploitPair: card.exploitPair
      }));
      return;
    }
    if (content.sourceType === "matching") {
      question.type = "matching";
      question.options = content.options;
      question.rows = content.rows;
      question.answer = content.answer;
    }
    if (current) current.questions.push(question);
    else questions.push(question);
  });
  if (sections.length) restored.sections = sections;
  if (questions.length) restored.questions = questions;
  return restored;
}

export function catalogFromPackage(pkg) {
  return (pkg.activities || []).map((activity) => ({
    id: activity.id,
    version: activity.version,
    title: activity.metadata?.title,
    purpose: activity.metadata?.summary,
    type: activity.metadata?.activityType,
    detail: activity.metadata?.detail,
    topics: activity.metadata?.topics || [],
    path: activity.metadata?.href
  }));
}

function convertUnit3() {
  const hubRoot = join(PROJECTS, "unit-3-Cyber-Security-Hub");
  const titles = {
    1: "Introduction to Cyber Security",
    2: "Threats and Vulnerabilities",
    3: "Types of attacker",
    4: "Motivations and targets",
    5: "Impacts of cyber security incidents",
    6: "Ethical, legal and operational considerations",
    7: "Risk management, testing and monitoring"
  };
  const registry = loadScript(join(hubRoot, "js/course-context.js")).Unit3CourseContext.ACTIVITY_REGISTRY;
  const globals = {};
  const sources = {};
  for (let week = 2; week <= 7; week += 1) {
    const dir = join(hubRoot, `week-${week}/data`);
    for (const name of readdirSync(dir).filter((file) => file.endsWith(".js"))) {
      const sandbox = loadScript(join(dir, name));
      Object.keys(sandbox).forEach((key) => {
        const value = sandbox[key];
        if (!value || typeof value !== "object" || Array.isArray(value)) return;
        const activityId = kebabActivityId(value.activityId || value.id);
        if (!activityId) return;
        sources[activityId] = clone(value);
        globals[activityId] = key;
      });
    }
  }

  const weeks = [];
  const sessions = [];
  const activities = [];
  const sessionActivities = {};

  Object.values(registry).forEach((entry) => {
    const id = kebabActivityId(entry.activityId);
    const weekNumber = entry.weekNumber;
    const sessionLabel = /2/.test(entry.sessionName || "") ? 2 : 1;
    const sessionId = `week-${weekNumber}-session-${sessionLabel}`;
    sessionActivities[sessionId] = sessionActivities[sessionId] || [];
    sessionActivities[sessionId].push(id);
    const source = sources[id] || {
      activityId: id,
      title: entry.activityName,
      description: weekNumber === 1
        ? "Week 1 item text continues to load through the existing Activity API until that copy is extracted into this package."
        : entry.activityName
    };
    activities.push(envelope("lp.content.activity", id, semver(entry.activityVersion), {
      title: entry.activityName,
      status: "available",
      summary: source.description || source.purpose || entry.activityName,
      href: null,
      activityType: entry.activityType,
      runtimeGlobal: globals[id] || null
    }, {
      learningOutcomes: ["LO1"],
      assignment: "formative-practice",
      questions: [],
      assets: []
    }, {
      blocks: convertSourceToBlocks(id, source)
    }));
  });

  for (let week = 1; week <= 7; week += 1) {
    const weekId = `week-${week}`;
    const weekSessions = [`week-${week}-session-1`, `week-${week}-session-2`];
    weeks.push(envelope("lp.content.week", weekId, "0.1.0", {
      teachingWeek: week,
      title: titles[week],
      status: "available"
    }, {
      curriculum: "unit-3-cyber-security-curriculum",
      learningOutcomes: ["LO1"],
      assignment: "formative-practice",
      sessions: weekSessions
    }));
    weekSessions.forEach((sessionId, index) => {
      sessions.push(envelope("lp.content.session", sessionId, "0.1.0", {
        title: `Session ${index + 1}`,
        kind: index === 0 ? "session" : "retrieval",
        sortOrder: index + 1
      }, {
        week: weekId,
        activities: sessionActivities[sessionId] || []
      }));
    });
  }

  const assigned = new Set(activities.map((item) => item.id));
  Object.keys(sources).forEach((id) => {
    if (assigned.has(id)) return;
    const source = sources[id];
    activities.push(envelope("lp.content.activity", id, "1.0.0", {
      title: source.title || source.activityName || id,
      status: "available",
      summary: source.description || "",
      href: null,
      runtimeGlobal: globals[id] || null
    }, {
      learningOutcomes: ["LO1"],
      assignment: "formative-practice",
      questions: [],
      assets: []
    }, {
      blocks: convertSourceToBlocks(id, source)
    }));
    const weekMatch = id.match(/^week(\d)/);
    const weekNumber = weekMatch ? Number(weekMatch[1]) : 2;
    const sessionId = `week-${weekNumber}-session-2`;
    const session = sessions.find((item) => item.id === sessionId);
    if (session && !session.relationships.activities.includes(id)) {
      session.relationships.activities.push(id);
    }
  });

  const assembled = {
    schema: "lp.content.package",
    schemaVersion: SCHEMA,
    id: "unit-3-cyber-security-content",
    version: "0.2.0",
    hub: envelope("lp.content.hub", "unit-3-cyber-security", "0.2.0", {
      name: "Unit 3 Cyber Security Hub",
      description: "OCR Level 3 IT Unit 3 Cyber Security learner hub."
    }, { curriculum: "unit-3-cyber-security-curriculum" }),
    curriculum: envelope("lp.content.curriculum", "unit-3-cyber-security-curriculum", "0.1.0", {
      title: "Unit 3 Cyber Security",
      course: "ocr-level-3-it"
    }, {
      learningOutcomes: ["LO1"],
      assignments: ["formative-practice"],
      weeks: weeks.map((item) => item.id)
    }),
    learningOutcomes: [envelope("lp.content.learning-outcome", "LO1", "0.1.0", {
      title: "Understand the need for cyber security"
    }, {})],
    assignments: [envelope("lp.content.assignment", "formative-practice", "0.1.0", {
      title: "Formative Unit 3 practice",
      status: "available"
    }, {})],
    weeks,
    sessions,
    activities,
    questions: [],
    assets: []
  };
  return { assembled, hubRoot, globals };
}

function convertTLevel() {
  const hubRoot = join(PROJECTS, "tlevel-software-development-hub");
  const catalog = loadScript(join(hubRoot, "js/data/foundations/catalog.js")).FoundationActivityCatalog;
  const files = {
    "foundations-programming-diagnostic": "programming-diagnostic.js",
    "foundations-requirements-classification": "requirements-classification.js",
    "foundations-problem-decomposition": "problem-decomposition.js",
    "foundations-data-design": "data-design.js",
    "foundations-testing-methods": "testing-methods.js"
  };
  const activities = catalog.map((entry) => {
    const source = loadScript(join(hubRoot, "js/data/foundations", files[entry.id])).FoundationActivityData;
    return envelope("lp.content.activity", entry.id, semver(entry.version), {
      title: entry.title,
      status: "available",
      summary: entry.purpose,
      href: entry.path,
      activityType: entry.type,
      topics: entry.topics,
      detail: entry.detail
    }, {
      learningOutcomes: ["foundations-lo"],
      assignment: "foundations-practice",
      questions: [],
      assets: []
    }, {
      blocks: convertSourceToBlocks(entry.id, source)
    });
  });
  const week = envelope("lp.content.week", "foundations", "0.1.0", {
    teachingWeek: 1,
    title: "Technical Foundations",
    status: "available"
  }, {
    curriculum: "tlevel-software-development-curriculum",
    learningOutcomes: ["foundations-lo"],
    assignment: "foundations-practice",
    sessions: catalog.map((entry) => `${entry.id}-session`)
  });
  const sessions = catalog.map((entry, index) => envelope("lp.content.session", `${entry.id}-session`, "0.1.0", {
    title: entry.title,
    kind: "session",
    sortOrder: index + 1
  }, {
    week: "foundations",
    activities: [entry.id]
  }));
  const assembled = {
    schema: "lp.content.package",
    schemaVersion: SCHEMA,
    id: "tlevel-software-development-content",
    version: "0.2.0",
    hub: envelope("lp.content.hub", "tlevel-software-development", "0.1.0", {
      name: "T Level Digital Software Development Hub",
      description: "T Level Digital Software Development learner hub."
    }, { curriculum: "tlevel-software-development-curriculum" }),
    curriculum: envelope("lp.content.curriculum", "tlevel-software-development-curriculum", "0.1.0", {
      title: "T Level Digital Software Development",
      course: "t-level-digital-software-development"
    }, {
      learningOutcomes: ["foundations-lo"],
      assignments: ["foundations-practice"],
      weeks: ["foundations"]
    }),
    learningOutcomes: [envelope("lp.content.learning-outcome", "foundations-lo", "0.1.0", {
      title: "Prepare for occupational software development tasks"
    }, {})],
    assignments: [envelope("lp.content.assignment", "foundations-practice", "0.1.0", {
      title: "Formative Foundations practice",
      status: "available"
    }, {})],
    weeks: [week],
    sessions,
    activities,
    questions: [],
    assets: []
  };
  return { assembled, hubRoot };
}

function guardDataFiles(hubRoot, pattern, token) {
  const files = [];
  function visit(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory() && entry.name !== "node_modules" && entry.name !== "vendor") visit(path);
      else if (entry.isFile() && pattern.test(path)) files.push(path);
    }
  }
  visit(hubRoot);
  files.forEach((path) => {
    const source = readFileSync(path, "utf8");
    if (source.includes("__lpPublishedCurriculum")) return;
    const next = source.replace(/('use strict';|"use strict";)\n/, `$1\n  if (typeof globalThis !== "undefined" && globalThis.__lpPublishedCurriculum) {\n    return;\n  }\n`);
    if (next !== source) writeFileSync(path, next);
  });
  return files.length;
}

function main() {
  const unit3 = convertUnit3();
  const tlevel = convertTLevel();
  for (const item of [unit3, tlevel]) {
    const result = validatePackage(item.assembled);
    if (!result.valid) {
      console.error(item.assembled.id, result.issues.slice(0, 20));
      throw new Error(`VALIDATION_FAILED:${item.assembled.id}:${result.issues.length}`);
    }
  }
  writePackage(join(unit3.hubRoot, "content/unit-3-cyber-security"), unit3.assembled);
  mkdirSync(join(unit3.hubRoot, "src/curriculum"), { recursive: true });
  writeFileSync(join(unit3.hubRoot, "src/curriculum/runtime-globals.json"), JSON.stringify(unit3.globals, null, 2) + "\n");
  writePackage(join(tlevel.hubRoot, "content/tlevel-software-development"), tlevel.assembled);
  guardDataFiles(join(unit3.hubRoot, "week-2"), /\/data\/.+\.js$/);
  guardDataFiles(join(unit3.hubRoot, "week-3"), /\/data\/.+\.js$/);
  guardDataFiles(join(unit3.hubRoot, "week-4"), /\/data\/.+\.js$/);
  guardDataFiles(join(unit3.hubRoot, "week-5"), /\/data\/.+\.js$/);
  guardDataFiles(join(unit3.hubRoot, "week-6"), /\/data\/.+\.js$/);
  guardDataFiles(join(unit3.hubRoot, "week-7"), /\/data\/.+\.js$/);
  guardDataFiles(join(tlevel.hubRoot, "js/data/foundations"), /\.js$/);
  console.log(JSON.stringify({
    unit3: { version: unit3.assembled.version, activities: unit3.assembled.activities.length, weeks: unit3.assembled.weeks.length },
    tlevel: { version: tlevel.assembled.version, activities: tlevel.assembled.activities.length, weeks: tlevel.assembled.weeks.length }
  }, null, 2));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
