begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select ok(
  exists (
    select 1
    from platform.hubs
    where hub_code = 'unit-14-software-engineering-for-business'
      and active
      and status = 'testing'
      and manifest_version = '1.0.0'
      and manifest_sha256 ~ '^[0-9a-f]{64}$'
  ),
  'Unit 14 hub is registered with reviewed manifest provenance'
);

select ok(
  exists (
    select 1
    from platform.hub_course_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.courses as course on course.id = link.course_id
    where hub.hub_code = 'unit-14-software-engineering-for-business'
      and course.stable_key = 'ocr-level-3-it'
      and link.active
  ),
  'Unit 14 hub is linked to the OCR Level 3 IT course'
);

select ok(
  exists (
    select 1
    from learning.modules as module
    join learning.courses as course on course.id = module.course_id
    where course.stable_key = 'ocr-level-3-it'
      and module.stable_key = 'unit-14-software-engineering-for-business'
      and module.sort_order = 14
      and module.active
  ),
  'Unit 14 module exists under OCR Level 3 IT'
);

select is(
  (
    select count(*)::int
    from learning.topics as topic
    join learning.modules as module on module.id = topic.module_id
    where module.stable_key = 'unit-14-software-engineering-for-business'
  ),
  4,
  'Unit 14 learning outcomes are registered as topics lo1–lo4'
);

select is(
  (
    select count(*)::int
    from learning.curriculum_weeks as week
    join learning.modules as module on module.id = week.module_id
    where module.stable_key = 'unit-14-software-engineering-for-business'
  ),
  19,
  'Unit 14 has 19 curriculum week metadata records'
);

select is(
  (
    select count(*)::int
    from learning.activities as activity
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-14-software-engineering-for-business'
  ),
  11,
  'Week 1 registers 11 activities with canonical ids'
);

select is(
  (
    select count(*)::int
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-14-software-engineering-for-business'
      and version.version = '0.1.0'
      and version.published_at is not null
      and version.retired_at is null
  ),
  11,
  'Week 1 activity versions 0.1.0 are published and not retired'
);

select ok(
  (
    select bool_and(activity.stable_key in (
      'week-1-baseline-diagnostic',
      'week-1-business-data-explorer',
      'week-1-variables-and-data-types',
      'week-1-input-and-output',
      'week-1-github-classroom-guidance',
      'week-1-review',
      'week-1-guided-business-data',
      'week-1-first-commits',
      'week-1-first-python-business-program',
      'week-1-assignment-1-guide',
      'week-1-homework-extension'
    ))
    from learning.activities as activity
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-14-software-engineering-for-business'
  ),
  'registered activity keys preserve the canonical Week 1 identifiers'
);

select is(
  (
    select count(*)::int
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week-1-baseline-diagnostic'
  ),
  4,
  'baseline diagnostic has four registered questions'
);

select ok(
  exists (
    select 1
    from learning.questions as question
    where question.stable_key = 'u14-w1-biz-class:customer-name'
  ),
  'classification items use the deterministic questionId:itemId key'
);

select is(
  (
    select count(*)::int
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-14-software-engineering-for-business'
  ),
  (
    select count(*)::int
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-14-software-engineering-for-business'
  ),
  'every Unit 14 question has a protected marking specification'
);

select is(
  (
    select count(*)::int
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    where learner_group.code = 'UNIT14-TEST-A'
      and assignment.active
  ),
  11,
  'UNIT14-TEST-A has the 11 published Week 1 activity assignments'
);

select ok(
  exists (
    select 1
    from learning.groups as learner_group
    join learning.courses as course on course.id = learner_group.course_id
    where learner_group.code = 'UNIT14-TEST-A'
      and course.stable_key = 'ocr-level-3-it'
      and learner_group.active
      and learner_group.registration_open = false
      and learner_group.registration_key = 'unit14-year-1-test'
  ),
  'Unit 14 synthetic group is closed so it does not add a public registration option'
);

select lives_ok(
  $$
    insert into learning.modules (id, course_id, stable_key, title, sort_order, active)
    select id, course_id, stable_key, title, sort_order, active
    from learning.modules
    where stable_key = 'unit-14-software-engineering-for-business'
    on conflict (course_id, stable_key) do update set title = excluded.title
  $$,
  'duplicate module import is idempotent'
);

select is(
  (
    select count(*)::int
    from learning.modules
    where stable_key = 'unit-14-software-engineering-for-business'
  ),
  1,
  're-importing the Unit 14 module does not duplicate it'
);

select throws_ok(
  $$
    update learning.activity_versions
    set content_hash = repeat('a', 64)
    from learning.activities as activity
    where activity.id = activity_versions.activity_id
      and activity.stable_key = 'week-1-baseline-diagnostic'
      and activity_versions.published_at is not null
  $$,
  '55000',
  'PUBLISHED_ACTIVITY_VERSION_IMMUTABLE',
  'published Unit 14 activity versions cannot be silently mutated'
);

select throws_ok(
  $$
    insert into learning.question_marking (question_id, spec)
    select question.id, '{"mode":"completion"}'::jsonb
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week-1-assignment-1-guide'
    on conflict (question_id) do update set spec = excluded.spec
  $$,
  '55000',
  'PUBLISHED_QUESTION_MARKING_IMMUTABLE',
  'published formative marking specifications remain immutable'
);

select * from finish();
rollback;
