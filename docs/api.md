# Learner and public API

## Boundary

The `api` schema is the supported boundary for learner hubs. Direct browser
queries to `learning`, `platform` or `admin_api` are prohibited.

## Learner-safe reads

Authenticated learner views:

- `api.my_profile`
- `api.my_enrolments`
- `api.my_assignments`
- `api.my_activity_delivery`
- `api.curriculum_weeks`
- `api.my_attempts`
- `api.my_responses`
- `api.my_activity_progress`

Authenticated in-progress drafts:

- `api.get_activity_state(activity_key, activity_version)`
- `api.save_activity_state(activity_key, activity_version, state, client_updated_at default null, hub_code default null)`
- `api.clear_activity_state(activity_key, activity_version)`

These persist unfinished responses so a learner can resume across browsers and
devices. They are not attempts, scores, or derived progress. Identity is always
`auth.uid()`. Direct table access is revoked. Saving after `api.submit_attempt`
does not reopen a completed draft unless the payload `startedAt` is after
`completed_at` (a new attempt).

Teacher-scoped analytics views are retained for compatibility and use teacher
group access through RLS.

## Registration and onboarding

`api.registration_options()` returns only active, explicitly opened learner
registration choices. It exposes stable keys and display values, not internal
UUIDs.

`api.complete_learner_onboarding(first_name, surname, student_number,
registration_option)` derives the verified Auth user, creates or safely links
one learner profile and creates the selected enrolment transactionally. It is
idempotent for an identical completed onboarding, lets an already-linked learner
join an additional open group, and reuses or reactivates an existing enrolment
when a matching unlinked roster record is linked. It still rejects profile,
email and student-number conflicts. It is not the generic “enter this hub”
RPC.

## Hub access and hub-scoped assignments

Authority for hub-scoped assignment reads:

```text
auth.uid()
  → learning.students
  → active learning.enrolments
  → platform.hub_group_links (groups permitted for this hub)
  → learning.activity_assignments for those groups
```

`platform.hub_course_links` remains necessary but is not sufficient. Unit 3,
Unit 14 and Readiness all use `ocr-level-3-it`; delivery-group permission is
`platform.hub_group_links`.

`api.resolve_learner_hub_access(p_hub_code, p_course_key)` is authenticated,
`SECURITY DEFINER`, empty `search_path`. Identity is only `auth.uid()`. The
browser may identify the authored hub and course. It must not send student,
enrolment, group or role UUIDs. Returned columns are learner-safe display and
status fields only.

Statuses:

- `profile_required` — no active `learning.students` row. If exactly one
  eligible open bound group exists, `registration_option` is that group's
  existing `registration_key` so profile completion can call
  `complete_learner_onboarding` without a platform-wide picker.
- `enrolled` — active enrolment in a group bound to this hub. No write.
- `enrolled_created` — auto-enrol into the single `open_auto` bound group for
  this hub. Other-hub enrolments do not block that write. The write is only
  into the hub-bound group.
- `enrolled_reactivated` — inactive enrolment in an eligible `open_auto`
  hub-bound group is reactivated. `open_explicit` and `closed` are not
  reactivated by opening the hub; those remain JoinClass /
  `complete_learner_onboarding` or staff placement.
- `ambiguous` — more than one eligible `open_auto` group and the learner is not
  already enrolled. No pick-list of keys.
- `no_enrolment` — profile exists but this hub has no matching enrolment, and
  auto-enrol is not permitted (`open_explicit`, or Unit 3 JoinClass).
- `no_open_group` — no eligible open join path (including closed-only bindings
  such as Unit 14).

`api.my_hub_assignments(p_hub_code)` returns the same learner-safe assignment
fields as `api.my_assignments` except `assignment_id`. It filters to groups
bound to that hub. `api.my_assignments` remains the unscoped union of all
active enrolments.

Current `api.my_assignments` callers (unscoped compatibility union):

- Core `platform.assignments.getAssignments()` (compatibility)
- Core vendor IIFE ready-path in older hub copies
- README and this document's learner-safe read list

Unit 3 `js/core/supabase-learning-api.js` `getMyAssignments` and T Level
`js/core/supabase-analytics.js` prefer `api.my_hub_assignments` through Core
`getHubAssignments(hubCode)` when that method exists, and fall back to
`getAssignments()` otherwise.

`api.submit_attempt` and `api.mark_formative_response` are unchanged. They still
resolve the unique current assignment across active enrolments by activity key.

## Submission contract 0.1.0

`api.submit_attempt(...)` accepts:

- activity key;
- semantic activity version;
- client attempt ID;
- structured response array;
- relative source page;
- optional paired started/completed timestamps;
- optional declared programming language.

It never accepts learner ID, student number, enrolment ID, assignment ID,
attempt number or authoritative top-level score.

The backend:

1. derives the learner from `auth.uid()`;
2. resolves the published activity version;
3. finds exactly one current assignment across all active enrolments;
4. validates response completeness and question/version membership;
5. derives the next attempt number;
6. stores attempt and responses atomically;
7. returns the stored result;
8. returns the existing result for an identical idempotent retry.

Zero matching assignments returns `ACTIVITY_NOT_ASSIGNED`; more than one
matching assignment returns `ACTIVITY_ASSIGNMENT_AMBIGUOUS`.

Response items may still include client marks (`awarded_score` and
`is_correct`) for compatibility with older hubs. Those fields are never
authoritative. The backend always marks through protected
`learning.question_marking` via `learning.score_submitted_item`:
deterministic formative comparison where a spec exists (`single-choice`,
`classification`, `python-patterns`, `multi-field-exact`). Explicit
`completion` and `requires_review` specs, and questions with no spec, stay
pending evidence (`is_correct` null, score 0, `requires_review` true) and do
not award marks for text presence or client-supplied scores.
`multi-field-exact` compares only configured object fields against
`correctValues` (trim always; case-insensitive only when
`caseInsensitive` is true). Extra learner fields are ignored for
correctness. There is no partial credit. Malformed specs stay pending.
The submission contract version remains 0.1.0.

## Public compatibility RPCs

- `api.registered_hubs()` returns active, non-retired hub metadata.
- `api.platform_contract_versions()` returns active/deprecated client contract
  versions, including the hub-manifest and core compatibility authorities.
- `api.platform_health()` returns current health summaries explicitly marked
  public, never protected diagnostics.

These RPCs are callable before authentication because they expose configuration
and service availability only.

## Readiness diagnostics

Readiness diagnostics are anonymous pre-enrolment checks. They are **not**
authenticated learner attempts. They must not be stored in `learning.attempts`.
Student name and student ID are learner-supplied reporting labels. They are
not Auth credentials, not `learning.students` identity, and not enrolment keys.
The RPCs do not call `auth.uid()` and do not create learner accounts.

Browsers write only through these `api` RPCs. Direct DML on
`learning.diagnostic_sessions` and `learning.diagnostic_responses` is revoked
from `anon` and `authenticated`.

### `api.start_diagnostic(p_hub_code, p_student_name, p_student_id, p_course_key default null)`

Starts or resumes one `started` sitting for an active registered hub, course,
diagnostic version, and trimmed student ID. This is deduplication, not
authentication: the RPC still does not call `auth.uid()`, still does not verify
the ID against `learning.students`, and still accepts a self-declared name.

`diagnostic_key` is the hub code. `diagnostic_version` is derived server-side
from `platform.hubs.features.diagnosticVersion`, defaulting to `1.0.0`. Clients
must not send a version.

Behaviour:

- no matching sitting → insert and return `resumed: false`
- matching `started` (or `abandoned`) sitting → return that row with
  `resumed: true`; the original stored name is preserved
- matching `completed` sitting → raise `DIAGNOSTIC_ALREADY_COMPLETED` with no
  session id, name, timestamps, or responses

Returns `{id, started_at, status, hub_code, course_key, resumed}`. Does not
return scores, marking keys, or internal UUIDs other than the session id.

If `p_course_key` is omitted, the hub must have exactly one active course
link. The Year 1 readiness hub is expected to use existing course
`ocr-level-3-it`; there is no Year 1-only course.

Error codes: `INVALID_HUB_CODE`, `INVALID_STUDENT_NAME`, `INVALID_STUDENT_ID`,
`INVALID_COURSE_KEY`, `DIAGNOSTIC_HUB_UNKNOWN`, `DIAGNOSTIC_HUB_INACTIVE`,
`DIAGNOSTIC_HUB_COURSE_NOT_LINKED`, `DIAGNOSTIC_COURSE_REQUIRED`,
`DIAGNOSTIC_COURSE_UNKNOWN`, `DIAGNOSTIC_VERSION_INVALID`,
`DIAGNOSTIC_ALREADY_COMPLETED`, `DIAGNOSTIC_START_FAILED`.

`DIAGNOSTIC_ALREADY_COMPLETED` is an accepted, minimal enumeration signal: an
anonymous caller who already knows a student ID can learn that a completed
sitting exists for that ID and diagnostic version. The error must not include
learner name, completed date, responses, score, confidence, or session UUID.

### `api.submit_diagnostic_response(p_session_id, p_activity_id, p_unit_key, p_question_key, p_evidence, p_is_not_sure default false, p_confidence default null, p_topic_key default null)`

Persists one question's evidence. Repeat submissions for the same
`(session, activity_id, question_key)` upsert while the session is `started`.
Completed sessions reject further writes (`DIAGNOSTIC_SESSION_COMPLETED`).

The RPC does not accept `is_correct`, `score`, or attempt number. The server
looks up `learning.diagnostic_question_marking` for the **session** diagnostic
key/version and stores `is_correct`, `awarded_score`, and `max_score`. Client
evidence may include forged correctness fields; they are ignored. A sitting
whose version has no spec stays unmarked. Client evidence may contain a
`not-sure` option; the server also derives `is_not_sure` from that evidence.

`unit_key` is currently an allowlisted client value
(`general`, `global-information`, `fundamentals-of-it`, `cyber-security`,
`web-design`) because the diagnostic package is not yet a published catalogue
projection. Display labels are not stored.

Returns `{id, activity_id, question_key, is_not_sure}`. Does not return
correctness or scores.

### `api.complete_diagnostic(p_session_id)`

Marks the session `completed` and sets `completed_at`. Repeat completion is
idempotent and returns the existing completion. It does not accept a client
final score and does not return awarded marks. Staff totals are derived from
already-stored response marks in `admin_api.diagnostic_sessions`. Completion
does not create a new sitting. After completion,
`api.start_diagnostic` for the same student ID and diagnostic version raises
`DIAGNOSTIC_ALREADY_COMPLETED`.

Returns `{id, completed_at, status}`.

Possession of a session UUID is the write capability for submit/complete.
There is no list/read RPC for anonymous clients, so one learner cannot enumerate
another learner's diagnostic rows.

## Published curriculum

`api.published_curriculum()` returns hub, course, version and timestamp
metadata for currently published curriculum packages. It is available to
anonymous clients, authenticated learners and staff. It does not return
package bodies.

`api.published_curriculum_package(hub_code, course_key)` returns the current
published canonical teaching package for one hub and course. The three-argument
form `api.published_curriculum_package(hub_code, course_key, package_version)`
returns that version, including superseded historical rows. Latest reads never
return drafts or staff publication fields or `learning.question_marking`.
Learner hubs must not read Admin storage. See
[Backend publication](backend-publication.md).

## Error model

Existing learner RPCs return stable uppercase message codes with meaningful
SQLSTATE categories. Frontends must map codes to learner-friendly language and
must not display raw database details.

The current contract predates a JSON error envelope. Introducing one requires a
versioned API migration and compatibility period.
