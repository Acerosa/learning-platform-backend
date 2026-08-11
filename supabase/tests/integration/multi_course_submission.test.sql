begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

create schema multi_course_tests;

create function multi_course_tests.requirements_payload()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_agg(
    jsonb_build_object(
      'question_id', question.stable_key,
      'response_payload', to_jsonb('synthetic-response'::text),
      'awarded_score', 0,
      'is_correct', false
    )
    order by question.ordinal
  )
  from learning.questions as question
  where question.activity_version_id = '91000000-0000-4000-8000-000000000001'
$$;

grant usage on schema multi_course_tests to authenticated;
grant execute on function multi_course_tests.requirements_payload() to authenticated;

insert into learning.groups (
  id,
  academic_year_id,
  course_id,
  code,
  name,
  active,
  registration_open
) select
  '62000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  course.id,
  'MULTI-COURSE-B',
  'Synthetic second-course group',
  true,
  false
from learning.courses as course
where course.stable_key = 'ocr-level-3-it';

insert into learning.enrolments (
  id,
  student_id,
  group_id,
  joined_on,
  status
) values (
  '72000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '62000000-0000-4000-8000-000000000001',
  '2026-09-01',
  'active'
);

select no_plan();

select is(
  (
    select count(*)
    from learning.enrolments
    where student_id = '30000000-0000-4000-8000-000000000001'
      and status = 'active'
  ),
  2::bigint,
  'the learner has two active enrolments in different courses'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$select * from api.submit_attempt(
    'foundations-requirements-classification',
    '1.0.0',
    'multi-course-resolved-1',
    multi_course_tests.requirements_payload(),
    '/foundations/requirements-classification/',
    null,
    null,
    null
  )$$,
  'submission resolves the one matching assignment across multiple enrolments'
);

reset role;

select is(
  (
    select enrolment_id
    from learning.attempts
    where client_attempt_id = 'multi-course-resolved-1'
  ),
  '70000000-0000-4000-8000-000000000001'::uuid,
  'the attempt is stored against the enrolment whose group owns the assignment'
);

insert into learning.activity_assignments (
  id,
  group_id,
  activity_version_id,
  required,
  active
) values (
  '92000000-0000-4000-8000-000000000099',
  '62000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000001',
  true,
  true
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select * from api.submit_attempt(
    'foundations-requirements-classification',
    '1.0.0',
    'multi-course-ambiguous-1',
    multi_course_tests.requirements_payload(),
    '/foundations/requirements-classification/',
    null,
    null,
    null
  )$$,
  '23514',
  'ACTIVITY_ASSIGNMENT_AMBIGUOUS',
  'the backend rejects ambiguous delivery rather than guessing an enrolment'
);

reset role;

select * from finish();
rollback;
