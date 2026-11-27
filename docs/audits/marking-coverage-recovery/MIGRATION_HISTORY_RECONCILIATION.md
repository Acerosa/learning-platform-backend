# Migration history reconciliation (read-only)

**Project:** `hubwpkrqndorznwzvaer`  
**Captured:** 2026-11-27

## Known timestamp aliases (repo filename → hosted version)

| Repository migration | Hosted version | Notes |
| --- | --- | --- |
| `20261127110000_add_curriculum_learner_package_column.sql` | `20261127101530` | Phase B |
| `20261127110100_publish_time_learner_packages.sql` | `20261127101533` | Phase B |
| `20261127110200_backfill_curriculum_learner_packages.sql` | `20261127101536` | Phase B |
| `20261127110300_published_curriculum_uses_learner_package.sql` | `20261127101858` | Phase B |
| `20261127120000_resolve_unbound_catalogue_marking.sql` | `20261127103555` | PR #68 |
| `20261127130000_restore_published_marking_coverage.sql` | `20261127111520` | PR #69 |
| `20261127140000_publish_time_marking_coverage_validation.sql` | `20261127112542` | PR #70 |
| `20261127150000_foundations_language_aware_marking.sql` | `20261127122144` | Foundations language-variants |
| `20261127160000_grant_students_synthetic_columns_for_admin_learners.sql` | `20261127144141` | PR #80 — column SELECT for `admin_api.learners` |

Hosted timestamps differ from repository filenames because MCP `apply_migration` assigns its own version clock. Repository filenames remain the source of truth for ordering in git.

### PR #80 grant mapping and rollback

- **Purpose:** Least-privilege `GRANT SELECT (is_synthetic, synthetic_purpose) ON learning.students TO authenticated` so `security_invoker` view `admin_api.learners` works for `platform_admin` without table-wide SELECT.
- **Verify production:** `has_column_privilege('authenticated','learning.students','is_synthetic','SELECT')` / `synthetic_purpose` → true; `created_at` → false; `anon` synthetic → false; learner JWT returns 0 `admin_api.learners` rows.
- **Rollback (compensating forward migration only):** `REVOKE SELECT (is_synthetic, synthetic_purpose) ON learning.students FROM authenticated;` — restores the pre-#80 People failure for staff; do not drop columns or rewrite RLS. Prefer a new dated migration over editing history.

## Did migration drift cause missing marking specs?

No evidence that timestamp aliases removed or skipped marking registration. Missing Foundations specs came from catalogue publication/projection gaps (staff keys present, `question_marking` rows absent; language/code items projected without answer keys). Unbound Unit 3 collisions came from multiple published catalogue versions, not migration history.

## Safe reconciliation plan (do not execute yet)

1. Export `supabase_migrations.schema_migrations` and diff against `supabase/migrations/*.sql` names.
2. Maintain an alias table (as above) in ops docs; do not rename hosted rows.
3. Prefer MCP `apply_migration` / isolated SQL for production; avoid unrestricted `supabase db push`.
4. Before any history repair: snapshot schema_migrations, confirm no duplicate checksums, and rehearse on a branch database.
5. Do not delete hosted migration rows to “match” filenames.
