# Disaster recovery runbook (learning platform)

Practical recovery steps for the hosted Supabase project `hubwpkrqndorznwzvaer` and GitHub Pages hubs. This is operational guidance, not a destructive restore exercise.

## Coverage inventory

| Area | Current arrangement | Gap |
| --- | --- | --- |
| Postgres database | Supabase managed backups / PITR per project plan | Confirm retention days in Supabase dashboard; document restore owner |
| Storage objects | Supabase storage (if used for assets) | Confirm bucket backup inclusion |
| Auth users | Supabase Auth | Restore couples with DB; password hashes not separately exportable by staff |
| Curriculum publications | `platform.curriculum_publications` (+ learner packages) | Protected by RLS; recover via DB restore or republish from git content packages |
| Learner progress / assessments | `learning.attempts`, `responses`, `activity_states`, formative checks | DB restore only; no automatic re-mark without approval |
| Migration history | `supabase_migrations.schema_migrations` | Keep alias table; never delete rows to “fix” filenames |
| Repositories / Pages | GitHub + workflow Pages | Redeploy from default branch; do not rely on HTML 200 alone |

## Incident playbooks

### Database outage

1. Check Supabase status and project health advisories.
2. Freeze curriculum publishes and non-essential admin writes.
3. If restore required: use Supabase dashboard PITR/backup to a **new** project or verified restore slot first.
4. Validate row counts for attempts/responses/activity_states/publications against last known baseline.
5. Re-point apps only after auth + RLS smoke checks.

### Deployment / white-page failure

1. Confirm workflow-based Pages build succeeded and assets are under `/assets/` (or hub base path).
2. Verify JS responses are `application/javascript`, not `text/html`.
3. Confirm no references to undeployed `.tsx` sources in production HTML.
4. Confirm published curriculum RPC returns expected package version (not unexpected bundled fallback).
5. Roll forward with a fix PR; avoid force-pushing default branches.

### Curriculum retrieval failure

1. Call `api.published_curriculum_package` for the hub (anon).
2. Confirm `learner_package` present and sanitisation version current.
3. If Phase B path fails closed to rebuild, measure latency; do not raise anon statement timeout.
4. Republish only with marking coverage validation green.

### Marking failure (`requires_review` / null `is_correct` for auto items)

1. Query unresolved published questions (staff diagnostic / coverage gaps).
2. Prefer restore from staff package keys or unbound resolve fixes; never invent answers.
3. Learners can re-check formative answers after fix; do not bulk re-mark history without approval.

## Rollback readiness

- Phase B: `docs/audits/phase-b-learner-packages/rollback_precomputed_learner_packages.sql`
- Marking restore: reverse function definitions from prior migrations; do not bulk-delete marking without a reviewed list
- Publication validation failures automatically keep the previous published curriculum (transactional abort)

## Monitoring gaps to close

- Automated post-deploy smoke (MIME, boot, curriculum version) across hubs
- Alert on elevated formative `requires_review` rates
- Scheduled migration alias drift report
