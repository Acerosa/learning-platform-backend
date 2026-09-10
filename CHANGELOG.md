# Changelog

All notable changes to the Learning Platform Backend are documented here.

The project follows Semantic Versioning.

Git tag `curriculum-engine-mvp` (2026-08-13) is the Unit 14 Curriculum Engine
MVP baseline: hub registration, Week 1 catalogue publication, and evidence-only
`api.submit_attempt`. It is not a hosted production release.

## [Unreleased]

### Added

- Classroom Group Generator automatic role assignment. Sessions store an
  optional `specialist_role_title`; generation assigns `project_manager`,
  `tester`, and `specialist` seats (2 testers when group size > 8). Staff can
  override individual roles. Migration `20260910180000_classroom_group_roles`.
  Local-only until hosted review.

- Classroom Group Generator domain for temporary classroom teams (not
  `learning.groups`, not hub/course-bound). Tables
  `learning.grouping_sessions`, `learning.grouping_teams`,
  `learning.grouping_participants`; balancing helper
  `learning.balanced_group_sizes`; anonymous RPCs
  `api.join_grouping_session` and `api.my_grouping_status`; staff RPCs under
  `admin_api.*` gated by `platform_admin`. Migration
  `20260910160000_classroom_group_generator`. Local-only until hosted review.

### Fixed

- Phase 1A.1 authoritative current assignment membership for reporting.
  `api.my_hub_activity_progress` returns one row per logical activity key by
  selecting `learning.current_activity_assignment_id` among active group
  assignments (prefer non-retired, then latest `published_at`). Historical
  multi-version assignments stay active for version-pinned submit/state APIs;
  attempts/responses are not deleted. Local migration
  `20260910140000_reporting_current_assignment_membership`; do not apply
  hosted until separate review. See
  `docs/reporting-current-assignment-membership.md`.
- `api.ensure_learner_auth_link()` links `auth.uid()` to the unique active
  unlinked `learning.students` row whose `contact_email` matches the Auth
  email. Prevents false first-time onboarding / `ONBOARDING_CONFLICT` when a
  roster learner already exists for that email but was never Auth-linked.
  Migration `20260910150000_ensure_learner_auth_link`.

### Added

- Phase 1A learner reporting read `api.my_hub_activity_progress(hub_code)`.
  Hub-scoped completed-attempt progress for the authenticated learner only
  (`auth.uid()`). Uses the same hub ↔ group binding as
  `api.my_hub_assignments`. Excludes formative checks and activity drafts.
  Does not change submit, formative marking, drafts, or
  `api.my_activity_progress`. Local migration
  `20260910093000_learner_hub_activity_progress`; do not apply hosted until
  review.

### Security

- Learner group authority is no longer client-chosen.
  `api.complete_learner_onboarding` is profile/linking only;
  `p_registration_option` is ignored and cannot create or reactivate
  enrolments. `api.registration_options()` no longer lists class keys.
  `open_auto` hubs enrol through `api.resolve_learner_hub_access`.
  Controlled hubs enrol through `api.join_learner_hub_group(hub_code,
  class_key)`, which accepts only an `open_explicit` group bound to that
  hub. Local migration `20260909200000_hub_bound_learner_onboarding`; do
  not apply hosted until review.

### Added

- Authoritative hub ↔ group binding `platform.hub_group_links` and learner RPCs
  `api.resolve_learner_hub_access(hub_code, course_key)` and
  `api.my_hub_assignments(hub_code)`. Identity is `auth.uid()`. Hubs may send
  only their authored hub code and course key. `api.my_assignments`,
  `api.registration_options` and `api.complete_learner_onboarding` are unchanged.
  Unit 3 / Unit 14 / Readiness sharing `ocr-level-3-it` cannot inherit access
  from each other: each hub has explicit group bindings. `open_auto` auto-enrol
  writes only into the requested hub's single eligible group and is not blocked
  by unrelated active enrolments. Resolver reactivation is limited to eligible
  `open_auto` groups; `open_explicit` and `closed` are not restored just by
  opening the hub. `hub_group_links` is many-to-many because
  `learning.groups` are course-year cohorts, not hub-owned containers. Local
  migration `20260909110815_onboard_unlinked_existing_enrolment` is the
  repository filename for the already-hosted onboarding patch; do not apply
  it a second time.

### Fixed

- `api.complete_learner_onboarding` reuses or reactivates an existing enrolment
  when a matching unlinked roster learner completes onboarding into a group
  they already belong to. The previous student-number link path always inserted
  a new enrolment and mapped that unique-constraint failure to
  `ONBOARDING_CONFLICT`, which also rolled back the Auth link. Profile, email
  and student-number conflicts are unchanged.

### Changed

- Documented the production Admin Portal authentication path as Supabase
  email/password plus backend `learning.teachers` / `platform.staff_roles`
  authorisation. First-admin bootstrap is privileged SQL, not a public
  setup URL. `admin_api.claim_initial_platform_admin` remains the consumed
  historical one-time claim.

### Added

- Authenticated in-progress activity drafts: `learning.activity_states` with
  `api.get_activity_state`, `api.save_activity_state`, and
  `api.clear_activity_state`. Server-side resume state is separate from
  completed attempts. Marks and scores cannot be injected through the draft
  payload. `api.submit_attempt` still creates authoritative attempt history
  and completes the matching draft. A later in-progress save does not reopen a
  completed draft unless the client started a new attempt after completion.

- Migration `20260908153000_publish_l2e_expanded_weeks_0_3_13`: publish
  immutable curriculum package `0.3.13` for
  `l2e-exploring-emerging-digital-technologies` /
  `gateway-level-2-digital-it-skills` from the expanded Weeks 1–3 hub
  package (39 activities), project marking catalogue keys, supersede
  `0.3.12`, and assign all published L2E module activity versions to
  `L2E-DELIVERY-A`. Leaves superseded stale Weeks 2–3 activity versions
  in place for history. Contract tests:
  `scripts/ops/tests/l2e-catalogue-alignment.test.mjs` and
  `supabase/tests/database/l2e_expanded_weeks_catalogue.test.sql`.

- Migration `20260908140000_activate_l2e_formative_delivery`: open teaching
  group `L2E-DELIVERY-A` (`registration_key` `l2e-year-1-delivery`) for
  `gateway-level-2-digital-it-skills`, assigning every published L2E module
  activity version. Fixes signed-in learner Check-answer failures caused by
  `ACTIVITY_NOT_ASSIGNED` when only exclusive-smoke `L2E-TEST-A` existed.
  `L2E-TEST-A` remains closed and Week 1 smoke-only.

### Added

- Synthetic QA persona `TLEVEL_DSD_Y2_TEST_LEARNER` joins the existing
  teaching group `TLEVEL-DSD-Y2` (`join_existing_group`) so Week 1
  classification, drag-drop, and short-response can be smoke-tested against
  the normal teaching assignment set. The group is not marked synthetic,
  registration and assignments are left unchanged, and exclusive
  `TLEVEL-TEST-A` / `TLEVEL_TEST_LEARNER` remain restricted to
  `week-1-lesson-1-ex-01`. Credentials stay in gitignored env
  (`TLEVEL_DSD_Y2_TEST_EMAIL` / `TLEVEL_DSD_Y2_TEST_PASSWORD`).

### Changed

- `platform.strip_learner_answer_keys` also removes object `correct` maps used
  by drag-drop blocks. Boolean `correct` remains stripped. Teaching strings
  such as `feedback.correct` are unchanged. Named answer-key fields
  (`correctOptionId`, `correctCategoryId`, `correctValues`, and the rest of the
  existing list) are unchanged.

### Added

- Server-authoritative Readiness Diagnostic marking for version `1.1.0` (current
  25-question contract, 24 scorable marks). Specs live in
  `learning.diagnostic_question_marking`. `api.submit_diagnostic_response`
  marks against the sitting version and ignores client scores. Learner RPCs
  still do not return correctness, scores, or answer keys. Admin session views
  expose `awarded_score`, `max_score`, and completion `score_percentage`.
  Historical `1.0.0` sittings stay unmarked until a separately approved spec
  exists. See [Diagnostic versioning](docs/diagnostic-versioning.md).

### Added

- One readiness diagnostic sitting per hub, course, diagnostic version, and
  trimmed student ID. `api.start_diagnostic` reuses a `started` sitting
  (`resumed: true`) and raises `DIAGNOSTIC_ALREADY_COMPLETED` for a completed
  sitting of the same version, without returning a session id or learner
  details. Uniqueness is
  `(hub_id, course_id, diagnostic_key, diagnostic_version, student_id)`.
  `diagnostic_key` is the hub code; `diagnostic_version` is server-derived from
  hub `features.diagnosticVersion` (default `1.0.0`), not hub software version
  and not content-package version. Student ID remains a self-declared reporting
  label: names are not a uniqueness key and are not overwritten on resume.
  Response-level upsert on `(diagnostic_session_id, activity_id, question_key)`
  is unchanged. No Auth, no `learning.attempts`, no scores.

### Added

- Testing registration of `level-3-it-year-1-readiness` against existing
  course `ocr-level-3-it`. Core contract `0.2.5` is recorded so the hub can
  register. No Year 1-only course is created. Hosted apply records
  `add_readiness_diagnostic_persistence` and
  `register_level_3_it_year_1_readiness`; hub status remains `testing`.
- Anonymous readiness diagnostic persistence, separate from `learning.attempts`.
  Tables `learning.diagnostic_sessions` and `learning.diagnostic_responses`
  store learner-supplied name/student ID as reporting identifiers only.
  Learner hubs write through `api.start_diagnostic`,
  `api.submit_diagnostic_response`, and `api.complete_diagnostic` (no
  `auth.uid()`, no client scores). Staff read
  `admin_api.diagnostic_sessions`, `diagnostic_responses`, and
  `diagnostic_summary` (`platform_admin` only). `is_correct` stays null until
  a published diagnostic marking spec exists.
- Contextual assessment analytics read models: `admin_api.learner_activity_performance`
  (one row per learner/assignment/activity version, including unattempted assigned
  learners) and `admin_api.question_group_performance` (question aggregates scoped
  to a teaching group). First/latest/best/attempt-average scores stay on the same
  learner and assignment. `activity_analytics` now includes canonical titles and
  participation. Hub is not assumed 1:1 with course; linked hub codes are
  exposed only where `platform.hub_course_links` already relates them.

### Added

- `admin_api.inspect_synthetic_qa_learners` and
  `admin_api.inspect_synthetic_qa_auth_user` give the ops provisioner a
  service-role read of synthetic QA readiness without exposing the `learning`
  schema through PostgREST. Learner RLS is unchanged.
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
