# Learning Hub Development Standard (operational summary)

This document summarises the **verified** Learning Platform contracts that hubs
and backend changes must follow. Detailed mechanics live in
[architecture.md](architecture.md), [precomputed-learner-packages.md](precomputed-learner-packages.md),
[hub-registration.md](hub-registration.md), Core `docs/deployment-health.md`,
and the recovery runbooks under `docs/audits/` / `docs/runbooks/`.

Do not treat proposed or unimplemented ideas as operational requirements.

## Curriculum

| Requirement | Verified behaviour |
| --- | --- |
| Authoritative staff packages | Stored on `platform.curriculum_publications.package` |
| Precomputed learner-safe packages | `learner_package` + `learner_package_sanitisation_version` (`lp.strip.v2`) |
| Publication-time sanitisation | `platform.learner_curriculum_package` / `strip_learner_answer_keys` |
| Sanitisation version enforcement | Outdated or forged versions rejected; regenerate/backfill on version bump |
| Safe fallback | API may construct Phase A learner package only when stored package is null; hubs must not silently ship bundled curriculum as published |
| Publication immutability | Published rows are immutable except controlled derived-field regeneration |
| Publication rollback | Failed publish (including marking coverage) aborts the transaction; previous published curriculum remains active |

## Marking

| Requirement | Verified behaviour |
| --- | --- |
| Server-side marking | `mark_evidence_response` / `score_submitted_item` via `question_marking` |
| Spec registration | Projection + restore/enrich from staff blocks; language-variants from hub banks where projection emptied keys |
| Fingerprint validation | Required; do not disable |
| Unbound catalogue resolve | Unique automatic published spec; fail closed on ambiguity |
| Language-specific marking | Mode `language-variants`; attempt programming language required |
| Client formative marking | Allowed for Foundations UX via hub banks when learner packages strip keys; not grade authority |
| Protected answer keys | Not in learner packages or public health endpoints |
| Coverage validation | `assert_package_marking_coverage` at publish |
| Admin diagnostics | `published_marking_coverage_gaps` / `_summary` (staff roles only) |

## Deployment

| Requirement | Verified behaviour |
| --- | --- |
| Pages source | GitHub Actions workflow artifact |
| Compiled assets + MIME | Health checks fail on HTML-served JS or TypeScript source refs |
| Smoke / curriculum version | Core deployment-health + hub workflow smokes |
| Release / rollback | Compensating forward migrations; see disaster recovery runbook |

## Database operations

| Requirement | Verified behaviour |
| --- | --- |
| Isolated migrations | MCP `apply_migration` / reviewed SQL; no unrestricted `db push` |
| Hosted timestamp mapping | Alias inventory in marking-coverage recovery docs |
| Baseline / integrity | Capture attempt/response/publication counts before marking restores |
| Security | RLS; revoke anon on protected RPCs; no answer keys in public diagnostics |

## Development

- Regression: `supabase test db`, hub unit/CI suites, Pages health where applicable.
- Authenticated browser verification uses synthetic QA learners only
  (`docs/synthetic-qa-learners.md`). Do not use real student credentials.
- Shared package compatibility: pin Core/UI versions per hub manifests.
- PR/CI: required checks must pass; do not bypass branch protection.
