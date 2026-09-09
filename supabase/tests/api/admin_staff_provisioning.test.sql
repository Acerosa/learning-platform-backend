begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '23000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'provision.admin@local.invalid',
  null,
  clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"synthetic":true,"fixture":"provision-admin"}'::jsonb,
  clock_timestamp(),
  clock_timestamp()
);

set local role anon;
select throws_like(
  $$insert into learning.teachers (auth_user_id, staff_reference, display_name, active)
    values ('23000000-0000-4000-8000-000000000001', 'PROVISION-ADMIN', 'Provisioned Admin', true)$$,
  '%permission denied%',
  'anonymous users cannot create staff profiles'
);
select throws_like(
  $$insert into platform.staff_roles (teacher_id, role)
    values ('31000000-0000-4000-8000-000000000001', 'platform_admin')$$,
  '%permission denied%',
  'anonymous users cannot grant platform administrator roles'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_like(
  $$insert into learning.teachers (auth_user_id, staff_reference, display_name, active)
    values ('23000000-0000-4000-8000-000000000001', 'PROVISION-ADMIN', 'Provisioned Admin', true)$$,
  '%permission denied%',
  'an authenticated learner cannot create a staff profile'
);
select throws_like(
  $$insert into platform.staff_roles (teacher_id, role)
    values ('31000000-0000-4000-8000-000000000001', 'platform_admin')$$,
  '%permission denied%',
  'an authenticated learner cannot grant platform administrator roles'
);
select throws_ok(
  $$select * from admin_api.claim_initial_platform_admin(repeat('a', 64))$$,
  '28000',
  'BOOTSTRAP_NOT_AUTHORISED',
  'an ordinary authenticated user cannot publicly invoke first-admin bootstrap'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select throws_like(
  $$insert into platform.staff_roles (teacher_id, role)
    values ('31000000-0000-4000-8000-000000000002', 'platform_admin')$$,
  '%permission denied%',
  'authenticated non-admin staff cannot self-promote to platform_admin'
);
reset role;

-- Controlled first-admin SQL, executed only with a privileged database role.
insert into learning.teachers (
  auth_user_id,
  staff_reference,
  display_name,
  active
)
select
  auth_user.id,
  'PROVISION-ADMIN',
  'Provisioned Administrator',
  true
from auth.users as auth_user
where auth_user.id = '23000000-0000-4000-8000-000000000001'
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
where teacher.auth_user_id = '23000000-0000-4000-8000-000000000001'
  and not exists (
    select 1
    from platform.staff_roles as staff_role
    where staff_role.teacher_id = teacher.id
      and staff_role.role = 'platform_admin'
      and staff_role.revoked_at is null
  );

-- Re-run the same controlled SQL; it must stay idempotent.
insert into learning.teachers (
  auth_user_id,
  staff_reference,
  display_name,
  active
)
select
  auth_user.id,
  'PROVISION-ADMIN',
  'Provisioned Administrator',
  true
from auth.users as auth_user
where auth_user.id = '23000000-0000-4000-8000-000000000001'
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
where teacher.auth_user_id = '23000000-0000-4000-8000-000000000001'
  and not exists (
    select 1
    from platform.staff_roles as staff_role
    where staff_role.teacher_id = teacher.id
      and staff_role.role = 'platform_admin'
      and staff_role.revoked_at is null
  );

select is(
  (
    select count(*)
    from learning.teachers as teacher
    where teacher.auth_user_id = '23000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'controlled first-admin SQL creates exactly one staff profile'
);

select is(
  (
    select count(*)
    from platform.staff_roles as staff_role
    join learning.teachers as teacher on teacher.id = staff_role.teacher_id
    where teacher.auth_user_id = '23000000-0000-4000-8000-000000000001'
      and staff_role.role = 'platform_admin'
      and staff_role.revoked_at is null
  ),
  1::bigint,
  're-running controlled first-admin SQL does not duplicate platform_admin'
);

select ok(
  (
    select teacher.active
    from learning.teachers as teacher
    where teacher.auth_user_id = '23000000-0000-4000-8000-000000000001'
  ),
  'the provisioned administrator is an active learning.teachers row'
);

select * from finish();
rollback;
