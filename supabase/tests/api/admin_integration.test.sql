begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_view(
  'admin_api',
  'current_staff_context',
  'the admin API exposes a current-staff session projection'
);

select has_view(
  'admin_api',
  'dashboard_summary',
  'the admin API exposes a dashboard aggregate'
);

select has_view(
  'admin_api',
  'activity_performance',
  'the admin API exposes activity performance aggregates'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from admin_api.current_staff_context),
  0::bigint,
  'a learner session has no staff context'
);

select is(
  (select count(*) from admin_api.dashboard_summary),
  0::bigint,
  'a learner session cannot read dashboard aggregates'
);

select is(
  (select count(*) from admin_api.activity_performance),
  0::bigint,
  'a learner session cannot read analytics aggregates'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (select active_roles from admin_api.current_staff_context),
  '{}'::text[],
  'an ordinary teacher receives an active profile with no platform roles'
);

select is(
  (select count(*) from admin_api.dashboard_summary),
  0::bigint,
  'an ordinary teacher cannot read platform dashboard aggregates'
);

reset role;

update learning.teachers
set active = false
where auth_user_id = '20000000-0000-4000-8000-000000000002';

set local role authenticated;

select is(
  (select count(*) from admin_api.current_staff_context),
  0::bigint,
  'an inactive teacher has no current staff context'
);

reset role;

update learning.teachers
set active = true
where auth_user_id = '20000000-0000-4000-8000-000000000002';

insert into learning.attempts (
  id,
  client_attempt_id,
  student_id,
  enrolment_id,
  assignment_id,
  activity_version_id,
  attempt_number,
  status,
  score,
  max_score,
  marking_source,
  evidence_level,
  submission_hash,
  received_at,
  completed_at
) values (
  '93000000-0000-4000-8000-000000000001',
  'phase-2-admin-integration',
  '30000000-0000-4000-8000-000000000001',
  '70000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000001',
  1,
  'completed',
  1,
  1,
  'server',
  'summary_only',
  repeat('a', 64),
  clock_timestamp(),
  clock_timestamp()
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (select display_name from admin_api.current_staff_context),
  'Synthetic Platform Administrator',
  'the local platform administrator resolves through the current session view'
);

select ok(
  (select active_roles from admin_api.current_staff_context)
    @> array['platform_admin']::text[],
  'platform administrator authority is backend-derived'
);

select is(
  (select registered_hubs from admin_api.dashboard_summary),
  3::bigint,
  'dashboard hub count is backend-derived'
);

select is(
  (select active_learners from admin_api.dashboard_summary),
  3::bigint,
  'dashboard learner count is backend-derived'
);

select is(
  (select recent_attempts from admin_api.dashboard_summary),
  2::bigint,
  'dashboard recent-attempt count is backend-derived'
);

select is(
  (select group_code from admin_api.attempts where attempt_id = '93000000-0000-4000-8000-000000000003'),
  'DEMO-GROUP',
  'the seeded demonstration attempt is available to the platform administrator'
);

select is(
  (select group_codes from admin_api.learners where student_number = 'SYNTH-0001'),
  array['TEST-GROUP-A']::text[],
  'the minimised learner list includes active group context'
);

select is(
  (select active_learner_count from admin_api.groups where group_code = 'TEST-GROUP-A'),
  1::bigint,
  'the group list exposes a backend-derived active learner count'
);

select is(
  (select group_code from admin_api.attempts where attempt_id = '93000000-0000-4000-8000-000000000001'),
  'TEST-GROUP-A',
  'the attempt summary includes safe group context'
);

select is(
  (select completed_attempts from admin_api.activity_performance where group_code = 'TEST-GROUP-A'),
  1::bigint,
  'activity analytics are aggregated in the backend'
);

reset role;

select * from finish();
rollback;
