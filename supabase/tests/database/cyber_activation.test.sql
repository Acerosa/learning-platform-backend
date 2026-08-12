begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

create schema cyber_activation_tests;

create function cyber_activation_tests.malware_payload(correct_count integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_agg(
    jsonb_build_object(
      'question_id', question.stable_key,
      'response_payload', to_jsonb(
        case
          when question.ordinal <= correct_count then 'synthetic-correct'
          else 'synthetic-review'
        end
      ),
      'awarded_score', case
        when question.ordinal <= correct_count then question.max_score
        else 0
      end,
      'is_correct', question.ordinal <= correct_count
    )
    order by question.ordinal
  )
  from learning.questions as question
  join learning.activity_versions as version
    on version.id = question.activity_version_id
  join learning.activities as activity
    on activity.id = version.activity_id
  where activity.stable_key = 'week2-malware-symptoms'
    and version.version = '1.0.0'
$$;

grant usage on schema cyber_activation_tests to authenticated, anon;
grant execute on function cyber_activation_tests.malware_payload(integer) to authenticated, anon;

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
      '12000000-0000-4000-8000-000000000001'::uuid,
      'cyber.activation.one@local.invalid',
      'cyber-activation-one'
    ),
    (
      '12000000-0000-4000-8000-000000000002'::uuid,
      'cyber.activation.two@local.invalid',
      'cyber-activation-two'
    )
) as fixture(id, email, fixture);

select no_plan();

select is(
  (
    select count(*)::int
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-3-cyber-security'
  ),
  76,
  'Cyber catalogue still contains exactly 76 activity versions'
);

select is(
  (
    select count(*)::int
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-3-cyber-security'
      and version.published_at is not null
      and version.retired_at is null
  ),
  68,
  'Weeks 2–7 Cyber activity versions are published (Week 1 remains unpublished)'
);

select is(
  (
    select count(*)::int
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-3-cyber-security'
      and activity.stable_key like 'u3-w01-%'
      and version.published_at is null
  ),
  8,
  'Week 1 Cyber versions stay unpublished for Apps Script markSection'
);

select is(
  (
    select count(*)::int
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    where learner_group.code = 'CYBER-TEST-A'
      and assignment.active
  ),
  68,
  'CYBER-TEST-A has 68 active Weeks 2–7 Cyber assignments'
);

select ok(
  exists (
    select 1
    from learning.groups as learner_group
    join learning.courses as course on course.id = learner_group.course_id
    where learner_group.code = 'CYBER-TEST-A'
      and course.stable_key = 'ocr-level-3-it'
      and learner_group.active
      and learner_group.registration_open
      and learner_group.registration_key = 'cyber-year-1-test'
      and learner_group.year_group = 'Year 1'
  ),
  'Cyber synthetic test group is active with open registration'
);

set local role anon;
select throws_like(
  $$select * from api.registration_options()$$,
  '%permission denied%',
  'anonymous callers cannot read Cyber registration options'
);
select throws_like(
  $$select * from api.complete_learner_onboarding(
    'Cyber', 'Learner', 'CYBER-001', 'cyber-year-1-test'
  )$$,
  '%permission denied%',
  'anonymous callers cannot complete Cyber onboarding'
);
select throws_like(
  $$select * from api.submit_attempt(
    'week2-malware-symptoms',
    '1.0.0',
    'anon-cyber-attempt',
    cyber_activation_tests.malware_payload(1)
  )$$,
  '%permission denied%',
  'anonymous callers cannot submit Cyber attempts'
);
reset role;

set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated","email":"cyber.activation.one@local.invalid"}';
set local role authenticated;

select ok(
  exists (
    select 1
    from api.registration_options()
    where registration_option = 'cyber-year-1-test'
      and course_key = 'ocr-level-3-it'
      and group_code = 'CYBER-TEST-A'
      and year_group = 'Year 1'
  ),
  'authenticated unlinked learners see the Cyber registration option'
);

select is(
  (
    select idempotent
    from api.complete_learner_onboarding(
      'Cyber',
      'Activation',
      'CYBER-ACT-001',
      'cyber-year-1-test'
    )
  ),
  false,
  'Cyber onboarding creates the learner profile and enrolment'
);

select ok(
  exists (
    select 1
    from api.my_enrolments
    where group_code = 'CYBER-TEST-A'
      and status = 'active'
      and course_title = 'OCR Level 3 IT'
  ),
  'Cyber onboarding yields an active OCR Level 3 IT enrolment'
);

select is(
  (select count(*)::int from api.my_assignments),
  68,
  'Cyber learner can see all 68 assigned Weeks 2–7 activities'
);

select lives_ok(
  $$
    select *
    from api.submit_attempt(
      'week2-malware-symptoms',
      '1.0.0',
      'cyber-activation-attempt-1',
      cyber_activation_tests.malware_payload(7),
      '/week-2/malware-symptoms/',
      null,
      null,
      null
    )
  $$,
  'representative Week 2 Cyber submission succeeds'
);

select is(
  (
    select attempt_number
    from api.my_attempts
    where client_attempt_id = 'cyber-activation-attempt-1'
  ),
  1,
  'Cyber submission derives attempt number 1 from the server'
);

select ok(
  (
    select score = 7
      and max_score = 10
      and activity_key = 'week2-malware-symptoms'
    from api.my_attempts
    where client_attempt_id = 'cyber-activation-attempt-1'
  ),
  'Cyber attempt stores bounded score and resolved activity key'
);

select is(
  (
    select count(*)::int
    from api.my_responses
    where attempt_id = (
      select attempt_id
      from api.my_attempts
      where client_attempt_id = 'cyber-activation-attempt-1'
    )
  ),
  10,
  'Cyber submission persists all malware question responses'
);

select ok(
  exists (
    select 1
    from api.my_activity_progress
    where activity_key = 'week2-malware-symptoms'
      and attempt_count >= 1
  ),
  'Cyber progress view reflects the submitted activity'
);

select is(
  (
    select idempotent
    from api.submit_attempt(
      'week2-malware-symptoms',
      '1.0.0',
      'cyber-activation-attempt-1',
      cyber_activation_tests.malware_payload(7),
      '/week-2/malware-symptoms/',
      null,
      null,
      null
    )
  ),
  true,
  'identical Cyber client_attempt_id retry is idempotent'
);

select is(
  (
    select count(*)::int
    from api.my_attempts
    where client_attempt_id = 'cyber-activation-attempt-1'
  ),
  1,
  'idempotent Cyber retry does not create a second attempt'
);

select throws_ok(
  $$
    select *
    from api.submit_attempt(
      'week2-malware-symptoms',
      '1.0.0',
      'cyber-activation-attempt-1',
      cyber_activation_tests.malware_payload(3),
      '/week-2/malware-symptoms/',
      null,
      null,
      null
    )
  $$,
  '23505',
  'CLIENT_ATTEMPT_ID_CONFLICT',
  'conflicting Cyber client_attempt_id reuse is rejected'
);
reset role;

select is(
  (
    select student.auth_user_id
    from learning.students as student
    join learning.attempts as attempt
      on attempt.student_id = student.id
    where attempt.client_attempt_id = 'cyber-activation-attempt-1'
  ),
  '12000000-0000-4000-8000-000000000001'::uuid,
  'Cyber attempt ownership is derived from auth.uid()'
);

set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated","email":"cyber.activation.two@local.invalid"}';
set local role authenticated;

select is(
  (
    select idempotent
    from api.complete_learner_onboarding(
      'Cyber',
      'Isolation',
      'CYBER-ACT-002',
      'cyber-year-1-test'
    )
  ),
  false,
  'second Cyber learner can onboard into the same test group'
);

select is(
  (
    select count(*)::int
    from api.my_attempts
    where client_attempt_id = 'cyber-activation-attempt-1'
  ),
  0,
  'second Cyber learner cannot read the first learner attempt'
);

select is(
  (select count(*)::int from api.my_responses),
  0,
  'second Cyber learner has no responses before their own submission'
);

select lives_ok(
  $$
    select *
    from api.submit_attempt(
      'week2-malware-symptoms',
      '1.0.0',
      'cyber-activation-attempt-peer',
      cyber_activation_tests.malware_payload(4),
      '/week-2/malware-symptoms/',
      null,
      null,
      null
    )
  $$,
  'second Cyber learner can submit their own Week 2 attempt'
);

select is(
  (
    select count(*)::int
    from api.my_attempts
    where client_attempt_id = 'cyber-activation-attempt-1'
  ),
  0,
  'second Cyber learner still cannot see the first learner attempt after submitting'
);

select is(
  (
    select count(*)::int
    from api.my_attempts
    where client_attempt_id = 'cyber-activation-attempt-peer'
  ),
  1,
  'second Cyber learner can read only their own attempt'
);
reset role;

select * from finish();
rollback;
