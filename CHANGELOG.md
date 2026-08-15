# Changelog

All notable changes to the Learning Platform Backend are documented here.

The project follows Semantic Versioning.

Git tag `curriculum-engine-mvp` (2026-08-13) is the Unit 14 Curriculum Engine
MVP baseline: hub registration, Week 1 catalogue publication, and evidence-only
`api.submit_attempt`. It is not a hosted production release.

## [Unreleased]

### Added

- Learner-safe `api.published_curriculum_package(hub, course)` returning the
  current published canonical teaching package. Drafts, superseded rows, staff
  publication fields and `learning.question_marking` are not exposed. Anonymous
  read is allowed for published teaching content.
- Server-side, transactional, idempotent catalogue projection from a published
  `lp.content` package into delivery tables. Published activity versions remain
  immutable. OCR assignment briefs stay inside the package.
- Local seed of the reviewed Unit 14 curriculum package `0.2.0` for
  database-first learner delivery.

### Changed

- `admin_api.publish_curriculum` now projects the delivery catalogue in the
  same transaction as the immutable publication row.
- `api.published_curriculum()` is also callable by anonymous clients.
- Canonical published packages are the runtime source of truth for Unit 14.
  The generator SQL path remains for reviewed historical imports.
- Administrative hub registration through `admin_api.register_hub` and updates
  through `admin_api.update_hub`. Authorised `platform_admin` staff can register
  or maintain a reviewed `learning-platform-hub.json` in `platform.hubs` with
  course links and an audit event. Duplicate hub codes are rejected on
  register. `admin_api.courses` exposes the course catalogue for validation.
  This is not curriculum publication.
- Controlled curriculum publication pipeline: immutable
  `platform.curriculum_publications` catalogue, server-side package validation,
  `admin_api.publish_curriculum`, staff publication history, and learner-safe
  `api.published_curriculum()` metadata. Published rows cannot be edited;
  a newer version supersedes the previous current row and keeps audit history.
- Unit 14 hub registration and Week 1 content-package publication: 19 week
  metadata records, four hub-owned OCR assignment artefacts, 11 published Week 1
  activity versions, protected formative marking specs, and a closed
  `UNIT14-TEST-A` delivery group.
- Deterministic `lp.content` package generator with validation and idempotent SQL.
- Compatible evidence-only `api.submit_attempt` path: Core payloads without
  `awarded_score` / `is_correct` are server-marked; client-marked Unit 3 / T Level
  payloads are unchanged.
- Cyber Security Hub backend activation: publish the 68 grounded Weeks 2–7
  Unit 3 activity versions, open a synthetic `CYBER-TEST-A` registration group,
  and assign those published versions for shared-backend smoke testing. Week 1
  remains unpublished because it has no imported question rows and still relies
  on Apps Script `markSection`. Publish updates only affect unpublished rows so
  already-published hosted versions stay immutable.
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
