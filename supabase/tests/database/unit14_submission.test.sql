begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

create schema unit14_tests;

create function unit14_tests.baseline_payload()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_array(
    jsonb_build_object(
      'question_id', 'u14-w1-base-q1',
      'response_type', 'single-choice',
      'response_payload', jsonb_build_object('optionId', 'a')
    ),
    jsonb_build_object(
      'question_id', 'u14-w1-base-q2',
      'response_type', 'single-choice',
      'response_payload', jsonb_build_object('optionId', 'c')
    ),
    jsonb_build_object(
      'question_id', 'u14-w1-base-q3',
      'response_type', 'single-choice',
      'response_payload', jsonb_build_object('optionId', 'a')
    ),
    jsonb_build_object(
      'question_id', 'u14-w1-base-q4',
      'response_type', 'written',
      'response_payload', jsonb_build_object('text', 'No previous programming')
    )
  );
$$;

create function unit14_tests.cheated_baseline_payload()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_array(
    jsonb_build_object(
      'question_id', 'u14-w1-base-q1',
      'response_type', 'single-choice',
      'response_payload', jsonb_build_object('optionId', 'z'),
      'awarded_score', 1,
      'is_correct', true
    ),
    jsonb_build_object(
      'question_id', 'u14-w1-base-q2',
      'response_type', 'single-choice',
      'response_payload', jsonb_build_object('selectedOptionId', 'z'),
      'awarded_score', 1,
      'is_correct', true
    ),
    jsonb_build_object(
      'question_id', 'u14-w1-base-q3',
      'response_type', 'single-choice',
      'response_payload', jsonb_build_object('optionId', 'z'),
      'awarded_score', 1,
      'is_correct', true
    ),
    jsonb_build_object(
      'question_id', 'u14-w1-base-q4',
      'response_type', 'written',
      'response_payload', jsonb_build_object('text', 'Claiming full marks')
    )
  );
$$;

create function unit14_tests.reflection_payload()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_array(
    jsonb_build_object(
      'question_id', 'u14-w1-a1-notes',
      'response_type', 'reflection',
      'response_payload', jsonb_build_object('text', 'A variable stores a changing business value.')
    )
  );
$$;

grant usage on schema unit14_tests to authenticated, anon;
grant execute on function unit14_tests.baseline_payload() to authenticated, anon;
grant execute on function unit14_tests.cheated_baseline_payload() to authenticated, anon;
grant execute on function unit14_tests.reflection_payload() to authenticated, anon;

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
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  fixture.id,
  'authenticated',
  'authenticated',
  fixture.email,
  null,
  clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('synthetic', true, 'fixture', fixture.fixture),
  clock_timestamp(),
  clock_timestamp()
from (
  values
    (
      '14000000-0000-4000-8000-000000000001'::uuid,
      'unit14.learner.one@local.invalid',
      'unit14-one'
    ),
    (
      '14000000-0000-4000-8000-000000000002'::uuid,
      'unit14.learner.two@local.invalid',
      'unit14-two'
    )
) as fixture(id, email, fixture);

insert into learning.students (
  id, auth_user_id, student_number, first_name, surname, display_name, active
) values
  (
    '34000000-0000-4000-8000-000000000001',
    '14000000-0000-4000-8000-000000000001',
    'U14-SYNTH-001',
    'Unit14',
    'Learner',
    'Unit 14 Synthetic Learner One',
    true
  ),
  (
    '34000000-0000-4000-8000-000000000002',
    '14000000-0000-4000-8000-000000000002',
    'U14-SYNTH-002',
    'Unit14',
    'Peer',
    'Unit 14 Synthetic Learner Two',
    true
  );

insert into learning.enrolments (student_id, group_id, joined_on, status)
select
  student.id,
  learner_group.id,
  '2026-09-01',
  'active'
from learning.students as student
join learning.groups as learner_group
  on learner_group.code = 'UNIT14-TEST-A'
where student.student_number in ('U14-SYNTH-001', 'U14-SYNTH-002');

select no_plan();

set local role anon;
select throws_like(
  $$select * from api.submit_attempt(
    'week-1-baseline-diagnostic',
    '0.1.0',
    'anon-unit14',
    unit14_tests.baseline_payload()
  )$$,
  '%permission denied%',
  'anonymous callers cannot submit Unit 14 attempts'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select * from api.submit_attempt(
    'week-1-baseline-diagnostic',
    '0.1.0',
    'student-a-unit14',
    unit14_tests.baseline_payload()
  )$$,
  '42501',
  'ACTIVITY_NOT_ASSIGNED',
  'a T Level learner cannot submit a Unit 14 activity'
);

select is(
  (select count(*) from api.my_assignments where activity_key like 'week-1-%'),
  0::bigint,
  'Student A does not see Unit 14 Week 1 assignments'
);

select throws_like(
  $$select count(*) from learning.question_marking$$,
  '%permission denied%',
  'learners cannot read protected question marking specifications'
);
reset role;

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*)::int from api.my_assignments),
  24,
  'the Unit 14 learner can see the 24 assigned Week 1 and Week 2 activities'
);

select ok(
  exists (
    select 1
    from api.curriculum_weeks
    where module_key = 'unit-14-software-engineering-for-business'
      and week_key = 'week-1'
  ),
  'authenticated learners can read Unit 14 week metadata through the learner API'
);

select lives_ok(
  $$
    select *
    from api.submit_attempt(
      'week-1-baseline-diagnostic',
      '0.1.0',
      'unit14-baseline-1',
      unit14_tests.baseline_payload(),
      '/weeks/week-1/'
    )
  $$,
  'evidence-only diagnostic submission is accepted'
);

select is(
  (
    select marking_source
    from api.my_attempts
    where client_attempt_id = 'unit14-baseline-1'
  ),
  'server',
  'diagnostic attempts are server-marked'
);

select is(
  (
    select score
    from api.my_attempts
    where client_attempt_id = 'unit14-baseline-1'
  ),
  2.00,
  'two correct single-choice items score 2; the incorrect item and written item are not awarded'
);

select is(
  (
    select count(*)::int
    from api.my_responses
    where attempt_id = (
      select attempt_id from api.my_attempts where client_attempt_id = 'unit14-baseline-1'
    )
  ),
  4,
  'all four diagnostic responses are stored'
);

select ok(
  exists (
    select 1
    from api.my_responses
    where attempt_id = (
      select attempt_id from api.my_attempts where client_attempt_id = 'unit14-baseline-1'
    )
      and question_key = 'u14-w1-base-q3'
      and is_correct = false
      and awarded_score = 0
  ),
  'an incorrect single-choice item is marked by the backend, not the browser'
);

select lives_ok(
  $$
    select *
    from api.submit_attempt(
      'week-1-baseline-diagnostic',
      '0.1.0',
      'unit14-baseline-cheat-1',
      unit14_tests.cheated_baseline_payload(),
      '/weeks/week-1/'
    )
  $$,
  'client-supplied full marks on a marked activity are accepted as evidence'
);

select is(
  (
    select score
    from api.my_attempts
    where client_attempt_id = 'unit14-baseline-cheat-1'
  ),
  0.00,
  'client-supplied scores cannot override protected question marking'
);

select is(
  (
    select marking_source
    from api.my_attempts
    where client_attempt_id = 'unit14-baseline-cheat-1'
  ),
  'server',
  'questions with marking specs are recorded as server-marked even when the client sends scores'
);

select ok(
  exists (
    select 1
    from api.my_responses
    where attempt_id = (
      select attempt_id from api.my_attempts where client_attempt_id = 'unit14-baseline-1'
    )
      and question_key = 'u14-w1-base-q4'
      and is_correct is null
      and awarded_score = 0
  ),
  'the written diagnostic item stays completion-only evidence'
);

select lives_ok(
  $$
    select *
    from api.submit_attempt(
      'week-1-assignment-1-guide',
      '0.1.0',
      'unit14-reflection-1',
      unit14_tests.reflection_payload(),
      '/weeks/week-1/'
    )
  $$,
  'reflection completion evidence is accepted'
);

select is(
  (
    select score
    from api.my_attempts
    where client_attempt_id = 'unit14-reflection-1'
  ),
  0.00,
  'reflection is stored as completion, not as an automated grade'
);

select ok(
  exists (
    select 1
    from api.my_activity_progress
    where activity_key = 'week-1-baseline-diagnostic'
      and attempt_count >= 1
  ),
  'diagnostic progress is visible through the learner API'
);

select is(
  (
    select idempotent
    from api.submit_attempt(
      'week-1-baseline-diagnostic',
      '0.1.0',
      'unit14-baseline-1',
      unit14_tests.baseline_payload(),
      '/weeks/week-1/'
    )
  ),
  true,
  'identical Unit 14 retries are idempotent'
);
reset role;

select ok(
  exists (
    select 1
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.questions as question on question.id = response.question_id
    where attempt.client_attempt_id = 'unit14-baseline-1'
      and question.stable_key = 'u14-w1-base-q4'
      and response.requires_review
      and response.is_correct is null
  ),
  'completion-only diagnostic evidence is flagged for review without a fake grade'
);

select ok(
  exists (
    select 1
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    where attempt.client_attempt_id = 'unit14-reflection-1'
      and response.requires_review
      and response.is_correct is null
      and response.marking_source = 'server'
  ),
  'reflection responses remain reviewable server evidence'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from api.my_attempts),
  0::bigint,
  'a peer in the same Unit 14 group cannot read another learner''s attempts'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select ok(
  exists (
    select 1
    from admin_api.hubs
    where hub_code = 'unit-14-software-engineering-for-business'
      and active
  ),
  'the Central Admin Portal hub view includes Unit 14'
);

select ok(
  exists (
    select 1
    from admin_api.hub_course_links
    where hub_code = 'unit-14-software-engineering-for-business'
      and course_key = 'ocr-level-3-it'
  ),
  'admin hub/course links include Unit 14'
);

select ok(
  exists (
    select 1
    from admin_api.assignments
    where activity_key = 'week-1-baseline-diagnostic'
  ),
  'admin assignment reads include Unit 14 Week 1 group delivery'
);

select ok(
  exists (
    select 1
    from admin_api.attempts
    where activity_key = 'week-1-baseline-diagnostic'
  ),
  'admin attempt reads include the Unit 14 diagnostic submission'
);

select ok(
  exists (
    select 1
    from admin_api.activity_performance
    where activity_key = 'week-1-baseline-diagnostic'
  ),
  'admin activity performance includes the Unit 14 diagnostic'
);
reset role;

select * from finish();
rollback;
