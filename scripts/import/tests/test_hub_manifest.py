#!/usr/bin/env python3
"""Unit tests for repository-driven hub manifest validation and SQL generation."""

from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest


IMPORT_DIR = Path(__file__).resolve().parents[1]
ROOT = IMPORT_DIR.parents[1]
sys.path.insert(0, str(IMPORT_DIR))

from hub_manifest import (  # noqa: E402
    deterministic_hub_id,
    generate_registration_sql,
    load_json,
    manifest_sha256,
    validate_manifest,
)


MANIFESTS_ROOT = ROOT / "supabase/data/manifests"
CONTRACTS_PATH = MANIFESTS_ROOT / "platform-contracts.json"
REGISTRY_ROOT = MANIFESTS_ROOT / "hubs"
VALID_MANIFEST_PATH = (
    REGISTRY_ROOT / "unit-3-cyber-security/learning-platform-hub.json"
)


class HubManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.valid_manifest = load_json(VALID_MANIFEST_PATH)

    def validate_temporary(
        self,
        manifest: dict,
        *,
        registry_manifest: dict | None = None,
    ):
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        temporary_root = Path(temporary.name)
        candidate = temporary_root / "candidate/learning-platform-hub.json"
        candidate.parent.mkdir(parents=True)
        candidate.write_text(json.dumps(manifest), encoding="utf-8")
        registry = temporary_root / "registry"
        if registry_manifest is not None:
            registered = registry / "registered/learning-platform-hub.json"
            registered.parent.mkdir(parents=True)
            registered.write_text(json.dumps(registry_manifest), encoding="utf-8")
        return validate_manifest(
            candidate,
            contracts_path=CONTRACTS_PATH,
            manifests_root=MANIFESTS_ROOT,
            registry_root=registry,
        )

    def test_reviewed_hub_manifests_are_valid(self) -> None:
        for path in sorted(REGISTRY_ROOT.rglob("learning-platform-hub.json")):
            with self.subTest(path=path):
                report = validate_manifest(path)
                self.assertTrue(
                    report.valid,
                    "\n".join(issue.render() for issue in report.issues),
                )

    def test_unknown_fields_and_invalid_semver_fail_clearly(self) -> None:
        manifest = deepcopy(self.valid_manifest)
        manifest["hubSpecificThing"] = True
        manifest["version"] = "v1"
        report = self.validate_temporary(manifest)
        codes = {issue.code for issue in report.issues}
        self.assertIn("SCHEMA_UNKNOWN_FIELD", codes)
        self.assertIn("INVALID_SEMVER", codes)

    def test_semver_rejects_leading_zero_numeric_prerelease(self) -> None:
        manifest = deepcopy(self.valid_manifest)
        manifest["version"] = "1.0.0-01"
        report = self.validate_temporary(manifest)
        self.assertIn("INVALID_SEMVER", {issue.code for issue in report.issues})

    def test_unknown_course_and_unsupported_contract_fail(self) -> None:
        manifest = deepcopy(self.valid_manifest)
        manifest["courses"] = ["unknown-course"]
        manifest["compatibility"]["required"]["learnerApiContractVersion"] = "9.0.0"
        manifest["compatibility"]["testedCombinations"] = [
            deepcopy(manifest["compatibility"]["required"])
        ]
        report = self.validate_temporary(manifest)
        codes = {issue.code for issue in report.issues}
        self.assertIn("UNKNOWN_COURSE", codes)
        self.assertIn("UNSUPPORTED_PLATFORM_VERSION", codes)

    def test_duplicate_identity_repository_and_deployment_fail(self) -> None:
        registered = deepcopy(self.valid_manifest)
        candidate = deepcopy(self.valid_manifest)
        candidate["repositoryUrl"] += "/"
        candidate["deploymentUrl"] += "/"
        report = self.validate_temporary(candidate, registry_manifest=registered)
        codes = {issue.code for issue in report.issues}
        self.assertIn("DUPLICATE_HUB_ID", codes)
        self.assertIn("DUPLICATE_REPOSITORY", codes)
        self.assertIn("DUPLICATE_DEPLOYMENT", codes)

    def test_required_combination_must_be_tested(self) -> None:
        manifest = deepcopy(self.valid_manifest)
        manifest["compatibility"]["testedCombinations"] = [
            {
                "coreVersion": "0.1.0",
                "learnerApiContractVersion": "0.1.0",
                "submissionContractVersion": "0.1.1",
            }
        ]
        report = self.validate_temporary(manifest)
        self.assertIn(
            "REQUIRED_COMBINATION_NOT_TESTED",
            {issue.code for issue in report.issues},
        )

    def test_generator_is_deterministic_and_defaults_to_inactive(self) -> None:
        first = generate_registration_sql(self.valid_manifest)
        second = generate_registration_sql(deepcopy(self.valid_manifest))
        self.assertEqual(first, second)
        self.assertIn(deterministic_hub_id(self.valid_manifest["hubId"]), first)
        self.assertIn(manifest_sha256(self.valid_manifest), first)
        self.assertIn("  'planned',\n  false,", first)
        self.assertNotIn("supabase db push", first.lower())

    def test_generator_refuses_unsafe_active_lifecycle(self) -> None:
        with self.assertRaisesRegex(ValueError, "active hubs must have"):
            generate_registration_sql(self.valid_manifest, status="planned", active=True)


if __name__ == "__main__":
    unittest.main()
