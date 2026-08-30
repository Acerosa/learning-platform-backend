#!/usr/bin/env python3
"""Tests for the Unit 3 Batch A1 recovery generator."""

from __future__ import annotations

from pathlib import Path
import sys
import unittest


IMPORT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IMPORT_DIR))

from generate_unit3_batch_a1 import generate  # noqa: E402
from generate_unit3_batch_a1_recovery import build_catalogue, generate_recovery  # noqa: E402


ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "supabase/data/manifests/unit3-batch-a1"
ORIGINAL_A1 = ROOT / "supabase/migrations/20260830220000_unit3_batch_a1_canonical_catalogue.sql"
RECOVERY = ROOT / "supabase/migrations/20260830223000_unit3_batch_a1_recovery.sql"


class Unit3BatchA1RecoveryTests(unittest.TestCase):
    def test_original_a1_migration_is_unchanged(self) -> None:
        self.assertEqual(generate(MANIFEST), ORIGINAL_A1.read_text(encoding="utf-8"))

    def test_recovery_generation_is_deterministic(self) -> None:
        self.assertEqual(generate_recovery(MANIFEST), generate_recovery(MANIFEST))

    def test_committed_recovery_sql_matches_generator(self) -> None:
        self.assertEqual(generate_recovery(MANIFEST), RECOVERY.read_text(encoding="utf-8"))

    def test_recovery_keeps_stable_residue_identity(self) -> None:
        baseline = next(item for item in build_catalogue(MANIFEST) if item["activityKey"] == "u3-w01-baseline")
        self.assertEqual(baseline["versionId"], "0228c12e-1ac3-5c07-ad9f-7c24d355c858")
        self.assertEqual(baseline["contentHash"], "37a5ccb5eaae5cf5f18e75f1058a08ec17032e538810dde5540df88b686e3cc7")
        self.assertTrue(baseline["allowEmptyUnpublished"])
        self.assertEqual(baseline["questionCount"], 10)

    def test_recovery_sql_is_guarded_and_narrow(self) -> None:
        sql = generate_recovery(MANIFEST)
        self.assertIn("UNIT3_BATCH_A1_RECOVERY_CONFLICT", sql)
        self.assertIn("apply_unit3_batch_a1_recovery", sql)
        self.assertIn("W2OCR-Q08", sql)
        self.assertIn("week5-vulnerability-patterns", sql)
        self.assertIn("on conflict (activity_id, version) do nothing", sql)
        self.assertIn("on conflict (activity_version_id, stable_key) do nothing", sql)
        self.assertIn("on conflict (group_id, activity_version_id) do nothing", sql)
        self.assertNotIn("on conflict (stable_key) do update", sql)
        self.assertNotIn("do update set required", sql)
        self.assertNotIn("insert into supabase_migrations", sql)
        self.assertNotIn("update supabase_migrations", sql)
        self.assertNotIn("delete from supabase_migrations", sql)
        self.assertNotIn("0.2.10", sql)
        self.assertNotIn("publish_curriculum", sql)


if __name__ == "__main__":
    unittest.main()
