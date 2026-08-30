#!/usr/bin/env python3
"""Tests for the Unit 3 Batch A1 catalogue generator."""

from __future__ import annotations

from pathlib import Path
import sys
import unittest


IMPORT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IMPORT_DIR))

from generate_unit3_batch_a1 import generate  # noqa: E402


MANIFEST = Path(__file__).resolve().parents[3] / "supabase/data/manifests/unit3-batch-a1"


class Unit3BatchA1Tests(unittest.TestCase):
    def test_generation_is_deterministic(self) -> None:
        first = generate(MANIFEST)
        second = generate(MANIFEST)
        self.assertEqual(first, second)

    def test_sql_covers_required_catalogue_rows(self) -> None:
        sql = generate(MANIFEST)
        self.assertIn("1.1.0", sql)
        self.assertIn("BAS-Q01", sql)
        self.assertIn("CIA-Q12", sql)
        self.assertIn("INC-Q01", sql)
        self.assertIn("GLO-Q01", sql)
        self.assertIn("RET-Q02A", sql)
        self.assertIn("Q001", sql)
        self.assertIn("OCR-Q05", sql)
        self.assertIn("PM-Q07", sql)
        self.assertIn("W2OCR-Q08", sql)
        self.assertIn("week5-vulnerability-patterns", sql)
        self.assertIn("week5-threat-vulnerability-risk", sql)
        self.assertIn("week5-controls-matching", sql)
        self.assertIn("week5-secure-rewrite", sql)
        self.assertIn("'P1'", sql)
        self.assertIn("'T8'", sql)
        self.assertIn("'C1'", sql)
        self.assertIn("'R6'", sql)
        self.assertIn("correctOptionId", sql)
        self.assertIn("correctCategoryId", sql)
        self.assertNotIn("learner-note", sql)
        self.assertNotIn("publish_curriculum", sql)
        self.assertNotIn("0.2.10", sql)
        self.assertNotIn("MW-Q1", sql)

    def test_week1_has_no_inferred_marking(self) -> None:
        sql = generate(MANIFEST)
        baseline_pos = sql.index("BAS-Q01")
        week5_pos = sql.index("week5-vulnerability-patterns")
        week1_sql = sql[baseline_pos:week5_pos]
        self.assertNotIn("question_marking", week1_sql)
        self.assertIn("question_marking", sql[week5_pos:])


if __name__ == "__main__":
    unittest.main()
