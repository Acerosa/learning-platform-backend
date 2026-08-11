alter table learning.academic_years enable row level security;
alter table learning.courses enable row level security;
alter table learning.groups enable row level security;
alter table learning.students enable row level security;
alter table learning.teachers enable row level security;
alter table learning.enrolments enable row level security;
alter table learning.teacher_group_access enable row level security;
alter table learning.modules enable row level security;
alter table learning.topics enable row level security;
alter table learning.activities enable row level security;
alter table learning.activity_versions enable row level security;
alter table learning.activity_assignments enable row level security;
alter table learning.questions enable row level security;
alter table learning.question_topics enable row level security;
alter table learning.attempts enable row level security;
alter table learning.responses enable row level security;

revoke all on all tables in schema learning from public, anon, authenticated;
revoke all on all sequences in schema learning from public, anon, authenticated;
revoke all on all functions in schema learning from public, anon, authenticated;

grant usage on schema learning to authenticated;
grant usage on schema api to authenticated;

grant select (
  id,
  auth_user_id,
  student_number,
  first_name,
  display_name,
  active
) on learning.students to authenticated;

grant select (
  id,
  auth_user_id,
  staff_reference,
  display_name,
  active
) on learning.teachers to authenticated;

grant select on table
  learning.academic_years,
  learning.courses,
  learning.groups,
  learning.enrolments,
  learning.teacher_group_access,
  learning.modules,
  learning.topics,
  learning.activities,
  learning.activity_versions,
  learning.activity_assignments,
  learning.questions,
  learning.question_topics,
  learning.attempts,
  learning.responses
to authenticated;

create function learning.current_student_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select student.id
  from learning.students as student
  where student.auth_user_id = (select auth.uid())
    and student.active
  limit 1
$$;

create function learning.current_teacher_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select teacher.id
  from learning.teachers as teacher
  where teacher.auth_user_id = (select auth.uid())
    and teacher.active
  limit 1
$$;

create function learning.teacher_can_access_group(target_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from learning.teachers as teacher
    join learning.teacher_group_access as access
      on access.teacher_id = teacher.id
     and access.revoked_at is null
    join learning.groups as learner_group
      on learner_group.id = access.group_id
     and learner_group.active
    where teacher.auth_user_id = (select auth.uid())
      and teacher.active
      and access.group_id = target_group_id
  )
$$;

revoke all on function learning.current_student_id() from public, anon;
revoke all on function learning.current_teacher_id() from public, anon;
revoke all on function learning.teacher_can_access_group(uuid) from public, anon;

grant execute on function learning.current_student_id() to authenticated;
grant execute on function learning.current_teacher_id() to authenticated;
grant execute on function learning.teacher_can_access_group(uuid) to authenticated;

create policy academic_years_authenticated_read
on learning.academic_years
for select
to authenticated
using (active);

create policy courses_authenticated_read
on learning.courses
for select
to authenticated
using (active);

create policy groups_actor_scoped_read
on learning.groups
for select
to authenticated
using (
  exists (
    select 1
    from learning.enrolments as enrolment
    where enrolment.group_id = groups.id
      and enrolment.student_id = (select learning.current_student_id())
      and enrolment.status = 'active'
  )
  or (select learning.teacher_can_access_group(groups.id))
);

create policy students_actor_scoped_read
on learning.students
for select
to authenticated
using (
  id = (select learning.current_student_id())
  or exists (
    select 1
    from learning.enrolments as enrolment
    where enrolment.student_id = students.id
      and enrolment.status = 'active'
      and (select learning.teacher_can_access_group(enrolment.group_id))
  )
);

create policy teachers_own_profile_read
on learning.teachers
for select
to authenticated
using (id = (select learning.current_teacher_id()));

create policy enrolments_actor_scoped_read
on learning.enrolments
for select
to authenticated
using (
  student_id = (select learning.current_student_id())
  or (select learning.teacher_can_access_group(group_id))
);

create policy teacher_group_access_own_read
on learning.teacher_group_access
for select
to authenticated
using (teacher_id = (select learning.current_teacher_id()));

create policy modules_authenticated_read
on learning.modules
for select
to authenticated
using (active);

create policy topics_authenticated_read
on learning.topics
for select
to authenticated
using (active);

create policy activities_authenticated_read
on learning.activities
for select
to authenticated
using (active);

create policy activity_versions_published_read
on learning.activity_versions
for select
to authenticated
using (published_at is not null and retired_at is null);

create policy activity_assignments_actor_scoped_read
on learning.activity_assignments
for select
to authenticated
using (
  active
  and (
    exists (
      select 1
      from learning.enrolments as enrolment
      where enrolment.group_id = activity_assignments.group_id
        and enrolment.student_id = (select learning.current_student_id())
        and enrolment.status = 'active'
    )
    or (select learning.teacher_can_access_group(group_id))
  )
);

create policy questions_published_read
on learning.questions
for select
to authenticated
using (
  exists (
    select 1
    from learning.activity_versions as activity_version
    where activity_version.id = questions.activity_version_id
      and activity_version.published_at is not null
      and activity_version.retired_at is null
  )
);

create policy question_topics_published_read
on learning.question_topics
for select
to authenticated
using (
  exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    where question.id = question_topics.question_id
      and activity_version.published_at is not null
      and activity_version.retired_at is null
  )
);

create policy attempts_actor_scoped_read
on learning.attempts
for select
to authenticated
using (
  student_id = (select learning.current_student_id())
  or exists (
    select 1
    from learning.enrolments as enrolment
    where enrolment.id = attempts.enrolment_id
      and (select learning.teacher_can_access_group(enrolment.group_id))
  )
);

create policy responses_actor_scoped_read
on learning.responses
for select
to authenticated
using (
  exists (
    select 1
    from learning.attempts as attempt
    join learning.enrolments as enrolment
      on enrolment.id = attempt.enrolment_id
    where attempt.id = responses.attempt_id
      and (
        attempt.student_id = (select learning.current_student_id())
        or (select learning.teacher_can_access_group(enrolment.group_id))
      )
  )
);
