create view api.curriculum_weeks
with (security_invoker = true)
as
select
  week.id,
  course.stable_key as course_key,
  module.stable_key as module_key,
  week.stable_key as week_key,
  week.title,
  week.week_number,
  week.sort_order
from learning.curriculum_weeks as week
join learning.modules as module
  on module.id = week.module_id
join learning.courses as course
  on course.id = module.course_id
where week.active = true;

grant select on api.curriculum_weeks to authenticated;
