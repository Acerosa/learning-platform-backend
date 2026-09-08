begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(7);

-- Local CI seed does not include Gateway L2 / L2E catalogue rows. Create the
-- minimum course graph needed to exercise delivery activation, then run the
-- same upsert shape as the migration.

insert into learning.academic_years (
  id, code, starts_on, ends_on, active
)
select
  'a1000000-0000-4000-8000-0000000000b2'::uuid,
  '2026-27-L2E-DELIVERY-TEST',
  '2026-09-01'::date,
  '2027-08-31'::date,
  true
where not exists (
  select 1 from learning.academic_years where active
);

insert into learning.courses (
  id, stable_key, code, title, qualification_level, active
)
select
  'c5000000-0000-4000-8000-0000000000b2'::uuid,
  'gateway-level-2-digital-it-skills',
  'GW-L2-DITS-TEST',
  'Gateway Level 2 Digital and IT Skills (test)',
  'Level 2',
  true
where not exists (
  select 1 from learning.courses where stable_key = 'gateway-level-2-digital-it-skills'
);

insert into learning.modules (
  id, course_id, stable_key, title, sort_order, active
)
select
  'c5100000-0000-4000-8000-0000000000b2'::uuid,
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

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
)
select
  'a5100000-0000-4000-8000-0000000000b2'::uuid,
  module.id,
  'week-1-digital-technology',
  'What is digital technology?',
  'guided-activity',
  'supabase/tests/database/l2e_formative_delivery.test.sql',
  true
from learning.modules as module
where module.stable_key = 'l2e-exploring-emerging-digital-technologies'
  and not exists (
    select 1 from learning.activities where stable_key = 'week-1-digital-technology'
  );

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count, published_at
)
select
  'b5100000-0000-4000-8000-0000000000b2'::uuid,
  activity.id,
  '0.1.0',
  'l2e-delivery-test-hash',
  4,
  4,
  clock_timestamp()
from learning.activities as activity
where activity.stable_key = 'week-1-digital-technology'
  and not exists (
    select 1
    from learning.activity_versions as version
    where version.activity_id = activity.id
      and version.version = '0.1.0'
  );

select lives_ok(
  $$
    insert into learning.groups (
      id, academic_year_id, course_id, code, name, active, year_group,
      registration_key, registration_open, is_synthetic, synthetic_purpose
    )
    select
      '60000000-0000-4000-8000-0000000000a2'::uuid,
      academic_year.id,
      course.id,
      'L2E-DELIVERY-A',
      'L2E Gateway Delivery Group A',
      true,
      'Year 1',
      'l2e-year-1-delivery',
      true,
      false,
      null
    from learning.courses as course
    join lateral (
      select candidate.id
      from learning.academic_years as candidate
      where candidate.active
      order by candidate.code
      limit 1
    ) as academic_year on true
    where course.stable_key = 'gateway-level-2-digital-it-skills'
      and course.active
    on conflict (academic_year_id, course_id, code) do update
    set
      name = excluded.name,
      active = excluded.active,
      year_group = excluded.year_group,
      registration_key = excluded.registration_key,
      registration_open = excluded.registration_open,
      is_synthetic = false,
      synthetic_purpose = null;

    insert into learning.activity_assignments (
      id, group_id, activity_version_id, required, active
    )
    select
      md5(
        'l2e-delivery-activation:'
        || learner_group.id::text
        || ':'
        || activity_version.id::text
      )::uuid,
      learner_group.id,
      activity_version.id,
      true,
      true
    from learning.groups as learner_group
    join learning.courses as course
      on course.id = learner_group.course_id
    join learning.modules as module
      on module.course_id = course.id
    join learning.activities as activity
      on activity.module_id = module.id
    join learning.activity_versions as activity_version
      on activity_version.activity_id = activity.id
    where learner_group.code = 'L2E-DELIVERY-A'
      and course.stable_key = 'gateway-level-2-digital-it-skills'
      and module.stable_key = 'l2e-exploring-emerging-digital-technologies'
      and activity.active
      and activity_version.published_at is not null
      and activity_version.retired_at is null
    on conflict (group_id, activity_version_id) do update
    set
      required = excluded.required,
      active = excluded.active;
  $$,
  'L2E delivery activation upserts an open teaching group and published assignments'
);

select ok(
  exists (
    select 1
    from learning.groups as learner_group
    join learning.courses as course on course.id = learner_group.course_id
    where learner_group.code = 'L2E-DELIVERY-A'
      and course.stable_key = 'gateway-level-2-digital-it-skills'
      and learner_group.active
      and learner_group.registration_open
      and coalesce(learner_group.is_synthetic, false) = false
  ),
  'L2E-DELIVERY-A is an open non-synthetic teaching group for Gateway L2'
);

select ok(
  exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'L2E-DELIVERY-A'
      and assignment.active
      and activity.stable_key = 'week-1-digital-technology'
  ),
  'week-1-digital-technology is assigned to L2E-DELIVERY-A'
);

select lives_ok(
  $$select * from learning.ensure_synthetic_qa_groups()$$,
  'ensure_synthetic_qa_groups remains callable after delivery activation'
);

select ok(
  exists (
    select 1
    from learning.groups as learner_group
    where learner_group.code = 'L2E-TEST-A'
      and learner_group.is_synthetic
      and learner_group.registration_open = false
  ),
  'exclusive-smoke L2E-TEST-A remains closed and synthetic'
);

select ok(
  not exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'L2E-TEST-A'
      and assignment.active
      and activity.stable_key like 'week-[23]-%'
  ),
  'L2E-TEST-A exclusive allowlist is not expanded to Week 2/3 by delivery activation'
);

select is(
  (
    select count(*)::int
    from (
      select assignment.group_id, assignment.activity_version_id
      from learning.activity_assignments as assignment
      join learning.groups as learner_group on learner_group.id = assignment.group_id
      where learner_group.code = 'L2E-DELIVERY-A'
        and assignment.active
      group by assignment.group_id, assignment.activity_version_id
      having count(*) > 1
    ) as duplicates
  ),
  0,
  'L2E-DELIVERY-A has no duplicate activity assignments'
);

select * from finish();
rollback;
