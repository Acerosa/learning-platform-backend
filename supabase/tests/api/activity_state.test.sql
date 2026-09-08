begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

create schema activity_state_tests;
grant usage on schema activity_state_tests to authenticated;

create function activity_state_tests.requirements_payload()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_agg(
    jsonb_build_object(
      'question_id', question.stable_key,
      'response_payload', to_jsonb('synthetic-review'::text)
    )
    order by question.ordinal
  )
  from learning.questions as question
  where question.activity_version_id = '91000000-0000-4000-8000-000000000001'
$$;

grant execute on function activity_state_tests.requirements_payload() to authenticated;

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
) values (
  'aa000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'test-activity-state-draft',
  'Synthetic activity state draft',
  'test-only',
  'supabase/tests/api/activity_state.test.sql',
  true
);

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count
) values (
  'aa000000-0000-4000-8000-000000000002',
  'aa000000-0000-4000-8000-000000000001',
  '1.0.0',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  1,
  1
), (
  'aa000000-0000-4000-8000-000000000003',
  'aa000000-0000-4000-8000-000000000001',
  '2.0.0',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  1,
  1
);

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score
) values (
  'aa000000-0000-4000-8000-000000000011',
  'aa000000-0000-4000-8000-000000000002',
  'AS-Q1',
  'draft',
  'Draft',
  'single',
  'Draft item v1',
  1,
  1
), (
  'aa000000-0000-4000-8000-000000000012',
  'aa000000-0000-4000-8000-000000000003',
  'AS-Q1',
  'draft',
  'Draft',
  'single',
  'Draft item v2',
  1,
  1
);

update learning.activity_versions
set published_at = clock_timestamp()
where id in (
  'aa000000-0000-4000-8000-000000000002',
  'aa000000-0000-4000-8000-000000000003'
);

insert into learning.activity_assignments (
  id, group_id, activity_version_id, required, active
) values (
  'aa000000-0000-4000-8000-000000000021',
  '60000000-0000-4000-8000-000000000001',
  'aa000000-0000-4000-8000-000000000002',
  true,
  true
), (
  'aa000000-0000-4000-8000-000000000022',
  '60000000-0000-4000-8000-000000000001',
  'aa000000-0000-4000-8000-000000000003',
  true,
  true
), (
  'aa000000-0000-4000-8000-000000000023',
  '60000000-0000-4000-8000-000000000002',
  'aa000000-0000-4000-8000-000000000002',
  true,
  true
);

select no_plan();

set local role anon;
select throws_ok(
  $$select * from api.get_activity_state('test-activity-state-draft', '1.0.0')$$,
  '42501',
  NULL,
  'anonymous callers cannot read activity drafts'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$
    select *
    from api.save_activity_state(
      'test-activity-state-draft',
      '1.0.0',
      '{"responses":{"AS-Q1":"option-a"},"currentSectionId":"draft","score":99,"maxScore":10}'::jsonb
    )
  $$,
  'Learner A can save their own draft'
);

select is(
  (
    select state -> 'responses' ->> 'AS-Q1'
    from api.get_activity_state('test-activity-state-draft', '1.0.0')
  ),
  'option-a',
  'Learner A can read their own draft responses'
);

select is(
  (
    select state ? 'score' or state ? 'maxScore'
    from api.get_activity_state('test-activity-state-draft', '1.0.0')
  ),
  false,
  'draft payload cannot inject score or max score'
);

reset role;

select is(
  (
    select count(*)
    from learning.activity_states
    where student_id = '30000000-0000-4000-8000-000000000001'
      and activity_version_id = 'aa000000-0000-4000-8000-000000000002'
  ),
  1::bigint,
  'repeated setup still has one current draft row'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$
    select *
    from api.save_activity_state(
      'test-activity-state-draft',
      '1.0.0',
      '{"responses":{"AS-Q1":"option-b","AS-Q2":"typed"},"currentSectionId":"next"}'::jsonb
    )
  $$,
  'repeated save updates the same current draft'
);

select is(
  (
    select state -> 'responses' ->> 'AS-Q1'
    from api.get_activity_state('test-activity-state-draft', '1.0.0')
  ),
  'option-b',
  'the latest save replaces the previous draft payload'
);

reset role;

select is(
  (
    select count(*)
    from learning.activity_states
    where student_id = '30000000-0000-4000-8000-000000000001'
      and activity_version_id = 'aa000000-0000-4000-8000-000000000002'
  ),
  1::bigint,
  'repeated save does not create a second draft'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$
    select *
    from api.save_activity_state(
      'test-activity-state-draft',
      '2.0.0',
      '{"responses":{"AS-Q1":"version-two"}}'::jsonb
    )
  $$,
  'a different activity version stores a separate draft'
);

select is(
  (
    select state -> 'responses' ->> 'AS-Q1'
    from api.get_activity_state('test-activity-state-draft', '1.0.0')
  ),
  'option-b',
  'version 1.0.0 draft is unchanged by a 2.0.0 save'
);

select is(
  (
    select state -> 'responses' ->> 'AS-Q1'
    from api.get_activity_state('test-activity-state-draft', '2.0.0')
  ),
  'version-two',
  'version 2.0.0 draft is stored separately'
);

select throws_ok(
  $$insert into learning.activity_states (
      student_id, assignment_id, activity_version_id, state_payload
    ) values (
      '30000000-0000-4000-8000-000000000002',
      'aa000000-0000-4000-8000-000000000023',
      'aa000000-0000-4000-8000-000000000002',
      '{"stolen":true}'::jsonb
    )$$,
  '42501',
  NULL,
  'learners cannot insert activity drafts directly'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from api.get_activity_state('test-activity-state-draft', '1.0.0')),
  0::bigint,
  'Learner B cannot read Learner A draft'
);

select lives_ok(
  $$
    select *
    from api.save_activity_state(
      'test-activity-state-draft',
      '1.0.0',
      '{"responses":{"AS-Q1":"learner-b"}}'::jsonb
    )
  $$,
  'Learner B can save their own draft for the same activity'
);

select is(
  (
    select state -> 'responses' ->> 'AS-Q1'
    from api.get_activity_state('test-activity-state-draft', '1.0.0')
  ),
  'learner-b',
  'Learner B reads only their own draft'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select state -> 'responses' ->> 'AS-Q1'
    from api.get_activity_state('test-activity-state-draft', '1.0.0')
  ),
  'option-b',
  'Learner B save does not update Learner A draft'
);

select is(
  (
    select count(*)
    from learning.attempts
    where student_id = '30000000-0000-4000-8000-000000000001'
      and activity_version_id = 'aa000000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'autosaving a draft does not create an attempt'
);

select lives_ok(
  $$
    select *
    from api.save_activity_state(
      'foundations-requirements-classification',
      '1.0.0',
      '{"responses":{"REQ-001":"in-progress"}}'::jsonb
    )
  $$,
  'Learner A can draft an assigned foundations activity'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$
    select *
    from api.submit_attempt(
      'foundations-requirements-classification',
      '1.0.0',
      'activity-state-student-a-final',
      activity_state_tests.requirements_payload()
    )
  $$,
  'final submission still creates an authoritative attempt'
);

select is(
  (
    select count(*)
    from api.get_activity_state('foundations-requirements-classification', '1.0.0')
  ),
  0::bigint,
  'successful submit completes the matching in-progress draft'
);

select is(
  (
    select attempt_number
    from api.my_attempts
    where client_attempt_id = 'activity-state-student-a-final'
  ),
  (
    select count(*)::integer
    from learning.attempts
    where student_id = '30000000-0000-4000-8000-000000000001'
      and activity_version_id = '91000000-0000-4000-8000-000000000001'
  ),
  'the submitted attempt keeps sequential attempt numbering'
);

select is(
  (
    select count(*)
    from learning.attempts
    where student_id = '30000000-0000-4000-8000-000000000001'
      and client_attempt_id = 'activity-state-student-a-final'
  ),
  1::bigint,
  'exactly one authoritative attempt exists for the final submission'
);
reset role;

select is(
  (
    select status
    from learning.activity_states
    where student_id = '30000000-0000-4000-8000-000000000001'
      and activity_version_id = '91000000-0000-4000-8000-000000000001'
  ),
  'completed',
  'the foundations draft is completed rather than deleted'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$
    select *
    from api.save_activity_state(
      'foundations-requirements-classification',
      '1.0.0',
      '{"responses":{"REQ-001":"stale"},"startedAt":"2026-01-01T00:00:00Z"}'::jsonb
    )
  $$,
  'a late in-progress save after submit does not error'
);
reset role;

select is(
  (
    select status
    from learning.activity_states
    where student_id = '30000000-0000-4000-8000-000000000001'
      and activity_version_id = '91000000-0000-4000-8000-000000000001'
  ),
  'completed',
  'a late in-progress save does not reopen the completed draft'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*)
    from api.get_activity_state('foundations-requirements-classification', '1.0.0')
  ),
  0::bigint,
  'get_activity_state still hides the completed draft after a stale save'
);
reset role;

select is(
  (
    select count(*)
    from learning.attempts
    where student_id = '30000000-0000-4000-8000-000000000001'
      and activity_version_id = 'aa000000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'historical attempts for other activities remain unchanged'
);

select * from finish();
rollback;
