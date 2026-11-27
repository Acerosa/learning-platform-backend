# Phase B production deployment results

**Project:** `hubwpkrqndorznwzvaer`  
**Deployed:** 2026-11-27  
**Repository tip at deploy:** `bddc6b91bdbba507c0dc5c44d73feff8c5d8c561` (PR #67)  
**Status:** Applied and verified. Not rolled back.

## Applied migrations (hosted history)

MCP `apply_migration` recorded these hosted versions (names match repo files;
timestamps differ from repo filenames because of known hosted history drift —
repo files remain `20261127110000` … `20261127110300`):

| Hosted version | Name |
| --- | --- |
| `20261127101530` | `add_curriculum_learner_package_column` |
| `20261127101533` | `publish_time_learner_packages` |
| `20261127101536` | `backfill_curriculum_learner_packages` |
| `20261127101858` | `published_curriculum_uses_learner_package` |

Unrelated migrations were not applied.

## Curriculum equivalence (published hubs)

| Hub | Version | Acts | Learner MD5 | Equals Phase A |
| --- | --- | ---: | --- | --- |
| Unit 14 | 0.2.14 | 24 | `2ae5bae4212343eeacb1f316bff49efc` | yes |
| Unit 3 | 0.2.45 | 132 | `a745eabf45cda0d41d8d7c112503195c` | yes |
| L2E | 0.3.39 | 172 | `a4384600a8a4badfe9bdd5c0a2b80e4e` | yes |
| T Level | 0.4.47 | 408 | `882cebc4141ba81729e3fe4abb44de53` | yes |

All 180 publications: learner packages present; **0** equivalence failures.
API response package equals stored `learner_package` for all four published hubs.
No `correctOptionId` / teacher-note leakage in public RPC responses.

## Storage overhead

- All publications learner storage (column size sum): **≈ 26 MB**
- Four published hubs combined: **≈ 673 kB** (compressed column sizes)

## Production retrieval performance (anon PostgREST)

DB-side T Level `api.published_curriculum_package`: median **≈ 0 ms** (stored path).

End-to-end anon RPC (5 samples after warm):

| Hub | Acts | Response bytes | Min | Med | Max | Leak |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Unit 14 | 24 | 93 261 | 210 | 265 | 273 | no |
| Unit 3 | 132 | 708 771 | 341 | 374 | 431 | no |
| L2E | 172 | 542 391 | 312 | 336 | 1260 | no |
| T Level | 408 | 889 029 | 325 | 379 | 1441 | no |

Statement timeout unchanged (3 s). No `57014` observed in smoke tests.

## Security / integrity

- `anon` cannot `SELECT platform.curriculum_publications`
- API function includes sanitisation-version gate
- Progress counts unchanged vs pre-deploy baseline: attempts **2024**, responses **8179**, activity_states **2486**, publications **180**

## Browser verification

Hub: https://acerosa.github.io/tlevel-software-development-hub/

- Banner: “This teaching copy is the official published course version.”
- Weeks **1–7** available after published package load (weeks 8+ remain schedule-gated)
- No hub redeploy performed

## Rollback

`docs/audits/phase-b-learner-packages/rollback_precomputed_learner_packages.sql` remains available. Not executed.

## Limitations

- Hosted migration version timestamps differ from repository filenames (documented above).
- Production classroom concurrency was not load-tested; local 30×408 acceptance remains the concurrency evidence.
