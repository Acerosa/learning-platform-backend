# Content package publication

Canonical curriculum JSON stays in the learner hub. This repository consumes a
validated package and produces a reviewed catalogue migration. Runtime never
reads GitHub or hub files.

## Generator

```bash
python3 scripts/import/generate-content-package-migration.py \
  /path/to/hub/content/unit-14 \
  supabase/data/generated/import-unit14-week1-catalogue.sql \
  --json supabase/data/generated/unit14-content-registration.json
```

The script validates schema version, duplicate ids, broken references and
unsupported interactive evidence before writing SQL. The same package produces
the same SQL.

Reviewed Unit 14 artefacts:

- `supabase/data/manifests/hubs/unit-14-software-engineering-for-business/learning-platform-hub.json`
- `supabase/data/manifests/hubs/unit-14-software-engineering-for-business/content-registration.json`
- `supabase/migrations/20260813141000_register_unit14_hub.sql`
- `supabase/migrations/20260813142000_import_unit14_week1_catalogue.sql`

Hub Manifest 1.0.0 remains registration-only. A curriculum pointer would be a
future manifest-contract change, not an extra field on 1.0.0.

## What is registered

For Unit 14:

- hub identity and `ocr-level-3-it` course link
- module `unit-14-software-engineering-for-business`
- topics `lo1`–`lo4`
- 19 week metadata rows (planner dates null)
- Week 1 activities, versions `0.1.0`, questions, marking specs, delivery
- closed synthetic group `UNIT14-TEST-A` for local authenticated tests

OCR Assignments 1–4 stay hub-owned. `learning.activity_assignments` is group
delivery of activity versions.

## Immutability

Insert versions unpublished, insert questions and `learning.question_marking`,
then set `published_at`. Re-running the SQL skips question/marking inserts on
already-published versions. Published rows raise
`PUBLISHED_ACTIVITY_VERSION_IMMUTABLE` /
`PUBLISHED_QUESTION_MARKING_IMMUTABLE` if mutated.

## Tests

```bash
python3 -m unittest discover -s scripts/import/tests -p 'test_*.py'
```
