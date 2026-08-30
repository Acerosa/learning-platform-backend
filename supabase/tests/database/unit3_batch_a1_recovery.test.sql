begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(24);

create temporary table unit3_a1_recovery_evidence as
select
  (select count(*)::bigint from learning.attempts) as attempt_count,
  (select count(*)::bigint from learning.responses) as response_count,
  (select coalesce(md5(string_agg(id::text, ',' order by id)), '') from learning.attempts) as attempt_digest,
  (select coalesce(md5(string_agg(id::text, ',' order by id)), '') from learning.responses) as response_digest;

create temporary table week1_v100_snapshot as
select
  activity.stable_key,
  version.id,
  version.question_count,
  version.published_at,
  (
    select count(*)::int
    from learning.questions as question
    where question.activity_version_id = version.id
  ) as question_rows,
  (
    select coalesce(string_agg(question.stable_key, ',' order by question.ordinal), '')
    from learning.questions as question
    where question.activity_version_id = version.id
  ) as question_keys
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where activity.stable_key like 'u3-w01-%'
  and version.version = '1.0.0';

create schema unit3_a1_recovery_tests;

create function unit3_a1_recovery_tests.a1_version_ids()
returns setof uuid
language sql
stable
as $$
  select version.id
  from learning.activity_versions as version
  join learning.activities as activity on activity.id = version.activity_id
  where (activity.stable_key like 'u3-w01-%' and version.version = '1.1.0')
     or (activity.stable_key = 'week2-ocr-question-practice' and version.version = '1.1.0')
     or activity.stable_key in (
       'week5-vulnerability-patterns',
       'week5-threat-vulnerability-risk',
       'week5-controls-matching',
       'week5-secure-rewrite'
     )
$$;

create function unit3_a1_recovery_tests.set_immutability_triggers(enabled boolean)
returns void
language plpgsql
as $$
declare
  command text := case when enabled then 'enable' else 'disable' end;
begin
  execute format('alter table learning.activity_versions %s trigger activity_versions_immutable_after_publication', command);
  execute format('alter table learning.questions %s trigger questions_immutable_after_publication', command);
  execute format('alter table learning.question_topics %s trigger question_topics_immutable_after_publication', command);
  execute format('alter table learning.question_skills %s trigger question_skills_immutable_after_publication', command);
  execute format('alter table learning.question_marking %s trigger question_marking_immutable_after_publication', command);
  execute format('alter table learning.activity_version_languages %s trigger activity_version_languages_immutable_after_publication', command);
end;
$$;

create function unit3_a1_recovery_tests.simulate_partial_hosted_residue()
returns void
language plpgsql
as $$
begin
  perform unit3_a1_recovery_tests.set_immutability_triggers(false);

  delete from learning.question_marking
  where question_id in (
    select question.id
    from learning.questions as question
    where question.activity_version_id in (select unit3_a1_recovery_tests.a1_version_ids())
  );

  delete from learning.questions
  where activity_version_id in (select unit3_a1_recovery_tests.a1_version_ids());

  delete from learning.activity_delivery
  where activity_version_id in (select unit3_a1_recovery_tests.a1_version_ids());

  delete from learning.activity_assignments
  where activity_version_id in (select unit3_a1_recovery_tests.a1_version_ids());

  delete from learning.activity_version_languages
  where activity_version_id in (select unit3_a1_recovery_tests.a1_version_ids());

  delete from learning.activity_versions
  where id in (select unit3_a1_recovery_tests.a1_version_ids());

  delete from learning.activities
  where stable_key in (
    'week5-vulnerability-patterns',
    'week5-threat-vulnerability-risk',
    'week5-controls-matching',
    'week5-secure-rewrite'
  );

  insert into learning.activity_versions (
    id, activity_id, version, content_hash, max_score, question_count, published_at
  )
  select
    '0228c12e-1ac3-5c07-ad9f-7c24d355c858',
    activity.id,
    '1.1.0',
    '37a5ccb5eaae5cf5f18e75f1058a08ec17032e538810dde5540df88b686e3cc7',
    10,
    10,
    null
  from learning.activities as activity
  where activity.stable_key = 'u3-w01-baseline';

  perform unit3_a1_recovery_tests.set_immutability_triggers(true);
end;
$$;

select lives_ok(
  $$select learning.apply_unit3_batch_a1_recovery()$$,
  'recovery is a no-op on the already-complete local Batch A1 catalogue'
);

select is(
  (
    select count(*)::int
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key like 'u3-w01-%'
      and version.version = '1.1.0'
  ),
  82,
  'Week 1 live banks remain complete on version 1.1.0'
);

select is(
  (
    select count(*)::int
    from week1_v100_snapshot as snapshot
    join learning.activity_versions as version on version.id = snapshot.id
    join lateral (
      select
        count(*)::int as question_rows,
        coalesce(string_agg(question.stable_key, ',' order by question.ordinal), '') as question_keys
      from learning.questions as question
      where question.activity_version_id = version.id
    ) as current_state on true
    where version.question_count = snapshot.question_count
      and version.published_at is not distinct from snapshot.published_at
      and current_state.question_rows = snapshot.question_rows
      and current_state.question_keys = snapshot.question_keys
  ),
  8,
  'Week 1 1.0.0 identity, publication state, and question keys remain unchanged'
);

select is(
  (
    select count(*)::int
    from learning.activities
    where stable_key in (
      'week5-vulnerability-patterns',
      'week5-threat-vulnerability-risk',
      'week5-controls-matching',
      'week5-secure-rewrite'
    )
  ),
  4,
  'four Week 5 catalogue activities exist'
);

select is(
  (
    select count(*)::int
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key in (
      'week5-vulnerability-patterns',
      'week5-threat-vulnerability-risk',
      'week5-controls-matching',
      'week5-secure-rewrite'
    )
  ),
  30,
  '30 Week 5 marking specs exist'
);

select ok(
  exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.1.0'
      and question.stable_key = 'W2OCR-Q08'
  ),
  'W2OCR-Q08 exists on week2-ocr-question-practice 1.1.0'
);

select is(
  (
    select package_version
    from platform.curriculum_publications
    where hub_code = 'unit-3-cyber-security'
      and course_key = 'ocr-level-3-it'
      and status = 'published'
  ),
  '0.2.0',
  'recovery does not change the current Unit 3 publication'
);

select lives_ok(
  $$
  select unit3_a1_recovery_tests.simulate_partial_hosted_residue();
  select learning.apply_unit3_batch_a1_recovery();
  $$,
  'recovery completes Batch A1 from the known hosted residue'
);

select is(
  (
    select count(*)::int
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key like 'u3-w01-%'
      and version.version = '1.1.0'
  ),
  82,
  'partial-state recovery restores all Week 1 1.1.0 live question rows'
);

select is(
  (
    select version.question_count
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-w01-baseline'
      and version.version = '1.1.0'
  ),
  10,
  'recovered baseline 1.1.0 question_count is 10'
);

select is(
  (
    select count(*)::int
    from learning.questions
    where activity_version_id = '0228c12e-1ac3-5c07-ad9f-7c24d355c858'
  ),
  10,
  'recovered baseline 1.1.0 keeps the original residue version id'
);

select ok(
  (
    select version.published_at is not null
    from learning.activity_versions as version
    where version.id = '0228c12e-1ac3-5c07-ad9f-7c24d355c858'
  ),
  'recovered baseline 1.1.0 is published after questions are attached'
);

select is(
  (
    select count(*)::int
    from (
      values
        ('u3-w01-baseline', 10),
        ('u3-w01-cia', 12),
        ('u3-w01-incidents', 12),
        ('u3-w01-glossary', 12),
        ('u3-w01-retrieval', 12),
        ('u3-w01-command-words', 6),
        ('u3-w01-ocr-practice', 11),
        ('u3-w01-peer-improvement', 7)
    ) as expected(activity_key, expected_count)
    join learning.activities as activity on activity.stable_key = expected.activity_key
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.version = '1.1.0'
    join lateral (
      select count(*)::int as question_rows
      from learning.questions as question
      where question.activity_version_id = version.id
    ) as totals on totals.question_rows = expected.expected_count
      and version.question_count = expected.expected_count
  ),
  8,
  'all eight Week 1 1.1.0 counts match question rows'
);

select is(
  (
    select count(*)::int
    from (
      values
        ('week5-vulnerability-patterns', 8),
        ('week5-threat-vulnerability-risk', 8),
        ('week5-controls-matching', 8),
        ('week5-secure-rewrite', 6)
    ) as expected(activity_key, expected_count)
    join learning.activities as activity on activity.stable_key = expected.activity_key
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.version = '1.0.0'
    where version.question_count = expected.expected_count
  ),
  4,
  'Week 5 recovered question counts are 8/8/8/6'
);

select is(
  (
    select version.question_count
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.1.0'
  ),
  8,
  'recovered OCR 1.1.0 question_count is 8'
);

select is(
  (
    select count(*)::int
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.0.0'
  ),
  7,
  'OCR 1.0.0 remains unchanged after recovery'
);

select is(
  (
    select count(*)::int
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-malware-symptoms'
      and version.version = '1.0.0'
      and question.stable_key like 'MW-Q%'
  ),
  10,
  'historical week2-malware-symptoms question IDs remain unchanged'
);

select is(
  (
    select count(*)::int
    from week1_v100_snapshot as snapshot
    join learning.activity_versions as version on version.id = snapshot.id
    join lateral (
      select
        count(*)::int as question_rows,
        coalesce(string_agg(question.stable_key, ',' order by question.ordinal), '') as question_keys
      from learning.questions as question
      where question.activity_version_id = version.id
    ) as current_state on true
    where version.question_count = snapshot.question_count
      and version.published_at is not distinct from snapshot.published_at
      and current_state.question_rows = snapshot.question_rows
      and current_state.question_keys = snapshot.question_keys
  ),
  8,
  'Week 1 1.0.0 remains unchanged after partial-state recovery'
);

select is(
  (select count(*)::bigint from learning.attempts),
  (select attempt_count from unit3_a1_recovery_evidence),
  'attempt rows are not rewritten by recovery'
);

select is(
  (select count(*)::bigint from learning.responses),
  (select response_count from unit3_a1_recovery_evidence),
  'response rows are not rewritten by recovery'
);

select is(
  (select coalesce(md5(string_agg(id::text, ',' order by id)), '') from learning.attempts),
  (select attempt_digest from unit3_a1_recovery_evidence),
  'existing attempt identities are unchanged'
);

select is(
  (select coalesce(md5(string_agg(id::text, ',' order by id)), '') from learning.responses),
  (select response_digest from unit3_a1_recovery_evidence),
  'existing response identities are unchanged'
);

select throws_ok(
  $$
  select unit3_a1_recovery_tests.simulate_partial_hosted_residue();
  update learning.activity_versions
  set question_count = 9
  where id = '0228c12e-1ac3-5c07-ad9f-7c24d355c858';
  select learning.apply_unit3_batch_a1_recovery();
  $$,
  'P0001',
  'UNIT3_BATCH_A1_RECOVERY_CONFLICT: u3-w01-baseline 1.1.0 metadata is incompatible',
  'recovery fails closed on unexpected residue metadata'
);

select is(
  (
    select count(*)::int
    from platform.curriculum_publications
    where hub_code = 'unit-3-cyber-security'
      and status = 'published'
      and package_version = '0.2.10'
  ),
  0,
  'recovery does not publish Unit 3 0.2.10'
);

select * from finish();
rollback;
