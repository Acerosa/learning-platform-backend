begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

grant usage on schema extensions to anon, authenticated;

create schema tests_manifest;
grant usage on schema tests_manifest to anon, authenticated;

create function tests_manifest.payload_for_activity(
  target_activity_key text,
  correct_count integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_agg(
    jsonb_build_object(
      'question_id', question.stable_key,
      'response_payload',
        case
          when question.question_type in ('multiple', 'order', 'code-order')
            then jsonb_build_array('synthetic-response')
          when question.question_type = 'matching'
            then jsonb_build_object('synthetic-row', 'synthetic-response')
          else to_jsonb('synthetic-response'::text)
        end,
      'awarded_score', case when question.ordinal <= correct_count
        then question.max_score else 0 end,
      'is_correct', question.ordinal <= correct_count
    )
    order by question.ordinal
  )
  from learning.questions as question
  join learning.activity_versions as activity_version
    on activity_version.id = question.activity_version_id
  join learning.activities as activity on activity.id = activity_version.activity_id
  where activity.stable_key = target_activity_key
    and activity_version.published_at is not null
    and activity_version.retired_at is null
$$;

grant execute on function tests_manifest.payload_for_activity(text, integer)
to authenticated;

select no_plan();

select is(
  (select count(*) from learning.activities
    where stable_key like 'foundations-%'),
  5::bigint,
  'the manifest imports all five Foundations activities'
);

select is(
  (select count(*) from learning.activity_versions as activity_version
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity.stable_key like 'foundations-%'
      and activity_version.published_at is not null and activity_version.retired_at is null),
  5::bigint,
  'the manifest publishes one current version for every Foundations activity'
);

select is(
  (select count(*) from learning.questions as question
    join learning.activity_versions as activity_version on activity_version.id = question.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity.stable_key like 'foundations-%'),
  112::bigint,
  'the manifest imports all 112 reviewed question identifiers'
);

select is(
  (
    select count(*)
    from learning.topics as topic
    join learning.modules as module on module.id = topic.module_id
    where module.stable_key = 'software-development-foundations'
  ),
  21::bigint,
  'the manifest creates one grounded topic per reviewed activity section'
);

select is(
  (select count(*) from learning.question_topics as question_topic
    join learning.questions as question on question.id = question_topic.question_id
    join learning.activity_versions as activity_version on activity_version.id = question.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity.stable_key like 'foundations-%'),
  112::bigint,
  'every manifest question maps to its section-grounded topic'
);

select is(
  (select count(*) from learning.skills),
  3::bigint,
  'only the three Programming Diagnostic skills declared in Git are imported'
);

select is(
  (select count(*) from learning.question_skills),
  35::bigint,
  'every Programming Diagnostic question maps to its declared skill'
);

select is(
  (select count(*) from learning.coding_languages),
  3::bigint,
  'Python, JavaScript and C sharp are the only coding languages imported'
);

select is(
  (
    select count(*)
    from learning.activity_version_languages as version_language
    join learning.activity_versions as activity_version
      on activity_version.id = version_language.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity.stable_key like 'foundations-%'
  ),
  3::bigint,
  'only Programming Diagnostic declares selectable languages'
);

select ok(
  not exists (
    select 1
    from learning.activity_versions as activity_version
    left join lateral (
      select count(*) as question_count, sum(question.max_score) as max_score
      from learning.questions as question
      where question.activity_version_id = activity_version.id
    ) as totals on true
    where activity_version.published_at is not null
      and (
        totals.question_count <> activity_version.question_count
        or totals.max_score <> activity_version.max_score
      )
  ),
  'every published version question count and score total matches its manifest'
);

select is(
  (
    select count(*)
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    where learner_group.code not in ('CYBER-TEST-QA', 'TLEVEL-TEST-A', 'L2E-TEST-A')
  ),
  193::bigint,
  'pre-existing local assignments remain 193 excluding new hub-isolated QA groups'
);

set local role anon;
select throws_like(
  $$select * from api.my_activity_progress$$,
  '%permission denied%',
  'anonymous users cannot access the new private progress view'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from api.my_assignments),
  5::bigint,
  'Student A sees all five assignments for their own active group'
);

select lives_ok(
  $$
    select *
    from api.submit_attempt(
      'foundations-problem-decomposition',
      '1.0.0',
      'manifest-problem-attempt-1',
      tests_manifest.payload_for_activity('foundations-problem-decomposition', 0),
      '/foundations/problem-decomposition/',
      '2026-08-09T10:00:00Z',
      '2026-08-09T10:12:00Z',
      null
    )
  $$,
  'a heterogeneous non-coding response set is accepted'
);

select is(
  (select count(*) from api.my_responses
    where attempt_id = (
      select attempt_id from api.my_attempts
      where client_attempt_id = 'manifest-problem-attempt-1'
    )),
  17::bigint,
  'all heterogeneous Problem Decomposition responses persist'
);

select ok(
  (
    select
      count(*) filter (where jsonb_typeof(response_payload) = 'array') > 0
      and count(*) filter (where jsonb_typeof(response_payload) = 'object') > 0
      and count(*) filter (where jsonb_typeof(response_payload) = 'string') > 0
    from api.my_responses
    where attempt_id = (
      select attempt_id from api.my_attempts
      where client_attempt_id = 'manifest-problem-attempt-1'
    )
  ),
  'string, array and object response payloads are all retained'
);

select ok(
  (
    select
      source_page = '/foundations/problem-decomposition/'
      and client_started_at = '2026-08-09T10:00:00Z'::timestamptz
      and client_completed_at = '2026-08-09T10:12:00Z'::timestamptz
    from api.my_attempts
    where client_attempt_id = 'manifest-problem-attempt-1'
  ),
  'bounded client timing and source-page metadata persist'
);

select is(
  (
    select idempotent
    from api.submit_attempt(
      'foundations-problem-decomposition',
      '1.0.0',
      'manifest-problem-attempt-1',
      tests_manifest.payload_for_activity('foundations-problem-decomposition', 0),
      '/foundations/problem-decomposition/',
      '2026-08-09T10:00:00Z',
      '2026-08-09T10:12:00Z',
      null
    )
  ),
  true,
  'the richer attempt payload remains idempotent'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'foundations-problem-decomposition',
      '1.0.0',
      'manifest-problem-language-not-applicable',
      tests_manifest.payload_for_activity('foundations-problem-decomposition', 0),
      '/foundations/problem-decomposition/',
      '2026-08-09T10:00:00Z',
      '2026-08-09T10:12:00Z',
      'python'
    )
  $$,
  '22023',
  'PROGRAMMING_LANGUAGE_NOT_APPLICABLE',
  'a non-programming activity rejects programming-language metadata'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'foundations-programming-diagnostic',
      '2.0.0',
      'manifest-programming-language-required',
      tests_manifest.payload_for_activity('foundations-programming-diagnostic', 0),
      '/foundations/programming-diagnostic/',
      '2026-08-09T10:00:00Z',
      '2026-08-09T10:20:00Z',
      null
    )
  $$,
  '22023',
  'PROGRAMMING_LANGUAGE_REQUIRED',
  'Programming Diagnostic requires one declared language'
);

select lives_ok(
  $$
    select * from api.submit_attempt(
      'foundations-programming-diagnostic',
      '2.0.0',
      'manifest-programming-attempt-1',
      tests_manifest.payload_for_activity('foundations-programming-diagnostic', 0),
      '/foundations/programming-diagnostic/',
      '2026-08-09T10:00:00Z',
      '2026-08-09T10:20:00Z',
      'python'
    )
  $$,
  'Programming Diagnostic accepts a complete response set with a supported language'
);

select is(
  (select programming_language from api.my_attempts
    where client_attempt_id = 'manifest-programming-attempt-1'),
  'python',
  'the selected programming language is stored relationally'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'foundations-programming-diagnostic',
      '2.0.0',
      'manifest-programming-language-invalid',
      tests_manifest.payload_for_activity('foundations-programming-diagnostic', 0),
      '/foundations/programming-diagnostic/',
      '2026-08-09T10:00:00Z',
      '2026-08-09T10:20:00Z',
      'ruby'
    )
  $$,
  '22023',
  'INVALID_PROGRAMMING_LANGUAGE',
  'an undeclared programming language is rejected'
);

select lives_ok(
  $$
    select * from api.submit_attempt(
      'foundations-requirements-classification',
      '1.0.0',
      'manifest-requirements-attempt-1',
      tests_manifest.payload_for_activity('foundations-requirements-classification', 10),
      '/foundations/requirements-classification/',
      '2026-08-09T09:00:00Z',
      '2026-08-09T09:10:00Z',
      null
    )
  $$,
  'a first Requirements attempt is recorded for progress derivation'
);

select lives_ok(
  $$
    select * from api.submit_attempt(
      'foundations-requirements-classification',
      '1.0.0',
      'manifest-requirements-attempt-2',
      tests_manifest.payload_for_activity('foundations-requirements-classification', 15),
      '/foundations/requirements-classification/',
      '2026-08-09T11:00:00Z',
      '2026-08-09T11:10:00Z',
      null
    )
  $$,
  'a later Requirements attempt is recorded for progress derivation'
);

select ok(
  (
    select
      attempt_count = 2
      and first_score = 0
      and latest_score = 0
      and best_score = 0
      and improvement = 0
    from api.my_activity_progress
    where activity_key = 'foundations-requirements-classification'
  ),
  'the student progress view derives first, latest, best and improvement correctly'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select ok(
  (
    select
      students_completed = 1
      and latest_group_average_percentage = 0.00
      and completion_percentage = 100.00
    from api.teacher_group_activity_analytics
    where group_code = 'TEST-GROUP-A'
      and activity_key = 'foundations-requirements-classification'
  ),
  'teacher activity analytics derive latest group average and completion'
);

select ok(
  (
    select
      assigned_activities = 5
      and completed_activities = 3
      and completion_percentage = 60.00
      and latest_average_percentage = 0.00
      and requires_support
    from api.teacher_group_student_progress
    where group_code = 'TEST-GROUP-A'
      and student_number = 'SYNTH-0001'
  ),
  'teacher student progress derives overall completion, performance and support status'
);

select is(
  (select count(*) from api.teacher_group_student_progress
    where group_code = 'TEST-GROUP-B'),
  0::bigint,
  'Teacher A cannot read Group B student progress'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select is(
  (select count(*) from api.teacher_group_activity_analytics
    where group_code = 'TEST-GROUP-A'),
  0::bigint,
  'Teacher B cannot read Group A activity analytics'
);
reset role;

select throws_ok(
  $$
    delete from learning.question_skills
    where question_id = (
      select question.id
      from learning.questions as question
      where question.stable_key = 'FOUND-PROG-VAR-001'
    )
  $$,
  '55000',
  'PUBLISHED_QUESTION_SKILL_IMMUTABLE',
  'published question skill mappings are immutable'
);

select throws_ok(
  $$
    delete from learning.activity_version_languages
    where activity_version_id = (
      select activity_version.id
      from learning.activity_versions as activity_version
      join learning.activities as activity on activity.id = activity_version.activity_id
      where activity.stable_key = 'foundations-programming-diagnostic'
        and activity_version.version = '2.0.0'
    )
  $$,
  '55000',
  'PUBLISHED_ACTIVITY_LANGUAGE_IMMUTABLE',
  'published activity language mappings are immutable'
);

select * from finish();
rollback;
