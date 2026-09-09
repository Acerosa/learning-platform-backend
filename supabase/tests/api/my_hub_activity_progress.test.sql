begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_function(
  'api',
  'my_hub_activity_progress',
  array['text'],
  'Phase 1A exposes api.my_hub_activity_progress(text)'
);

select ok(
  (
    select prosecdef
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'api'
      and pg_proc.proname = 'my_hub_activity_progress'
  ),
  'my_hub_activity_progress is SECURITY DEFINER'
);

select throws_ok(
  $$select * from api.my_hub_activity_progress('reporting-pilot-alpha')$$,
  '28000',
  'AUTH_REQUIRED',
  'signed-out callers cannot read hub progress'
);

-- Isolated hubs / course link for TEST-GROUP-A/B (t-level foundations course).
insert into platform.hubs (
  id, hub_code, hub_name, description, hub_version, platform_version,
  manifest_version, core_version, learner_api_version, submission_contract_version,
  repository_url, deployment_url, activity_types, evidence_capabilities,
  features, compatibility, status, active, manifest, manifest_sha256
) values
  (
    '35a10000-0000-4000-8000-000000000001',
    'reporting-pilot-alpha',
    'Reporting Pilot Alpha',
    'Synthetic hub for Phase 1A reporting API tests.',
    '0.1.0',
    '0.2.0',
    '1.0.0',
    '0.2.0',
    '0.1.0',
    '0.1.0',
    'https://example.invalid/reporting-pilot-alpha',
    'https://example.invalid/reporting-pilot-alpha/',
    array['retrieval-quiz'],
    array['question-level'],
    '{}'::jsonb,
    '{}'::jsonb,
    'testing',
    true,
    '{}'::jsonb,
    repeat('1', 64)
  ),
  (
    '35a10000-0000-4000-8000-000000000002',
    'reporting-pilot-beta',
    'Reporting Pilot Beta',
    'Synthetic second hub for Phase 1A reporting API tests.',
    '0.1.0',
    '0.2.0',
    '1.0.0',
    '0.2.0',
    '0.1.0',
    '0.1.0',
    'https://example.invalid/reporting-pilot-beta',
    'https://example.invalid/reporting-pilot-beta/',
    array['retrieval-quiz'],
    array['question-level'],
    '{}'::jsonb,
    '{}'::jsonb,
    'testing',
    true,
    '{}'::jsonb,
    repeat('2', 64)
  );

insert into platform.hub_course_links (hub_id, course_id, active)
select hub.id, learner_group.course_id, true
from platform.hubs as hub
cross join learning.groups as learner_group
where hub.hub_code in ('reporting-pilot-alpha', 'reporting-pilot-beta')
  and learner_group.id = '60000000-0000-4000-8000-000000000001'
on conflict do nothing;

insert into learning.groups (
  id,
  academic_year_id,
  course_id,
  code,
  name,
  active,
  year_group,
  registration_key,
  registration_open
)
select
  mapping.id,
  template.academic_year_id,
  template.course_id,
  mapping.code,
  mapping.name,
  true,
  'Year 1',
  mapping.registration_key,
  false
from learning.groups as template
cross join (
  values
    (
      '60000000-0000-4000-8000-00000000a001'::uuid,
      'REPORT-ALPHA-A',
      'Reporting Alpha Group A',
      'reporting-alpha-a'
    ),
    (
      '60000000-0000-4000-8000-00000000a002'::uuid,
      'REPORT-ALPHA-B',
      'Reporting Alpha Group B',
      'reporting-alpha-b'
    ),
    (
      '60000000-0000-4000-8000-00000000b001'::uuid,
      'REPORT-BETA-G',
      'Reporting Beta Isolation Group',
      'reporting-beta-g'
    )
) as mapping(id, code, name, registration_key)
where template.id = '60000000-0000-4000-8000-000000000001';

insert into learning.enrolments (
  id, student_id, group_id, joined_on, status
) values
  (
    '70000000-0000-4000-8000-00000000a001',
    '30000000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-00000000a001',
    '2026-09-01',
    'active'
  ),
  (
    '70000000-0000-4000-8000-00000000a002',
    '30000000-0000-4000-8000-000000000002',
    '60000000-0000-4000-8000-00000000a002',
    '2026-09-01',
    'active'
  ),
  (
    '70000000-0000-4000-8000-00000000b001',
    '30000000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-00000000b001',
    '2026-09-01',
    'active'
  );

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
values
  (
    '35a10000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-00000000a001',
    true,
    'closed'
  ),
  (
    '35a10000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-00000000a002',
    true,
    'closed'
  ),
  (
    '35a10000-0000-4000-8000-000000000002',
    '60000000-0000-4000-8000-00000000b001',
    true,
    'closed'
  );

insert into learning.curriculum_weeks (
  id, module_id, stable_key, title, week_number, sort_order, active
) values (
  '35b10000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'reporting-week-2',
  'Reporting Week 2',
  2,
  90,
  true
);

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path
) values
  (
    '35c10000-0000-4000-8000-000000000001',
    '80000000-0000-4000-8000-000000000001',
    'reporting-alpha-multi',
    'Reporting Alpha Multi Attempt',
    'retrieval-quiz',
    'tests/reporting-alpha-multi.html'
  ),
  (
    '35c10000-0000-4000-8000-000000000002',
    '80000000-0000-4000-8000-000000000001',
    'reporting-alpha-outstanding',
    'Reporting Alpha Outstanding',
    'retrieval-quiz',
    'tests/reporting-alpha-outstanding.html'
  ),
  (
    '35c10000-0000-4000-8000-000000000003',
    '80000000-0000-4000-8000-000000000001',
    'reporting-beta-only',
    'Reporting Beta Only',
    'retrieval-quiz',
    'tests/reporting-beta-only.html'
  );

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count
) values
  (
    '35d10000-0000-4000-8000-000000000001',
    '35c10000-0000-4000-8000-000000000001',
    '1.0.0',
    repeat('a', 64),
    8,
    1
  ),
  (
    '35d10000-0000-4000-8000-000000000002',
    '35c10000-0000-4000-8000-000000000002',
    '1.0.0',
    repeat('b', 64),
    10,
    1
  ),
  (
    '35d10000-0000-4000-8000-000000000003',
    '35c10000-0000-4000-8000-000000000003',
    '1.0.0',
    repeat('c', 64),
    5,
    1
  ),
  (
    '35d10000-0000-4000-8000-000000000011',
    '35c10000-0000-4000-8000-000000000001',
    '2.0.0',
    repeat('d', 64),
    8,
    1
  );

insert into learning.activity_delivery (
  id,
  activity_version_id,
  academic_year_id,
  group_id,
  curriculum_week_id,
  week_number,
  session_number,
  sort_order,
  active
) values (
  '35e10000-0000-4000-8000-000000000001',
  '35d10000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-00000000a001',
  '35b10000-0000-4000-8000-000000000001',
  2,
  1,
  1,
  true
);

insert into learning.activity_assignments (
  id, group_id, activity_version_id, opens_at, due_at, required, active
) values
  (
    '35f10000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-00000000a001',
    '35d10000-0000-4000-8000-000000000001',
    null,
    null,
    true,
    true
  ),
  (
    '35f10000-0000-4000-8000-000000000002',
    '60000000-0000-4000-8000-00000000a001',
    '35d10000-0000-4000-8000-000000000002',
    null,
    null,
    true,
    true
  ),
  (
    '35f10000-0000-4000-8000-000000000003',
    '60000000-0000-4000-8000-00000000b001',
    '35d10000-0000-4000-8000-000000000003',
    null,
    null,
    true,
    true
  ),
  (
    '35f10000-0000-4000-8000-000000000004',
    '60000000-0000-4000-8000-00000000a002',
    '35d10000-0000-4000-8000-000000000001',
    null,
    null,
    true,
    true
  );

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score
) values (
  '35110000-0000-4000-8000-000000000001',
  '35d10000-0000-4000-8000-000000000001',
  'REPORT-Q1',
  'main',
  'Main',
  'single',
  'Reporting question',
  1,
  8
);

update learning.activity_versions
set published_at = clock_timestamp()
where id in (
  '35d10000-0000-4000-8000-000000000001',
  '35d10000-0000-4000-8000-000000000002',
  '35d10000-0000-4000-8000-000000000003',
  '35d10000-0000-4000-8000-000000000011'
);

-- Learner A: two completed attempts (first 4/8, latest 7/8), one started, one abandoned.
insert into learning.attempts (
  id, client_attempt_id, student_id, enrolment_id, assignment_id,
  activity_version_id, attempt_number, status, score, max_score,
  marking_source, evidence_level, submission_hash, received_at, completed_at
) values
  (
    '35210000-0000-4000-8000-000000000001',
    'reporting-a-first',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-00000000a001',
    '35f10000-0000-4000-8000-000000000001',
    '35d10000-0000-4000-8000-000000000001',
    1,
    'completed',
    4,
    8,
    'server',
    'summary_only',
    repeat('e', 64),
    timestamptz '2026-09-01 09:00:00+00',
    timestamptz '2026-09-01 09:05:00+00'
  ),
  (
    '35210000-0000-4000-8000-000000000002',
    'reporting-a-latest',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-00000000a001',
    '35f10000-0000-4000-8000-000000000001',
    '35d10000-0000-4000-8000-000000000001',
    2,
    'completed',
    7,
    8,
    'server',
    'summary_only',
    repeat('f', 64),
    timestamptz '2026-09-02 09:00:00+00',
    timestamptz '2026-09-02 09:05:00+00'
  ),
  (
    '35210000-0000-4000-8000-000000000003',
    'reporting-a-started',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-00000000a001',
    '35f10000-0000-4000-8000-000000000001',
    '35d10000-0000-4000-8000-000000000001',
    3,
    'started',
    0,
    8,
    'server',
    'summary_only',
    repeat('0', 64),
    timestamptz '2026-09-03 09:00:00+00',
    timestamptz '2026-09-03 09:00:00+00'
  ),
  (
    '35210000-0000-4000-8000-000000000004',
    'reporting-a-beta',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-00000000b001',
    '35f10000-0000-4000-8000-000000000003',
    '35d10000-0000-4000-8000-000000000003',
    1,
    'completed',
    5,
    5,
    'server',
    'summary_only',
    repeat('7', 64),
    timestamptz '2026-09-02 10:00:00+00',
    timestamptz '2026-09-02 10:05:00+00'
  );

-- Learner B on the shared alpha activity: must not leak to Learner A.
insert into learning.attempts (
  id, client_attempt_id, student_id, enrolment_id, assignment_id,
  activity_version_id, attempt_number, status, score, max_score,
  marking_source, evidence_level, submission_hash, received_at, completed_at
) values (
  '35210000-0000-4000-8000-000000000011',
  'reporting-b-secret',
  '30000000-0000-4000-8000-000000000002',
  '70000000-0000-4000-8000-00000000a002',
  '35f10000-0000-4000-8000-000000000004',
  '35d10000-0000-4000-8000-000000000001',
  1,
  'completed',
  1,
  8,
  'server',
  'summary_only',
  repeat('8', 64),
  timestamptz '2026-09-02 11:00:00+00',
  timestamptz '2026-09-02 11:05:00+00'
);

-- Formative check and draft must not affect attempt metrics.
insert into learning.formative_checks (
  client_check_id,
  student_id,
  assignment_id,
  activity_version_id,
  question_id,
  check_number,
  response_type,
  response_payload,
  awarded_score,
  max_score,
  is_correct,
  requires_review,
  marking_source,
  request_hash,
  source_page
) values (
  'reporting-formative-1',
  '30000000-0000-4000-8000-000000000001',
  '35f10000-0000-4000-8000-000000000001',
  '35d10000-0000-4000-8000-000000000001',
  '35110000-0000-4000-8000-000000000001',
  1,
  'single-choice',
  '{"optionId":"x"}'::jsonb,
  8,
  8,
  true,
  false,
  'server',
  repeat('9', 64),
  '/reporting/'
);

insert into learning.activity_states (
  student_id,
  assignment_id,
  activity_version_id,
  state_payload,
  status
) values (
  '30000000-0000-4000-8000-000000000001',
  '35f10000-0000-4000-8000-000000000001',
  '35d10000-0000-4000-8000-000000000001',
  '{"responses":{"REPORT-Q1":"draft-only"}}'::jsonb,
  'in_progress'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select * from api.my_hub_activity_progress('Not A Hub')$$,
  '22023',
  'INVALID_HUB_CODE',
  'invalid hub codes are rejected'
);

select throws_ok(
  $$select * from api.my_hub_activity_progress('missing-hub-code')$$,
  '22023',
  'HUB_UNKNOWN',
  'unknown hubs are rejected'
);

select is(
  (
    select count(*)
    from api.my_hub_activity_progress('reporting-pilot-alpha')
  ),
  2::bigint,
  'Learner A alpha hub returns only alpha-bound assignments for their enrolment'
);

select is(
  (
    select count(*)
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-beta-only'
  ),
  0::bigint,
  'beta-only assignments do not leak into the alpha hub response'
);

select is(
  (
    select attempt_count
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  2::bigint,
  'only completed attempts are counted'
);

select is(
  (
    select first_score
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  4::numeric,
  'first_score uses earliest completed attempt by received_at'
);

select is(
  (
    select latest_score
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  7::numeric,
  'latest_score uses latest completed attempt by received_at'
);

select is(
  (
    select best_score
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  7::numeric,
  'best_score is the highest completed score'
);

select is(
  (
    select improvement
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  3::numeric,
  'improvement is latest_score - first_score'
);

select is(
  (
    select first_percentage
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  50.00,
  'first_percentage normalises first attempt by its max_score'
);

select is(
  (
    select latest_percentage
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  87.50,
  'latest_percentage normalises latest attempt by its max_score'
);

select is(
  (
    select improvement_percentage_points
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  37.50,
  'improvement_percentage_points is latest_percentage - first_percentage'
);

select is(
  (
    select completed
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  true,
  'activities with completed attempts are marked completed'
);

select is(
  (
    select attempt_count
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-outstanding'
  ),
  0::bigint,
  'assigned activities with no completed attempts return zero progress'
);

select is(
  (
    select completed
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-outstanding'
  ),
  false,
  'outstanding assigned activities are not marked completed'
);

select is(
  (
    select week_key
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  'reporting-week-2',
  'week_key comes from linked curriculum_weeks when delivery is available'
);

select is(
  (
    select session_number
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  1,
  'session_number comes from activity_delivery when available'
);

select is(
  (
    select week_key
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-outstanding'
  ),
  null,
  'missing delivery context returns null week_key rather than guessing'
);

select is(
  (
    select count(*)
    from api.my_hub_activity_progress('reporting-pilot-beta')
  ),
  1::bigint,
  'Learner A beta hub returns only beta-bound assignments'
);

select is(
  (
    select activity_key
    from api.my_hub_activity_progress('reporting-pilot-beta')
  ),
  'reporting-beta-only',
  'beta hub progress is isolated from alpha activities'
);

select is(
  (
    select latest_score
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  7::numeric,
  'Learner A does not see Learner B score of 1 on the shared activity'
);

select is(
  (
    select count(*) = 0
    from information_schema.columns
    where table_schema = 'api'
      and table_name = 'my_hub_activity_progress'
  ),
  true,
  'my_hub_activity_progress is a function, not a view exposing columns'
);

reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*)
    from api.my_hub_activity_progress('reporting-pilot-alpha')
  ),
  1::bigint,
  'Learner B receives only their alpha-bound assignment'
);

select is(
  (
    select latest_score
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where activity_key = 'reporting-alpha-multi'
  ),
  1::numeric,
  'Learner B sees only their own completed score'
);

select is(
  (
    select count(*)
    from api.my_hub_activity_progress('reporting-pilot-alpha')
    where latest_score = 7
  ),
  0::bigint,
  'Learner B cannot observe Learner A scores'
);

select is(
  (
    select count(*)
    from api.my_hub_activity_progress('reporting-pilot-beta')
  ),
  0::bigint,
  'Learner B has no beta-bound enrolment and receives an empty set'
);

reset role;

select throws_ok(
  $$select api.my_hub_activity_progress(
      'reporting-pilot-alpha',
      '30000000-0000-4000-8000-000000000001'
    )$$,
  '42883',
  null,
  'fabricated learner identity cannot be supplied as an argument'
);

select * from finish();
rollback;
