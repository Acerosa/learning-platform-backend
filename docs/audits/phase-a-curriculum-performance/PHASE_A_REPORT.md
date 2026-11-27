# Phase A — Published curriculum performance optimisation

**Status:** Applied to production `hubwpkrqndorznwzvaer` and verified.  
**Branch:** `fix/published-curriculum-performance`  
**Production migration version:** `20261127091231` (`optimize_learner_curriculum_package`)  
**Repository migration file:** `supabase/migrations/20261127091231_optimize_learner_curriculum_package.sql`  
**Phase B:** Out of scope (not implemented).

## Root cause

`platform.strip_learner_answer_keys` and `platform.learner_curriculum_package` built learner packages with repeated `jsonb ||` accumulation while walking nested activities/blocks. For the T Level package (408 activities) this exceeded the anonymous PostgREST `statement_timeout` (3s), so `api.published_curriculum_package` failed with SQLSTATE `57014`. Hubs fell back to the bundled teaching copy (T Level 0.4.31), which left Weeks 3/4/6/7 planned.

## Implementation

Replaced only:

- `platform.strip_learner_answer_keys(jsonb)` — set-based `jsonb_agg` / `jsonb_object_agg`
- `platform.learner_curriculum_package(jsonb, text, text)` — SQL set-based activity/block aggregation

Preserved: signatures, immutability, `search_path = ''`, revoke from `public`/`anon`/`authenticated`, strip key list (including boolean/object `correct`), teacher-note filtering, ordering, empty/null handling.  
**Not modified:** `api.published_curriculum_package`, RLS, auth, timeouts, publications, learner data, hubs, Phase B precomputation.

## Rollback

Script: `docs/audits/phase-a-curriculum-performance/rollback_optimize_learner_curriculum_package.sql`  
Restores pre-Phase-A function bodies captured in:

- `production_before_strip_learner_answer_keys.sql`
- `production_before_learner_curriculum_package.sql`

Apply via targeted SQL only (do not `supabase db push`).

## Regression tests (local)

- New: `supabase/tests/database/learner_curriculum_package_performance.test.sql` — **24/24 PASS**
- Related suite: **136 PASS**
- Full database suite: **63 files / 1658 PASS**

Coverage includes nested arrays/objects, empties, JSON nulls, protected keys, `correct` handling, teacher-note removal, ordering, activity ids/versions, package equivalence, access boundaries, hub/course isolation.

## Curriculum package equivalence (production data)

Side-by-side candidate vs legacy on all four published hubs before cutover: **identical JSONB** and matching MD5 for every hub.

| Hub | Version | Activities | MD5 (legacy = Phase A) |
| --- | --- | ---: | --- |
| unit-14-software-engineering-for-business | 0.2.14 | 24 | `2ae5bae4212343eeacb1f316bff49efc` |
| unit-3-cyber-security | 0.2.45 | 132 | `a745eabf45cda0d41d8d7c112503195c` |
| l2e-exploring-emerging-digital-technologies | 0.3.39 | 172 | `a4384600a8a4badfe9bdd5c0a2b80e4e` |
| tlevel-software-development | 0.4.47 | 408 | `882cebc4141ba81729e3fe4abb44de53` |

Post-migration MD5s unchanged.

## Performance — database `learner_curriculum_package` (production)

| Hub | Activities | Legacy median ms | Phase A median ms |
| --- | ---: | ---: | ---: |
| Unit 14 | 24 | 98–136 | 57–58 |
| Unit 3 | 132 | 863–1233 | 339–363 |
| L2E | 172 | 1051–1052 | 368–387 |
| T Level | 408 | 3018–4096 | 565–568 |

Acceptance: T Level median DB execution **&lt; 1s** — **met** (~0.57s).

### Synthetic scaling (local Docker, optimised functions)

| Activities | Median ms | Learner bytes |
| ---: | ---: | ---: |
| 100 | 99 | 652473 |
| 250 | 247 | 1634837 |
| 408 | 436 | 2687885 |
| 500 | 491 | 3304297 |
| 1000 | 1024 | 6572549 |
| 2000 | 2150 | 13165273 |

2000-activity case is informational; Phase A does not claim long-term scalability (Phase B).

## Concurrency

**Local (largest local package, 76 activities):** 8 parallel workers OK (wall ~301ms).

**Production anon RPC `api.published_curriculum_package` (T Level):**

| Parallel requests | Result |
| ---: | --- |
| 1 | OK ~1.1s |
| 2 | OK ~1.5–1.7s |
| 4 | OK ~3.2–3.3s |
| 6+ | SQLSTATE `57014` statement timeout |

**Verified:** single-learner and small concurrent class use succeed. **Risk remaining:** a cold burst of ≥6 simultaneous T Level curriculum fetches can still hit the 3s anon timeout. Phase B precomputation is the intended mitigation. Timeout was **not** increased.

## Security verification

- Platform helpers remain non-executable by `anon` / `authenticated`.
- Public learner packages: no protected answer-key literals as JSON keys (`correctOptionId`, `modelAnswer`, `markScheme`, `answerKey`, `correctOrder`, `correctValues`, `correctAnswers`).
- Prose mentions of “modelAnswer” inside teaching strings may appear; these are not answer-key fields.
- Equivalence with legacy strip rules confirmed via identical MD5s.

## Production migration

- Applied only Phase A via Supabase `apply_migration` name `optimize_learner_curriculum_package`.
- Hosted version: **`20261127091231`** (matches repository filename).
- No unrelated migrations applied; no `db push`.
- Publication fingerprint unchanged:  
  `l2e:0.3.39:172,tlevel:0.4.47:408,unit-14:0.2.14:24,unit-3:0.2.45:132`
- Learner tables untouched by this DDL (function replace only). Counts observed after apply: attempts 2024, responses 8179, activity_states 2486, published_packages 4.

## Production RPC (anon, `Content-Profile: api`)

| Hub | Version | Activities | Median wall ms | HTTP |
| --- | --- | ---: | ---: | --- |
| T Level | 0.4.47 | 408 | ~1194 | 200 |
| Unit 3 | 0.2.45 | 132 | ~738 | 200 |
| L2E | 0.3.39 | 172 | ~722 | 200 |
| Unit 14 | 0.2.14 | 24 | ~318 | 200 |

T Level no longer returns `57014` for normal single requests.

## Browser verification (fresh cache-bypass load)

URL: https://acerosa.github.io/tlevel-software-development-hub/?phaseA=2

- RPC `published_curriculum_package` → HTTP 200 (~1.4s)
- Cache version **0.4.47**
- Status: “This teaching copy is the official published course version.” (not fallback)
- Weeks **1–7** available / open links
- Weeks **8–22** remain Coming soon / planned
- No bundled 0.4.31 fallback banner

## Remaining issues / risks

1. **Concurrency cliff:** ≥6 simultaneous cold T Level curriculum RPCs can still timeout under anon 3s limit — Phase B.
2. **Synthetic ≥1000 activities:** median approaches/exceeds 1s locally — expected Phase A limit.
3. **Migration history drift** between repo and hosted project remains; Phase A did not reconcile unrelated history.
4. Local DB fixtures do not contain full production package sizes; production equivalence/perf used hosted packages.

## Phase B (deferred)

- `learner_package` column on publications
- Publish-time precomputation + backfill
- Public RPC reads precomputed packages
