#!/usr/bin/env python3
"""Tests for the Unit 3 Batch B marking generator."""

from __future__ import annotations

from pathlib import Path
import sys
import unittest


IMPORT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IMPORT_DIR))

from generate_unit3_batch_b import WEEK_GROUPS, generate_sql  # noqa: E402


ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "supabase/data/manifests/unit3-batch-b/marking-policies.json"
ORIGINAL_A1 = ROOT / "supabase/migrations/20260830220000_unit3_batch_a1_canonical_catalogue.sql"


class Unit3BatchBTests(unittest.TestCase):
    def test_generation_matches_committed_migrations(self) -> None:
        import json

        policies = json.loads(MANIFEST.read_text(encoding="utf-8"))
        generated = generate_sql(policies)
        for filename, sql in generated.items():
            committed = ROOT / "supabase/migrations" / filename
            self.assertEqual(sql, committed.read_text(encoding="utf-8"), filename)

    def test_generation_is_deterministic(self) -> None:
        import json

        policies = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(generate_sql(policies), generate_sql(policies))

    def test_payloads_stay_small(self) -> None:
        for filename, _weeks in WEEK_GROUPS:
            size = (ROOT / "supabase/migrations" / filename).stat().st_size
            self.assertLess(size, 40_000, filename)
        runtime = ROOT / "supabase/migrations/20260830230000_unit3_batch_b_marking_runtime.sql"
        self.assertLess(runtime.stat().st_size, 20_000)

    def test_does_not_touch_batch_a1_or_publication(self) -> None:
        import json

        policies = json.loads(MANIFEST.read_text(encoding="utf-8"))
        sql = "\n".join(generate_sql(policies).values())
        self.assertNotIn("0.2.10", sql)
        self.assertNotIn("publish_curriculum", sql)
        self.assertNotIn("week5-vulnerability-patterns", sql)
        a1 = ORIGINAL_A1.read_text(encoding="utf-8")
        self.assertIn("BAS-Q01", a1)
        self.assertNotIn("apply_unit3_batch_b_marking", a1)

    def test_ocr_and_incidents_are_represented(self) -> None:
        import json

        policies = json.loads(MANIFEST.read_text(encoding="utf-8"))
        sql = "\n".join(generate_sql(policies).values())
        self.assertIn("W2OCR-Q07", sql)
        self.assertIn("W2OCR-Q08", sql)
        self.assertIn('"qt":"single"', sql)
        self.assertIn("INC-Q01", sql)
        self.assertIn("requires_review", sql)
        self.assertIn("MW-Q1", sql)
        self.assertIn("v_source.max_score", sql)
        self.assertNotIn("v_hash,\n      0,", sql)

    def test_every_policy_has_a_mode(self) -> None:
        import json

        policies = json.loads(MANIFEST.read_text(encoding="utf-8"))["policies"]
        self.assertEqual(len(policies), 585)
        self.assertTrue(all(item.get("mode") for item in policies))
        self.assertEqual(sum(1 for item in policies if item["action"] == "keep"), 30)
        self.assertEqual(sum(1 for item in policies if item["action"] == "version"), 555)


if __name__ == "__main__":
    unittest.main()
