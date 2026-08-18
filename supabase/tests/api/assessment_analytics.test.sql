begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_view(
  'admin_api',
  'assessment_overview',
  'admin API exposes assessment overview aggregates'
);

select has_view(
  'admin_api',
  'group_performance',
  'admin API exposes group performance aggregates'
);

select has_view(
  'admin_api',
  'learner_performance',
  'admin API exposes learner performance aggregates'
);

select has_view(
  'admin_api',
  'activity_analytics',
  'admin API exposes activity analytics aggregates'
);

select has_view(
  'admin_api',
  'question_performance',
  'admin API exposes question performance aggregates'
);

select has_view(
  'admin_api',
  'topic_performance',
  'admin API exposes topic performance aggregates'
);

select has_view(
  'admin_api',
  'skill_performance',
  'admin API exposes skill performance aggregates'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from admin_api.assessment_overview),
  0::bigint,
  'learners cannot read assessment overview'
);

select is(
  (select count(*) from admin_api.group_performance),
  0::bigint,
  'learners cannot read group performance'
);

select is(
  (select count(*) from admin_api.learner_performance),
  0::bigint,
  'learners cannot read learner performance'
);

select is(
  (select count(*) from admin_api.question_performance),
  0::bigint,
  'learners cannot read question performance'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from admin_api.assessment_overview),
  0::bigint,
  'ordinary teachers cannot read assessment overview'
);

select is(
  (select count(*) from admin_api.topic_performance),
  0::bigint,
  'ordinary teachers cannot read topic performance'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select isnt(
  (select count(*) from admin_api.assessment_overview),
  0::bigint,
  'platform admin can read assessment overview'
);

select ok(
  (
    select requires_review_count >= 0
      and reviewed_response_count >= 0
      and attempt_count >= completed_attempts
    from admin_api.assessment_overview
  ),
  'assessment overview review and attempt counters are coherent'
);

select ok(
  (select count(*) from admin_api.group_performance) > 0,
  'platform admin can read group performance rows'
);

select ok(
  (select count(*) from admin_api.learner_performance) > 0,
  'platform admin can read learner performance rows'
);

select ok(
  (select count(*) from admin_api.activity_analytics) > 0,
  'platform admin can read activity analytics rows'
);

select ok(
  (select count(*) from admin_api.question_performance) > 0,
  'platform admin can read question performance rows'
);

select ok(
  (
    select count(*) = 0
    from information_schema.columns
    where table_schema = 'admin_api'
      and table_name in (
        'assessment_overview',
        'group_performance',
        'learner_performance',
        'activity_analytics',
        'question_performance',
        'topic_performance',
        'skill_performance'
      )
      and column_name = 'response_payload'
  ),
  'analytics views do not expose response_payload columns'
);

select ok(
  (
    select count(*) = 0
    from information_schema.columns
    where table_schema = 'admin_api'
      and table_name in (
        'question_performance',
        'topic_performance',
        'skill_performance'
      )
      and column_name in ('correct_answer', 'answer_key', 'marking_key')
  ),
  'analytics views do not expose answer keys'
);

reset role;

select finish();

rollback;
