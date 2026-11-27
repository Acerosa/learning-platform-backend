# Phase B — Precomputed learner curriculum packages

**Status:** **Deployed to production and verified.** See `PRODUCTION_DEPLOYMENT_RESULTS.md`.  
**Branch:** `feat/precomputed-learner-curriculum-packages`  
**Base:** `main` @ `71127d3` (Phase A merged)  
**Production deploy tip:** `bddc6b91bdbba507c0dc5c44d73feff8c5d8c561`

## Root cause

Phase A reconstructed and sanitised curriculum JSON on every anonymous request.
Under simultaneous cold T Level fetches, work overlapped enough to exceed the
3s anon timeout. Classroom use needs O(1) retrieval of a stored learner-safe
package.

## Schema

`platform.curriculum_publications`:

- `learner_package jsonb` (nullable initially; object + 4 MiB checks)
- `learner_package_sanitisation_version text` (paired with package)

Staff `package` remains authoritative. Learner package is derived only.

## Function changes

- `platform.protect_curriculum_publication` — allow derived-field backfill/regen
  **only when** `learner_package` equals current Phase A output and
  `learner_package_sanitisation_version` equals `lp.strip.v1`
- `platform.publish_curriculum` / `platform.set_session_visibility` — store
  learner package in the same transaction as publication
- `platform.learner_package_sanitisation_version()` → `lp.strip.v1`
- `platform.regenerate_curriculum_learner_packages(...)` — platform-admin regen
- `api.published_curriculum_package` — uses stored package **only** when
  sanitisation version matches; otherwise rebuilds with Phase A
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
(wired in `supabase/config.toml`; publication seeds run after migrations).

## Sanitisation version enforcement

| Scenario | Behaviour |
| --- | --- |
| Valid package + current version | Serve stored `learner_package` |
| Missing learner package | Phase A rebuild |
| Missing sanitisation version | Pairing CHECK rejects package without version; API still rebuilds if version mismatches |
| Outdated sanitisation version | Phase A rebuild (poisoned/outdated payload not served) |
| Rules changed after publication | Bump constant + regenerate; until regen, API rebuilds |
| Regeneration failure | Trigger rejects non-equivalent payloads; API still rebuilds safely |

Performance: version check is a text equality on an already-fetched row.
Matching path avoids Phase A reconstruction (DB median ~2–3 ms local).

## Security / immutability

- Staff packages remain immutable (DELETE/UPDATE blocked)
- Derived-field exception requires exact Phase A equivalence + current version
- Arbitrary JSON / protected keys cannot enter via the derived-field path
- Unauthorised roles cannot modify learner packages
- Diagnostic view exposes presence/version only under staff role checks; never staff package body to anon
- Negative regression tests cover forged version, poisoned package, role denial

## Representative concurrency (local public RPC)

Environment: local Docker Supabase, anon JWT, existing **3s** statement timeout
(not increased). Calls go through PostgREST `api.published_curriculum_package`.

**408-activity package (rich tiled seed activities; classroom acceptance size)**  
Response ≈ 2.61 MiB. DB exec median **2 ms**. Stored = Phase A MD5 equal.

| Workers | Min | Med | P95 | Max | Errors | Timeouts | Integrity |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 42 | 45 | 47 | 47 | 0 | 0 | OK |
| 5 | 60 | 111 | 149 | 161 | 0 | 0 | OK |
| 10 | 96 | 245 | 472 | 490 | 0 | 0 | OK |
| 20 | 158 | 383 | 518 | 530 | 0 | 0 | OK |
| 30 | 70 | 517 | 738 | 784 | 0 | 0 | OK |
| 50 | 122 | 945 | 1313 | 1361 | 0 | 0 | OK |

**Acceptance:** 30 simultaneous cold requests for 408 activities — **PASS** (0 timeouts).

**1000 / 2000 activities (compact nested templates under 4 MiB staff limit)**  
Reported separately. Payloads smaller than rich 408 (~0.49 / ~0.98 MiB). DB median 2–3 ms. All worker levels 1–50: **0 errors, 0 timeouts, integrity OK**. See `representative_concurrency.txt`.

These are **verified local** results, not production load tests.

## Production curriculum equivalence (verified)

Project `hubwpkrqndorznwzvaer`. After stages 1–4, all four published hubs match
pre-captured Phase A learner MD5s; API packages equal stored learner packages.

| Hub | Version | Acts | Learner MD5 | Equals Phase A |
| --- | --- | ---: | --- | --- |
| Unit 14 | 0.2.14 | 24 | `2ae5bae4212343eeacb1f316bff49efc` | yes |
| Unit 3 | 0.2.45 | 132 | `a745eabf45cda0d41d8d7c112503195c` | yes |
| L2E | 0.3.39 | 172 | `a4384600a8a4badfe9bdd5c0a2b80e4e` | yes |
| T Level | 0.4.47 | 408 | `882cebc4141ba81729e3fe4abb44de53` | yes |

Storage: ≈ **673 kB** published learner columns; ≈ **26 MB** across all 180
historical publications (compressed column sizes).

## Backfill / migration safety

- Order: 10000 → 10100 → 10200 → 10300
- Stage 3 uses advisory lock shared with publish; concurrent publishes serialise
- Retry-safe; null/outdated rows reprocessed
- Publications during/after stage 2 store learner packages at publish time
- No maintenance window required for the four current hubs
- Interrupted before stage 4: Phase A API remains; columns unused — safe
- Recovery: re-run remaining migrations; backfill is idempotent

## Seed consistency

- `supabase/config.toml` includes `./data/seed/backfill-learner-packages.sql`
- Fresh `supabase db reset` + seed → 0 missing learner packages; all equal Phase A
- Missing packages detectable via `admin_api.publications_missing_learner_packages`
- No duplicated strip logic in seed (calls `learner_curriculum_package`)

## Extended rollback (local verified)

1. Phase B present → publish Unit 14 `9.9.77` with learner package  
2. Public API returns safe package  
3. Rollback restores Phase A functions; new publication still accessible via Phase A  
4. Attempts / marking / publication history preserved  
5. Reapply Phase B → 0 equivalence failures; API OK  
6. Interrupted stage-4 recovery: Phase A API works; reapplying 10300 restores gate  

Rollback script drops Phase B views before recreate (CREATE OR REPLACE cannot
remove columns).

## Tests / CI

- Full local suite: **64 files / 1690 PASS**
- Dedicated: `precomputed_learner_curriculum_packages.test.sql` (31)
- Rollout: `docs/audits/phase-b-learner-packages/PRODUCTION_ROLLOUT.md`

## Production deployment

Executed per `PRODUCTION_ROLLOUT.md`. Results: `PRODUCTION_DEPLOYMENT_RESULTS.md`.

Hosted versions: `20261127101530`, `20261127101533`, `20261127101536`,
`20261127101858` (names match repo; timestamps differ from filenames).

Production T Level anon RPC median ≈ **379 ms**; DB stored path ≈ **0 ms**.

## Remaining risks / limitations

1. Hosted migration timestamps differ from repository filenames (documented).
2. Production classroom concurrency not load-tested; local 30×408 remains the
   concurrency acceptance evidence.
3. Local 1000/2000 benches use compact templates under the staff 4 MiB limit.
