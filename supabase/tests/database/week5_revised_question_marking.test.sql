begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(8);

select is(
  (
    select count(*)
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity_version.version = '1.2.0'
      and activity.stable_key like 'week5-%'
  ),
  79::bigint,
  'every revised Week 5 catalogue question is registered on version 1.2.0'
);

select is(
  (
    select marking.spec->>'correctCategoryId'
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity.stable_key = 'week5-ransomware-companion'
      and activity_version.version = '1.2.0'
      and question.stable_key = 'SPOT-1'
  ),
  'Disruption',
  'Spot the impact item SPOT-1 is a classification question'
);

select is(
  (
    select marking.spec->>'correctOptionId'
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity.stable_key = 'week5-impacts-learning'
      and activity_version.version = '1.2.0'
      and question.stable_key = 'K5'
  ),
  'a',
  'Impacts Learning K5 is marked against the revised option'
);

select is(
  (
    select marking.spec->>'mode'
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity.stable_key = 'week5-exercise-debrief'
      and activity_version.version = '1.2.0'
      and question.stable_key = 'DB2'
  ),
  'ordering-exact',
  'the debrief chain is automatically ordered'
);

select is(
  (
    select count(*)
    from learning.activity_versions as activity_version
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity.stable_key = 'week5-ocr-question-practice'
      and activity_version.version = '1.2.0'
  ),
  0::bigint,
  'Week 5 OCR stays on its existing host catalogue version'
);

select is(
  (
    select count(*)
    from learning.activity_versions as activity_version
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity.stable_key like 'week4-%'
      and activity_version.version = '1.2.0'
  ),
  0::bigint,
  'Week 4 marking versions are unchanged'
);

select ok(
  (
    select bool_and(activity_version.published_at is not null)
    from learning.activity_versions as activity_version
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity_version.version = '1.2.0'
      and activity.stable_key like 'week5-%'
  ),
  'the new Week 5 marking versions are published'
);

select is(
  (
    select count(*)
    from learning.questions as old_question
    join learning.activity_versions as old_version
      on old_version.id = old_question.activity_version_id
    join learning.activities as activity on activity.id = old_version.activity_id
    where activity.stable_key = 'week5-ransomware-companion'
      and old_version.version = '1.0.0'
      and old_question.stable_key = 'RC1'
  ),
  1::bigint,
  'the previous ransomware question rows are still present'
);

select * from finish();

rollback;
