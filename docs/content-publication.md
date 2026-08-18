# Content package publication

Canonical curriculum is published into `platform.curriculum_publications`.
This repository can still generate a reviewed catalogue migration from a
validated package for historical imports. Runtime never reads GitHub or hub
files. Admin publication projects the delivery catalogue automatically.

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
- 24 Week 1 and Week 2 activities, versions `0.1.0`, questions, marking specs, delivery
- closed synthetic group `UNIT14-TEST-A` for local authenticated tests

OCR Assignments 1–4 stay hub-owned. `learning.activity_assignments` is group
delivery of activity versions.

## Immutability

Insert versions unpublished, insert questions and `learning.question_marking`,
then set `published_at`. Re-running the SQL skips question/marking inserts on
already-published versions. Published rows raise
`PUBLISHED_ACTIVITY_VERSION_IMMUTABLE` /
`PUBLISHED_QUESTION_MARKING_IMMUTABLE` if mutated.

## MVP baseline

Git tag `curriculum-engine-mvp` marks this Unit 14 publication path as the
Curriculum Engine MVP. Later weeks start from `main` at that tag. Client-marked
`submit_attempt` items remain accepted for Unit 3 / T Level compatibility.

Admin-authored `lp.content` snapshots enter the backend through
`admin_api.publish_curriculum`. Composition materialises library references
into the same canonical package before that RPC. Staff may open the live
package with `admin_api.current_curriculum_package` and save working copies
with `admin_api.save_curriculum_draft`. The generator remains for reviewed
historical imports. See [Backend publication](backend-publication.md).

## Tests

```bash
python3 -m unittest discover -s scripts/import/tests -p 'test_*.py'
```
