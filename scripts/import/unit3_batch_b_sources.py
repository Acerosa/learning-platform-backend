"""Authoritative Batch B marking sources for Unit 3.

GAS packs (weeks 2–4) are the canonical historical banks.
Hub JS/data files are used where GAS is absent (weeks 5–7) and for the
current Week 2 OCR bank intent. Learner-visible published packages are
not read. Week 1 live getActivity banks contain no answer keys.
"""
from __future__ import annotations

import json
import re
from pathlib import Path


HUB_ROOT = Path(__file__).resolve().parents[3] / "unit-3-Cyber-Security-Hub"
BACKEND_ROOT = Path(__file__).resolve().parents[2]
GAS_ROOT = HUB_ROOT / "apps-script"

ASSESSMENT_KEY_RE = re.compile(
    r"""['"]([A-Za-z0-9._:-]+)['"]\s*:\s*\{""",
)
CORRECT_OPTION_RE = re.compile(r"""correctOptionId"?\s*:\s*['"]([^'"]+)['"]""")
CORRECT_CATEGORY_RE = re.compile(r"""correctCategoryId"?\s*:\s*['"]([^'"]+)['"]""")
AUTO_MARK_RE = re.compile(r"""autoMark"?\s*:\s*(true|false)""")
SCORING_MODE_RE = re.compile(r"""scoringMode"?\s*:\s*['"]([^'"]+)['"]""")
ACTIVITY_ID_RE = re.compile(r"""activityId"?\s*:\s*['"]([^'"]+)['"]""")
QUESTION_ID_RE = re.compile(r"""questionId"?\s*:\s*['"]([^'"]+)['"]""")
CORRECT_INDEX_RE = re.compile(r"""correctIndex"?\s*:\s*(\d+)""")
PREFERRED_RE = re.compile(r"""preferred"?\s*:\s*['"]([^'"]+)['"]""")
ALTERNATIVE_RE = re.compile(r"""alternativeAnswers"?\s*:\s*(?:Object\.freeze\()?\[([^\]]*)\]""")
ALT_CREDIT_RE = re.compile(r"""altFullCredit"?\s*:\s*(true|false)""")
LEGISLATION_RE = re.compile(r"""legislation"?\s*:\s*['"]([^'"]+)['"]""")
DUTY_RE = re.compile(r"""duty"?\s*:\s*['"]([^'"]+)['"]""")
ACCEPTED_RE = re.compile(r"""accepted"?\s*:\s*(?:Object\.freeze\()?\[([^\]]*)\]""")

COMPLETION_ACTIVITY_MARKERS = (
    "peer",
    "improvement",
    "reflection",
    "debrief",
    "planner",
    "debate",
    "directed",
    "companion",
    "register",
    "observation",
    "organiser",
    "stakeholder-grid",
    "exercise",
    "guidance",
    "ncsc",
    "review",
    "monitoring",
    "considerations",
    "exposure",
    "analysis",
    "recommendation",
    "heightened",
    "sandbox",
)

OCR_ACTIVITY_MARKERS = ("ocr",)
REVIEW_ACTIVITY_MARKERS = (
    "retrieval",
    "justified",
    "analyse",
    "diagnostic",
)

SKIP_VERSIONING = frozenset(
    {
        "week5-vulnerability-patterns",
        "week5-threat-vulnerability-risk",
        "week5-controls-matching",
        "week5-secure-rewrite",
    }
)

OCR_ACTIVITY = "week2-ocr-question-practice"
OCR_HUB_MARKS = {
    "W2OCR-Q01": ("single", 2),
    "W2OCR-Q02": ("single", 2),
    "W2OCR-Q03": ("single", 2),
    "W2OCR-Q04": ("single", 2),
    "W2OCR-Q05": ("single", 2),
    "W2OCR-Q06": ("single", 2),
    "W2OCR-Q07": ("single", 2),
    "W2OCR-Q08": ("text", 6),
}
INDEX_TO_LETTER = "abcdefghijklmnopqrstuvwxyz"


def extract_object_after(text: str, start: int) -> str | None:
    brace = text.find("{", start)
    if brace < 0:
        return None
    depth = 0
    for index, char in enumerate(text[brace:], start=brace):
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace : index + 1]
    return None


def normalize_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def parse_gas_assessment(text: str) -> dict[str, dict]:
    marker = re.search(r"""['"]?assessment['"]?\s*:""", text)
    if not marker:
        return {}
    block = extract_object_after(text, marker.start())
    if not block:
        return {}
    results = {}
    for match in ASSESSMENT_KEY_RE.finditer(block):
        key = match.group(1)
        body = extract_object_after(block, match.start())
        if not body:
            continue
        option = CORRECT_OPTION_RE.search(body)
        category = CORRECT_CATEGORY_RE.search(body)
        auto = AUTO_MARK_RE.search(body)
        scoring = SCORING_MODE_RE.search(body)
        results[key] = {
            "correctOptionId": option.group(1) if option else None,
            "correctCategoryId": category.group(1) if category else None,
            "autoMark": auto.group(1) == "true" if auto else None,
            "scoringMode": scoring.group(1) if scoring else None,
            "source": "gas",
        }
        results[normalize_key(key)] = results[key]
    return results


def parse_hub_js(text: str) -> dict:
    activity_ids = ACTIVITY_ID_RE.findall(text)
    activity_id = activity_ids[0] if activity_ids else None
    answers: dict[str, dict] = {}
    ordered = []

    for match in re.finditer(
        r"""(?:id|questionId)"?\s*:\s*['"]([^'"]+)['"]""",
        text,
    ):
        ident = match.group(1)
        prefix = text[max(0, match.start() - 120) : match.start()]
        local = prefix.rfind("{")
        if local < 0:
            continue
        object_start = max(0, match.start() - 120) + local
        window = extract_object_after(text, object_start)
        if not window:
            continue
        option = CORRECT_OPTION_RE.search(window)
        category = CORRECT_CATEGORY_RE.search(window)
        index_match = CORRECT_INDEX_RE.search(window)
        accepted_match = ACCEPTED_RE.search(window)
        preferred = PREFERRED_RE.search(window)
        alt_match = ALTERNATIVE_RE.search(window)
        alt_credit = ALT_CREDIT_RE.search(window)
        legislation = LEGISLATION_RE.search(window)
        duty = DUTY_RE.search(window)
        qtype = re.search(r"""type"?\s*:\s*['"]([^'"]+)['"]""", window)
        marks = re.search(r"""marks"?\s*:\s*(\d+)""", window)
        accepted = None
        if accepted_match:
            raw_accepted = accepted_match.group(1) or ""
            accepted = re.findall(r"""['"]([^'"]+)['"]""", raw_accepted)
        alternatives = []
        if alt_match:
            alternatives = re.findall(r"""['"]([^'"]+)['"]""", alt_match.group(1) or "")
        payload = {
            "correctOptionId": option.group(1) if option else None,
            "correctCategoryId": category.group(1) if category else None,
            "correctIndex": int(index_match.group(1)) if index_match else None,
            "accepted": accepted,
            "preferred": preferred.group(1) if preferred else None,
            "alternatives": alternatives,
            "altFullCredit": alt_credit.group(1) == "true" if alt_credit else False,
            "legislation": legislation.group(1) if legislation else None,
            "duty": duty.group(1) if duty else None,
            "type": qtype.group(1) if qtype else None,
            "marks": int(marks.group(1)) if marks else None,
            "source": "hub-js",
        }
        if (
            payload["correctOptionId"]
            or payload["correctCategoryId"]
            or payload["correctIndex"] is not None
            or payload["accepted"]
            or payload["preferred"]
            or payload["legislation"]
        ):
            answers[ident] = payload
            answers[normalize_key(ident)] = payload
            ordered.append(ident)

    nested_checks = [int(match.group(1)) for match in CORRECT_INDEX_RE.finditer(text)]

    return {
        "activityId": activity_id,
        "answers": answers,
        "ordered_ids": ordered,
        "nested_indexes": nested_checks,
    }


def letter_from_index(index: int) -> str:
    if index < 0 or index >= len(INDEX_TO_LETTER):
        raise ValueError(f"correctIndex out of range: {index}")
    return INDEX_TO_LETTER[index]


def next_version(current: str) -> str:
    major, minor, patch = (int(part) for part in current.split("."))
    return f"{major}.{minor + 1}.{patch}"


def activity_completion_like(activity_key: str) -> bool:
    return any(marker in activity_key for marker in COMPLETION_ACTIVITY_MARKERS)


def activity_ocr_like(activity_key: str) -> bool:
    return any(marker in activity_key for marker in OCR_ACTIVITY_MARKERS)


def activity_review_like(activity_key: str) -> bool:
    return any(marker in activity_key for marker in REVIEW_ACTIVITY_MARKERS)


def load_gas_answers() -> dict[str, dict[str, dict]]:
    by_activity: dict[str, dict[str, dict]] = {}
    if not GAS_ROOT.exists():
        return by_activity
    for path in GAS_ROOT.rglob("*Data.gs"):
        text = path.read_text(encoding="utf-8")
        activity_ids = ACTIVITY_ID_RE.findall(text)
        assessment = parse_gas_assessment(text)
        if not assessment:
            continue
        for activity_id in activity_ids or [path.stem]:
            by_activity.setdefault(activity_id, {}).update(assessment)
    return by_activity


def load_hub_answers() -> dict[str, dict]:
    by_activity: dict[str, dict] = {}
    for week in range(2, 8):
        data_dir = HUB_ROOT / f"week-{week}" / "data"
        if not data_dir.exists():
            continue
        for path in data_dir.glob("*.js"):
            parsed = parse_hub_js(path.read_text(encoding="utf-8"))
            activity_id = parsed["activityId"]
            if not activity_id:
                continue
            by_activity[activity_id] = parsed
    return by_activity


def ocr_hub_answers(hub_answers: dict) -> dict[str, dict]:
    parsed = hub_answers.get(OCR_ACTIVITY) or {}
    mapped = {}
    ordered = parsed.get("ordered_ids") or []
    answers = parsed.get("answers") or {}
    for index, hub_id in enumerate(ordered, start=1):
        key = f"W2OCR-Q{index:02d}"
        source = answers.get(hub_id)
        if not source:
            continue
        option = source.get("correctOptionId")
        if option is None and source.get("correctIndex") is not None:
            option = letter_from_index(source["correctIndex"])
        mapped[key] = {
            "correctOptionId": option,
            "correctCategoryId": source.get("correctCategoryId"),
            "source": "hub-js",
            "hubId": hub_id,
        }
    return mapped


def choose_policy(activity_key: str, question: dict, proven: dict | None) -> dict:
    qtype = question["question_type"]
    key = question["question_key"]

    if activity_key == "u3-w01-incidents":
        return {
            "mode": "requires_review",
            "reason": "dual incidentType+ciaAim classification; keys not in repo",
            "source": None,
            "confidence": "high",
            "action": "version",
        }

    if activity_key.startswith("u3-w01-"):
        if activity_key == "u3-w01-peer-improvement":
            return {
                "mode": "completion",
                "reason": "peer/reflection evidence",
                "source": None,
                "confidence": "high",
                "action": "version",
            }
        if qtype == "single":
            return {
                "mode": "requires_review",
                "reason": "Week 1 objective item; answer keys absent from getActivity",
                "source": None,
                "confidence": "high",
                "action": "version",
            }
        return {
            "mode": "requires_review",
            "reason": "Week 1 free-text / OCR extended; no proven key",
            "source": None,
            "confidence": "high",
            "action": "version",
        }

    if proven and proven.get("legislation") and proven.get("duty"):
        return {
            "mode": "requires_review",
            "reason": "dual legislation+duty classification; single category would be lossy",
            "source": proven.get("source"),
            "confidence": "high",
            "action": "version",
        }

    if proven and proven.get("preferred"):
        if proven.get("altFullCredit") and proven.get("alternatives"):
            return {
                "mode": "requires_review",
                "reason": "preferred measure has full-credit alternatives; exact_category would be lossy",
                "source": proven.get("source"),
                "confidence": "high",
                "action": "version",
            }
        return {
            "mode": "classification",
            "correctCategoryId": proven["preferred"],
            "reason": "authoritative preferred category with no full-credit alternative",
            "source": proven.get("source"),
            "confidence": "high",
            "action": "version",
        }

    if proven and proven.get("accepted"):
        accepted = proven["accepted"]
        if len(accepted) == 1:
            return {
                "mode": "classification",
                "correctCategoryId": accepted[0],
                "reason": "authoritative single accepted category",
                "source": proven.get("source"),
                "confidence": "high",
                "action": "version",
            }
        return {
            "mode": "requires_review",
            "reason": "multiple accepted categories; single exact_category would be lossy",
            "source": proven.get("source"),
            "confidence": "high",
            "action": "version",
        }

    if proven and proven.get("correctOptionId") and proven.get("autoMark") is not False:
        scoring = proven.get("scoringMode")
        if scoring in {None, "exact", "objective"} or proven.get("source") == "hub-js":
            if qtype == "matching":
                return {
                    "mode": "classification",
                    "correctCategoryId": proven["correctOptionId"],
                    "reason": "authoritative category/option id",
                    "source": proven.get("source"),
                    "confidence": "high",
                    "action": "version",
                }
            return {
                "mode": "single-choice",
                "correctOptionId": proven["correctOptionId"],
                "reason": "authoritative correctOptionId",
                "source": proven.get("source"),
                "confidence": "high",
                "action": "version",
            }

    if proven and proven.get("correctCategoryId") and proven.get("autoMark") is not False:
        return {
            "mode": "classification",
            "correctCategoryId": proven["correctCategoryId"],
            "reason": "authoritative correctCategoryId",
            "source": proven.get("source"),
            "confidence": "high",
            "action": "version",
        }

    if proven and proven.get("correctIndex") is not None and proven.get("autoMark") is not False:
        return {
            "mode": "single-choice",
            "correctOptionId": letter_from_index(proven["correctIndex"]),
            "reason": "authoritative correctIndex from hub JS",
            "source": proven.get("source"),
            "confidence": "high",
            "action": "version",
        }

    if qtype == "text":
        if activity_ocr_like(activity_key) or activity_review_like(activity_key):
            return {
                "mode": "requires_review",
                "reason": "extended/exam-style response",
                "source": proven.get("source") if proven else None,
                "confidence": "high",
                "action": "version",
            }
        if activity_completion_like(activity_key):
            return {
                "mode": "completion",
                "reason": "reflection/applied completion evidence",
                "source": proven.get("source") if proven else None,
                "confidence": "high",
                "action": "version",
            }
        return {
            "mode": "requires_review",
            "reason": "free-text without proven objective key",
            "source": proven.get("source") if proven else None,
            "confidence": "medium",
            "action": "version",
        }

    if qtype == "single" and activity_completion_like(activity_key) and not proven:
        return {
            "mode": "completion",
            "reason": "self-assessment / non-exam choice without a proven key",
            "source": None,
            "confidence": "medium",
            "action": "version",
        }

    return {
        "mode": "requires_review",
        "reason": "objective item without a proven authoritative key",
        "source": proven.get("source") if proven else None,
        "confidence": "medium",
        "action": "version",
    }


def lookup_map(mapping: dict, question_key: str) -> dict | None:
    if not mapping:
        return None
    if question_key in mapping:
        return mapping[question_key]
    normalized = normalize_key(question_key)
    if normalized in mapping:
        return mapping[normalized]
    for key, value in mapping.items():
        if normalize_key(key) == normalized:
            return value
    return None


def proven_for(activity_key: str, question: dict, gas: dict, hub: dict, ocr_hub: dict) -> dict | None:
    question_key = question["question_key"]
    if activity_key == OCR_ACTIVITY and question_key in ocr_hub:
        candidate = dict(ocr_hub[question_key])
        candidate["autoMark"] = question_key != "W2OCR-Q08"
        return candidate
    gas_row = lookup_map(gas.get(activity_key) or {}, question_key)
    if gas_row:
        return gas_row
    hub_parsed = hub.get(activity_key) or {}
    hub_row = lookup_map(hub_parsed.get("answers") or {}, question_key)
    if hub_row:
        return hub_row
    seen = []
    seen_norm = set()
    answers = hub_parsed.get("answers") or {}
    for ident in hub_parsed.get("ordered_ids") or []:
        normalized = normalize_key(ident)
        if normalized in seen_norm:
            continue
        if ident in answers or normalized in answers:
            seen.append(ident)
            seen_norm.add(normalized)
    questions_in_activity = question.get("_activity_question_count")
    if seen and questions_in_activity == len(seen):
        ordinal = question["ordinal"]
        if 1 <= ordinal <= len(seen):
            return lookup_map(answers, seen[ordinal - 1])
    nested = hub_parsed.get("nested_indexes") or []
    if nested and questions_in_activity == len(nested) and not seen:
        ordinal = question["ordinal"]
        if 1 <= ordinal <= len(nested):
            return {
                "correctIndex": nested[ordinal - 1],
                "source": "hub-js",
                "autoMark": True,
            }
    return None


def build_policies(catalogue_rows: list[dict]) -> dict:
    gas = load_gas_answers()
    hub = load_hub_answers()
    ocr_hub = ocr_hub_answers(hub)

    by_activity: dict[str, dict] = {}
    for row in catalogue_rows:
        activity = by_activity.setdefault(
            row["activity_key"],
            {
                "activityKey": row["activity_key"],
                "title": row["title"],
                "gitPath": row["git_path"],
                "weekNumber": row["week_number"],
                "sessionNumber": row["session_number"],
                "versions": {},
            },
        )
        version = activity["versions"].setdefault(
            row["version"],
            {
                "version": row["version"],
                "versionId": row["version_id"],
                "published": row["published"],
                "questionCount": row["question_count"],
                "maxScore": row["max_score"],
                "questions": [],
            },
        )
        version["questions"].append(row)

    policies = []
    for activity_key, activity in sorted(by_activity.items()):
        published_versions = [
            version
            for version in activity["versions"].values()
            if version["published"]
        ]
        if not published_versions:
            continue
        source = max(published_versions, key=lambda item: tuple(int(part) for part in item["version"].split(".")))
        if activity_key in SKIP_VERSIONING:
            for question in source["questions"]:
                spec = question.get("marking_spec") or {}
                policies.append(
                    {
                        "activityKey": activity_key,
                        "sourceVersion": source["version"],
                        "newVersion": None,
                        "questionKey": question["question_key"],
                        "questionType": question["question_type"],
                        "maxScore": question["q_max"],
                        "existingSpec": spec,
                        "mode": spec.get("mode"),
                        "action": "keep",
                        "reason": "existing marking spec already correct",
                        "source": "learning.question_marking",
                        "confidence": "high",
                    }
                )
            continue

        target_version = next_version(source["version"])
        question_count = len(source["questions"])
        for question in source["questions"]:
            question = dict(question)
            question["_activity_question_count"] = question_count
            proven = proven_for(activity_key, question, gas, hub, ocr_hub)
            if activity_key == OCR_ACTIVITY and question["question_key"] in ocr_hub:
                hub_row = ocr_hub[question["question_key"]]
                if hub_row.get("correctOptionId") and question["question_key"] != "W2OCR-Q08":
                    proven = {
                        **hub_row,
                        "autoMark": True,
                        "scoringMode": "objective",
                    }
            choice = choose_policy(activity_key, question, proven)
            item = {
                "activityKey": activity_key,
                "sourceVersion": source["version"],
                "newVersion": target_version,
                "questionKey": question["question_key"],
                "questionType": question["question_type"],
                "maxScore": question["q_max"],
                "existingSpec": question.get("marking_spec"),
                "ordinal": question["ordinal"],
                "sectionKey": question["section_key"],
                "sectionTitle": question["section_title"],
                "sourceQuestionId": question["question_id"],
                "weekNumber": activity["weekNumber"],
                "sessionNumber": activity["sessionNumber"],
                **choice,
            }
            if activity_key == OCR_ACTIVITY and question["question_key"] in OCR_HUB_MARKS:
                new_type, new_score = OCR_HUB_MARKS[question["question_key"]]
                item["newQuestionType"] = new_type
                item["newMaxScore"] = new_score
            policies.append(item)

    return {
        "gasActivities": sorted(gas),
        "hubActivities": sorted(hub),
        "policies": policies,
    }
