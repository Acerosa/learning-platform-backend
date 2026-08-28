begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(17);

create function pg_temp.tlevel_weeks_package(
  p_version text,
  p_week1_status text default 'planned',
  p_week2_status text default 'planned',
  p_week3_status text default 'planned',
  p_week1_title text default 'Week 1 title'
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'schema', 'lp.content.package',
    'schemaVersion', '0.1.0',
    'id', 'tlevel-software-development-content',
    'version', p_version,
    'hub', jsonb_build_object(
      'schema', 'lp.content.hub',
      'schemaVersion', '0.1.0',
      'id', 'tlevel-software-development',
      'version', '0.1.0',
      'metadata', jsonb_build_object('name', 'T Level Digital Software Development Hub'),
      'relationships', jsonb_build_object('curriculum', 'tlevel-software-development-curriculum')
    ),
    'curriculum', jsonb_build_object(
      'schema', 'lp.content.curriculum',
      'schemaVersion', '0.1.0',
      'id', 'tlevel-software-development-curriculum',
      'version', '0.1.0',
      'metadata', jsonb_build_object(
        'title', 'T Level Digital Software Development',
        'course', 't-level-digital-software-development'
      ),
      'relationships', jsonb_build_object(
        'learningOutcomes', '[]'::jsonb,
        'assignments', '[]'::jsonb,
        'weeks', jsonb_build_array('week-1', 'week-2', 'week-3')
      )
    ),
    'learningOutcomes', '[]'::jsonb,
    'assignments', '[]'::jsonb,
    'weeks', jsonb_build_array(
      jsonb_build_object(
        'schema', 'lp.content.week',
        'schemaVersion', '0.1.0',
        'id', 'week-1',
        'version', '0.1.0',
        'metadata', jsonb_build_object(
          'title', p_week1_title,
          'teachingWeek', 1,
          'status', p_week1_status
        ),
        'relationships', jsonb_build_object('sessions', '[]'::jsonb)
      ),
      jsonb_build_object(
        'schema', 'lp.content.week',
        'schemaVersion', '0.1.0',
        'id', 'week-2',
        'version', '0.1.0',
        'metadata', jsonb_build_object(
          'title', 'Week 2 title',
          'teachingWeek', 2,
          'status', p_week2_status
        ),
        'relationships', jsonb_build_object('sessions', '[]'::jsonb)
      ),
      jsonb_build_object(
        'schema', 'lp.content.week',
        'schemaVersion', '0.1.0',
        'id', 'week-3',
        'version', '0.1.0',
        'metadata', jsonb_build_object(
          'title', 'Week 3 title',
          'teachingWeek', 3,
          'status', p_week3_status
        ),
        'relationships', jsonb_build_object('sessions', '[]'::jsonb)
      )
    ),
    'sessions', '[]'::jsonb,
    'activities', '[]'::jsonb,
    'questions', '[]'::jsonb,
    'assets', '[]'::jsonb
  )
$$;

-- Ground the T Level hub module and a legacy foundations row at teaching week 1.
insert into learning.modules (id, course_id, stable_key, title, sort_order, active)
select
  platform.curriculum_catalogue_id(
    'module', 't-level-digital-software-development:tlevel-software-development'
  ),
  course.id,
  'tlevel-software-development',
  'T Level Digital Software Development',
  0,
  true
from learning.courses as course
where course.stable_key = 't-level-digital-software-development'
on conflict (course_id, stable_key) do nothing;

insert into learning.curriculum_weeks (
  id, module_id, stable_key, title, week_number, sort_order, active
)
select
  platform.curriculum_catalogue_id(
    'week', 't-level-digital-software-development:tlevel-software-development:foundations'
  ),
  platform.curriculum_catalogue_id(
    'module', 't-level-digital-software-development:tlevel-software-development'
  ),
  'foundations',
  'Technical Foundations',
  1,
  1,
  true
where not exists (
  select 1
  from learning.curriculum_weeks as week
  join learning.modules as module on module.id = week.module_id
  where module.stable_key = 'tlevel-software-development'
    and week.week_number = 1
);

select ok(
  exists (
    select 1
    from learning.curriculum_weeks as week
    join learning.modules as module on module.id = week.module_id
    where module.stable_key = 'tlevel-software-development'
      and week.stable_key = 'foundations'
      and week.week_number = 1
  ),
  'legacy foundations week row exists at teaching week 1 before projection'
);

insert into learning.modules (id, course_id, stable_key, title, sort_order, active)
select
  platform.curriculum_catalogue_id(
    'module', 't-level-digital-software-development:projection-conflict-test'
  ),
  course.id,
  'projection-conflict-test',
  'Projection conflict test module',
  99,
  true
from learning.courses as course
where course.stable_key = 't-level-digital-software-development'
on conflict (course_id, stable_key) do nothing;

insert into learning.curriculum_weeks (
  id, module_id, stable_key, title, week_number, sort_order, active
)
values
  (
    '11111111-1111-4111-8111-111111111101',
    platform.curriculum_catalogue_id(
      'module', 't-level-digital-software-development:projection-conflict-test'
    ),
    'slot-one-alpha',
    'Alpha slot',
    1,
    1,
    true
  ),
  (
    '11111111-1111-4111-8111-111111111102',
    platform.curriculum_catalogue_id(
      'module', 't-level-digital-software-development:projection-conflict-test'
    ),
    'week-beta',
    'Beta slot',
    2,
    2,
    true
  )
on conflict do nothing;

select throws_ok(
  $$select platform.project_curriculum_package(
    jsonb_build_object(
      'hub', jsonb_build_object('metadata', jsonb_build_object('title', 'Conflict hub')),
      'curriculum', jsonb_build_object('metadata', jsonb_build_object('title', 'Conflict curriculum')),
      'weeks', jsonb_build_array(
        jsonb_build_object(
          'id', 'week-beta',
          'metadata', jsonb_build_object('title', 'Beta re-slot', 'teachingWeek', 1)
        )
      ),
      'learningOutcomes', '[]'::jsonb,
      'sessions', '[]'::jsonb,
      'activities', '[]'::jsonb
    ),
    'projection-conflict-test',
    't-level-digital-software-development',
    '9.9.9',
    null
  )$$,
  '22023',
  'CATALOGUE_PROJECTION_CONFLICT',
  'irreconcilable stable-key and week-number identities raise an intentional platform error'
);

create temp table pg_temp.week_projection_fixture as
select week.id as legacy_week_id
from learning.curriculum_weeks as week
join learning.modules as module on module.id = week.module_id
where module.stable_key = 'tlevel-software-development'
  and week.stable_key = 'foundations'
  and week.week_number = 1;

grant select on pg_temp.week_projection_fixture to authenticated;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  format(
    $sql$select admin_api.publish_curriculum(
      'published',
      'tlevel-software-development',
      't-level-digital-software-development',
      '0.3.0',
      '0.1.0',
      '0.1.0',
      %L::jsonb,
      'Regression Author',
      'Regression Reviewer',
      'Week visibility baseline.'
    )$sql$,
    pg_temp.tlevel_weeks_package('0.3.0')::text
  ),
  'publication succeeds when package week-1 reconciles legacy foundations row'
);

select is(
  (
    select count(*)::bigint
    from learning.curriculum_weeks as week
    join learning.modules as module on module.id = week.module_id
    where module.stable_key = 'tlevel-software-development'
  ),
  3::bigint,
  'projection creates three catalogue weeks without duplicate teaching slots'
);

select is(
  (
    select week.stable_key
    from learning.curriculum_weeks as week
    join learning.modules as module on module.id = week.module_id
    where module.stable_key = 'tlevel-software-development'
      and week.week_number = 1
  ),
  'week-1',
  'teaching week 1 stable key is reconciled to week-1'
);

select is(
  (
    select week.id
    from learning.curriculum_weeks as week
    join learning.modules as module on module.id = week.module_id
    where module.stable_key = 'tlevel-software-development'
      and week.week_number = 1
  ),
  (select legacy_week_id from pg_temp.week_projection_fixture),
  'legacy week row id is preserved when stable key changes'
);

select is(
  (
    select package_version
    from admin_api.publish_curriculum(
      'published',
      'tlevel-software-development',
      't-level-digital-software-development',
      '0.3.1',
      '0.1.0',
      '0.1.0',
      pg_temp.tlevel_weeks_package('0.3.1', 'planned', 'planned', 'available'),
      'Regression Author',
      'Regression Reviewer',
      'Week visibility: post week-3'
    )
  ),
  '0.3.1',
  'successive publication 0.3.0 to 0.3.1 succeeds after week reconciliation'
);

select is(
  (
    select status
    from platform.curriculum_publications
    where hub_code = 'tlevel-software-development'
      and course_key = 't-level-digital-software-development'
      and package_version = '0.3.0'
  ),
  'superseded',
  '0.3.0 publication is superseded by 0.3.1'
);

select is(
  (
    select status
    from platform.curriculum_publications
    where hub_code = 'tlevel-software-development'
      and course_key = 't-level-digital-software-development'
      and package_version = '0.3.1'
  ),
  'published',
  '0.3.1 publication is published'
);

select is(
  (
    select package->>'version'
    from api.published_curriculum_package(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  '0.3.1',
  'published package version is 0.3.1 after week visibility publication'
);

select is(
  (
    select package->'weeks'->2->'metadata'->>'status'
    from api.published_curriculum_package(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'available',
  'published package exposes week-3 as available after visibility publication'
);

select is(
  (
    select package->'weeks'->0->'metadata'->>'status'
    from api.published_curriculum_package(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'planned',
  'published package keeps week-1 planned after week-3 visibility publication'
);

select is(
  (
    select idempotent
    from admin_api.publish_curriculum(
      'published',
      'tlevel-software-development',
      't-level-digital-software-development',
      '0.3.1',
      '0.1.0',
      '0.1.0',
      pg_temp.tlevel_weeks_package('0.3.1', 'planned', 'planned', 'available'),
      'Regression Author',
      'Regression Reviewer',
      'Week visibility: post week-3'
    )
  ),
  true,
  'retrying the same published snapshot remains idempotent'
);

select is(
  (
    select count(*)::bigint
    from learning.curriculum_weeks as week
    join learning.modules as module on module.id = week.module_id
    where module.stable_key = 'tlevel-software-development'
  ),
  3::bigint,
  'idempotent republication does not create duplicate curriculum week rows'
);

select is(
  (
    select package_version
    from admin_api.publish_curriculum(
      'published',
      'tlevel-software-development',
      't-level-digital-software-development',
      '0.3.2',
      '0.1.0',
      '0.1.0',
      pg_temp.tlevel_weeks_package('0.3.2', 'planned', 'planned', 'available', 'Updated Week 1 title'),
      'Regression Author',
      'Regression Reviewer',
      'Title-only week metadata refresh.'
    )
  ),
  '0.3.2',
  'a newer publication version with the same weeks updates projection metadata'
);

select is(
  (
    select week.title
    from learning.curriculum_weeks as week
    join learning.modules as module on module.id = week.module_id
    where module.stable_key = 'tlevel-software-development'
      and week.stable_key = 'week-1'
  ),
  'Updated Week 1 title',
  'catalogue week title updates without changing week identity'
);

select is(
  (
    select count(*)::bigint
    from learning.curriculum_weeks as week
    join learning.modules as module on module.id = week.module_id
    where module.stable_key = 'tlevel-software-development'
  ),
  3::bigint,
  'successive publication versions do not create duplicate curriculum week rows'
);

select * from finish();

rollback;
