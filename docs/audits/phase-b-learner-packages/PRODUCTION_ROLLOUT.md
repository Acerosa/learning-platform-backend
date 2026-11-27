# Phase B production rollout procedure

**Project:** `hubwpkrqndorznwzvaer`  
**Do not** use `supabase db push`. Apply only the four Phase B migrations below.  
**Do not** apply unrelated pending migrations or reconcile historical drift.  
**Do not** deploy hubs, modify student records, or increase statement timeouts.

## Migration order

1. `20261127110000_add_curriculum_learner_package_column.sql`
2. `20261127110100_publish_time_learner_packages.sql`
3. `20261127110200_backfill_curriculum_learner_packages.sql`
4. `20261127110300_published_curriculum_uses_learner_package.sql`

Record each version in hosted `supabase_migrations.schema_migrations` as applied
(manual insert if the migration runner cannot apply due to history discrepancies).

## Pre-deployment verification

1. PR #67 checks green; commit under review matches branch tip.
2. Run read-only section A of `production_equivalence_procedure.sql`.
3. Confirm expected learner MD5s match the captured baseline:

| Hub | Version | Acts | Expected learner MD5 | Expected learner bytes |
| --- | --- | ---: | --- | ---: |
| unit-14-software-engineering-for-business | 0.2.14 | 24 | `2ae5bae4212343eeacb1f316bff49efc` | 100553 |
| unit-3-cyber-security | 0.2.45 | 132 | `a745eabf45cda0d41d8d7c112503195c` | 741365 |
| l2e-exploring-emerging-digital-technologies | 0.3.39 | 172 | `a4384600a8a4badfe9bdd5c0a2b80e4e` | 591517 |
| tlevel-software-development | 0.4.47 | 408 | `882cebc4141ba81729e3fe4abb44de53` | 961645 |

4. Storage: ≈ **2.3 MiB** additional for current four published packages.
5. Rollback artefacts present under `docs/audits/phase-b-learner-packages/`.
6. **No publication maintenance window** required: stage 2 stores on publish;
   stage 3 backfills null/outdated under the same advisory lock as publish.

## Expected locks / duration

- Stages 1–2 / 4: function/view DDL — seconds.
- Stage 3: row-level `FOR UPDATE` + Phase A generation per row. Four hubs
  dominated by T Level (~0.5–1 s) — typically **under 10 s**. Retry-safe.

## Deployment steps

1. Apply migration 1; confirm columns + hardened protect trigger.
2. Apply migration 2; confirm publish paths generate learner packages.
3. Apply migration 3; run section B equivalence assertion (`LEARNER_PACKAGE_EQUIVALENCE_FAILED` → abort).
4. Confirm `admin_api.publications_missing_learner_packages` empty for staff.
5. Apply migration 4; confirm API version gate.
6. Anon RPC smoke for four hubs (activity counts / versions).
7. Browser: T Level Weeks 1–7, published banner.
8. Confirm attempts / responses / activity_states counts unchanged.
9. Record migration versions in hosted history.

## Security verification (post-deploy)

- Anon cannot SELECT `platform.curriculum_publications`.
- Staff diagnostic view does not expose staff package body to learners.
- Spot-check: outdated sanitisation version (staging only) forces rebuild.

## Rollback decision points

- Fail before stage 4 → leave columns; Phase A API still live.
- Fail after stage 4 → run `rollback_precomputed_learner_packages.sql`
  (restore Phase A functions; keep columns; drop/recreate views).
- Equivalence assertion failure → do not proceed; investigate; retry stage 3.

## Post-deployment monitoring

- Anon RPC latency and `57014` rate for T Level.
- Diagnostic view emptiness.
- Publication success rate (Admin publish / session visibility).
- Compare stored learner MD5s to the pre-captured expected values above.
