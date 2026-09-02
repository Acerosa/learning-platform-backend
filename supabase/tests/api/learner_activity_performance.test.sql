begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_view(
  'admin_api',
  'learner_activity_performance',
  'admin API exposes contextual learner/activity analytics'
);

select has_view(
  'admin_api',
  'question_group_performance',
  'admin API exposes group-scoped question analytics'
);

select ok(
  coalesce((
    select option_value = 'true'
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    join pg_options_to_table(relation.reloptions) as options on true
    where namespace.nspname = 'admin_api'
      and relation.relname = 'learner_activity_performance'
      and options.option_name = 'security_invoker'
  ), false),
  'learner_activity_performance uses invoker security'
);

select ok(
  (
    select count(*) = 0
    from information_schema.columns
    where table_schema = 'admin_api'
      and table_name in (
        'learner_activity_performance',
        'question_group_performance'
      )
      and column_name in (
        'response_payload',
        'correct_answer',
        'answer_key',
        'marking_key'
      )
  ),
  'contextual analytics views do not expose payloads or answer keys'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from admin_api.learner_activity_performance),
  0::bigint,
  'learners cannot read learner activity performance'
);

select is(
  (select count(*) from admin_api.question_group_performance),
  0::bigint,
  'learners cannot read group-scoped question performance'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from admin_api.learner_activity_performance),
  0::bigint,
  'ordinary teachers cannot read learner activity performance'
);

reset role;

-- Isolated activities so first/latest/best cannot leak across unrelated work.
insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path
) values
  (
    'aa000000-0000-4000-8000-000000000001',
    '80000000-0000-4000-8000-000000000001',
    'contextual-analytics-alpha',
    'Contextual Analytics Alpha',
    'retrieval-quiz',
    'tests/contextual-analytics-alpha.html'
  ),
  (
    'aa000000-0000-4000-8000-000000000002',
    '80000000-0000-4000-8000-000000000001',
    'contextual-analytics-beta',
    'Contextual Analytics Beta',
    'retrieval-quiz',
    'tests/contextual-analytics-beta.html'
  );

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count
) values
  (
    'ab000000-0000-4000-8000-000000000001',
    'aa000000-0000-4000-8000-000000000001',
    '1.0.0',
    repeat('1', 64),
    100,
    2
  ),
  (
    'ab000000-0000-4000-8000-000000000002',
    'aa000000-0000-4000-8000-000000000002',
    '1.0.0',
    repeat('2', 64),
    100,
    1
  );

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score
) values
  (
    'ac000000-0000-4000-8000-000000000001',
    'ab000000-0000-4000-8000-000000000001',
    'q1',
    'section-1',
    'Section 1',
    'single',
    'Question 1',
    1,
    1
  ),
  (
    'ac000000-0000-4000-8000-000000000002',
    'ab000000-0000-4000-8000-000000000001',
    'q2',
    'section-1',
    'Section 1',
    'single',
    'Question 2',
    2,
    1
  );

update learning.activity_versions
set published_at = clock_timestamp()
where id in (
  'ab000000-0000-4000-8000-000000000001',
  'ab000000-0000-4000-8000-000000000002'
);

insert into learning.activity_assignments (
  id, group_id, activity_version_id, required, active
) values
  (
    'ad000000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-000000000001',
    'ab000000-0000-4000-8000-000000000001',
    true,
    true
  ),
  (
    'ad000000-0000-4000-8000-000000000002',
    '60000000-0000-4000-8000-000000000001',
    'ab000000-0000-4000-8000-000000000002',
    true,
    true
  ),
  (
    'ad000000-0000-4000-8000-000000000003',
    '60000000-0000-4000-8000-000000000002',
    'ab000000-0000-4000-8000-000000000001',
    true,
    true
  );

insert into learning.attempts (
  id, client_attempt_id, student_id, enrolment_id, assignment_id,
  activity_version_id, attempt_number, status, score, max_score,
  marking_source, evidence_level, submission_hash, received_at, completed_at
) values
  (
    'a3000000-0000-4000-8000-000000000011',
    'contextual-analytics-a1',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001',
    'ad000000-0000-4000-8000-000000000001',
    'ab000000-0000-4000-8000-000000000001',
    1,
    'completed',
    50,
    100,
    'server',
    'question_level',
    repeat('a', 64),
    timestamptz '2026-09-01 08:59:00+00',
    timestamptz '2026-09-01 09:00:00+00'
  ),
  (
    'a3000000-0000-4000-8000-000000000012',
    'contextual-analytics-a2',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001',
    'ad000000-0000-4000-8000-000000000001',
    'ab000000-0000-4000-8000-000000000001',
    2,
    'completed',
    80,
    100,
    'server',
    'question_level',
    repeat('b', 64),
    timestamptz '2026-09-02 08:59:00+00',
    timestamptz '2026-09-02 09:00:00+00'
  ),
  (
    'a3000000-0000-4000-8000-000000000021',
    'contextual-analytics-b1',
    '30000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001',
    'ad000000-0000-4000-8000-000000000002',
    'ab000000-0000-4000-8000-000000000002',
    1,
    'completed',
    20,
    100,
    'server',
    'summary_only',
    repeat('c', 64),
    timestamptz '2026-09-01 11:59:00+00',
    timestamptz '2026-09-01 12:00:00+00'
  );

insert into learning.responses (
  id, attempt_id, question_id, response_payload, awarded_score, max_score,
  is_correct, requires_review, marking_source
) values
  (
    'a4000000-0000-4000-8000-000000000011',
    'a3000000-0000-4000-8000-000000000012',
    'ac000000-0000-4000-8000-000000000001',
    '{"optionId":"fixture"}'::jsonb,
    1,
    1,
    true,
    true,
    'server'
  );

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select ok(
  (select count(*) from admin_api.learner_activity_performance) > 0,
  'platform admin can read learner activity performance rows'
);

select ok(
  (
    select count(*) > 0
    from admin_api.learner_activity_performance
    where student_number = 'SYNTH-0001'
      and attempt_count = 0
  ),
  'assigned learners with no attempts are represented'
);

select is(
  (
    select first_score_percentage
    from admin_api.learner_activity_performance
    where student_number = 'SYNTH-0001'
      and assignment_id = 'ad000000-0000-4000-8000-000000000001'
  ),
  50.00,
  'first result uses the earliest completed attempt for the same learner/activity'
);

select is(
  (
    select latest_score_percentage
    from admin_api.learner_activity_performance
    where student_number = 'SYNTH-0001'
      and assignment_id = 'ad000000-0000-4000-8000-000000000001'
  ),
  80.00,
  'latest result uses the latest completed attempt for the same learner/activity'
);

select is(
  (
    select best_score_percentage
    from admin_api.learner_activity_performance
    where student_number = 'SYNTH-0001'
      and assignment_id = 'ad000000-0000-4000-8000-000000000001'
  ),
  80.00,
  'best result is the highest completed score for the same learner/activity'
);

select is(
  (
    select average_score_percentage
    from admin_api.learner_activity_performance
    where student_number = 'SYNTH-0001'
      and assignment_id = 'ad000000-0000-4000-8000-000000000001'
  ),
  65.00,
  'attempt average is the mean of completed scores for the same learner/activity'
);

select is(
  (
    select first_score_percentage
    from admin_api.learner_activity_performance
    where student_number = 'SYNTH-0001'
      and assignment_id = 'ad000000-0000-4000-8000-000000000002'
  ),
  20.00,
  'a second activity does not inherit first/latest scores from another activity'
);

select is(
  (
    select latest_score_percentage
    from admin_api.learner_activity_performance
    where student_number = 'SYNTH-0001'
      and assignment_id = 'ad000000-0000-4000-8000-000000000002'
  ),
  20.00,
  'latest result for a second activity stays on that activity'
);

select ok(
  (
    select count(distinct course_key) filter (
      where group_code = 'TEST-GROUP-A'
    ) = 1
    from admin_api.learner_activity_performance
  ),
  'TEST-GROUP-A rows stay on a single course'
);

select is(
  (
    select requires_review_count
    from admin_api.learner_activity_performance
    where student_number = 'SYNTH-0001'
      and assignment_id = 'ad000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'review counts remain scoped to the learner/assignment'
);

select ok(
  (
    select count(*) > 0
    from admin_api.activity_analytics
    where group_code = 'TEST-GROUP-A'
      and activity_title is not null
      and course_title is not null
      and group_name is not null
  ),
  'activity analytics expose canonical titles'
);

select ok(
  (
    select participation_percentage is not null
      or assigned_learner_count = 0
    from admin_api.activity_analytics
    where assignment_id = 'ad000000-0000-4000-8000-000000000001'
  ),
  'activity analytics expose participation for an assignment'
);

select ok(
  (
    select count(*) > 0
    from admin_api.question_group_performance
    where group_code = 'TEST-GROUP-A'
      and assignment_id = 'ad000000-0000-4000-8000-000000000001'
      and correct_count >= 1
      and requires_review_count >= 1
      and unanswered_count >= 1
  ),
  'group-scoped question analytics can be narrowed to a course/group/activity'
);

select ok(
  (
    select count(*) = 0
    from admin_api.question_group_performance
    where group_code = 'TEST-GROUP-B'
      and assignment_id = 'ad000000-0000-4000-8000-000000000001'
  ),
  'question analytics for one group do not leak another group assignment'
);

reset role;

select finish();

rollback;
