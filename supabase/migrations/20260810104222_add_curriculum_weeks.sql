create table learning.curriculum_weeks (
  id uuid primary key default gen_random_uuid(),

  module_id uuid not null
    references learning.modules(id)
    on delete restrict,

  stable_key text not null,
  title text not null,

  week_number integer not null,
  sort_order integer not null default 0,

  active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint curriculum_weeks_week_number_valid
    check (week_number > 0),

  constraint curriculum_weeks_sort_order_valid
    check (sort_order >= 0),

  constraint curriculum_weeks_module_key_unique
    unique (module_id, stable_key),

  constraint curriculum_weeks_module_number_unique
    unique (module_id, week_number)
);

create index curriculum_weeks_module_idx
on learning.curriculum_weeks(module_id);

create index curriculum_weeks_order_idx
on learning.curriculum_weeks(module_id, sort_order);

alter table learning.curriculum_weeks enable row level security;

grant select on learning.curriculum_weeks to authenticated;

create policy authenticated_users_read_active_curriculum_weeks
on learning.curriculum_weeks
for select
to authenticated
using (active = true);
