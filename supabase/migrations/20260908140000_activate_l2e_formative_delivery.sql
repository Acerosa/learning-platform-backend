-- Activate L2E formative delivery for signed-in learners.
--
-- Root cause: Check-answer / Check types call api.mark_formative_response, which
-- requires an active enrolment into a group that has the activity assigned.
-- L2E previously only had exclusive synthetic QA group L2E-TEST-A (registration
-- closed, Week 1 smoke allowlist only). Real learners therefore received
-- ACTIVITY_NOT_ASSIGNED and the hub showed "Your answer could not be checked."
--
-- This migration mirrors Unit 3 CYBER-TEST-A activation:
--   - create an open teaching/delivery group for Gateway L2 Digital IT Skills
--   - assign every published, non-retired activity version in the L2E module
-- L2E-TEST-A remains the closed exclusive-smoke fixture and is not modified.

insert into learning.groups (
  id,
  academic_year_id,
  course_id,
  code,
  name,
  active,
  year_group,
  registration_key,
  registration_open,
  is_synthetic,
  synthetic_purpose
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
  id,
  group_id,
  activity_version_id,
  required,
  active
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
