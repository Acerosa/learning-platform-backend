# Release process

## Versioning

The repository follows Semantic Versioning.

- Major: breaking API/contract change.
- Minor: backward-compatible platform capability.
- Patch: compatible correction or documentation/test improvement.

Database migration timestamps are independent from package/release versions.

## Required gates

1. Working tree reviewed and free from credentials or learner exports.
2. `python3 scripts/validation/validate_repository.py` passes.
3. A clean `supabase db reset` succeeds.
4. `supabase test db` passes database, RLS, API and integration suites.
5. Active hub API/submission compatibility is reviewed.
6. Security, privacy and RLS changes are reviewed.
7. `CHANGELOG.md` and contract versions are updated.
8. Migration and rollback plans are documented.
9. Hosted migration history is reconciled.
10. Deployment is explicitly approved.

## Deployment separation

Local success is not hosted deployment. Frontend deployment is also not backend
deployment. Release reporting must distinguish:

- implemented;
- locally validated;
- staged/dry-run;
- hosted migration applied;
- post-deployment verification complete.

## Hosted deployment

No hosted command is part of the automatic foundation workflow. When approved,
use the linked project, reviewed Supabase CLI commands and the exact migration
plan for that release. Never expose credentials in logs or commit local link
metadata.

## Verification and rollback

After an approved deployment, verify Auth linkage, onboarding, active
enrolments, assignment delivery, idempotent submission, response persistence,
progress, teacher scoping and admin denial/allow cases with synthetic accounts.

Rollback is release-specific. Prefer a compensating forward migration; never
drop or rewrite learner history to make a schema rollback convenient.

## Repository publication

Commit, remote creation, push, tags and releases require explicit instruction.
This foundation does not perform them automatically.
