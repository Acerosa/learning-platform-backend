begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(28);

select is(
  (
    select count(*)::int
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-3-cyber-security'
  ),
  585,
  'Batch B attaches marking to every latest Unit 3 question row that needs a policy'
);

select ok(
  not exists (
    select 1
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    join lateral (
      select max(other.version) as latest
      from learning.activity_versions as other
      where other.activity_id = version.activity_id
        and other.published_at is not null
        and other.retired_at is null
    ) as latest on true
    left join learning.questions as question on question.activity_version_id = version.id
    left join learning.question_marking as marking on marking.question_id = question.id
    where module.stable_key = 'unit-3-cyber-security'
      and version.version = latest.latest
      and version.published_at is not null
      and question.id is not null
      and marking.question_id is null
  ),
  'every question on each activity latest published version has an explicit marking spec'
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
      and version.version = '1.0.0'
  ),
  30,
  'Week 5 Batch A1 marking specs remain on unchanged 1.0.0 rows'
);

select ok(
  not exists (
    select 1
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key in (
      'week5-vulnerability-patterns',
      'week5-threat-vulnerability-risk',
      'week5-controls-matching',
      'week5-secure-rewrite'
    )
      and version.version <> '1.0.0'
  ),
  'Week 5 activities with complete specs are not re-versioned'
);

select is(
  (
    select question.question_type
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.1.0'
      and question.stable_key = 'W2OCR-Q07'
  ),
  'text',
  'published OCR 1.1.0 Q07 remains text'
);

select is(
  (
    select version.max_score
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.1.0'
  ),
  26::numeric,
  'published OCR 1.1.0 max_score remains 26'
);

select ok(
  exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    join learning.question_marking as marking on marking.question_id = question.id
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.2.0'
      and question.stable_key = 'W2OCR-Q07'
      and question.question_type = 'single'
      and question.max_score = 2
      and marking.spec->>'mode' = 'single-choice'
      and marking.spec->>'correctOptionId' = 'c'
  ),
  'OCR 1.2.0 Q07 is the hub MCQ / 2-mark item'
);

select ok(
  exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    join learning.question_marking as marking on marking.question_id = question.id
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.2.0'
      and question.stable_key = 'W2OCR-Q08'
      and question.question_type = 'text'
      and question.max_score = 6
      and marking.spec->>'mode' = 'requires_review'
  ),
  'OCR 1.2.0 Q08 remains the 6-mark extended response with requires_review'
);

select is(
  (
    select version.max_score
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.2.0'
  ),
  20::numeric,
  'OCR 1.2.0 total is the hub 20-mark bank'
);

select ok(
  not exists (
    select 1
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key like 'u3-w01-%'
      and version.version = '1.1.0'
  ),
  'Week 1 1.1.0 is left without backfilled marking'
);

select is(
  (
    select count(*)::int
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key like 'u3-w01-%'
      and version.version = '1.2.0'
      and marking.spec->>'mode' = 'requires_review'
  ),
  75,
  'Week 1 1.2.0 objective and free-text items without keys use requires_review'
);

select is(
  (
    select count(*)::int
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-w01-peer-improvement'
      and version.version = '1.2.0'
      and marking.spec->>'mode' = 'completion'
  ),
  7,
  'Week 1 peer-improvement 1.2.0 uses completion'
);

select ok(
  not exists (
    select 1
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-w01-incidents'
      and version.version = '1.2.0'
      and marking.spec->>'mode' <> 'requires_review'
  ),
  'Week 1 incidents 1.2.0 are not flattened to a single category'
);

select is(
  (
    select question.id::text
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-malware-symptoms'
      and version.version = '1.0.0'
      and question.stable_key = 'MW-Q1'
  ),
  '1abe8aff-83f6-5708-9c04-fd6a900d3701',
  'historical MW-Q1 question id is unchanged'
);

select ok(
  not exists (
    select 1
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    where question.id = '1abe8aff-83f6-5708-9c04-fd6a900d3701'
  ),
  'historical MW-Q1 1.0.0 is not backfilled with marking'
);

select ok(
  not exists (
    select 1
    from learning.attempts as attempt
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-malware-symptoms'
      and version.version = '1.1.0'
  ),
  'Batch B does not write learner attempts onto new marking versions'
);

select is(
  (
    select (learning.mark_evidence_response(
      question.id,
      jsonb_build_object('optionId', 'B'),
      question.max_score
    )).is_correct
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-malware-symptoms'
      and version.version = '1.1.0'
      and question.stable_key = 'MW-Q1'
  ),
  true,
  'correct Week 2 option is server-marked true'
);

select is(
  (
    select (learning.mark_evidence_response(
      question.id,
      jsonb_build_object('optionId', 'A'),
      question.max_score
    )).is_correct
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-malware-symptoms'
      and version.version = '1.1.0'
      and question.stable_key = 'MW-Q1'
  ),
  false,
  'wrong Week 2 option is server-marked false'
);

select is(
  (
    select (learning.mark_evidence_response(
      question.id,
      jsonb_build_object('categoryId', 'Penetration testing'),
      question.max_score
    )).is_correct
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week7-testing-matching'
      and version.version = '1.1.0'
      and question.stable_key = 'M1'
  ),
  true,
  'correct classification category is server-marked true'
);

select is(
  (
    select (learning.mark_evidence_response(
      question.id,
      jsonb_build_object('categoryId', 'Fuzzing'),
      question.max_score
    )).is_correct
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week7-testing-matching'
      and version.version = '1.1.0'
      and question.stable_key = 'M1'
  ),
  false,
  'wrong classification category is server-marked false'
);

select ok(
  (
    select mark.requires_review
       and mark.is_correct is null
       and mark.awarded_score = 0
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object('text', 'forged', 'is_correct', true, 'awarded_score', 6),
      question.max_score
    ) as mark
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.2.0'
      and question.stable_key = 'W2OCR-Q08'
  ),
  'requires_review OCR extended responses stay pending and unscored'
);

select ok(
  (
    select mark.requires_review
       and mark.is_correct is null
       and mark.awarded_score = 0
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object('text', 'peer reflection'),
      question.max_score
    ) as mark
    where activity.stable_key = 'u3-w01-peer-improvement'
      and version.version = '1.2.0'
      and question.stable_key = 'PM-Q02'
  ),
  'completion items are pending evidence, not automatic full marks'
);

select is(
  (
    select (learning.mark_evidence_response(
      question.id,
      jsonb_build_object('optionId', 'b'),
      question.max_score
    )).is_correct
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week5-vulnerability-patterns'
      and version.version = '1.0.0'
      and question.stable_key = 'P1'
  ),
  false,
  'unchanged Week 5 specs still reject the wrong option'
);

select is(
  (
    select (learning.mark_evidence_response(
      question.id,
      jsonb_build_object('optionId', 'a'),
      question.max_score
    )).is_correct
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week5-vulnerability-patterns'
      and version.version = '1.0.0'
      and question.stable_key = 'P1'
  ),
  true,
  'unchanged Week 5 specs still accept the correct option'
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
  'OCR 1.0.0 question rows remain seven'
);

select ok(
  not exists (
    select 1
    from platform.curriculum_publications
    where hub_code = 'unit-3-cyber-security'
      and package_version = '0.2.10'
  ),
  'Batch B does not publish curriculum 0.2.10'
);

select throws_ok(
  $$
    insert into learning.question_marking (question_id, spec)
    select question.id, '{"mode":"completion"}'::jsonb
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-malware-symptoms'
      and version.version = '1.0.0'
      and question.stable_key = 'MW-Q1'
  $$,
  '55000',
  'PUBLISHED_QUESTION_MARKING_IMMUTABLE',
  'published historical versions still reject in-place marking backfill'
);

select lives_ok(
  $$select learning.apply_unit3_batch_b_marking('[]'::jsonb)$$,
  'empty Batch B replay is idempotent'
);

select * from finish();
rollback;
