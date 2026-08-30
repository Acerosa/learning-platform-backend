begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(12);

select is(
  (
    select package_version
    from platform.curriculum_publications
    where hub_code = 'unit-3-cyber-security'
      and course_key = 'ocr-level-3-it'
      and status = 'published'
  ),
  '0.2.0',
  'Unit 3 has a current published curriculum package'
);

select is(
  (
    select jsonb_array_length(package->'activities')
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it')
  ),
  76,
  'the Unit 3 learner package contains the 76 migrated activities'
);

select is(
  (
    select package->>'version'
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it')
  ),
  '0.2.0',
  'the Unit 3 learner package carries publication version 0.2.0'
);

select is(
  (
    select package->'curriculum'->'metadata'->>'course'
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it')
  ),
  'ocr-level-3-it',
  'the Unit 3 package keeps the OCR course identity'
);

select is(
  (
    select package_version
    from platform.curriculum_publications
    where hub_code = 'tlevel-software-development'
      and course_key = 't-level-digital-software-development'
      and status = 'published'
  ),
  '0.2.0',
  'T Level has a current published curriculum package'
);

select is(
  (
    select jsonb_array_length(package->'activities')
    from api.published_curriculum_package(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  5,
  'the T Level learner package contains the five Foundations activities'
);

select is(
  (
    select package->'curriculum'->'metadata'->>'course'
    from api.published_curriculum_package(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  't-level-digital-software-development',
  'the T Level package uses the registered T Level course'
);

select is(
  (
    select package_version
    from platform.curriculum_publications
    where hub_code = 'unit-14-software-engineering-for-business'
      and course_key = 'ocr-level-3-it'
      and status = 'published'
  ),
  '0.2.0',
  'Unit 14 remains published after the static-hub migration seed'
);

select is(
  (
    select count(*)
    from platform.curriculum_publications
    where hub_code = 'unit-3-cyber-security'
      and package_version = '0.2.0'
  ),
  1::bigint,
  'the Unit 3 migrated publication is not duplicated'
);

select is(
  (
    select version.version
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-threat-vulnerability-sort'
    order by version.version
    limit 1
  ),
  '1.0.0',
  'existing Unit 3 activity versions remain 1.0.0 after publication'
);

select is(
  (
    select version.version
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'foundations-programming-diagnostic'
  ),
  '2.0.0',
  'the Programming Diagnostic version remains 2.0.0'
);

select is(
  (
    select count(*)::int
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    where module.stable_key = 'unit-3-cyber-security'
  ),
  592,
  'Unit 3 historical question rows remain and Batch A1 adds the missing banks'
);

select * from finish();
rollback;
