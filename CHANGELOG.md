# Changelog

All notable changes to the Learning Platform Backend are documented here.

The project follows Semantic Versioning.

Git tag `curriculum-engine-mvp` (2026-08-13) is the Unit 14 Curriculum Engine
MVP baseline: hub registration, Week 1 catalogue publication, and evidence-only
`api.submit_attempt`. It is not a hosted production release.

## [Unreleased]

### Added

- Permanent hub-isolated synthetic QA learners and closed groups
  (`CYBER-TEST-QA`, `TLEVEL-TEST-A`, `UNIT14-TEST-A`, `L2E-TEST-A`).
  Auth users are created through the Admin API; application rows use
  `auth_user_id` and do not copy email into `learning.students`.
  Ordinary enrolment/assignment RLS is unchanged. New QA groups receive
  only the explicit smoke activity, not the full published catalogue.
  `npm run provision:synthetic-qa` is the idempotent admin/ops command that
  creates or safely reuses the four Auth users and links them through
  `admin_api.provision_synthetic_qa_learner`.
- Shared `multi-field-exact` marking mode: configured object fields must
  all match `correctValues`. Extra learner fields are ignored. Trim is
  always applied; case-insensitive comparison is opt-in via
  `caseInsensitive`. Malformed specs stay pending evidence. No partial
  credit. Published historical versions and learner attempts are
  unchanged.
- Unit 3 `week6-legislation-matching` `1.2.0` uses `multi-field-exact`
  for the hub legislation/duty pairs. Incidents stay `requires_review`
  because authoritative pairs are not in the catalogue source.
- Unit 3 Batch A1 catalogue completeness: new unpublished-then-published
  activity versions for the eight live Week 1 banks (`1.1.0`), the four missing
  Week 5 activities, and `W2OCR-Q08` on `week2-ocr-question-practice` `1.1.0`.
  Published `1.0.0` rows, learner evidence, and curriculum publication are not
  mutated.
- Unit 3 Batch A1 hosted recovery: a guarded replayable migration completes
  the truncated MCP apply while retaining the unpublished `u3-w01-baseline`
  `1.1.0` residue id, without rewriting `schema_migrations` or published data.
- Unit 3 Batch B authoritative marking: new activity versions attach explicit
  `single-choice`, `classification`, `completion`, or `requires_review` specs.
  Published versions, historical evidence, and curriculum publication are
  unchanged. Week 5 activities that already had complete specs are not
  re-versioned.

### Security

- Learner-facing `published_curriculum_package` strips answer keys
  (`correctOptionId`, `correctValues`, and related marking fields) while
  keeping teaching structure. Protected `learning.question_marking`
  remains the scoring source.
- `api.submit_attempt` ignores client `awarded_score` / `is_correct` when a
  marking spec exists. Questions without a spec keep the previous client-mark
  path.
- Client `awarded_score` / `is_correct` are never applied. Questions without a
  marking spec now take the same pending-evidence path as `completion` /
  `requires_review` (score 0). Historical attempts are unchanged.
- Direct `INSERT`/`UPDATE`/`DELETE` on `library` tables is revoked from
  `authenticated`; staff writes remain on existing SECURITY DEFINER RPCs.

### Changed

- Hosted production cutover: Unit 3 and T Level classified **DATABASE_DRIVEN**
  after Admin publication and live hub verification
  (`data-curriculum-source=published`). Unit 14 remains **DATABASE_DRIVEN**.

### Added

- Optional `api.published_curriculum_package(hub, course, version)` for explicit
  historical/superseded package reads. Two-argument latest-published behaviour
  is unchanged.

- Assessment analytics read models: `assessment_overview`, `group_performance`,
  `learner_performance`, `activity_analytics`, `question_performance`,
  `topic_performance`, and `skill_performance` (platform-admin aggregates; no
  payloads or answer keys).

### Added

- Teacher review mutation `admin_api.review_response` with feedback persistence,
  attempt total recalculation, completed-row review bypass, and audit events.
- Additive response columns `feedback_summary` and `feedback_next_step`, plus
  `teacher` marking source.

### Added

- Additive `admin_api.responses` staff evidence/marks projection and attempt
  summary fields `requires_review` and `question_count` for Results / Markbook.

### Changed
- Hub Registry Core generation aligned to `0.2.0` for Unit 14, Unit 3 and
  T Level. `learning-platform-core` contract `0.2.0` is registered; `0.1.0`
  remains for historical migrations.

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
