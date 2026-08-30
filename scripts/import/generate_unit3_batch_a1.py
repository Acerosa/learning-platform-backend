#!/usr/bin/env python3
"""Generate the Batch A1 Unit 3 catalogue completeness migration.

Sources (do not merge blindly):
  Week 1 banks — live Activity API getActivity capture
  Week 5 four activities — deployed hub content package scored items
  Week 2 OCR Q08 — current hub week-2/data/ocr-practice.js

Versioning:
  Published 1.0.0 rows are immutable. Week 1 and Week 2 OCR get new 1.1.0
  versions. The four missing Week 5 activities get new 1.0.0 rows.
  Curriculum publication is not touched.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
import uuid

NAMESPACE = uuid.UUID("8c1b6c04-5ac5-4b36-bd1e-f2f8c2b2a0b1")
COURSE_KEY = "ocr-level-3-it"
MODULE_KEY = "unit-3-cyber-security"
PUBLISHED_AT = "2026-08-30T21:00:00Z"
NEW_WEEK1_VERSION = "1.1.0"
NEW_OCR_VERSION = "1.1.0"
WEEK5_VERSION = "1.0.0"

WEEK1_TYPE_MAP = {
    "single-choice": "single",
    "classification": "matching",
    "short-response": "text",
    "extended-response": "text",
    "reflection": "text",
    "self-assessment": "single",
}

WEEK1_DELIVERY = {
    "u3-w01-baseline": 1,
    "u3-w01-cia": 1,
    "u3-w01-incidents": 1,
    "u3-w01-glossary": 1,
    "u3-w01-command-words": 2,
    "u3-w01-ocr-practice": 2,
    "u3-w01-peer-improvement": 2,
    "u3-w01-retrieval": 2,
}

LIVE_ID_TO_KEY = {
    "U3-W01-BASELINE": "u3-w01-baseline",
    "U3-W01-CIA": "u3-w01-cia",
    "U3-W01-INCIDENTS": "u3-w01-incidents",
    "U3-W01-GLOSSARY": "u3-w01-glossary",
    "U3-W01-RETRIEVAL": "u3-w01-retrieval",
    "U3-W01-COMMAND-WORDS": "u3-w01-command-words",
    "U3-W01-OCR-PRACTICE": "u3-w01-ocr-practice",
    "U3-W01-PEER-IMPROVEMENT": "u3-w01-peer-improvement",
}

OCR_V100_QUESTIONS = (
    ("W2OCR-Q01", "single", 1, 1),
    ("W2OCR-Q02", "single", 2, 1),
    ("W2OCR-Q03", "single", 3, 2),
    ("W2OCR-Q04", "single", 4, 4),
    ("W2OCR-Q05", "single", 5, 3),
    ("W2OCR-Q06", "single", 6, 3),
    ("W2OCR-Q07", "text", 7, 6),
)

WEEK5_ACTIVITIES = (
    {
        "stableKey": "week5-vulnerability-patterns",
        "title": "Recognising vulnerability patterns",
        "gitPath": "week-5/vulnerability-patterns/index.html",
        "sessionNumber": 1,
        "sectionKey": "pattern-checks",
        "sectionTitle": "Pattern checks",
    },
    {
        "stableKey": "week5-threat-vulnerability-risk",
        "title": "Vulnerability, threat and risk",
        "gitPath": "week-5/threat-vulnerability-risk/index.html",
        "sessionNumber": 1,
        "sectionKey": "classify-statements",
        "sectionTitle": "Classify statements",
    },
    {
        "stableKey": "week5-controls-matching",
        "title": "Choosing defensive controls",
        "gitPath": "week-5/controls-matching/index.html",
        "sessionNumber": 2,
        "sectionKey": "match-controls",
        "sectionTitle": "Match controls",
    },
    {
        "stableKey": "week5-secure-rewrite",
        "title": "Improving insecure implementations",
        "gitPath": "week-5/secure-rewrite/index.html",
        "sessionNumber": 2,
        "sectionKey": "secure-rewrites",
        "sectionTitle": "Secure rewrites",
    },
)


def sql_literal(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def deterministic_id(kind, key):
    return str(uuid.uuid5(NAMESPACE, f"{kind}:{key}"))


def content_hash(payload) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def section_key(section_id: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", (section_id or "questions").lower()).strip("-")
    if not slug or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", slug):
        raise ValueError(f"invalid section key from {section_id!r}")
    return slug


def json_spec(spec: dict) -> str:
    return sql_literal(json.dumps(spec, separators=(",", ":"), ensure_ascii=False))


def week_select(week_no: int) -> str:
    return (
        "(select id from learning.curriculum_weeks where module_id = "
        "(select id from learning.modules where course_id = "
        f"(select id from learning.courses where stable_key = {sql_literal(COURSE_KEY)}) "
        f"and stable_key = {sql_literal(MODULE_KEY)}) "
        f"and stable_key = {sql_literal(f'week-{week_no}')})"
    )


def module_select() -> str:
    return (
        "(select id from learning.modules where course_id = "
        f"(select id from learning.courses where stable_key = {sql_literal(COURSE_KEY)}) "
        f"and stable_key = {sql_literal(MODULE_KEY)})"
    )


def emit_version_block(lines, *, activity_key, activity_id_sql, version, version_id, content_hash_value, max_score, question_count, week_no, session_number, questions):
    lines += [
        "insert into learning.activity_versions (id, activity_id, version, content_hash, max_score, question_count, published_at)",
        f"values ({sql_literal(version_id)}, {activity_id_sql}, {sql_literal(version)}, {sql_literal(content_hash_value)}, {sql_literal(max_score)}, {sql_literal(question_count)}, null)",
        "on conflict (activity_id, version) do nothing;",
        "",
    ]
    for question in questions:
        question_id = deterministic_id("question", f"{activity_key}:{version}:{question['stableKey']}")
        lines += [
            "insert into learning.questions (",
            "  id, activity_version_id, stable_key, section_key, section_title, question_type, analytics_title, ordinal, max_score",
            ")",
            "select",
            f"  {sql_literal(question_id)},",
            f"  {sql_literal(version_id)},",
            f"  {sql_literal(question['stableKey'])},",
            f"  {sql_literal(question['sectionKey'])},",
            f"  {sql_literal(question['sectionTitle'])},",
            f"  {sql_literal(question['questionType'])},",
            f"  {sql_literal(question['analyticsTitle'])},",
            f"  {sql_literal(question['ordinal'])},",
            f"  {sql_literal(question['maxScore'])}",
            "from learning.activity_versions as version",
            f"where version.id = {sql_literal(version_id)}",
            "  and version.published_at is null",
            "on conflict (activity_version_id, stable_key) do nothing;",
            "",
        ]
        spec = question.get("marking")
        if spec:
            lines += [
                "insert into learning.question_marking (question_id, spec)",
                "select question.id, " + json_spec(spec) + "::jsonb",
                "from learning.questions as question",
                "join learning.activity_versions as version on version.id = question.activity_version_id",
                f"where question.id = {sql_literal(question_id)}",
                "  and version.published_at is null",
                "on conflict (question_id) do nothing;",
                "",
            ]
    lines += [
        "update learning.activity_versions",
        f"set published_at = {sql_literal(PUBLISHED_AT)}::timestamptz",
        f"where id = {sql_literal(version_id)}",
        "  and published_at is null;",
        "",
        "insert into learning.activity_delivery (",
        "  activity_version_id, academic_year_id, curriculum_week_id, week_number, session_number, sort_order, active",
        ")",
        "select",
        f"  {sql_literal(version_id)},",
        "  academic_year.id,",
        f"  {week_select(week_no)},",
        f"  {week_no},",
        f"  {session_number},",
        "  0,",
        "  true",
        "from learning.academic_years as academic_year",
        "where academic_year.active",
        "  and not exists (",
        "    select 1 from learning.activity_delivery as delivery",
        f"    where delivery.activity_version_id = {sql_literal(version_id)}",
        "      and delivery.academic_year_id = academic_year.id",
        "      and delivery.group_id is null",
        "  )",
        "order by academic_year.code",
        "limit 1;",
        "",
        "insert into learning.activity_assignments (id, group_id, activity_version_id, required, active)",
        "select",
        f"  {sql_literal(deterministic_id('assignment', 'CYBER-TEST-A:' + activity_key + ':' + version))},",
        "  learner_group.id,",
        f"  {sql_literal(version_id)},",
        "  true,",
        "  true",
        "from learning.groups as learner_group",
        "where learner_group.code = 'CYBER-TEST-A'",
        "on conflict (group_id, activity_version_id) do update",
        "set required = excluded.required, active = excluded.active;",
        "",
    ]


def week1_questions(live_activity: dict) -> list[dict]:
    questions = []
    for index, raw in enumerate(live_activity["questions"], start=1):
        live_type = raw.get("questionType") or raw.get("type")
        mapped = WEEK1_TYPE_MAP.get(live_type)
        if not mapped:
            raise ValueError(f"unsupported live question type {live_type!r} for {raw.get('questionId')}")
        questions.append(
            {
                "stableKey": raw["questionId"],
                "sectionKey": section_key(raw.get("sectionId") or "questions"),
                "sectionTitle": raw.get("sectionTitle") or "Questions",
                "questionType": mapped,
                "analyticsTitle": raw["questionId"],
                "ordinal": index,
                "maxScore": int(raw.get("marks") or raw.get("maxScore") or 1),
                "marking": None,
            }
        )
    return questions


def generate(manifest_dir: Path) -> str:
    live = json.loads((manifest_dir / "week1-live-banks.json").read_text(encoding="utf-8"))
    week5 = json.loads((manifest_dir / "week5-four-activities.json").read_text(encoding="utf-8"))
    ocr_q08 = json.loads((manifest_dir / "week2-ocr-q08.json").read_text(encoding="utf-8"))

    lines = [
        "-- Generated by scripts/import/generate_unit3_batch_a1.py; do not edit manually.",
        "-- Batch A1: canonical Unit 3 catalogue completeness.",
        "-- Does not mutate published 1.0.0 rows, learner evidence, or curriculum publications.",
        "begin;",
        "",
    ]

    for live_id, activity_key in LIVE_ID_TO_KEY.items():
        bank = live[live_id]
        questions = week1_questions(bank)
        version_id = deterministic_id("version", f"{activity_key}:{NEW_WEEK1_VERSION}")
        payload = {
            "activityKey": activity_key,
            "version": NEW_WEEK1_VERSION,
            "source": "live-getActivity",
            "questions": questions,
        }
        emit_version_block(
            lines,
            activity_key=activity_key,
            activity_id_sql=f"(select id from learning.activities where stable_key = {sql_literal(activity_key)})",
            version=NEW_WEEK1_VERSION,
            version_id=version_id,
            content_hash_value=content_hash(payload),
            max_score=sum(question["maxScore"] for question in questions),
            question_count=len(questions),
            week_no=1,
            session_number=WEEK1_DELIVERY[activity_key],
            questions=questions,
        )

    ocr_key = "week2-ocr-question-practice"
    ocr_questions = [
        {
            "stableKey": stable_key,
            "sectionKey": "questions",
            "sectionTitle": "Questions",
            "questionType": question_type,
            "analyticsTitle": stable_key,
            "ordinal": ordinal,
            "maxScore": max_score,
            "marking": None,
        }
        for stable_key, question_type, ordinal, max_score in OCR_V100_QUESTIONS
    ]
    ocr_questions.append(
        {
            "stableKey": ocr_q08["stableKey"],
            "sectionKey": ocr_q08["sectionKey"],
            "sectionTitle": ocr_q08["sectionTitle"],
            "questionType": ocr_q08["questionType"],
            "analyticsTitle": ocr_q08["stableKey"],
            "ordinal": ocr_q08["ordinal"],
            "maxScore": ocr_q08["maxScore"],
            "marking": None,
        }
    )
    ocr_version_id = deterministic_id("version", f"{ocr_key}:{NEW_OCR_VERSION}")
    emit_version_block(
        lines,
        activity_key=ocr_key,
        activity_id_sql=f"(select id from learning.activities where stable_key = {sql_literal(ocr_key)})",
        version=NEW_OCR_VERSION,
        version_id=ocr_version_id,
        content_hash_value=content_hash({"activityKey": ocr_key, "version": NEW_OCR_VERSION, "questions": ocr_questions}),
        max_score=sum(question["maxScore"] for question in ocr_questions),
        question_count=len(ocr_questions),
        week_no=2,
        session_number=2,
        questions=ocr_questions,
    )

    for meta in WEEK5_ACTIVITIES:
        activity_key = meta["stableKey"]
        source = week5[activity_key]
        questions = []
        for index, raw in enumerate(source["questions"], start=1):
            marking = None
            if raw["questionType"] == "single" and raw.get("correctOptionId"):
                marking = {"mode": "single-choice", "correctOptionId": raw["correctOptionId"]}
            elif raw["questionType"] == "matching" and raw.get("correctCategoryId"):
                marking = {"mode": "classification", "correctCategoryId": raw["correctCategoryId"]}
            questions.append(
                {
                    "stableKey": raw["stableKey"],
                    "sectionKey": meta["sectionKey"],
                    "sectionTitle": meta["sectionTitle"],
                    "questionType": raw["questionType"],
                    "analyticsTitle": raw["stableKey"],
                    "ordinal": index,
                    "maxScore": 1,
                    "marking": marking,
                }
            )
        activity_id = deterministic_id("activity", f"{COURSE_KEY}:{MODULE_KEY}:{activity_key}")
        version_id = deterministic_id("version", f"{activity_key}:{WEEK5_VERSION}")
        lines += [
            "insert into learning.activities (id, module_id, stable_key, title, activity_type, git_path, active)",
            f"values ({sql_literal(activity_id)}, {module_select()}, {sql_literal(activity_key)}, {sql_literal(meta['title'])}, 'practice', {sql_literal(meta['gitPath'])}, true)",
            "on conflict (stable_key) do update set title = excluded.title, git_path = excluded.git_path, active = true;",
            "",
        ]
        emit_version_block(
            lines,
            activity_key=activity_key,
            activity_id_sql=sql_literal(activity_id),
            version=WEEK5_VERSION,
            version_id=version_id,
            content_hash_value=content_hash({"activityKey": activity_key, "version": WEEK5_VERSION, "questions": questions}),
            max_score=sum(question["maxScore"] for question in questions),
            question_count=len(questions),
            week_no=5,
            session_number=meta["sessionNumber"],
            questions=questions,
        )

    lines += ["commit;", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Unit 3 Batch A1 catalogue SQL.")
    default_manifest = Path(__file__).resolve().parents[2] / "supabase/data/manifests/unit3-batch-a1"
    parser.add_argument("--manifest-dir", type=Path, default=default_manifest)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    sql = generate(args.manifest_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(sql, encoding="utf-8")
    print(f"Generated {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
