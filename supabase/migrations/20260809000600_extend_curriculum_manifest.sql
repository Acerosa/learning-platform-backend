alter table learning.questions
  drop constraint question_type_valid;

alter table learning.questions
  add constraint question_type_valid
  check (
    question_type in (
      'single',
      'multiple',
      'text',
      'matching',
      'order',
      'predict-output',
      'code-gap',
      'line-select',
      'code-order',
      'code-editor'
    )
  );

create table learning.skills (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null
    references learning.modules (id) on delete restrict,
  stable_key text not null,
  title text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint skill_stable_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint skill_sort_order_valid check (sort_order >= 0),
  constraint skills_module_stable_key_unique unique (module_id, stable_key)
);

create index skills_module_sort_idx
  on learning.skills (module_id, sort_order);

create table learning.question_skills (
  question_id uuid not null
    references learning.questions (id) on delete cascade,
  skill_id uuid not null
    references learning.skills (id) on delete restrict,
  weight numeric(6,5) not null default 1,
  primary key (question_id, skill_id),
  constraint question_skill_weight_valid check (weight > 0 and weight <= 1)
);

create index question_skills_skill_question_idx
  on learning.question_skills (skill_id, question_id);

create table learning.coding_languages (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  title text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  constraint coding_language_stable_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint coding_language_sort_order_valid check (sort_order >= 0)
);

create table learning.activity_version_languages (
  activity_version_id uuid not null
    references learning.activity_versions (id) on delete cascade,
  coding_language_id uuid not null
    references learning.coding_languages (id) on delete restrict,
  primary key (activity_version_id, coding_language_id)
);

create index activity_version_languages_language_idx
  on learning.activity_version_languages (coding_language_id, activity_version_id);

create function learning.reject_published_question_skill_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_question_id uuid;
begin
  target_question_id := case when tg_op = 'DELETE'
    then old.question_id
    else new.question_id
  end;

  if exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    where question.id = target_question_id
      and activity_version.published_at is not null
  ) then
    raise exception using
      errcode = '55000',
      message = 'PUBLISHED_QUESTION_SKILL_IMMUTABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger question_skills_immutable_after_publication
before insert or update or delete on learning.question_skills
for each row execute function learning.reject_published_question_skill_change();

create function learning.reject_published_activity_language_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_version_id uuid;
begin
  target_version_id := case when tg_op = 'DELETE'
    then old.activity_version_id
    else new.activity_version_id
  end;

  if exists (
    select 1
    from learning.activity_versions as activity_version
    where activity_version.id = target_version_id
      and activity_version.published_at is not null
  ) then
    raise exception using
      errcode = '55000',
      message = 'PUBLISHED_ACTIVITY_LANGUAGE_IMMUTABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger activity_version_languages_immutable_after_publication
before insert or update or delete on learning.activity_version_languages
for each row execute function learning.reject_published_activity_language_change();

alter table learning.skills enable row level security;
alter table learning.question_skills enable row level security;
alter table learning.coding_languages enable row level security;
alter table learning.activity_version_languages enable row level security;

revoke all on table
  learning.skills,
  learning.question_skills,
  learning.coding_languages,
  learning.activity_version_languages
from public, anon, authenticated;

revoke all on function learning.reject_published_question_skill_change()
from public, anon, authenticated;

revoke all on function learning.reject_published_activity_language_change()
from public, anon, authenticated;

grant select on table
  learning.skills,
  learning.question_skills,
  learning.coding_languages,
  learning.activity_version_languages
to authenticated;

create policy skills_authenticated_read
on learning.skills
for select
to authenticated
using (active);

create policy question_skills_published_read
on learning.question_skills
for select
to authenticated
using (
  exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    where question.id = question_skills.question_id
      and activity_version.published_at is not null
      and activity_version.retired_at is null
  )
);

create policy coding_languages_authenticated_read
on learning.coding_languages
for select
to authenticated
using (active);

create policy activity_version_languages_published_read
on learning.activity_version_languages
for select
to authenticated
using (
  exists (
    select 1
    from learning.activity_versions as activity_version
    where activity_version.id = activity_version_languages.activity_version_id
      and activity_version.published_at is not null
      and activity_version.retired_at is null
  )
);
