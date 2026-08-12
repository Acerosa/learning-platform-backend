-- Activate Unit 3 Cyber Security delivery for shared-backend testing.
-- Publishes imported Weeks 2–7 catalogue versions (grounded question rows
-- present), opens a synthetic Cyber learner group for registration, and assigns
-- every published Cyber version to that group.
--
-- Week 1 versions remain unpublished: they have no imported question rows and
-- continue to rely on Apps Script markSection. Learner identities are not
-- created here.

insert into learning.academic_years (
  id,
  code,
  starts_on,
  ends_on,
  active
)
values (
  '40000000-0000-4000-8000-000000000001',
  '2026-27',
  '2026-09-01',
  '2027-08-31',
  true
)
on conflict (code) do nothing;

update learning.activity_versions as version
set published_at = coalesce(version.published_at, '2026-08-12T12:00:00Z'::timestamptz)
from learning.activities as activity
join learning.modules as module
  on module.id = activity.module_id
where version.activity_id = activity.id
  and module.stable_key = 'unit-3-cyber-security'
  and activity.stable_key not like 'u3-w01-%'
  and version.retired_at is null;

insert into learning.groups (
  id,
  academic_year_id,
  course_id,
  code,
  name,
  active,
  year_group,
  registration_key,
  registration_open
)
select
  '60000000-0000-4000-8000-000000000010',
  academic_year.id,
  course.id,
  'CYBER-TEST-A',
  'Cyber Security Synthetic Test Group A',
  true,
  'Year 1',
  'cyber-year-1-test',
  true
from learning.academic_years as academic_year
cross join learning.courses as course
where academic_year.code = '2026-27'
  and academic_year.active
  and course.stable_key = 'ocr-level-3-it'
  and course.active
on conflict (academic_year_id, course_id, code) do update
set
  name = excluded.name,
  active = excluded.active,
  year_group = excluded.year_group,
  registration_key = excluded.registration_key,
  registration_open = excluded.registration_open;

insert into learning.activity_assignments (
  id,
  group_id,
  activity_version_id,
  required,
  active
)
select
  md5(
    'cyber-activation:'
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
where learner_group.code = 'CYBER-TEST-A'
  and course.stable_key = 'ocr-level-3-it'
  and module.stable_key = 'unit-3-cyber-security'
  and activity.stable_key not like 'u3-w01-%'
  and activity_version.published_at is not null
  and activity_version.retired_at is null
on conflict (group_id, activity_version_id) do update
set
  required = excluded.required,
  active = excluded.active;
