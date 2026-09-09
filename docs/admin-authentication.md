# Admin authentication and first-administrator bootstrap

Authentication is Supabase Auth. Authorisation is Postgres.

```text
auth.uid()
  → learning.teachers.auth_user_id (active)
  → platform.staff_roles.role = platform_admin (revoked_at is null)
  → admin_api views and SECURITY DEFINER RPCs
```

`admin_api.current_staff_context` is the browser-safe projection of that
path. It does not accept an identity or role argument.

## First administrator

Do not use a public `/setup-admin` route, a magic bootstrap URL, a
hard-coded email in the Admin Portal, or “first registrant becomes admin”.

1. Create the Auth user in the Supabase Dashboard (email, temporary
   password, confirmed email as required).
2. Copy `auth.users.id`.
3. Insert `learning.teachers` for that `auth_user_id`.
4. Insert `platform.staff_roles` with `role = 'platform_admin'`.
5. Sign into the Admin Portal with email and password.
6. Confirm `admin_api.current_staff_context.active_roles` includes
   `platform_admin`.
7. Confirm a learner JWT cannot select Admin views.

Idempotent SQL:

```sql
insert into learning.teachers (
  auth_user_id,
  staff_reference,
  display_name,
  active
)
select
  auth_user.id,
  'PLATFORM-ADMIN',
  'Platform Administrator',
  true
from auth.users as auth_user
where auth_user.id = '<AUTH_USER_UUID>'
  and not exists (
    select 1
    from learning.teachers as teacher
    where teacher.auth_user_id = auth_user.id
  );

insert into platform.staff_roles (
  teacher_id,
  role
)
select
  teacher.id,
  'platform_admin'
from learning.teachers as teacher
where teacher.auth_user_id = '<AUTH_USER_UUID>'
  and not exists (
    select 1
    from platform.staff_roles as staff_role
    where staff_role.teacher_id = teacher.id
      and staff_role.role = 'platform_admin'
      and staff_role.revoked_at is null
  );
```

The hosted project already has an active `platform_admin` staff row from the
original `admin_api.claim_initial_platform_admin` claim. That credential is
consumed. Do not rotate or reuse it for later staff.

## Subsequent administrators

There is no Admin Portal mutation that creates Auth users or grants
`platform_admin`. Repeat the Dashboard + SQL procedure above. Direct
`INSERT` from `anon` or `authenticated` is revoked. RLS remains enabled.

A future `admin_api` staff-invite RPC must itself require
`platform.current_staff_has_role('platform_admin')`.

## Password reset

Password reset is owned by Supabase Auth (`resetPasswordForEmail` /
recovery session / `updateUser`). It does not write `learning` or
`platform` tables and does not grant roles.
