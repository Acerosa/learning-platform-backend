#!/usr/bin/env python3
"""Validate a canonical lp.content package and generate backend registration SQL.

The hub remains the curriculum authoring source. This module produces a
reviewed catalogue artefact: identities, weeks, Week 1 questions/versions and
formative marking metadata. It does not copy teaching prose into the database
and it does not invent OCR assignment tables.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from hashlib import sha256
import json
from pathlib import Path
import re
from typing import Any
import uuid


ROOT = Path(__file__).resolve().parents[2]
SUPPORTED_SCHEMA_VERSION = "0.1.0"
REGISTRATION_VERSION = "0.1.0"
NAMESPACE = uuid.UUID("c014a7e0-14e1-4c14-9e14-0a14c0140001")
STABLE_KEY_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SEMVER_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
QUESTION_KEY_PATTERN = re.compile(r"^[A-Za-z0-9._:-]+$")

INTERACTIVE_TYPES = {
    "single-choice",
    "classification",
    "short-response",
    "reflection",
    "code-editor",
    "python-exercise",
}
PROSE_TYPES = {
    "heading",
    "paragraph",
    "markdown",
    "image",
    "video",
    "callout",
    "accordion",
    "reference",
    "hint",
    "quote",
    "divider",
    "teacher-note",
}
QUESTION_TYPE_MAP = {
    "single-choice": "single",
    "classification": "matching",
    "short-response": "text",
    "reflection": "text",
    "code-editor": "code-editor",
    "python-exercise": "code-editor",
}


class PackageError(ValueError):
    def __init__(self, code: str, path: str, message: str) -> None:
        super().__init__(f"{code} at {path}: {message}")
        self.code = code
        self.path = path
        self.message = message


@dataclass
class ValidationIssue:
    code: str
    path: str
    message: str

    def render(self) -> str:
        return f"{self.code} at {self.path}: {self.message}"


@dataclass
class ContentPackage:
    directory: Path
    index: dict[str, Any]
    hub: dict[str, Any]
    curriculum: dict[str, Any]
    learning_outcomes: list[dict[str, Any]]
    assignments: list[dict[str, Any]]
    weeks: list[dict[str, Any]]
    sessions: list[dict[str, Any]]
    activities: list[dict[str, Any]]
    issues: list[ValidationIssue] = field(default_factory=list)


def sql_literal(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def deterministic_id(kind: str, key: str) -> str:
    return str(uuid.uuid5(NAMESPACE, f"{kind}:{key}"))


def content_hash(value: Any) -> str:
    return sha256(canonical_json(value).encode("utf-8")).hexdigest()


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PackageError("INVALID_JSON", str(path), str(error)) from error


def _as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def js_pattern_to_posix(pattern: str) -> str:
    return (
        pattern.replace(r"\s", "[[:space:]]")
        .replace(r"\d", "[[:digit:]]")
        .replace(r"\w", "[[:alnum:]_]")
    )


def lo_key(value: str) -> str:
    return value.strip().lower()


def load_package(directory: str | Path) -> ContentPackage:
    root = Path(directory).resolve()
    index_path = root / "index.json"
    index = load_json(index_path)
    if not isinstance(index, dict):
        raise PackageError("INVALID_SCHEMA", "index.json", "package index must be an object")
    relations = index.get("relationships") or {}

    def load_related(name: str) -> Any:
        relative = relations.get(name)
        if not isinstance(relative, str) or not relative:
            raise PackageError("BROKEN_REFERENCE", f"index.json.relationships.{name}", "missing file pointer")
        return load_json(root / relative)

    return ContentPackage(
        directory=root,
        index=index,
        hub=load_related("hub"),
        curriculum=load_related("curriculum"),
        learning_outcomes=_as_list(load_related("learningOutcomes")),
        assignments=_as_list(load_related("assignments")),
        weeks=_as_list(load_related("weeks")),
        sessions=_as_list(load_related("sessions")),
        activities=_as_list(load_related("activities")),
    )


def _require_envelope(document: dict[str, Any], schema: str, path: str, issues: list[ValidationIssue]) -> None:
    if document.get("schema") != schema:
        issues.append(ValidationIssue("INVALID_SCHEMA", f"{path}.schema", f"expected {schema}"))
    version = document.get("schemaVersion")
    if version != SUPPORTED_SCHEMA_VERSION:
        issues.append(
            ValidationIssue(
                "UNSUPPORTED_CONTENT_VERSION",
                f"{path}.schemaVersion",
                f"supported schemaVersion is {SUPPORTED_SCHEMA_VERSION}",
            )
        )
    if not isinstance(document.get("id"), str) or not document["id"].strip():
        issues.append(ValidationIssue("INVALID_SCHEMA", f"{path}.id", "id is required"))
    if not isinstance(document.get("version"), str) or not SEMVER_PATTERN.fullmatch(document.get("version") or ""):
        issues.append(ValidationIssue("UNSUPPORTED_CONTENT_VERSION", f"{path}.version", "version must be x.y.z"))


def validate_package(package: ContentPackage) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    _require_envelope(package.index, "lp.content.package", "index.json", issues)
    _require_envelope(package.hub, "lp.content.hub", "hub.json", issues)
    _require_envelope(package.curriculum, "lp.content.curriculum", "curriculum.json", issues)

    seen_ids: dict[str, str] = {}

    def remember(doc_id: str, path: str) -> None:
        if doc_id in seen_ids:
            issues.append(ValidationIssue("DUPLICATE_ID", path, f"{doc_id!r} already used at {seen_ids[doc_id]}"))
        else:
            seen_ids[doc_id] = path

    remember(package.index["id"], "index.json")
    remember(package.hub["id"], "hub.json")
    remember(package.curriculum["id"], "curriculum.json")

    lo_ids: set[str] = set()
    for index, outcome in enumerate(package.learning_outcomes):
        path = f"learning-outcomes.json[{index}]"
        if not isinstance(outcome, dict):
            issues.append(ValidationIssue("INVALID_SCHEMA", path, "learning outcome must be an object"))
            continue
        _require_envelope(outcome, "lp.content.learning-outcome", path, issues)
        remember(str(outcome.get("id")), path)
        lo_ids.add(str(outcome.get("id")))
        if not STABLE_KEY_PATTERN.fullmatch(lo_key(str(outcome.get("id") or ""))):
            issues.append(ValidationIssue("INVALID_SCHEMA", f"{path}.id", "learning outcome id must map to a stable key"))

    assignment_ids: set[str] = set()
    for index, assignment in enumerate(package.assignments):
        path = f"assignments.json[{index}]"
        if not isinstance(assignment, dict):
            issues.append(ValidationIssue("INVALID_SCHEMA", path, "assignment must be an object"))
            continue
        _require_envelope(assignment, "lp.content.assignment", path, issues)
        remember(str(assignment.get("id")), path)
        assignment_ids.add(str(assignment.get("id")))
        for outcome_id in assignment.get("relationships", {}).get("learningOutcomes") or []:
            if outcome_id not in lo_ids:
                issues.append(ValidationIssue("BROKEN_REFERENCE", f"{path}.relationships.learningOutcomes", str(outcome_id)))

    week_ids: set[str] = set()
    for index, week in enumerate(package.weeks):
        path = f"weeks.json[{index}]"
        if not isinstance(week, dict):
            issues.append(ValidationIssue("INVALID_SCHEMA", path, "week must be an object"))
            continue
        _require_envelope(week, "lp.content.week", path, issues)
        remember(str(week.get("id")), path)
        week_ids.add(str(week.get("id")))
        if not STABLE_KEY_PATTERN.fullmatch(str(week.get("id") or "")):
            issues.append(ValidationIssue("INVALID_SCHEMA", f"{path}.id", "week id must be a stable key"))
        metadata = week.get("metadata") or {}
        if not isinstance(metadata.get("teachingWeek"), int) or metadata["teachingWeek"] <= 0:
            issues.append(ValidationIssue("INVALID_SCHEMA", f"{path}.metadata.teachingWeek", "positive week number required"))
        for outcome_id in week.get("relationships", {}).get("learningOutcomes") or []:
            if outcome_id not in lo_ids:
                issues.append(ValidationIssue("BROKEN_REFERENCE", f"{path}.relationships.learningOutcomes", str(outcome_id)))
        assignment_id = week.get("relationships", {}).get("assignment")
        if assignment_id and assignment_id not in assignment_ids:
            issues.append(ValidationIssue("BROKEN_REFERENCE", f"{path}.relationships.assignment", str(assignment_id)))

    session_ids: set[str] = set()
    activity_ids_from_sessions: set[str] = set()
    for index, session in enumerate(package.sessions):
        path = f"sessions.json[{index}]"
        if not isinstance(session, dict):
            issues.append(ValidationIssue("INVALID_SCHEMA", path, "session must be an object"))
            continue
        _require_envelope(session, "lp.content.session", path, issues)
        remember(str(session.get("id")), path)
        session_ids.add(str(session.get("id")))
        week_id = (session.get("relationships") or {}).get("week")
        if week_id not in week_ids:
            issues.append(ValidationIssue("BROKEN_REFERENCE", f"{path}.relationships.week", str(week_id)))
        for activity_id in (session.get("relationships") or {}).get("activities") or []:
            activity_ids_from_sessions.add(str(activity_id))

    for week_index, week in enumerate(package.weeks):
        for session_id in (week.get("relationships") or {}).get("sessions") or []:
            if session_id not in session_ids:
                issues.append(
                    ValidationIssue(
                        "BROKEN_REFERENCE",
                        f"weeks.json[{week_index}].relationships.sessions",
                        str(session_id),
                    )
                )

    question_keys: set[str] = set()
    activity_ids: set[str] = set()
    for index, activity in enumerate(package.activities):
        path = f"activities.json[{index}]"
        if not isinstance(activity, dict):
            issues.append(ValidationIssue("INVALID_SCHEMA", path, "activity must be an object"))
            continue
        _require_envelope(activity, "lp.content.activity", path, issues)
        activity_id = str(activity.get("id") or "")
        remember(activity_id, path)
        activity_ids.add(activity_id)
        if not STABLE_KEY_PATTERN.fullmatch(activity_id):
            issues.append(ValidationIssue("INVALID_SCHEMA", f"{path}.id", "activity id must be a stable key"))
        for outcome_id in (activity.get("relationships") or {}).get("learningOutcomes") or []:
            if outcome_id not in lo_ids:
                issues.append(ValidationIssue("BROKEN_REFERENCE", f"{path}.relationships.learningOutcomes", str(outcome_id)))
        assignment_id = (activity.get("relationships") or {}).get("assignment")
        if assignment_id and assignment_id not in assignment_ids:
            issues.append(ValidationIssue("BROKEN_REFERENCE", f"{path}.relationships.assignment", str(assignment_id)))
        extracted: list[dict[str, Any]] = []
        try:
            extracted = extract_questions(activity)
        except PackageError as error:
            issues.append(ValidationIssue(error.code, error.path, error.message))
        for question in extracted:
            key = question["stableKey"]
            if key in question_keys:
                issues.append(ValidationIssue("DUPLICATE_ID", f"{path}.questions", f"duplicate question key {key}"))
            question_keys.add(key)
        if not extracted:
            issues.append(
                ValidationIssue(
                    "UNSUPPORTED_ACTIVITY_EVIDENCE",
                    path,
                    "published activities must expose at least one registrable evidence item",
                )
            )

    for activity_id in sorted(activity_ids_from_sessions - activity_ids):
        issues.append(ValidationIssue("BROKEN_REFERENCE", "sessions.json.relationships.activities", activity_id))

    course_key = ((package.curriculum.get("metadata") or {}).get("course"))
    if not isinstance(course_key, str) or not STABLE_KEY_PATTERN.fullmatch(course_key):
        issues.append(ValidationIssue("INVALID_SCHEMA", "curriculum.json.metadata.course", "course stable key required"))

    package.issues = issues
    return issues


def extract_questions(activity: dict[str, Any]) -> list[dict[str, Any]]:
    questions: list[dict[str, Any]] = []
    activity_id = activity.get("id") or "activity"
    for block_index, block in enumerate(activity.get("blocks") or []):
        if not isinstance(block, dict):
            raise PackageError("INVALID_SCHEMA", f"{activity_id}.blocks[{block_index}]", "block must be an object")
        block_type = str(block.get("type") or "")
        content = block.get("content") if isinstance(block.get("content"), dict) else {}
        path = f"{activity_id}.blocks[{block_index}]"
        if block_type in PROSE_TYPES:
            continue
        if block_type not in INTERACTIVE_TYPES:
            if content.get("questionId"):
                raise PackageError("UNSUPPORTED_ACTIVITY_EVIDENCE", path, f"unsupported interactive type {block_type}")
            continue
        question_id = str(content.get("questionId") or "")
        if not question_id or not QUESTION_KEY_PATTERN.fullmatch(question_id):
            raise PackageError("INVALID_SCHEMA", f"{path}.content.questionId", "questionId is required")
        backend_type = QUESTION_TYPE_MAP[block_type]
        if block_type == "classification":
            items = content.get("items") or []
            if not items:
                raise PackageError("UNSUPPORTED_ACTIVITY_EVIDENCE", path, "classification items are required")
            for item in items:
                item_id = str((item or {}).get("id") or "")
                if not item_id or not QUESTION_KEY_PATTERN.fullmatch(item_id):
                    raise PackageError("INVALID_SCHEMA", f"{path}.items", "classification item id is required")
                stable_key = f"{question_id}:{item_id}"
                correct = (item or {}).get("correctCategoryId")
                marking = (
                    {"mode": "classification", "correctCategoryId": str(correct)}
                    if isinstance(correct, str) and correct
                    else {"mode": "completion"}
                )
                questions.append(_question(stable_key, backend_type, marking, len(questions) + 1))
            continue
        marking = _block_marking(block_type, content, path)
        questions.append(_question(question_id, backend_type, marking, len(questions) + 1))
    return questions


def _question(stable_key: str, question_type: str, marking: dict[str, Any], ordinal: int) -> dict[str, Any]:
    return {
        "stableKey": stable_key,
        "questionType": question_type,
        "analyticsTitle": stable_key,
        "ordinal": ordinal,
        "maxScore": 1,
        "marking": marking,
    }


def _block_marking(block_type: str, content: dict[str, Any], path: str) -> dict[str, Any]:
    if block_type == "single-choice":
        correct = content.get("correctOptionId")
        if isinstance(correct, str) and correct:
            return {"mode": "single-choice", "correctOptionId": correct}
        return {"mode": "completion"}
    if block_type in {"short-response", "reflection"}:
        return {"mode": "completion"}
    if block_type in {"code-editor", "python-exercise"}:
        required = []
        checks = content.get("checks") if isinstance(content.get("checks"), dict) else {}
        for item in checks.get("required") or []:
            pattern = (item or {}).get("pattern")
            if not isinstance(pattern, str) or not pattern:
                raise PackageError("INVALID_SCHEMA", f"{path}.checks.required", "pattern is required")
            required.append(js_pattern_to_posix(pattern))
        prohibited = []
        for item in checks.get("prohibited") or []:
            pattern = (item or {}).get("pattern")
            if not isinstance(pattern, str) or not pattern:
                raise PackageError("INVALID_SCHEMA", f"{path}.checks.prohibited", "pattern is required")
            prohibited.append(js_pattern_to_posix(pattern))
        if required or prohibited:
            return {"mode": "python-patterns", "required": required, "prohibited": prohibited}
        return {"mode": "completion"}
    return {"mode": "completion"}


def activity_type_for(activity: dict[str, Any]) -> str:
    types = {str(block.get("type") or "") for block in activity.get("blocks") or []}
    activity_id = str(activity.get("id") or "")
    if "diagnostic" in activity_id:
        return "diagnostic"
    if "python-exercise" in types or "code-editor" in types:
        return "coding-exercise"
    if "classification" in types:
        return "classification"
    if "single-choice" in types:
        return "diagnostic"
    return "reflection"


def activity_requires_python(activity: dict[str, Any]) -> bool:
    return any(
        str(block.get("type") or "") in {"python-exercise", "code-editor"}
        for block in activity.get("blocks") or []
    )


def build_registration(package: ContentPackage) -> dict[str, Any]:
    issues = validate_package(package)
    if issues:
        raise PackageError(issues[0].code, issues[0].path, issues[0].message)
    course_key = package.curriculum["metadata"]["course"]
    module_key = package.hub["id"]
    sessions_by_id = {session["id"]: session for session in package.sessions}
    activity_delivery: dict[str, dict[str, Any]] = {}
    for week in package.weeks:
        week_number = week["metadata"]["teachingWeek"]
        for session_id in week.get("relationships", {}).get("sessions") or []:
            session = sessions_by_id[session_id]
            session_number = int((session.get("metadata") or {}).get("sortOrder") or 0) or None
            for sort_order, activity_id in enumerate(session.get("relationships", {}).get("activities") or [], start=1):
                activity_delivery[activity_id] = {
                    "weekKey": week["id"],
                    "weekNumber": week_number,
                    "sessionNumber": session_number,
                    "sortOrder": sort_order,
                }

    activities = []
    for activity in sorted(package.activities, key=lambda item: item["id"]):
        questions = extract_questions(activity)
        delivery = activity_delivery.get(activity["id"])
        if delivery is None:
            raise PackageError("BROKEN_REFERENCE", activity["id"], "activity is not referenced by a session")
        version = activity["version"]
        question_payload = [
            {
                "stableKey": question["stableKey"],
                "questionType": question["questionType"],
                "ordinal": question["ordinal"],
                "marking": question["marking"],
            }
            for question in questions
        ]
        activities.append(
            {
                "id": activity["id"],
                "title": activity["metadata"]["title"],
                "version": version,
                "activityType": activity_type_for(activity),
                "requiresPython": activity_requires_python(activity),
                "gitPath": f"content/unit-14/activities/{activity['id']}",
                "delivery": delivery,
                "learningOutcomes": [
                    lo_key(item) for item in (activity.get("relationships") or {}).get("learningOutcomes") or []
                ],
                "questions": questions,
                "contentHash": content_hash(
                    {
                        "activityKey": activity["id"],
                        "version": version,
                        "questions": question_payload,
                    }
                ),
            }
        )

    return {
        "registrationVersion": REGISTRATION_VERSION,
        "provenance": {
            "hubId": package.hub["id"],
            "contentId": package.index["id"],
            "contentVersion": package.index["version"],
            "sourceSchemaVersion": package.index["schemaVersion"],
            "generatedBackendRegistrationVersion": REGISTRATION_VERSION,
        },
        "courseKey": course_key,
        "module": {
            "stableKey": module_key,
            "title": (package.curriculum.get("metadata") or {}).get("title") or package.hub["metadata"]["name"],
            "sortOrder": 14,
        },
        "topics": [
            {
                "stableKey": lo_key(outcome["id"]),
                "title": outcome["metadata"]["title"],
                "sortOrder": index,
                "sourceId": outcome["id"],
            }
            for index, outcome in enumerate(package.learning_outcomes, start=1)
        ],
        "weeks": [
            {
                "stableKey": week["id"],
                "title": week["metadata"]["title"],
                "weekNumber": week["metadata"]["teachingWeek"],
                "sortOrder": week["metadata"]["teachingWeek"],
            }
            for week in sorted(package.weeks, key=lambda item: item["metadata"]["teachingWeek"])
        ],
        "assignments": [
            {
                "id": assignment["id"],
                "stableKey": (assignment.get("metadata") or {}).get("key") or lo_key(assignment["id"]),
                "title": assignment["metadata"]["title"],
                "hubOnly": True,
                "reason": "learning.activity_assignments is group delivery, not an OCR assignment catalogue",
            }
            for assignment in package.assignments
        ],
        "hubOnly": [
            "OCR assignment criteria and Pass/Merit/Distinction judgement",
            "session teaching copy and block prose",
            "planner dates (null in the canonical package)",
            "Weeks 2–19 activity and session content",
        ],
        "activities": activities,
        "deliveryGroup": {
            "code": "UNIT14-TEST-A",
            "name": "Unit 14 Synthetic Test Group A",
            "registrationKey": "unit14-year-1-test",
            "registrationOpen": False,
            "yearGroup": "Year 1",
        },
    }


def generate_sql(registration: dict[str, Any], *, published_at: str = "2026-08-13T12:00:00Z") -> str:
    course_key = registration["courseKey"]
    module = registration["module"]
    module_key = module["stableKey"]
    module_id = deterministic_id("module", f"{course_key}:{module_key}")
    group = registration["deliveryGroup"]
    group_id = deterministic_id("group", group["code"].lower())
    lines = [
        "-- Generated by scripts/import/generate-content-package-migration.py; review before applying.",
        f"-- hub_id: {registration['provenance']['hubId']}",
        f"-- content_id: {registration['provenance']['contentId']}",
        f"-- content_version: {registration['provenance']['contentVersion']}",
        f"-- source_schema_version: {registration['provenance']['sourceSchemaVersion']}",
        f"-- generated_backend_registration_version: {registration['provenance']['generatedBackendRegistrationVersion']}",
        "-- OCR A1–A4 remain hub-owned; this file does not insert an assignment catalogue.",
        "begin;",
        "",
        "select pg_catalog.pg_advisory_xact_lock(",
        f"  pg_catalog.hashtextextended({sql_literal('content-package:' + module_key)}, 0)",
        ");",
        "",
        "do $$",
        "begin",
        "  if not exists (",
        "    select 1 from learning.courses as course",
        f"    where course.stable_key = {sql_literal(course_key)} and course.active",
        "  ) then",
        f"    raise exception using errcode = '23514', message = {sql_literal('CONTENT_COURSE_NOT_FOUND:' + course_key)};",
        "  end if;",
        "end",
        "$$;",
        "",
        "insert into learning.modules (id, course_id, stable_key, title, sort_order, active)",
        "select",
        f"  {sql_literal(module_id)},",
        "  course.id,",
        f"  {sql_literal(module_key)},",
        f"  {sql_literal(module['title'])},",
        f"  {sql_literal(module['sortOrder'])},",
        "  true",
        "from learning.courses as course",
        f"where course.stable_key = {sql_literal(course_key)}",
        "  and course.active",
        "on conflict (course_id, stable_key) do update set",
        "  title = excluded.title,",
        "  sort_order = excluded.sort_order,",
        "  active = true;",
        "",
    ]

    for topic in registration["topics"]:
        topic_id = deterministic_id("topic", f"{course_key}:{module_key}:{topic['stableKey']}")
        lines += [
            "insert into learning.topics (id, module_id, stable_key, title, sort_order, active)",
            f"values ({sql_literal(topic_id)}, {sql_literal(module_id)}, {sql_literal(topic['stableKey'])}, {sql_literal(topic['title'])}, {sql_literal(topic['sortOrder'])}, true)",
            "on conflict (module_id, stable_key) do update set title = excluded.title, sort_order = excluded.sort_order, active = true;",
            "",
        ]

    for week in registration["weeks"]:
        week_id = deterministic_id("week", f"{course_key}:{module_key}:{week['stableKey']}")
        lines += [
            "insert into learning.curriculum_weeks (id, module_id, stable_key, title, week_number, sort_order, active)",
            f"values ({sql_literal(week_id)}, {sql_literal(module_id)}, {sql_literal(week['stableKey'])}, {sql_literal(week['title'])}, {sql_literal(week['weekNumber'])}, {sql_literal(week['sortOrder'])}, true)",
            "on conflict (module_id, stable_key) do update set title = excluded.title, week_number = excluded.week_number, sort_order = excluded.sort_order, active = true;",
            "",
        ]

    lines += [
        "insert into learning.groups (",
        "  id, academic_year_id, course_id, code, name, active, year_group, registration_key, registration_open",
        ")",
        "select",
        f"  {sql_literal(group_id)},",
        "  academic_year.id,",
        "  course.id,",
        f"  {sql_literal(group['code'])},",
        f"  {sql_literal(group['name'])},",
        "  true,",
        f"  {sql_literal(group['yearGroup'])},",
        f"  {sql_literal(group['registrationKey'])},",
        f"  {sql_literal(group['registrationOpen'])}",
        "from learning.courses as course",
        "join lateral (",
        "  select candidate.id from learning.academic_years as candidate",
        "  where candidate.active order by candidate.code limit 1",
        ") as academic_year on true",
        f"where course.stable_key = {sql_literal(course_key)} and course.active",
        "on conflict (academic_year_id, course_id, code) do update set",
        "  name = excluded.name, active = excluded.active, year_group = excluded.year_group,",
        "  registration_key = excluded.registration_key, registration_open = excluded.registration_open;",
        "",
    ]

    for activity in registration["activities"]:
        activity_id = deterministic_id("activity", activity["id"])
        version_id = deterministic_id("version", f"{activity['id']}:{activity['version']}")
        week_id = deterministic_id("week", f"{course_key}:{module_key}:{activity['delivery']['weekKey']}")
        question_count = len(activity["questions"])
        max_score = question_count
        lines += [
            "insert into learning.activities (id, module_id, stable_key, title, activity_type, git_path, active)",
            f"values ({sql_literal(activity_id)}, {sql_literal(module_id)}, {sql_literal(activity['id'])}, {sql_literal(activity['title'])}, {sql_literal(activity['activityType'])}, {sql_literal(activity['gitPath'])}, true)",
            "on conflict (stable_key) do update set title = excluded.title, activity_type = excluded.activity_type, git_path = excluded.git_path, active = true;",
            "",
            "insert into learning.activity_versions (id, activity_id, version, content_hash, max_score, question_count, published_at)",
            f"values ({sql_literal(version_id)}, {sql_literal(activity_id)}, {sql_literal(activity['version'])}, {sql_literal(activity['contentHash'])}, {sql_literal(max_score)}, {sql_literal(question_count)}, null)",
            "on conflict (activity_id, version) do nothing;",
            "",
        ]
        if activity["requiresPython"]:
            lines += [
                "insert into learning.activity_version_languages (activity_version_id, coding_language_id)",
                "select version.id, coding_language.id",
                "from learning.activity_versions as version",
                "join learning.coding_languages as coding_language",
                "  on coding_language.stable_key = 'python' and coding_language.active",
                f"where version.id = {sql_literal(version_id)}",
                "  and version.published_at is null",
                "on conflict (activity_version_id, coding_language_id) do nothing;",
                "",
            ]
        for question in activity["questions"]:
            question_id = deterministic_id("question", f"{activity['id']}:{activity['version']}:{question['stableKey']}")
            spec = canonical_json(question["marking"])
            topic_keys = activity["learningOutcomes"] or ["lo1"]
            lines += [
                "insert into learning.questions (",
                "  id, activity_version_id, stable_key, section_key, section_title, question_type, analytics_title, ordinal, max_score",
                ")",
                "select",
                f"  {sql_literal(question_id)},",
                f"  {sql_literal(version_id)},",
                f"  {sql_literal(question['stableKey'])},",
                f"  {sql_literal(activity['delivery']['weekKey'])},",
                f"  {sql_literal('Week ' + str(activity['delivery']['weekNumber']))},",
                f"  {sql_literal(question['questionType'])},",
                f"  {sql_literal(question['analyticsTitle'])},",
                f"  {sql_literal(question['ordinal'])},",
                f"  {sql_literal(question['maxScore'])}",
                "from learning.activity_versions as version",
                f"where version.id = {sql_literal(version_id)}",
                "  and version.published_at is null",
                "on conflict (activity_version_id, stable_key) do nothing;",
                "",
                "insert into learning.question_marking (question_id, spec)",
                "select question.id, " + sql_literal(spec) + "::jsonb",
                "from learning.questions as question",
                "join learning.activity_versions as version on version.id = question.activity_version_id",
                f"where question.id = {sql_literal(question_id)}",
                "  and version.published_at is null",
                "on conflict (question_id) do nothing;",
                "",
            ]
            for topic_key in topic_keys:
                topic_id = deterministic_id("topic", f"{course_key}:{module_key}:{topic_key}")
                lines += [
                    "insert into learning.question_topics (question_id, topic_id, weight)",
                    "select question.id, " + sql_literal(topic_id) + ", 1",
                    "from learning.questions as question",
                    "join learning.activity_versions as version on version.id = question.activity_version_id",
                    f"where question.id = {sql_literal(question_id)}",
                    "  and version.published_at is null",
                    "on conflict (question_id, topic_id) do nothing;",
                    "",
                ]
        lines += [
            "update learning.activity_versions",
            f"set published_at = {sql_literal(published_at)}::timestamptz",
            f"where id = {sql_literal(version_id)}",
            "  and published_at is null;",
            "",
            "insert into learning.activity_delivery (",
            "  activity_version_id, academic_year_id, curriculum_week_id, week_number, session_number, sort_order, active",
            ")",
            "select",
            f"  {sql_literal(version_id)},",
            "  academic_year.id,",
            f"  {sql_literal(week_id)},",
            f"  {sql_literal(activity['delivery']['weekNumber'])},",
            f"  {sql_literal(activity['delivery']['sessionNumber'])},",
            f"  {sql_literal(activity['delivery']['sortOrder'])},",
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
            f"  {sql_literal(deterministic_id('assignment', group['code'] + ':' + activity['id'] + ':' + activity['version']))},",
            f"  {sql_literal(group_id)},",
            f"  {sql_literal(version_id)},",
            "  true,",
            "  true",
            "on conflict (group_id, activity_version_id) do update set required = excluded.required, active = excluded.active;",
            "",
        ]

    lines += ["commit;", ""]
    return "\n".join(lines)
