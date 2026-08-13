#!/usr/bin/env python3
"""Tests for canonical content-package validation and SQL generation."""

from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile
import unittest


IMPORT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IMPORT_DIR))

from content_package import (  # noqa: E402
    PackageError,
    build_registration,
    generate_sql,
    load_package,
)


FIXTURE = Path(__file__).resolve().parent / "fixtures/content-package"
UNIT14 = Path(
    "/Users/ricardorosa/Projects/unit-14-software-engineering-for-business-hub/content/unit-14"
)


def write_package(base: dict[str, object], directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    for name, payload in base.items():
        (directory / name).write_text(json.dumps(payload), encoding="utf-8")
    return directory


def fixture_documents() -> dict[str, object]:
    documents = {}
    for path in FIXTURE.glob("*.json"):
        documents[path.name] = json.loads(path.read_text(encoding="utf-8"))
    return documents


class ContentPackageTests(unittest.TestCase):
    def test_fixture_generation_is_deterministic(self) -> None:
        first = build_registration(load_package(FIXTURE))
        second = build_registration(load_package(FIXTURE))
        self.assertEqual(first, second)
        self.assertEqual(generate_sql(first), generate_sql(second))
        self.assertEqual(len(first["weeks"]), 2)
        self.assertEqual(len(first["assignments"]), 1)
        self.assertTrue(first["assignments"][0]["hubOnly"])
        self.assertEqual(len(first["activities"]), 2)
        diagnostic = next(item for item in first["activities"] if item["id"] == "week-1-baseline-diagnostic")
        keys = [question["stableKey"] for question in diagnostic["questions"]]
        self.assertEqual(keys, ["u14-w1-base-q1", "u14-w1-biz-class:customer-name"])
        self.assertEqual(diagnostic["questions"][0]["marking"]["mode"], "single-choice")
        reflection = next(item for item in first["activities"] if item["id"] == "week-1-assignment-1-guide")
        self.assertEqual(reflection["questions"][0]["marking"]["mode"], "completion")
        sql = generate_sql(first)
        self.assertIn("learning.question_marking", sql)
        self.assertIn("UNIT14-TEST-A", sql)
        self.assertNotIn("/Users/", sql)
        self.assertIn("week-1-baseline-diagnostic", sql)

    def test_unsupported_schema_version_is_rejected(self) -> None:
        documents = fixture_documents()
        documents["index.json"]["schemaVersion"] = "9.0.0"
        with tempfile.TemporaryDirectory() as temporary:
            path = write_package(documents, Path(temporary) / "package")
            with self.assertRaises(PackageError) as raised:
                build_registration(load_package(path))
            self.assertEqual(raised.exception.code, "UNSUPPORTED_CONTENT_VERSION")

    def test_duplicate_activity_ids_are_rejected(self) -> None:
        documents = fixture_documents()
        documents["activities.json"].append(deepcopy(documents["activities.json"][0]))
        with tempfile.TemporaryDirectory() as temporary:
            path = write_package(documents, Path(temporary) / "package")
            with self.assertRaises(PackageError) as raised:
                build_registration(load_package(path))
            self.assertEqual(raised.exception.code, "DUPLICATE_ID")

    def test_broken_session_activity_reference_is_rejected(self) -> None:
        documents = fixture_documents()
        documents["sessions.json"][0]["relationships"]["activities"].append("missing-activity")
        with tempfile.TemporaryDirectory() as temporary:
            path = write_package(documents, Path(temporary) / "package")
            with self.assertRaises(PackageError) as raised:
                build_registration(load_package(path))
            self.assertEqual(raised.exception.code, "BROKEN_REFERENCE")

    def test_unsupported_interactive_evidence_is_rejected(self) -> None:
        documents = fixture_documents()
        documents["activities.json"][1]["blocks"][0]["type"] = "live-exam"
        documents["activities.json"][1]["blocks"][0]["content"]["questionId"] = "u14-w1-live"
        with tempfile.TemporaryDirectory() as temporary:
            path = write_package(documents, Path(temporary) / "package")
            with self.assertRaises(PackageError) as raised:
                build_registration(load_package(path))
            self.assertEqual(raised.exception.code, "UNSUPPORTED_ACTIVITY_EVIDENCE")

    def test_duplicate_question_keys_are_rejected(self) -> None:
        documents = fixture_documents()
        documents["activities.json"][0]["blocks"].append(
            deepcopy(documents["activities.json"][0]["blocks"][0])
        )
        with tempfile.TemporaryDirectory() as temporary:
            path = write_package(documents, Path(temporary) / "package")
            with self.assertRaises(PackageError) as raised:
                build_registration(load_package(path))
            self.assertEqual(raised.exception.code, "DUPLICATE_ID")

    @unittest.skipUnless(UNIT14.is_dir(), "Unit 14 canonical package is not checked out")
    def test_unit14_package_registers_expected_catalogue(self) -> None:
        registration = build_registration(load_package(UNIT14))
        self.assertEqual(registration["provenance"]["hubId"], "unit-14-software-engineering-for-business")
        self.assertEqual(len(registration["weeks"]), 19)
        self.assertEqual(len(registration["assignments"]), 4)
        self.assertTrue(all(item["hubOnly"] for item in registration["assignments"]))
        self.assertEqual(len(registration["activities"]), 11)
        self.assertEqual(
            [item["id"] for item in registration["activities"]],
            sorted(
                [
                    "week-1-baseline-diagnostic",
                    "week-1-business-data-explorer",
                    "week-1-variables-and-data-types",
                    "week-1-input-and-output",
                    "week-1-github-classroom-guidance",
                    "week-1-review",
                    "week-1-guided-business-data",
                    "week-1-first-commits",
                    "week-1-first-python-business-program",
                    "week-1-assignment-1-guide",
                    "week-1-homework-extension",
                ]
            ),
        )
        first = generate_sql(registration)
        second = generate_sql(build_registration(load_package(UNIT14)))
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
