begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(12);

select is(
  (
    select count(*)::int
    from learning.synthetic_qa_smoke_activities
    where persona = 'L2E_TEST_LEARNER'
  ),
  10,
  'L2E QA allowlist catalogues ten published Week 1 Check-answer activities'
);

select ok(
  not exists (
    select 1
    from learning.synthetic_qa_smoke_activities
    where persona = 'L2E_TEST_LEARNER'
      and activity_key in (
        'week-1-reflection',
        'week-2-classify',
        'week-2-retrieval',
        'week-3-classify',
        'week-3-retrieval'
      )
  ),
  'L2E QA allowlist excludes review-only and later-week activities'
);

select is(
  (
    select count(*)::int
    from learning.synthetic_qa_smoke_activities
    where persona = 'UNIT3_TEST_LEARNER'
  ),
  1,
  'Unit 3 QA allowlist remains a single smoke activity'
);

select is(
  (
    select count(*)::int
    from learning.synthetic_qa_smoke_activities
    where persona = 'TLEVEL_TEST_LEARNER'
  ),
  1,
  'T Level QA allowlist remains a single smoke activity'
);

select lives_ok(
  $$select * from learning.ensure_synthetic_qa_groups()$$,
  'ensure_synthetic_qa_groups remains idempotent after the Week 1 allowlist'
);

select is(
  (
    select count(*)::int
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'CYBER-TEST-QA'
      and assignment.active
  ),
  1,
  'CYBER-TEST-QA still has exactly one active assignment'
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
      and activity.stable_key = 'week-1-reflection'
  ),
  'L2E-TEST-A is not assigned the review-only reflection activity'
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
  'L2E-TEST-A is not assigned published Week 2 or Week 3 activities'
);

select is(
  (
    select count(*)::int
    from (
      select assignment.group_id, assignment.activity_version_id
      from learning.activity_assignments as assignment
      join learning.groups as learner_group on learner_group.id = assignment.group_id
      where learner_group.code = 'L2E-TEST-A'
        and assignment.active
      group by assignment.group_id, assignment.activity_version_id
      having count(*) > 1
    ) as duplicates
  ),
  0,
  'ensure_synthetic_qa_groups does not create duplicate L2E assignments'
);

select lives_ok(
  $$
    insert into learning.activity_assignments (
      id, group_id, activity_version_id, required, active
    )
    select
      '60000000-0000-4000-8000-000000000099'::uuid,
      learner_group.id,
      version.id,
      true,
      true
    from learning.groups as learner_group
    join learning.activities as activity
      on activity.stable_key = 'week-2-classify'
    join learning.activity_versions as version
      on version.activity_id = activity.id
    where learner_group.code = 'L2E-TEST-A'
      and version.published_at is not null
      and version.retired_at is null
    limit 1
  $$,
  'exclusive-smoke guard swallows an uncatalogued Week 2 assignment insert'
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
      and activity.stable_key = 'week-2-classify'
  ),
  'exclusive-smoke guard does not store an uncatalogued Week 2 assignment'
);

select ok(
  exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'L2E-TEST-A'
      and assignment.active
      and activity.stable_key = 'week-1-welcome'
      and version.retired_at is null
      and version.published_at is not null
  )
  or not exists (
    select 1
    from learning.activities as activity
    join learning.activity_versions as version
      on version.activity_id = activity.id
    where activity.stable_key = 'week-1-welcome'
      and version.published_at is not null
      and version.retired_at is null
  ),
  'week-1-welcome is assigned when that published version exists'
);

select * from finish();
rollback;
