create table learning.modules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null
    references learning.courses (id) on delete restrict,
  stable_key text not null,
  title text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint module_stable_key_valid check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint module_sort_order_valid check (sort_order >= 0),
  constraint modules_course_stable_key_unique unique (course_id, stable_key)
);

create index modules_course_sort_idx
  on learning.modules (course_id, sort_order);

create table learning.topics (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null
    references learning.modules (id) on delete restrict,
  stable_key text not null,
  title text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint topic_stable_key_valid check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint topic_sort_order_valid check (sort_order >= 0),
  constraint topics_module_stable_key_unique unique (module_id, stable_key)
);

create index topics_module_sort_idx
  on learning.topics (module_id, sort_order);

create table learning.activities (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null
    references learning.modules (id) on delete restrict,
  stable_key text not null unique,
  title text not null,
  activity_type text not null,
  git_path text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint activity_stable_key_valid check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint activity_git_path_relative check (
    git_path <> ''
    and git_path !~ '^([a-z]+:|/)'
    and git_path !~ '(^|/)\.\.(/|$)'
  )
);

create index activities_module_active_idx
  on learning.activities (module_id, active);

create table learning.activity_versions (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null
    references learning.activities (id) on delete restrict,
  version text not null,
  content_hash text not null,
  git_commit_sha text,
  max_score numeric(8,2) not null,
  question_count integer not null,
  published_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  constraint activity_version_unique unique (activity_id, version),
  constraint activity_content_hash_unique unique (activity_id, content_hash),
  constraint activity_version_semver_valid
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint activity_content_hash_valid
    check (content_hash ~ '^[0-9a-f]{64}$'),
  constraint activity_commit_sha_valid
    check (git_commit_sha is null or git_commit_sha ~ '^[0-9a-f]{40}$'),
  constraint activity_version_score_valid check (max_score > 0),
  constraint activity_version_question_count_valid check (question_count > 0),
  constraint activity_version_lifecycle_valid
    check (retired_at is null or (published_at is not null and retired_at >= published_at))
);

create index activity_versions_activity_published_idx
  on learning.activity_versions (activity_id, published_at desc);

create table learning.activity_assignments (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null
    references learning.groups (id) on delete restrict,
  activity_version_id uuid not null
    references learning.activity_versions (id) on delete restrict,
  opens_at timestamptz,
  due_at timestamptz,
  required boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint activity_assignment_unique unique (group_id, activity_version_id),
  constraint activity_assignment_dates_valid
    check (due_at is null or opens_at is null or due_at >= opens_at)
);

create index activity_assignments_group_active_idx
  on learning.activity_assignments (group_id, active, due_at);

create index activity_assignments_version_group_idx
  on learning.activity_assignments (activity_version_id, group_id);

create table learning.questions (
  id uuid primary key default gen_random_uuid(),
  activity_version_id uuid not null
    references learning.activity_versions (id) on delete restrict,
  stable_key text not null,
  section_key text not null,
  section_title text not null,
  question_type text not null,
  analytics_title text not null,
  ordinal integer not null,
  max_score numeric(8,2) not null,
  authored_difficulty smallint,
  constraint questions_version_stable_key_unique
    unique (activity_version_id, stable_key),
  constraint questions_version_ordinal_unique
    unique (activity_version_id, ordinal),
  constraint question_section_key_valid
    check (section_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint question_type_valid
    check (question_type in ('single', 'multiple', 'text', 'matching', 'order')),
  constraint question_ordinal_valid check (ordinal > 0),
  constraint question_max_score_valid check (max_score > 0),
  constraint question_difficulty_valid
    check (authored_difficulty is null or authored_difficulty between 1 and 5)
);

create index questions_version_section_ordinal_idx
  on learning.questions (activity_version_id, section_key, ordinal);

create table learning.question_topics (
  question_id uuid not null
    references learning.questions (id) on delete cascade,
  topic_id uuid not null
    references learning.topics (id) on delete restrict,
  weight numeric(6,5) not null default 1,
  primary key (question_id, topic_id),
  constraint question_topic_weight_valid check (weight > 0 and weight <= 1)
);

create index question_topics_topic_question_idx
  on learning.question_topics (topic_id, question_id);

create function learning.reject_published_activity_version_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.published_at is not null then
    raise exception using
      errcode = '55000',
      message = 'PUBLISHED_ACTIVITY_VERSION_IMMUTABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger activity_versions_immutable_after_publication
before update or delete on learning.activity_versions
for each row execute function learning.reject_published_activity_version_change();

create function learning.reject_published_question_change()
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
      message = 'PUBLISHED_QUESTION_IMMUTABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger questions_immutable_after_publication
before insert or update or delete on learning.questions
for each row execute function learning.reject_published_question_change();

create function learning.reject_published_question_topic_change()
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
      message = 'PUBLISHED_QUESTION_TOPIC_IMMUTABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger question_topics_immutable_after_publication
before insert or update or delete on learning.question_topics
for each row execute function learning.reject_published_question_topic_change();
