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

## Public compatibility RPCs

- `api.registered_hubs()` returns active, non-retired hub metadata.
- `api.platform_contract_versions()` returns active/deprecated client contract
  versions, including the hub-manifest and core compatibility authorities.
- `api.platform_health()` returns current health summaries explicitly marked
  public, never protected diagnostics.

These RPCs are callable before authentication because they expose configuration
and service availability only.

## Error model

Existing learner RPCs return stable uppercase message codes with meaningful
SQLSTATE categories. Frontends must map codes to learner-friendly language and
must not display raw database details.

The current contract predates a JSON error envelope. Introducing one requires a
versioned API migration and compatibility period.
