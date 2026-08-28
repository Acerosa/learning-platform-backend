begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_view(
  'admin_api',
  'recent_attempts',
  'admin_api exposes a bounded recent attempts dashboard view'
);

select ok(
  coalesce((
    select option_value = 'true'
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    join pg_options_to_table(relation.reloptions) as options on true
    where namespace.nspname = 'admin_api'
      and relation.relname = 'recent_attempts'
      and options.option_name = 'security_invoker'
  ), false),
  'recent_attempts uses invoker security'
);

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
) values
  (
    '93000000-0000-4000-8000-000000000101',
    'recent-attempts-test-1',
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
    repeat('1', 64),
    timestamptz '2026-08-01T10:00:00Z',
    timestamptz '2026-08-01T10:05:00Z'
  ),
  (
    '93000000-0000-4000-8000-000000000102',
    'recent-attempts-test-2',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    2,
    'completed',
    2,
    2,
    'server',
    'summary_only',
    repeat('2', 64),
    timestamptz '2026-08-02T10:00:00Z',
    timestamptz '2026-08-02T10:05:00Z'
  ),
  (
    '93000000-0000-4000-8000-000000000103',
    'recent-attempts-test-3',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    3,
    'completed',
    3,
    3,
    'server',
    'summary_only',
    repeat('3', 64),
    timestamptz '2026-08-03T10:00:00Z',
    timestamptz '2026-08-03T10:05:00Z'
  ),
  (
    '93000000-0000-4000-8000-000000000104',
    'recent-attempts-test-4',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    4,
    'completed',
    4,
    4,
    'server',
    'summary_only',
    repeat('4', 64),
    timestamptz '2026-08-04T10:00:00Z',
    timestamptz '2026-08-04T10:05:00Z'
  ),
  (
    '93000000-0000-4000-8000-000000000105',
    'recent-attempts-test-5',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    5,
    'completed',
    5,
    5,
    'server',
    'summary_only',
    repeat('5', 64),
    timestamptz '2026-08-05T10:00:00Z',
    timestamptz '2026-08-05T10:05:00Z'
  ),
  (
    '93000000-0000-4000-8000-000000000106',
    'recent-attempts-test-6',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    6,
    'completed',
    6,
    6,
    'server',
    'summary_only',
    repeat('6', 64),
    timestamptz '2026-08-06T10:00:00Z',
    timestamptz '2026-08-06T10:05:00Z'
  ),
  (
    '93000000-0000-4000-8000-000000000107',
    'recent-attempts-test-tie-a',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    7,
    'completed',
    7,
    7,
    'server',
    'summary_only',
    repeat('7', 64),
    timestamptz '2026-08-07T10:00:00Z',
    timestamptz '2026-08-07T12:00:00Z'
  ),
  (
    '93000000-0000-4000-8000-000000000108',
    'recent-attempts-test-tie-b',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    8,
    'completed',
    8,
    8,
    'server',
    'summary_only',
    repeat('8', 64),
    timestamptz '2026-08-07T11:00:00Z',
    timestamptz '2026-08-07T12:00:00Z'
  );

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select ok(
  (select count(*) from admin_api.recent_attempts) <= 5,
  'recent attempts are bounded to five rows'
);

select is(
  (select attempt_id from admin_api.recent_attempts order by completed_at desc, attempt_id desc limit 1),
  '93000000-0000-4000-8000-000000000108'::uuid,
  'recent attempts are ordered by completed_at then attempt_id descending'
);

select ok(
  not exists (
    select 1
    from admin_api.recent_attempts
    where attempt_id = '93000000-0000-4000-8000-000000000101'
  ),
  'older attempts fall outside the five-row dashboard window'
);

select ok(
  (
    select array_agg(column_name::text order by ordinal_position)
    from information_schema.columns
    where table_schema = 'admin_api'
      and table_name = 'recent_attempts'
  ) = array[
    'attempt_id',
    'student_number',
    'activity_key',
    'activity_version',
    'status',
    'score',
    'max_score',
    'completed_at'
  ]::text[],
  'recent attempts exposes only dashboard summary columns'
);

select ok(
  (select count(*) from admin_api.attempts where attempt_id = '93000000-0000-4000-8000-000000000101') = 1,
  'the full attempts admin view still includes older attempt history'
);

reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from admin_api.recent_attempts),
  0::bigint,
  'learners cannot read recent attempts through the admin API'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from admin_api.recent_attempts),
  0::bigint,
  'ordinary teachers cannot read recent attempts through the admin API'
);

reset role;

select * from finish();
rollback;
