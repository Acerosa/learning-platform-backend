# Central Admin Portal API foundation

## Status

The admin API contract is version `0.1.0` and **draft**. It is read-only.

## Authentication and roles

The Central Admin Portal will use Supabase Auth. An authenticated user must map
to an active `learning.teachers` profile and an active
`platform.staff_roles` record. Auth claims supplied by the browser do not grant
platform roles.

## Read views

`admin_api` currently exposes:

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

All views use `security_invoker = true`; underlying RLS remains authoritative.
Only `platform_admin` can read platform-wide learner, enrolment, assignment and
attempt views in this release.

`admin_api.hubs` now includes the reviewed manifest version and hash, exact
core/learner-API/submission requirements, declared capabilities and structured
compatibility metadata. This supports a future validation/approval screen
without making the portal fetch GitHub during normal operation.

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

Planned areas include hub registration, group admission, enrolment changes,
assignments, activity lifecycle and staff-role management. None is claimed as
implemented in 0.1.0.

Phase 1 hub registration is deliberately an offline reviewed-manifest and
migration workflow; it is not an administrative mutation RPC.

## Data minimisation

Admin views expose only fields required by the initial read use cases. Response
payloads are not included in the general attempt view. New PII or evidence
projections require an explicit purpose and authorisation review.
