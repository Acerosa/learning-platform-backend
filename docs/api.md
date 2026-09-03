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

Teacher-scoped analytics views are retained for compatibility and use teacher
group access through RLS.

## Registration and onboarding

`api.registration_options()` returns only active, explicitly opened learner
registration choices. It exposes stable keys and display values, not internal
UUIDs.

`api.complete_learner_onboarding(first_name, surname, student_number,
registration_option)` derives the verified Auth user, creates or safely links
one learner profile and creates the selected enrolment transactionally. It is
idempotent for an identical completed onboarding and rejects conflicts.

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

Creates a `started` session for an active registered hub.

Returns `{id, started_at, status, hub_code, course_key}`. Does not return
scores, marking keys, or internal UUIDs other than the session id.

If `p_course_key` is omitted, the hub must have exactly one active course
link. The Year 1 readiness hub is expected to use existing course
`ocr-level-3-it`; there is no Year 1-only course.

Error codes: `INVALID_HUB_CODE`, `INVALID_STUDENT_NAME`, `INVALID_STUDENT_ID`,
`INVALID_COURSE_KEY`, `DIAGNOSTIC_HUB_UNKNOWN`, `DIAGNOSTIC_HUB_INACTIVE`,
`DIAGNOSTIC_HUB_COURSE_NOT_LINKED`, `DIAGNOSTIC_COURSE_REQUIRED`,
`DIAGNOSTIC_COURSE_UNKNOWN`.

### `api.submit_diagnostic_response(p_session_id, p_activity_id, p_unit_key, p_question_key, p_evidence, p_is_not_sure default false, p_confidence default null, p_topic_key default null)`

Persists one question's evidence. Repeat submissions for the same
`(session, activity_id, question_key)` upsert while the session is `started`.
Completed sessions reject further writes (`DIAGNOSTIC_SESSION_COMPLETED`).

The RPC does not accept `is_correct`, `score`, or attempt number. `is_correct`
is always stored as null until an authoritative diagnostic marking spec exists
in `learning.question_marking`. Client evidence may contain a `not-sure`
option; the server also derives `is_not_sure` from that evidence.

`unit_key` is currently an allowlisted client value
(`general`, `global-information`, `fundamentals-of-it`, `cyber-security`,
`web-design`) because the diagnostic package is not yet a published catalogue
projection. Display labels are not stored.

Returns `{id, activity_id, question_key, is_not_sure}`. Does not return
correctness or scores.

### `api.complete_diagnostic(p_session_id)`

Marks the session `completed` and sets `completed_at`. Repeat completion is
idempotent and returns the existing completion. It does not accept a client
final score and does not compute a readiness percentage while `is_correct`
remains unset.

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
