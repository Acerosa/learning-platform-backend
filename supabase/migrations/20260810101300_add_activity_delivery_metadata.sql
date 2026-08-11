create table learning.activity_delivery (
  id uuid primary key default gen_random_uuid(),

  activity_version_id uuid not null
    references learning.activity_versions(id)
    on delete restrict,

  academic_year_id uuid not null
    references learning.academic_years(id)
    on delete restrict,

  group_id uuid
    references learning.groups(id)
    on delete restrict,

  week_number integer,
  session_number integer,

  sort_order integer not null default 0,

  available_from timestamptz,
  available_until timestamptz,

  active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint activity_delivery_week_valid
    check (week_number is null or week_number > 0),

  constraint activity_delivery_session_valid
    check (session_number is null or session_number > 0),

  constraint activity_delivery_sort_valid
    check (sort_order >= 0),

  constraint activity_delivery_window_valid
    check (
      available_until is null
      or available_from is null
      or available_until >= available_from
    )
);

create unique index activity_delivery_unique_group_schedule
on learning.activity_delivery (
  activity_version_id,
  academic_year_id,
  group_id
)
where group_id is not null;

create index activity_delivery_activity_version_idx
on learning.activity_delivery(activity_version_id);

create index activity_delivery_academic_year_idx
on learning.activity_delivery(academic_year_id);

create index activity_delivery_group_idx
on learning.activity_delivery(group_id);

create index activity_delivery_schedule_idx
on learning.activity_delivery (
  academic_year_id,
  week_number,
  session_number,
  sort_order
);

alter table learning.activity_delivery enable row level security;
