# Phase B — Precomputed learner curriculum packages

**Status:** Implemented and tested locally. **Not applied to production.**  
**Branch:** `feat/precomputed-learner-curriculum-packages`  
**Base:** `main` @ `71127d3` (Phase A merged)

## Root cause of remaining concurrency issue

Phase A still reconstructed and sanitised curriculum JSON on every anonymous
request. Under ≥6 simultaneous cold T Level fetches, work overlapped enough to
exceed the 3s anon timeout. Classroom use needs O(1) retrieval of a stored
learner-safe package.

## Schema

`platform.curriculum_publications`:

- `learner_package jsonb` (nullable initially; object + 4 MiB checks)
- `learner_package_sanitisation_version text` (paired with package)

Staff `package` remains authoritative. Learner package is derived only.

## Function changes

- `platform.protect_curriculum_publication` — allow derived-field backfill/regen
- `platform.publish_curriculum` — generate + store learner package in insert txn
- `platform.set_session_visibility` — same for patch publications
- `platform.learner_package_sanitisation_version()` → `lp.strip.v1`
- `platform.regenerate_curriculum_learner_packages(...)` — platform-admin regen
- `api.published_curriculum_package` (2- and 3-arg) — `coalesce(learner_package, Phase A)`
- Views: `admin_api.curriculum_publications` (+ presence/version),  
  `admin_api.publications_missing_learner_packages`

## Migrations

| Version | File |
| --- | --- |
| `20261127110000` | `add_curriculum_learner_package_column.sql` |
| `20261127110100` | `publish_time_learner_packages.sql` |
| `20261127110200` | `backfill_curriculum_learner_packages.sql` |
| `20261127110300` | `published_curriculum_uses_learner_package.sql` |

Local seed follow-up: `supabase/data/seed/backfill-learner-packages.sql`
(publication seeds run after migrations).

## Regression tests

- Full suite: **64 files / 1684 PASS** (local)
- New: `precomputed_learner_curriculum_packages.test.sql` (25)
- Extended: `curriculum_publication.test.sql` asserts publish-time learner package

## Local benchmarks (verified)

Environment: local Docker Supabase. Packages are **seed-sized** (5 / 24 / 76
activities), not production 408/132/172/24. Figures are local evidence only.

| Path | Largest local (76 act) median |
| --- | ---: |
| Stored learner_package read | ~0 ms |
| Phase A reconstruct | ~80 ms |
| API `published_curriculum_package` | ~0 ms |

Synthetic generation vs stored read:

| Activities | Publish/gen median | Stored read median |
| ---: | ---: | ---: |
| 408 | ~424 ms | ~1 ms |
| 1000 | ~1034 ms | ~2 ms |
| 2000 | ~2154 ms | ~3 ms |

Concurrency (local API, largest published seed package):

| N | Result |
| ---: | --- |
| 1–50 | all OK, no statement timeouts |

**Assumption:** production T Level (408 activities, ~1 MB learner JSON) will also
avoid reconstruction timeouts once backfilled; confirm on staging before prod.

## Security

- Reuses Phase A strip rules only (no divergent sanitiser)
- Structural protected-key checks in Phase B tests
- Table still revoked from anon; staff SELECT unchanged
- Public API still returns learner-safe package only
- Sanitisation bump + `regenerate_curriculum_learner_packages` documented

## Production plan (not executed)

1. Apply `20261127110000` … `20261127110300` only (targeted, not `db push`)
2. Confirm hosted versions recorded
3. Confirm four published hubs have learner packages + matching Phase A hashes
4. Smoke anon RPC + browser Weeks 1–7
5. Keep rollback script ready

## Rollback

`docs/audits/phase-b-learner-packages/rollback_precomputed_learner_packages.sql`  
Restores Phase A functions; leaves columns unused.

## Outstanding risks

1. Production concurrency with real 408-activity payload not load-tested here
2. Seed files still insert staff-only rows; local seed backfill required
3. Hosted migration history drift remains; apply Phase B versions carefully
4. NOT NULL constraint on learner_package deferred until after prod backfill verification
