# Central Admin Portal API foundation

## Status

The admin API contract is version `0.2.0` and **draft**. It exposes read models,
the single-use initial administrator bootstrap, hub registration, curriculum
publication, teacher response review, and assessment analytics aggregates.

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
- `dashboard_summary`
- `activity_performance`
- `assessment_overview`
- `group_performance`
- `learner_performance`
- `activity_analytics`
- `question_performance`
- `topic_performance`
- `skill_performance`
- `curriculum_publications`
- `responses`

All views use `security_invoker = true`; underlying RLS remains authoritative.
Only `platform_admin` can read platform-wide learner, enrolment, assignment,
attempt and assessment-analytics views in this release. Group-scoped teacher
analytics reads are not opened yet; teacher review mutations remain separately
authorised through `admin_api.review_response`.

`current_staff_context` is the browser-safe session projection used by the
portal after Supabase Auth restores a session. It returns only the current
active staff profile and active backend roles. It does not accept an identity
or role from the browser.

`dashboard_summary` and `activity_performance` are platform-admin-only,
backend-derived operational aggregates. Assessment analytics views add
staff-facing educational aggregates without a warehouse:

| View | Purpose |
| --- | --- |
| `assessment_overview` | Platform KPIs: learners, groups, attempts, completion, average result, review backlog, participation, topic/skill metadata coverage counts |
| `group_performance` | Per-group participation, completion, average/best/latest performance, review backlog |
| `learner_performance` | Per-learner assigned/completed activities, first/latest/best/average scores, review counts |
| `activity_analytics` | Per-assignment assigned vs attempted learners, completion, score distribution, review backlog |
| `question_performance` | Per-question response counts, correctness, awarded score averages, review counts, topic/skill keys |
| `topic_performance` / `skill_performance` | Existing `topic_keys` / `skill_keys` rollups only; incomplete metadata is visible as sparse coverage |

These aggregates expose summary scores and counts only. They do not include
response payloads or answer keys. Intervention/“needs attention” interpretation
remains in `@learning-platform/results`.

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
