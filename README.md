# Learning Platform Backend

The single authoritative Supabase backend repository for all Learning Platform
learner hubs and the future Central Admin Portal.

Version: **0.1.0 (foundation)**

Curriculum Engine MVP baseline: git tag `curriculum-engine-mvp`. See
[docs/content-publication.md](docs/content-publication.md).

## Purpose

This repository owns shared backend data and behaviour:

- Supabase configuration and reproducible migrations;
- Auth-to-learner and Auth-to-staff linkage;
- academic years, courses, groups and enrolments;
- curriculum, activities, versions, questions and delivery;
- assignments, attempts, responses, progress and analytics;
- learner registration and onboarding;
- Row Level Security and approved API boundaries;
- hub registration and platform contract versions;
- staff roles and the read-only Central Admin Portal API foundation;
- audit-event and operational-health foundations;
- backend tests, fixtures and release controls.

Learner hubs own curriculum content, presentation and subject-specific activity
behaviour. They must not own database migrations, RLS or authoritative learner
records.

## Extraction source

The foundation was extracted from the proven shared Supabase implementation in
`tlevel-software-development-hub` at commit `2e24b1b`.

All 18 source migrations were copied unchanged and in their original order.
Forward migrations add the new platform-owned registry and administrative
foundations and make `api.submit_attempt` compatible with multiple active
course enrolments. Stable UUIDs, Auth mappings, activity keys, attempts,
responses and API signatures are preserved.

The source hub and the Unit 3 Cyber Security Hub are reference implementations
only. This repository does not modify either hub.

## Architecture

```text
Learner hubs ────────> api schema ────────┐
                                           │
Central Admin Portal ─> admin_api schema ──┼─> learning + platform schemas
                                           │
Supabase Auth ───────> auth.uid() ─────────┘
```

- `learning`: protected learner, staff, curriculum and evidence domain.
- `platform`: protected hub registry, contracts, staff roles, audit and health.
- `api`: learner-safe and public compatibility views/RPCs.
- `admin_api`: staff-only, RLS-protected Central Admin Portal boundary.

Browsers never provide authoritative learner IDs, enrolment IDs, permissions
or attempt numbers. Learner identity derives from `auth.uid()` and protected
relationships. Privileged credentials must never be committed or placed in a
browser application.

See [docs/architecture.md](docs/architecture.md) for the complete boundary.

## Repository structure

```text
learning-platform-backend/
├── README.md
├── CHANGELOG.md
├── LICENSE
├── supabase/
│   ├── config.toml
│   ├── migrations/
│   ├── seed.sql
│   ├── tests/
│   │   ├── database/
│   │   ├── rls/
│   │   ├── api/
│   │   └── integration/
│   └── data/
│       ├── manifests/
│       ├── fixtures/
│       └── generated/
├── scripts/
│   ├── validation/
│   ├── import/
│   └── release/
└── docs/
    ├── architecture.md
    ├── database.md
    ├── api.md
    ├── rls.md
    ├── migrations.md
    ├── admin-api.md
    └── release-process.md
```

## Requirements

- Supabase CLI
- Docker-compatible local container runtime
- Python 3 for dependency-free repository/import validation

No hosted Supabase link is required for local development.

## Local setup and validation

From the repository root:

```bash
python3 scripts/validation/validate_repository.py
supabase start
supabase db reset
supabase test db
```

`supabase db reset` is local and destructive to the local development database.
It must not be confused with a hosted deployment.

Stop local services with:

```bash
supabase stop
```

All seed identities and records are synthetic and use `.invalid` email
addresses.

## Supported learner API

Existing hubs retain these contracts:

- `api.my_profile`
- `api.my_enrolments`
- `api.my_assignments`
- `api.my_activity_delivery`
- `api.curriculum_weeks`
- `api.my_attempts`
- `api.my_responses`
- `api.my_activity_progress`
- `api.registration_options()`
- `api.complete_learner_onboarding(...)`
- `api.submit_attempt(...)`

The foundation also adds safe discovery RPCs:

- `api.registered_hubs()`
- `api.platform_contract_versions()`
- `api.platform_health()`

The `api` schema is the supported learner-facing boundary. Hubs must not query
protected schemas directly.

## Administrative foundation

`admin_api` currently provides read-only views for current staff context, hubs,
contracts, staff roles, audit events, operational health, learners, groups,
enrolments, assignments, attempts, dashboard counts, activity-performance
aggregates and curriculum publication history. Access requires an active staff
profile and the appropriate role in `platform.staff_roles`; learner Auth
sessions return no administrative data.

Hub registration is a narrow `admin_api` mutation: `admin_api.register_hub`.
It accepts a reviewed `learning-platform-hub.json` object plus lifecycle
status, requires `platform_admin`, and writes `platform.hubs` plus declared
course links. Duplicate hub codes are rejected. See
[Hub registration](docs/hub-registration.md).

Curriculum publication is a separate mutation:
`admin_api.publish_curriculum`. It accepts only Approved or Published snapshots,
re-validates them on the server and stores an immutable catalogue row. See
[Backend publication](docs/backend-publication.md). Other administrative
mutations remain unspecified.

## Curriculum and hub manifests

Reviewed manifests live in `supabase/data/manifests/`. They are source
artefacts, not runtime database reads. Production data changes must be converted
to reviewed migrations.

Every learner hub uses the LHDS root manifest `learning-platform-hub.json`.
The schema, validation report and deterministic registration-migration workflow
are documented in [docs/hub-registration.md](docs/hub-registration.md). GitHub
is an onboarding source, never a runtime dependency.

The initial hub registry contains draft/testing metadata for:

- Unit 3 Cyber Security Hub
- T Level Digital Software Development Hub
- Unit 14 Software Engineering for Business Hub

None of these hubs is marked certified by this repository.

## Security rules

- Never commit service-role keys, database passwords, access tokens or real
  learner/staff exports.
- Never expose the `learning`, `platform` or `admin_api` schemas to anonymous
  learner code.
- Keep SECURITY DEFINER functions narrow, input-validated and configured with
  `search_path = ''`.
- Enable and test RLS on every protected table.
- Do not use feature flags, hub status or frontend checks as authorisation.
- Keep audit context minimal and free from arbitrary learner PII.

## Current limitations

- `api.submit_attempt` still accepts client-marked items when both
  `awarded_score` and `is_correct` are present (Unit 3 / T Level). Core
  evidence-only items omit both fields and are server-marked from protected
  `learning.question_marking`. Rejecting client marks on questions that have
  marking specs is later contract work; do not break historical attempts.
- The admin API is read-only and version `0.1.0` remains draft.
- Audit and health tables/functions are foundations; no external monitoring or
  event pipeline is configured.
- Hosted migration history has not been reconciled to this new repository.
- No hosted Supabase deployment, link, push or remote migration is performed by
  this foundation.

## Documentation

- [Architecture](docs/architecture.md)
- [Database](docs/database.md)
- [Learner and public API](docs/api.md)
- [RLS and trust model](docs/rls.md)
- [Migration ownership](docs/migrations.md)
- [Central Admin Portal API](docs/admin-api.md)
- [Repository-driven hub registration](docs/hub-registration.md)
- [Content package publication](docs/content-publication.md)
- [Backend curriculum publication](docs/backend-publication.md)
- [Release process](docs/release-process.md)

## Release policy

Use semantic versioning. A backend release requires a clean local reset, all
pgTAP suites, compatibility review for every active hub, release notes and an
explicitly approved hosted deployment plan. Do not run `supabase db push` or
repair hosted migration history from this repository without that approval.
