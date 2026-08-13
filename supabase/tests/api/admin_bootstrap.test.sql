begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_table(
  'platform',
  'admin_bootstrap_credentials',
  'the bootstrap credential is stored in a protected platform table'
);

select has_function(
  'admin_api',
  'claim_initial_platform_admin',
  array['text'],
  'the admin API exposes the narrow bootstrap claim RPC'
);

select has_function(
  'admin_api',
  'publish_curriculum',
  array['text', 'text', 'text', 'text', 'text', 'text', 'jsonb', 'text', 'text', 'text'],
  'the admin API exposes the curriculum publication RPC'
);

select ok(
  (
    select relation.relrowsecurity
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'platform'
      and relation.relname = 'admin_bootstrap_credentials'
  ),
  'the bootstrap credential table has RLS enabled'
);

select ok(
  (
    select credential.token_hash
      <> '7e33adc820a85ed2d28acc86bce70b82dcca7eca19836fc1b6b99e84d88ec4b9'
    from platform.admin_bootstrap_credentials as credential
    where credential.bootstrap_key = 'initial-platform-admin'
  ),
  'the previously exposed bootstrap credential is invalid after rotation'
);

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
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '22000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'bootstrap.unconfirmed@local.invalid',
    null,
    null,
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"synthetic":true,"fixture":"bootstrap-unconfirmed"}'::jsonb,
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '22000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'bootstrap.initial@local.invalid',
    null,
    clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"synthetic":true,"fixture":"bootstrap-initial"}'::jsonb,
    clock_timestamp(),
    clock_timestamp()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '22000000-0000-4000-8000-000000000003',
    'authenticated',
    'authenticated',
    'bootstrap.second@local.invalid',
    null,
    clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"synthetic":true,"fixture":"bootstrap-second"}'::jsonb,
    clock_timestamp(),
    clock_timestamp()
  );

set local role anon;
select throws_like(
  $$select * from admin_api.claim_initial_platform_admin(repeat('a', 64))$$,
  '%permission denied%',
  'anonymous users cannot invoke the bootstrap claim'
);
reset role;

set local "request.jwt.claim.sub" = '22000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"22000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from admin_api.claim_initial_platform_admin(repeat('a', 64))$$,
  '28000',
  'EMAIL_CONFIRMATION_REQUIRED',
  'the bootstrap requires a confirmed Auth identity'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from admin_api.claim_initial_platform_admin(repeat('0', 64))$$,
  '28000',
  'BOOTSTRAP_NOT_AUTHORISED',
  'an ordinary staff account cannot escalate without the bootstrap credential'
);
reset role;

select is(
  (
    select count(*)
    from platform.staff_roles as staff_role
    join learning.teachers as teacher on teacher.id = staff_role.teacher_id
    where teacher.auth_user_id = '20000000-0000-4000-8000-000000000002'
      and staff_role.role = 'platform_admin'
      and staff_role.revoked_at is null
  ),
  0::bigint,
  'a rejected caller receives no platform administrator grant'
);

update platform.staff_roles
set revoked_at = clock_timestamp()
where role = 'platform_admin'
  and revoked_at is null;

update platform.admin_bootstrap_credentials
set
  token_hash = encode(extensions.digest(repeat('a', 64), 'sha256'), 'hex'),
  expires_at = clock_timestamp() + interval '1 hour',
  consumed_at = null,
  consumed_by_auth_user_id = null
where bootstrap_key = 'initial-platform-admin';

set local "request.jwt.claim.sub" = '22000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"22000000-0000-4000-8000-000000000002","role":"authenticated","email":"untrusted@example.invalid"}';
set local role authenticated;
select is(
  (
    select idempotent
    from admin_api.claim_initial_platform_admin(repeat('a', 64))
  ),
  false,
  'the valid first claim provisions the initial administrator'
);
reset role;

select is(
  (
    select teacher.auth_user_id
    from learning.teachers as teacher
    join platform.staff_roles as staff_role on staff_role.teacher_id = teacher.id
    where staff_role.role = 'platform_admin'
      and staff_role.revoked_at is null
  ),
  '22000000-0000-4000-8000-000000000002'::uuid,
  'the provisioned staff identity comes from auth.uid()'
);

select is(
  (
    select count(*)
    from platform.staff_roles as staff_role
    join learning.teachers as teacher on teacher.id = staff_role.teacher_id
    where teacher.auth_user_id = '22000000-0000-4000-8000-000000000002'
      and staff_role.role = 'platform_admin'
      and staff_role.revoked_at is null
  ),
  1::bigint,
  'the first claim creates exactly one active platform administrator grant'
);

select is(
  (
    select count(*)
    from platform.audit_events
    where event_key = 'staff.bootstrap.platform-admin'
      and actor_auth_user_id = '22000000-0000-4000-8000-000000000002'
      and outcome = 'succeeded'
  ),
  1::bigint,
  'the successful bootstrap claim is audited'
);

set local "request.jwt.claim.sub" = '22000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"22000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from admin_api.claim_initial_platform_admin(repeat('a', 64))$$,
  '28000',
  'BOOTSTRAP_UNAVAILABLE',
  'the successful caller cannot reuse the consumed credential'
);
reset role;

select is(
  (
    select count(*)
    from platform.staff_roles as staff_role
    join learning.teachers as teacher on teacher.id = staff_role.teacher_id
    where teacher.auth_user_id = '22000000-0000-4000-8000-000000000002'
      and staff_role.role = 'platform_admin'
      and staff_role.revoked_at is null
  ),
  1::bigint,
  'a retry cannot create a duplicate active platform administrator grant'
);

set local "request.jwt.claim.sub" = '22000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"22000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from admin_api.claim_initial_platform_admin(repeat('a', 64))$$,
  '28000',
  'BOOTSTRAP_UNAVAILABLE',
  'the consumed bootstrap cannot elevate another account'
);
reset role;

select is(
  (
    select count(*)
    from platform.audit_events
    where event_key = 'staff.bootstrap.platform-admin'
      and outcome = 'succeeded'
  ),
  1::bigint,
  'only one successful bootstrap audit event exists'
);

select * from finish();
rollback;
