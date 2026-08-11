grant select on learning.activity_delivery to authenticated;

create policy authenticated_users_read_active_delivery
on learning.activity_delivery
for select
to authenticated
using (
  active = true
  and (
    group_id is null

    or exists (
      select 1
      from learning.enrolments as enrolment
      where enrolment.group_id = activity_delivery.group_id
        and enrolment.student_id = learning.current_student_id()
        and enrolment.status = 'active'
    )

    or learning.teacher_can_access_group(group_id)
  )
);
