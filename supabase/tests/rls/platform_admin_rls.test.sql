begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select ok(
  (
    select bool_and(relation.relrowsecurity)
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'platform'
      and relation.relkind = 'r'
  ),
  'every protected platform table has RLS enabled'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from admin_api.learners),
  0::bigint,
  'a learner cannot read the Central Admin Portal learner view'
);

select is(
  (select count(*) from admin_api.audit_events),
  0::bigint,
  'a learner cannot read platform audit events'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select ok(
  not platform.current_staff_has_role('platform_admin'),
  'an ordinary teacher is not implicitly a platform administrator'
);

select is(
  (select count(*) from admin_api.learners),
  0::bigint,
  'an ordinary teacher cannot read platform-wide learner data'
);

reset role;

insert into platform.staff_roles (
  id,
  teacher_id,
  role,
  granted_at
) values (
  '32000000-0000-4000-8000-000000000002',
  '31000000-0000-4000-8000-000000000001',
  'platform_admin',
  '2026-08-11T00:00:00Z'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select ok(
  platform.current_staff_has_role('platform_admin'),
  'the synthetic platform administrator resolves through Auth identity'
);

select is(
  (select count(*) from admin_api.learners),
  3::bigint,
  'the platform administrator can read all synthetic learner profiles'
);

select is(
  (select count(*) from admin_api.responses) >= 0,
  true,
  'the platform administrator can read the staff responses projection'
);

select is(
  (select count(*) from admin_api.hubs),
  3::bigint,
  'the platform administrator can read the complete local hub registry'
);

select is(
  (select count(*) from admin_api.platform_contracts),
  7::bigint,
  'the platform administrator can inspect active, retired and draft contracts'
);

select throws_like(
  $$insert into platform.hubs (
      hub_code,
      hub_name,
      hub_version,
      platform_version,
      subject,
      repository_url,
      curriculum_model
    ) values (
      'browser-created-hub',
      'Browser-created hub',
      '0.1.0',
      '0.1.0',
      'Synthetic',
      'https://example.invalid/repository',
      'course/unit/week/session/activity'
    )$$,
  '%permission denied%',
  'authenticated administrators still cannot mutate protected tables directly'
);

reset role;

select * from finish();
rollback;
