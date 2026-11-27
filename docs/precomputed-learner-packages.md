# Precomputed learner curriculum packages (Phase B)

## Why

Phase A made on-request learner-package construction fast enough for single
requests, but six or more simultaneous cold T Level fetches can still exceed
the anonymous three-second statement timeout. Classroom concurrency needs the
expensive sanitisation work done once at publication time.

## Architecture

| Representation | Role |
| --- | --- |
| `platform.curriculum_publications.package` | Authoritative staff curriculum (authoring, validation, marking, projection) |
| `platform.curriculum_publications.learner_package` | Derived learner-safe teaching package |
| `learner_package_sanitisation_version` | Rule version used to build the derived package |

Publication transaction:

1. Validate the staff package (unchanged).
2. Generate `learner_package` with `platform.learner_curriculum_package` (Phase A).
3. Insert both packages in the same row insert.
4. Project the delivery catalogue.
5. Commit. Failure of learner-package generation aborts the publication.

Retrieval:

```sql
coalesce(
  publication.learner_package,
  platform.learner_curriculum_package(...)
)
```

Normal retrieval uses the stored package. The fallback exists only for
transition / defect recovery and must not conceal missing packages indefinitely.
Staff use `admin_api.publications_missing_learner_packages` to find gaps.

## Entry points that must generate learner packages

- `platform.publish_curriculum` / `admin_api.publish_curriculum`
- `platform.set_session_visibility` / `admin_api.set_session_visibility`

Historical one-off migration inserts are covered by the backfill migration.

## Immutability

Published rows remain immutable for staff curriculum fields. The protect trigger
allows only:

- `published` → `superseded` status transitions
- updates that change only `learner_package` and `learner_package_sanitisation_version`

## Sanitisation regeneration

Current version: `lp.strip.v1` (`platform.learner_package_sanitisation_version()`).

When strip rules change:

1. Update Phase A strip / learner builders.
2. Bump `platform.learner_package_sanitisation_version()`.
3. Run `platform.regenerate_curriculum_learner_packages()` as a platform admin
   (or a controlled migration that performs the same updates).
4. Confirm `admin_api.publications_missing_learner_packages` is empty.

Do not rely on curriculum version bumps alone to refresh sanitisation.

## Migrations

| Version | Purpose |
| --- | --- |
| `20261127110000` | Add nullable columns; extend protect trigger; staff view metadata |
| `20261127110100` | Publication-time generation + regenerate helper |
| `20261127110200` | Idempotent backfill of existing publications |
| `20261127110300` | Public RPC prefers stored package; diagnostic view |

Hosted application must use targeted migration apply for these versions only.
Do not `supabase db push` against production.

## Rollback

See `docs/audits/phase-b-learner-packages/rollback_precomputed_learner_packages.sql`.
Restores Phase A function bodies. Leaves columns in place unused.

## Performance expectations

- Publication pays the Phase A generation cost once per publish.
- Retrieval should be dominated by reading stored JSONB, not reconstruction.
- Classroom-scale concurrent cold reads should no longer time out for current
  package sizes, subject to staging verification.
- Phase B does not claim production-scale performance from local results alone.

## LHDS follow-up

Learning Hub Development Standard should note that learner hubs consume the
public teaching package only, and that curriculum availability continues to
come from published package metadata overlays. No hub redeploy is required for
Phase B database changes.
