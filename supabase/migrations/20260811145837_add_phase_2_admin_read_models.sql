-- Narrow read models required by the Phase 2 Central Admin Portal vertical
-- slice. Browser authority still derives from Auth identity, active staff
-- records and the existing platform RLS helpers.

update platform.contract_versions
set
  status = 'retired',
  published_at = coalesce(published_at, '2026-08-11T00:00:00Z'),
  deprecated_at = '2026-08-11T14:58:37Z'
where contract_key = 'admin-api'
  and version = '0.1.0'
  and status = 'draft';

insert into platform.contract_versions (
  contract_key,
  version,
  status,
  compatibility,
  contract_document
) values (
  'admin-api',
  '0.2.0',
  'draft',
  '{"previousVersion":"0.1.0","mode":"read-only"}'::jsonb,
  '{"schema":"admin_api","boundary":"authenticated staff read models"}'::jsonb
)
on conflict (contract_key, version) do nothing;

create view admin_api.current_staff_context
with (security_invoker = true)
as
select
  teacher.id as teacher_id,
  teacher.staff_reference,
  teacher.display_name,
  teacher.active,
  coalesce(
    array_agg(staff_role.role order by staff_role.role)
      filter (where staff_role.role is not null),
    '{}'::text[]
  ) as active_roles
from learning.teachers as teacher
left join platform.staff_roles as staff_role
  on staff_role.teacher_id = teacher.id
 and staff_role.revoked_at is null
where teacher.id = (select learning.current_teacher_id())
  and teacher.active
group by teacher.id, teacher.staff_reference, teacher.display_name, teacher.active;

-- Replace the foundation learner projection with the smaller Phase 2 list
-- shape. It intentionally excludes contact details and internal response data.
drop view admin_api.learners;

create view admin_api.learners
with (security_invoker = true)
as
select
  student.id as learner_id,
  student.student_number,
  student.display_name,
  student.active,
  coalesce(enrolment_summary.group_codes, '{}'::text[]) as group_codes,
  coalesce(enrolment_summary.active_enrolment_count, 0::bigint)
    as active_enrolment_count
from learning.students as student
left join lateral (
  select
    array_agg(learner_group.code order by learner_group.code)
      filter (where enrolment.status = 'active') as group_codes,
    count(*) filter (where enrolment.status = 'active')
      as active_enrolment_count
  from learning.enrolments as enrolment
  join learning.groups as learner_group on learner_group.id = enrolment.group_id
  where enrolment.student_id = student.id
) as enrolment_summary on true
where (select platform.current_staff_has_role('platform_admin'));

create or replace view admin_api.groups
with (security_invoker = true)
as
select
  learner_group.id as group_id,
  learner_group.code as group_code,
  learner_group.name as group_name,
  learner_group.year_group,
  learner_group.registration_open,
  learner_group.active,
  academic_year.id as academic_year_id,
  academic_year.code as academic_year,
  course.id as course_id,
  course.stable_key as course_key,
  course.title as course_title,
  (
    select count(*)
    from learning.enrolments as enrolment
    where enrolment.group_id = learner_group.id
      and enrolment.status = 'active'
  ) as active_learner_count
from learning.groups as learner_group
join learning.academic_years as academic_year
  on academic_year.id = learner_group.academic_year_id
join learning.courses as course on course.id = learner_group.course_id
where (select platform.current_staff_has_role('platform_admin'));

create or replace view admin_api.attempts
with (security_invoker = true)
as
select
  attempt.id as attempt_id,
  attempt.student_id as learner_id,
  student.student_number,
  attempt.enrolment_id,
  attempt.assignment_id,
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  attempt.attempt_number,
  attempt.status,
  attempt.score,
  attempt.max_score,
  attempt.marking_source,
  attempt.evidence_level,
  attempt.received_at,
  attempt.completed_at,
  learner_group.code as group_code
from learning.attempts as attempt
join learning.students as student on student.id = attempt.student_id
join learning.activity_versions as activity_version
  on activity_version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
join learning.activity_assignments as assignment
  on assignment.id = attempt.assignment_id
join learning.groups as learner_group on learner_group.id = assignment.group_id
where (select platform.current_staff_has_role('platform_admin'));

create view admin_api.dashboard_summary
with (security_invoker = true)
as
select
  (select count(*) from platform.hubs) as registered_hubs,
  (select count(*) from platform.hubs where active) as active_hubs,
  (select count(*) from learning.students where active) as active_learners,
  (select count(*) from learning.groups where active) as active_groups,
  (
    select count(*)
    from learning.enrolments
    where status = 'active'
  ) as active_enrolments,
  (select count(*) from learning.activity_assignments) as assignments,
  (
    select count(*)
    from learning.attempts
    where completed_at >= clock_timestamp() - interval '7 days'
  ) as recent_attempts,
  (
    select count(*)
    from learning.attempts
    where status = 'completed'
  ) as completed_attempts,
  (
    select round(avg((score / nullif(max_score, 0)) * 100), 2)
    from learning.attempts
    where status = 'completed'
  ) as average_score_percentage,
  (
    select count(*)
    from platform.operational_health
    where status = 'healthy'
  ) as healthy_services,
  (select count(*) from platform.operational_health) as service_count,
  (
    select count(*)
    from platform.contract_versions
    where status = 'active'
  ) as active_contracts,
  (select count(*) from platform.contract_versions) as contract_count
where (select platform.current_staff_has_role('platform_admin'));

create view admin_api.activity_performance
with (security_invoker = true)
as
select
  learner_group.code as group_code,
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  count(*) as completed_attempts,
  count(distinct attempt.student_id) as learner_count,
  round(avg((attempt.score / nullif(attempt.max_score, 0)) * 100), 2)
    as average_score_percentage,
  round(max((attempt.score / nullif(attempt.max_score, 0)) * 100), 2)
    as best_score_percentage,
  min(attempt.completed_at) as first_completed_at,
  max(attempt.completed_at) as latest_completed_at
from learning.attempts as attempt
join learning.activity_assignments as assignment
  on assignment.id = attempt.assignment_id
join learning.groups as learner_group on learner_group.id = assignment.group_id
join learning.activity_versions as activity_version
  on activity_version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
where attempt.status = 'completed'
  and (select platform.current_staff_has_role('platform_admin'))
group by
  learner_group.code,
  activity.stable_key,
  activity_version.version;

revoke all on
  admin_api.current_staff_context,
  admin_api.learners,
  admin_api.groups,
  admin_api.attempts,
  admin_api.dashboard_summary,
  admin_api.activity_performance
from public, anon, authenticated;

grant select on
  admin_api.current_staff_context,
  admin_api.learners,
  admin_api.groups,
  admin_api.attempts,
  admin_api.dashboard_summary,
  admin_api.activity_performance
to authenticated;

comment on view admin_api.current_staff_context is
  'Current active staff identity and active backend roles for portal access gating.';
comment on view admin_api.dashboard_summary is
  'Platform-admin-only operational counts for the Central Admin dashboard.';
comment on view admin_api.activity_performance is
  'Platform-admin-only activity performance aggregates without response payloads.';
