begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(6);

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

select ok(
  (
    select count(*)::int
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    join learning.modules as module on module.id = activity.module_id
    where learner_group.code = 'L2E-DELIVERY-A'
      and assignment.active
      and module.stable_key = 'l2e-exploring-emerging-digital-technologies'
      and activity.active
      and version.published_at is not null
      and version.retired_at is null
  ) >= 10,
  'L2E-DELIVERY-A receives the published L2E module activity set'
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
