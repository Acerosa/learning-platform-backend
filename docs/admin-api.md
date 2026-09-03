# Central Admin Portal API foundation

## Status

The admin API contract is version `0.2.0` and **draft**. It exposes read models,
the single-use initial administrator bootstrap, hub registration, curriculum
publication, teacher response review, assessment analytics aggregates, Content
Library CRUD, and Composition Engine RPCs.

## Authentication and roles

The Central Admin Portal uses Supabase Auth. An authenticated user must map
to an active `learning.teachers` profile and an active
`platform.staff_roles` record. Auth claims supplied by the browser do not grant
platform roles.

## Read views

`admin_api` currently exposes:

- `current_staff_context`
- `hubs`
- `hub_course_links`
- `platform_contracts`
- `staff_roles`
- `audit_events`
- `operational_health`
- `learners`
- `groups`
- `enrolments`
- `assignments`
- `attempts`
- `recent_attempts`
- `dashboard_summary`
- `activity_performance`
- `assessment_overview`
- `group_performance`
- `learner_performance`
- `activity_analytics`
- `learner_activity_performance`
- `question_performance`
- `question_group_performance`
- `topic_performance`
- `skill_performance`
- `curriculum_publications`
- `curriculum_drafts`
- `responses`
- `library_questions`
- `library_activities`
- `library_templates`
- `library_resources`
- `library_feedback`
- `library_hints`
- `composition_references`
- `composition_templates`
- `curriculum_recipes`
- `diagnostic_sessions`
- `diagnostic_responses`
- `diagnostic_summary`

All views use `security_invoker = true`; underlying RLS remains authoritative.
Only `platform_admin` can read platform-wide learner, enrolment, assignment,
attempt, readiness-diagnostic and assessment-analytics views in this release. Group-scoped teacher
analytics reads are not opened yet; teacher review mutations remain separately
authorised through `admin_api.review_response`.

`current_staff_context` is the browser-safe session projection used by the
portal after Supabase Auth restores a session. It returns only the current
active staff profile and active backend roles. It does not accept an identity
or role from the browser.

`dashboard_summary` and `activity_performance` are platform-admin-only,
backend-derived operational aggregates. `recent_attempts` returns at most five
attempt summaries ordered by latest `completed_at` for the Admin Dashboard;
full attempt history remains on `admin_api.attempts`. Assessment analytics views add
staff-facing educational aggregates without a warehouse:

| View | Purpose |
| --- | --- |
| `assessment_overview` | Platform KPIs: learners, groups, attempts, completion, average result, review backlog, participation, topic/skill metadata coverage counts |
| `group_performance` | Per-group participation, completion, average/best/latest performance, review backlog |
| `learner_performance` | Per-learner assigned/completed activities, first/latest/best/average scores, review counts. Learner-wide summary only; scores are not scoped to a course, group or activity. |
| `learner_activity_performance` | One row per active enrolment assignment (learner + assignment + activity version). First/latest/best/attempt-average scores are completed attempts for that same learner and assignment. Includes assigned learners with zero attempts. Canonical activity/course/group titles. Hub codes are included only as the course's linked hubs, which may be zero, one or many. |
| `activity_analytics` | Per-assignment assigned vs attempted learners, participation, completion, score distribution, review backlog, canonical titles |
| `question_performance` | Platform-wide per-question response counts, correctness, awarded score averages, review counts, topic/skill keys. Aggregates across teaching groups. |
| `question_group_performance` | Question aggregates scoped to a group assignment, including unanswered completed attempts. Does not invent partial credit. |
| `topic_performance` / `skill_performance` | Existing `topic_keys` / `skill_keys` rollups only; incomplete metadata is visible as sparse coverage |

These aggregates expose summary scores and counts only. They do not include
response payloads or answer keys. Intervention/“needs attention” interpretation
remains in `@learning-platform/results`.

## Readiness Diagnostic staff reads

Readiness diagnostics are separate from `admin_api.attempts` and
`admin_api.responses`. They are not academic grades. `platform_admin` can read:

| View | Purpose |
| --- | --- |
| `admin_api.diagnostic_sessions` | Session list: session id, student name, student ID, hub, course, status, started/completed times, response and Not-sure counts |
| `admin_api.diagnostic_responses` | Session detail: activity/question keys, unit/topic keys, evidence, confidence, Not-sure, server `is_correct` when later available |
| `admin_api.diagnostic_summary` | Hub/course counts: started, completed, completion percentage, response count, Not-sure count and percentage |

These views do **not** yet compute average readiness or unit/question
distributions. The next Admin dashboard can group `diagnostic_responses` by
`unit_key` / `question_key` for Not-sure rates and option distributions. Average
readiness by unit should be added only after authoritative `is_correct` exists;
do not treat completion percentage as a grade.

Proposed follow-up RPCs (not in this release):
`admin_api.diagnostic_session_detail(session_id)` and
`admin_api.diagnostic_unit_summary(hub_code, course_key)` once marking specs
or richer grouping is required. The three views above are enough to build the
Readiness Diagnostic list, detail, and headline counts.

**Query note:** topic/skill/question aggregates join curriculum metadata to
responses. At larger scale they may need materialised follow-ups; MVP computes
from authoritative records.

`admin_api.responses` is the staff Results/Markbook evidence projection. It
exposes question-level payloads, marks, review flags, and optional topic/skill
keys. Interpretation remains in `@learning-platform/results`. Teacher feedback
is readable here when present. Staff complete reviews through
`admin_api.review_response`.

`admin_api.hubs` now includes the reviewed manifest version and hash, exact
core/learner-API/submission requirements, declared capabilities and structured
compatibility metadata. This supports a future validation/approval screen
without making the portal fetch GitHub during normal operation.

The learner projection is deliberately minimised to student number, display
name, active state and aggregate group/enrolment context. Contact details are
not part of the Phase 2 list.

## Initial administrator bootstrap

`admin_api.claim_initial_platform_admin` is the single narrow exception to the
otherwise read-only Phase 2 contract. It accepts only an expiring, out-of-band
bootstrap token. The protected implementation derives the confirmed Auth
identity from `auth.uid()`, creates or reuses that identity's active teacher
profile, grants the fixed `platform_admin` role, records an audit event and
atomically consumes the credential. It cannot accept an Auth user ID or role
from the browser and cannot be reused by any account after the first claim.

The credential table is private, RLS-enabled and inaccessible through the Data
API. This mechanism exists only to establish the first production
administrator; subsequent staff administration must use a separately reviewed
administrator-only mutation.

## Mutations

Direct browser writes to protected tables are denied, including for platform
administrators. Future mutations must be narrow RPCs with:

- a documented role/permission requirement;
- validation and conflict behaviour;
- transactional writes;
- an audit event;
- idempotency where retries are possible;
- stable error codes;
- RLS and integration tests.

Planned areas include group admission, enrolment changes, assignments, activity
lifecycle and staff-role management.

Synthetic QA fixtures are provisioned through:

- `admin_api.ensure_synthetic_qa_groups()`
- `admin_api.provision_synthetic_qa_learner(auth_user_id, persona)`
- `admin_api.set_synthetic_qa_learner_active(persona, active)`
- `admin_api.inspect_synthetic_qa_learners()`
- `admin_api.inspect_synthetic_qa_auth_user(auth_user_id)`

These require `platform_admin` or the service role. They do not create Auth
users, do not copy email into learner records, do not bypass enrolment RLS,
and assign only the catalogued smoke activity allowlist rather than the full
module catalogue. `L2E-TEST-A` includes published Week 1 deterministic
Check-answer activities. Auth users are created or reused by the local admin
command `npm run provision:synthetic-qa`.
See [Synthetic QA learners](synthetic-qa-learners.md).

Hub registration is a reviewed administrative write, not curriculum
publication. `admin_api.register_hub` accepts a `learning-platform-hub.json`
object plus lifecycle status. It requires an active `platform_admin` role,
re-validates the manifest on the server, rejects duplicate hub codes, creates
`platform.hubs` and declared `platform.hub_course_links` in one transaction,
and records a minimised audit event. `admin_api.update_hub` updates an existing
row, synchronises course links, and records `hub.registration.updated`.
`admin_api.courses` is a staff-only course catalogue for validation. The
browser never writes `platform.hubs` directly. See
[Hub registration](hub-registration.md).

Curriculum publication remains a separate mutation:
`admin_api.publish_curriculum` accepts only Approved or Published snapshots
and stores an immutable catalogue row. Staff drafts use
`admin_api.save_curriculum_draft` / `get_curriculum_draft` /
`discard_curriculum_draft`. Opening live teaching copy for editing uses
`admin_api.current_curriculum_package`. See
[Backend publication](backend-publication.md).

Content Library mutations (`save_library_question`, `save_library_activity`,
`delete_library_item`, `publish_library_item`, `archive_library_item`,
`duplicate_library_item`, `search_library`, `get_library_question_detail`)
require an active content-author role (`platform_admin` or `curriculum_admin`).
`publish_library_item` validates a draft and sets `status = published`.
`archive_library_item` archives a published reusable asset without deleting it.
`duplicate_library_item` creates a new draft version from a published, archived
or superseded item. Composition `search_library` continues to filter
`p_status = published` and does not consume drafts. Composition mutations
(`save_composition_reference`, `detach_composition_reference`, template/recipe
CRUD, `save_composition_draft_state`) persist authoring state only. They do
not publish. EXECUTE is granted to `authenticated` and revoked from `anon` /
`PUBLIC`. Function bodies still call `library.is_content_author()`.

Teacher review is a separate mutation: `admin_api.review_response` accepts a
response id, awarded score, optional correctness, feedback summary and optional
next step. Identity comes from `auth.uid()`. Authorisation requires
`platform_admin` or group-scoped teacher access to the attempt’s group. The
RPC updates marks and feedback only, never `response_payload`, recalculates the
attempt total, clears `requires_review`, and records
`learning.response.reviewed` with before/after mark context.

The offline reviewed-manifest and migration generator remains available for
repository-driven registration. The Admin RPC is the staff-facing path for the
same LHDS contract.

## Data minimisation

Admin views expose only fields required by the initial read use cases. Response
payloads are not included in the general attempt view. New PII or evidence
projections require an explicit purpose and authorisation review.
