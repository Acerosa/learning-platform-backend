begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(4);

-- Classification projection must emit authoritative questionId:itemId keys,
-- matching hub formative markBlock calls for expanded L2E Weeks 2–3 activities.

create function pg_temp.class_package()
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'hub', jsonb_build_object(
      'schema', 'lp.content.hub',
      'schemaVersion', '0.1.0',
      'id', 'l2e-exploring-emerging-digital-technologies',
      'version', '0.1.0',
      'metadata', jsonb_build_object('name', 'L2E'),
      'relationships', jsonb_build_object('curriculum', 'l2e-curriculum')
    ),
    'curriculum', jsonb_build_object(
      'schema', 'lp.content.curriculum',
      'schemaVersion', '0.1.0',
      'id', 'l2e-curriculum',
      'version', '0.1.0',
      'metadata', jsonb_build_object('title', 'L2E', 'course', 'gateway-level-2-digital-it-skills'),
      'relationships', jsonb_build_object(
        'learningOutcomes', '[]'::jsonb,
        'assignments', '[]'::jsonb,
        'weeks', jsonb_build_array('week-2')
      )
    ),
    'learningOutcomes', '[]'::jsonb,
    'assignments', '[]'::jsonb,
    'weeks', jsonb_build_array(
      jsonb_build_object(
        'schema', 'lp.content.week',
        'schemaVersion', '0.1.0',
        'id', 'week-2',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Week 2', 'teachingWeek', 2),
        'relationships', jsonb_build_object('sessions', jsonb_build_array('week-2-session'))
      )
    ),
    'sessions', jsonb_build_array(
      jsonb_build_object(
        'schema', 'lp.content.session',
        'schemaVersion', '0.1.0',
        'id', 'week-2-session',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Session', 'kind', 'session'),
        'relationships', jsonb_build_object(
          'week', 'week-2',
          'activities', jsonb_build_array('week-2-iot-sectors-fixture')
        )
      )
    ),
    'activities', jsonb_build_array(
      jsonb_build_object(
        'schema', 'lp.content.activity',
        'schemaVersion', '0.1.0',
        'id', 'week-2-iot-sectors-fixture',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'IoT sectors fixture'),
        'relationships', jsonb_build_object(),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'schema', 'lp.content.block',
            'schemaVersion', '0.1.0',
            'id', 'week-2-iot-sectors-q',
            'version', '0.1.0',
            'type', 'classification',
            'metadata', jsonb_build_object(),
            'relationships', jsonb_build_object(),
            'content', jsonb_build_object(
              'questionId', 'week-2-iot-sectors-q',
              'prompt', 'Sort the examples',
              'categories', jsonb_build_array(
                jsonb_build_object('id', 'consumer', 'label', 'Consumer'),
                jsonb_build_object('id', 'industrial', 'label', 'Industrial')
              ),
              'items', jsonb_build_array(
                jsonb_build_object('id', 's1', 'label', 'Smart speaker', 'correctCategoryId', 'consumer'),
                jsonb_build_object('id', 's2', 'label', 'Factory sensor', 'correctCategoryId', 'industrial')
              ),
              'formative', true
            )
          ),
          jsonb_build_object(
            'schema', 'lp.content.block',
            'schemaVersion', '0.1.0',
            'id', 'week-2-iot-sectors-sc',
            'version', '0.1.0',
            'type', 'single-choice',
            'metadata', jsonb_build_object(),
            'relationships', jsonb_build_object(),
            'content', jsonb_build_object(
              'questionId', 'week-2-iot-sectors-sc-q',
              'prompt', 'Pick one',
              'options', jsonb_build_array(
                jsonb_build_object('id', 'a', 'label', 'A'),
                jsonb_build_object('id', 'b', 'label', 'B')
              ),
              'correctOptionId', 'a',
              'formative', true
            )
          )
        )
      )
    ),
    'assets', '[]'::jsonb
  );
$$;

insert into learning.academic_years (id, code, starts_on, ends_on, active)
select
  'a1000000-0000-4000-8000-0000000000c2'::uuid,
  '2026-27-L2E-CATALOGUE-TEST',
  '2026-09-01'::date,
  '2027-08-31'::date,
  true
where not exists (select 1 from learning.academic_years where active);

insert into learning.courses (
  id, stable_key, code, title, qualification_level, active
)
select
  'c5000000-0000-4000-8000-0000000000c2'::uuid,
  'gateway-level-2-digital-it-skills',
  'GW-L2-DITS-CAT',
  'Gateway Level 2 Digital and IT Skills (catalogue test)',
  'Level 2',
  true
where not exists (
  select 1 from learning.courses where stable_key = 'gateway-level-2-digital-it-skills'
);

insert into learning.modules (
  id, course_id, stable_key, title, sort_order, active
)
select
  'c5100000-0000-4000-8000-0000000000c2'::uuid,
  course.id,
  'l2e-exploring-emerging-digital-technologies',
  'Exploring New and Emerging Digital Technologies',
  1,
  true
from learning.courses as course
where course.stable_key = 'gateway-level-2-digital-it-skills'
  and not exists (
    select 1
    from learning.modules as module
    where module.course_id = course.id
      and module.stable_key = 'l2e-exploring-emerging-digital-technologies'
  );

select lives_ok(
  $$
    select platform.project_curriculum_package(
      pg_temp.class_package(),
      'l2e-exploring-emerging-digital-technologies',
      'gateway-level-2-digital-it-skills',
      '0.0.0-catalogue-fixture',
      null
    );
  $$,
  'project_curriculum_package accepts classification fixture'
);

select ok(
  exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'week-2-iot-sectors-fixture'
      and question.stable_key = 'week-2-iot-sectors-q:s1'
  ),
  'classification item projects as week-2-iot-sectors-q:s1'
);

select ok(
  exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    join learning.question_marking as marking
      on marking.question_id = question.id
    where activity.stable_key = 'week-2-iot-sectors-fixture'
      and question.stable_key = 'week-2-iot-sectors-sc-q'
      and marking.spec->>'mode' = 'single-choice'
  ),
  'single-choice projects with marking spec'
);

select ok(
  (
    select count(*)
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'week-2-iot-sectors-fixture'
  ) = 3,
  'fixture yields two classification items plus one single-choice'
);

select * from finish();
rollback;
