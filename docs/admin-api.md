# Central Admin Portal API foundation

## Status

The admin API contract is version `0.2.0` and **draft**. It exposes read models,
the single-use initial administrator bootstrap, hub registration, and curriculum
publication.

## Authentication and roles

The Central Admin Portal will use Supabase Auth. An authenticated user must map
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
- `curriculum_publications`

All views use `security_invoker = true`; underlying RLS remains authoritative.
Only `platform_admin` can read platform-wide learner, enrolment, assignment and
attempt views in this release.

`current_staff_context` is the browser-safe session projection used by the
portal after Supabase Auth restores a session. It returns only the current
active staff profile and active backend roles. It does not accept an identity
or role from the browser.

`dashboard_summary` and `activity_performance` are platform-admin-only,
backend-derived aggregates. The analytics view contains summary scores and
timestamps only; it does not expose learner response payloads.

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
and records a minimised audit event. The browser never writes `platform.hubs`
directly. See [Hub registration](hub-registration.md).

Curriculum publication remains a separate mutation:
`admin_api.publish_curriculum` accepts only Approved or Published snapshots
and stores an immutable catalogue row. See
[Backend publication](backend-publication.md).

The offline reviewed-manifest and migration generator remains available for
repository-driven registration. The Admin RPC is the staff-facing path for the
same LHDS contract.

## Data minimisation

Admin views expose only fields required by the initial read use cases. Response
payloads are not included in the general attempt view. New PII or evidence
projections require an explicit purpose and authorisation review.
