drop index if exists learning.enrolments_one_active_per_student;

create unique index enrolments_one_active_per_student_group
on learning.enrolments (student_id, group_id)
where status = 'active';

comment on index learning.enrolments_one_active_per_student_group is
'Allows a student to have concurrent active enrolments in different groups/courses while preventing duplicate active enrolment in the same group.';
