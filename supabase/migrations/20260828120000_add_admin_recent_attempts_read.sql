-- Bounded Admin Dashboard read for recent attempt summaries.
-- Returns at most five rows ordered by completion recency.

create index if not exists attempts_admin_recent_completed_idx
  on learning.attempts (completed_at desc nulls last, id desc);

comment on index learning.attempts_admin_recent_completed_idx is
  'Supports admin_api.recent_attempts bounded ordering by completion time.';

create or replace view admin_api.recent_attempts
with (security_invoker = true)
as
select
  ranked.attempt_id,
  ranked.student_number,
  ranked.activity_key,
  ranked.activity_version,
  ranked.status,
  ranked.score,
  ranked.max_score,
  ranked.completed_at
from (
  select
    attempt.id as attempt_id,
    student.student_number,
    activity.stable_key as activity_key,
    activity_version.version as activity_version,
    attempt.status,
    attempt.score,
    attempt.max_score,
    attempt.completed_at
  from learning.attempts as attempt
  join learning.students as student on student.id = attempt.student_id
  join learning.activity_versions as activity_version
    on activity_version.id = attempt.activity_version_id
  join learning.activities as activity on activity.id = activity_version.activity_id
  where (select platform.current_staff_has_role('platform_admin'))
  order by attempt.completed_at desc nulls last, attempt.id desc
  limit 5
) as ranked;

revoke all on admin_api.recent_attempts
  from public, anon, authenticated;

grant select on admin_api.recent_attempts
  to authenticated;

comment on view admin_api.recent_attempts is
  'Platform-admin dashboard projection of the five most recently completed attempts. Full attempt history remains on admin_api.attempts.';
