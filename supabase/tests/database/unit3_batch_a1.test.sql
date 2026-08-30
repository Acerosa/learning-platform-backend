begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(24);

select is(
  (
    select count(*)::int
    from learning.activities as activity
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-3-cyber-security'
  ),
  80,
  'Unit 3 catalogue maps all 80 hub activity IDs'
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
  'four missing Week 5 activities exist in the catalogue'
);

select is(
  (
    select version.question_count
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week5-vulnerability-patterns'
      and version.version = '1.0.0'
  ),
  8,
  'week5-vulnerability-patterns question_count is 8'
);

select is(
  (
    select version.question_count
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week5-threat-vulnerability-risk'
      and version.version = '1.0.0'
  ),
  8,
  'week5-threat-vulnerability-risk question_count is 8'
);

select is(
  (
    select version.question_count
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week5-controls-matching'
      and version.version = '1.0.0'
  ),
  8,
  'week5-controls-matching question_count is 8'
);

select is(
  (
    select version.question_count
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week5-secure-rewrite'
      and version.version = '1.0.0'
  ),
  6,
  'week5-secure-rewrite question_count is 6'
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
      and question.question_type = 'text'
      and question.max_score = 6
  ),
  'W2OCR-Q08 exists on week2-ocr-question-practice 1.1.0'
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
  'week2-ocr-question-practice 1.1.0 question_count is 8'
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
  'week2-ocr-question-practice 1.0.0 keeps its original seven question rows'
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
  'Week 1 live banks are complete on version 1.1.0'
);

select is(
  (
    select count(*)::int
    from (
      values
        ('u3-w01-baseline', 'BAS-Q01'),
        ('u3-w01-cia', 'CIA-Q01'),
        ('u3-w01-incidents', 'INC-Q01'),
        ('u3-w01-glossary', 'GLO-Q01'),
        ('u3-w01-retrieval', 'RET-Q01'),
        ('u3-w01-command-words', 'Q001'),
        ('u3-w01-ocr-practice', 'OCR-Q01'),
        ('u3-w01-peer-improvement', 'PM-Q01')
    ) as expected(activity_key, question_key)
    join learning.activities as activity on activity.stable_key = expected.activity_key
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.version = '1.1.0'
    join learning.questions as question
      on question.activity_version_id = version.id
     and question.stable_key = expected.question_key
  ),
  8,
  'Week 1 live question IDs exist in the catalogue'
);

select ok(
  not exists (
    select 1
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    left join lateral (
      select count(*) as question_rows
      from learning.questions as question
      where question.activity_version_id = version.id
    ) as totals on true
    where module.stable_key = 'unit-3-cyber-security'
      and (
        activity.stable_key like 'u3-w01-%' and version.version = '1.1.0'
        or activity.stable_key = 'week2-ocr-question-practice' and version.version = '1.1.0'
        or activity.stable_key in (
          'week5-vulnerability-patterns',
          'week5-threat-vulnerability-risk',
          'week5-controls-matching',
          'week5-secure-rewrite'
        )
      )
      and totals.question_rows <> version.question_count
  ),
  'affected activity_versions.question_count matches question rows'
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
  'historical week2-malware-symptoms question IDs are unchanged'
);

select ok(
  not exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key like 'u3-w01-%'
      and version.version = '1.1.0'
      and question.stable_key like '%learner-note%'
  ),
  'Week 1 1.1.0 does not reuse learner-note scaffolding IDs'
);

select is(
  (
    select count(*)::int
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key like 'u3-w01-%'
      and version.version = '1.1.0'
  ),
  0,
  'Week 1 live banks have no inferred marking specs'
);

select is(
  (
    select count(*)::int
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.1.0'
  ),
  0,
  'Week 2 OCR 1.1.0 has no invented marking specs'
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
  'Week 5 scored items have unambiguous hub marking specs'
);

select ok(
  not exists (
    select 1
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key like 'u3-w01-%'
      and version.version = '1.1.0'
      and (
        version.published_at is null
        or version.retired_at is not null
        or version.question_count <= 0
      )
  ),
  'Week 1 1.1.0 is published and structurally eligible for submit_attempt'
);

select ok(
  not exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key like 'u3-w01-%'
      and version.version = '1.1.0'
      and question.question_type not in ('single', 'multiple', 'text', 'matching', 'order')
  ),
  'Week 1 1.1.0 question types can be represented by response_payload'
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
  'Batch A1 does not publish Unit 3 0.2.10'
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
  'the current Unit 3 publication remains unchanged'
);

select is(
  (
    select jsonb_array_length(package->'activities')
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it')
  ),
  76,
  'published learner package still contains 76 activities'
);

select ok(
  exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.0.0'
      and question.stable_key = 'W2OCR-Q07'
  ),
  'established OCR question IDs on 1.0.0 are not renamed'
);

select is(
  (
    select count(*)::int
    from (
      values
        ('week5-vulnerability-patterns', 'P8'),
        ('week5-threat-vulnerability-risk', 'T1'),
        ('week5-controls-matching', 'C8'),
        ('week5-secure-rewrite', 'R1')
    ) as expected(activity_key, question_key)
    join learning.activities as activity on activity.stable_key = expected.activity_key
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.version = '1.0.0'
    join learning.questions as question
      on question.activity_version_id = version.id
     and question.stable_key = expected.question_key
  ),
  4,
  'Week 5 scored question IDs follow catalogue conventions'
);

select * from finish();
rollback;
