# Changelog

All notable changes to the Learning Platform Backend are documented here.

The project follows Semantic Versioning.

## [Unreleased]

### Added

- Cyber Security Hub backend activation: publish the 68 grounded Weeks 2–7
  Unit 3 activity versions, open a synthetic `CYBER-TEST-A` registration group,
  and assign those published versions for shared-backend smoke testing. Week 1
  remains unpublished because it has no imported question rows and still relies
  on Apps Script `markSection`.
- Focused Cyber activation pgTAP coverage for registration, onboarding,
  assignment visibility, representative Week 2 submission, progress reads,
  idempotency and cross-learner isolation.
- Phase 2 staff-session, dashboard and activity-performance read models for the
  first authenticated Central Admin Portal vertical slice.
- Backend-derived learner/group summary fields and safe group context on the
  administrative attempt list.
- A synthetic local-only platform-administrator role for end-to-end portal
  demonstration without weakening hosted authorization, plus an isolated
  learner/group/attempt fixture for repeatable Attempts and Analytics screens.
- LHDS `learning-platform-hub.json` schema and reviewed manifests for both
  current learner hubs.
- Dependency-free hub validation with conflict, course, naming, Semantic
  Versioning and platform compatibility checks.
- Deterministic, inactive-by-default hub registration migration generation.
- First-class manifest/core/API/submission compatibility metadata, provenance
  hashes, URL uniqueness and database enforcement for hub registrations.

### Changed

- Local seed assignment generation is scoped to each group's course so
  publishing Cyber versions does not attach them to T Level synthetic groups.
- Academic year seed insert is conflict-safe with the Cyber activation migration.
- The draft admin API contract advances to `0.2.0` for the new read-only views.
- The learner administration projection now excludes contact details and
  returns only the fields required by the Phase 2 list.
- The legacy aggregate hub metadata entries now link to and are cross-validated
  against the standard hub manifests without breaking their existing shape.
- Platform contract fixtures include active hub-manifest and core versions.

## [0.1.0] - 2026-08-11

### Added

- Dedicated platform backend repository and local Supabase project identity.
- Complete 18-migration source history extracted unchanged from the T Level
  Digital Software Development Hub.
- Existing learner identity, curriculum, assignment, attempt, response,
  progress, analytics, registration and onboarding services.
- Protected `platform` schema for hubs, contract versions, staff roles, audit
  events and operational health.
- RLS-protected, read-only `admin_api` foundation for the Central Admin Portal.
- Safe hub discovery, contract-version and public-health RPCs.
- Draft hub registry entries for both current learner hubs.
- Database, RLS, API and integration test directories and new foundation tests.
- Repository validation, curriculum import tooling and release documentation.

### Changed

- `api.submit_attempt` now resolves the single matching assignment across all
  active enrolments instead of requiring exactly one active enrolment.

### Security

- Platform administrator access derives from Supabase Auth and protected staff
  roles.
- Learner and ordinary teacher sessions cannot read platform-wide admin data.
- Audit and operational writes are restricted to the service role.

### Deliberately excluded

- Hosted Supabase deployment or project linking.
- Administrative mutation RPCs.
- Server-authoritative marking redesign.
- Changes to either existing learner hub repository.
