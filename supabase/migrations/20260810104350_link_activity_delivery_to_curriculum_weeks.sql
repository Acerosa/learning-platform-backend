alter table learning.activity_delivery
add column curriculum_week_id uuid
references learning.curriculum_weeks(id)
on delete restrict;

create index activity_delivery_curriculum_week_idx
on learning.activity_delivery(curriculum_week_id);
