# Row Level Security and authorisation

## Rules

All protected `learning` and `platform` tables have RLS enabled. Frontend logic
is never an authorisation boundary.

The local Data API exposes `api` and `admin_api`; it does not expose the
protected schemas. Schema exposure alone would not replace RLS.

## Learner access

Learner policies resolve `learning.current_student_id()` from `auth.uid()`.
Learners may read only their own profile, enrolments, attempts and responses,
plus currently published/assigned curriculum permitted by the established
policies.

Learner writes occur through narrow SECURITY DEFINER RPCs. Direct inserts into
learner records are not granted.

Anonymous readiness diagnostics are an explicit exception to `auth.uid()`
identity. `anon` may execute `api.start_diagnostic`,
`api.submit_diagnostic_response`, and `api.complete_diagnostic` only. Direct
INSERT/UPDATE/DELETE on `learning.diagnostic_sessions` and
`learning.diagnostic_responses` is revoked from `anon` and `authenticated`.
`anon` has no SELECT. Authenticated SELECT is granted but RLS limits it to
`platform_admin`. There is no anonymous read RPC for other learners' sessions.
Session UUID possession is the write capability for submit/complete.
`api.start_diagnostic` is idempotent per trimmed student ID and diagnostic
version; uniqueness is enforced by
`learning.diagnostic_sessions_one_sitting_idx`. A completed sitting raises
`DIAGNOSTIC_ALREADY_COMPLETED` without returning that session's UUID, name, or
responses. That error can reveal that a sitting exists for a guessed student
ID; that residual enumeration is accepted only because the payload is otherwise
empty. Duplicate prevention does not use `auth.uid()`.

## Teaching-group access

`learning.current_teacher_id()` maps Auth to an active staff profile.
`learning.teacher_can_access_group(group_id)` requires a current,
non-revoked `teacher_group_access` relationship.

This scope supports existing teacher analytics but does not grant Central Admin
Portal authority.

## Platform staff roles

`platform.staff_roles` supports:

- `platform_admin`
- `curriculum_admin`
- `operations`
- `auditor`
- `support`

Roles are explicit and revocable. An active teacher record without a platform
role receives no platform-wide access.

Version 0.1.0 grants full learner-domain read views only to `platform_admin`.
Other roles can read only the platform views appropriate to their role. No
authenticated role can mutate protected tables directly.

The `library` schema is staff-only. Every library table has RLS. Policies
require `library.is_content_author()` (`platform_admin` or
`curriculum_admin`). Anonymous clients have no table privilege and no EXECUTE
on library/composition RPCs. Authenticated non-authors may EXECUTE those RPCs
but receive empty results or author-role exceptions; they cannot mutate
library rows. All `admin_api` library and composition views use
`security_invoker = true`.

`platform.curriculum_publications` is readable by authorised staff roles.
Inserts occur only through `admin_api.publish_curriculum`. Published rows are
immutable except for the controlled supersede transition. Staff drafts live in
`platform.curriculum_drafts` and are readable/writable only through the
`admin_api` draft RPCs (`platform_admin` or `curriculum_admin`). Learners and
anonymous clients read current published teaching content only through
`api.published_curriculum()` and `api.published_curriculum_package()`. They
cannot read drafts, superseded bodies, staff publication fields or
`learning.question_marking`.

Hub registration inserts occur only through `admin_api.register_hub`. Updates
occur only through `admin_api.update_hub`. The minimum role is
`platform_admin`. Learners, anonymous clients and staff without that role
cannot register or update hubs. Direct inserts or updates on `platform.hubs`
remain denied.

## SECURITY DEFINER requirements

Every SECURITY DEFINER function must:

- set `search_path = ''`;
- fully qualify protected objects;
- derive identity from `auth.uid()`, except the documented anonymous public
  RPCs (`registered_hubs`, published curriculum, readiness diagnostics) which
  must not bind `auth.uid()` and must not create learner accounts;
- validate every browser-controlled input;
- expose the minimum capability;
- revoke default execution and re-grant only intended roles;
- have pgTAP coverage for permissions and identity boundaries.

## Service role

The service role is reserved for controlled backend operations. In 0.1.0 it can
record audit and operational-health events. It must never appear in hub or Admin
Portal browser configuration.

## Testing

RLS tests cover anonymous denial, learner isolation, ordinary-teacher denial,
explicit platform-admin access and absence of direct administrative mutation.
Any new protected table requires RLS and tests in the same migration/release.
