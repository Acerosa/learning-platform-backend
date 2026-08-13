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

`platform.curriculum_publications` is readable by authorised staff roles.
Inserts occur only through `admin_api.publish_curriculum`. Published rows are
immutable except for the controlled supersede transition.

## SECURITY DEFINER requirements

Every SECURITY DEFINER function must:

- set `search_path = ''`;
- fully qualify protected objects;
- derive identity from `auth.uid()`;
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
