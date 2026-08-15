# Migration ownership and workflow

## Authority

This repository is the authoritative source for all future shared backend
migrations. Learner hubs must not add, edit or deploy platform migrations.

## Extracted history

The first 18 migrations were copied unchanged from
`tlevel-software-development-hub` at `2e24b1b`. They create the established
identity, curriculum, RLS, API, evidence, delivery and onboarding system and
import the two reference curriculum catalogues.

Do not rewrite, squash, reorder or rename those files. Their content and stable
identifiers are part of compatibility with the existing hosted project.

## Forward-only changes

Create a new timestamped migration for every schema, RLS, API or contract
change. A migration must:

1. preserve existing learner and activity history;
2. use stable and reviewable SQL;
3. update grants/RLS explicitly;
4. add or update pgTAP coverage;
5. document API compatibility;
6. pass a clean local reset and the full test suite.

Generated curriculum SQL must be reviewed before it becomes a migration.
Runtime code does not read JSON manifests directly.

Generated hub-registration SQL follows the same rule. Validate the repository
root `learning-platform-hub.json`, generate into `supabase/data/generated/`,
review the compatibility assertions and lifecycle decision, then add it as a
new migration. Canonical `lp.content` packages use
`generate-content-package-migration.py` the same way; see
`docs/content-publication.md`. The generators do not modify a database or
deploy anything.

## Local validation

```bash
python3 scripts/validation/validate_repository.py
python3 -m unittest discover -s scripts/import/tests -p 'test_*.py'
supabase db reset
supabase test db
```

Forward migration `20260815190000_add_runtime_curriculum_delivery.sql` adds
the learner package RPC and catalogue projection. The Unit 14 `0.2.0` package
seed is local-only (`supabase/data/generated/seed-unit14-publication.sql`).
Hosted publication of that package is an Admin **Publish to Platform** (or an
equivalent reviewed SQL insert using a real hosted administrator identity).

## Hosted handoff warning

The existing hosted Supabase project already contains platform objects created
while migrations lived in a hub repository. Its recorded migration history may
not exactly match the extracted files, including the onboarding migration that
was previously applied through SQL Editor.

Before the first hosted deployment from this repository:

1. export and review hosted migration history;
2. compare object definitions and checksums;
3. reconcile history using supported Supabase migration-repair tooling;
4. take a tested backup and define rollback;
5. dry-run against a disposable environment;
6. run hub compatibility tests;
7. obtain explicit deployment approval.

Do not blindly run the full extracted history against the existing hosted
database. Do not manually edit Supabase migration-history tables.
