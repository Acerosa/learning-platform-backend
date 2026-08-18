-- Content Library schema: reusable questions, activities, templates, resources,
-- feedback, and hints that can be referenced across curriculum publications.

create schema if not exists library;

-- ─────────────────────────────────────────────────────────────────────────────
-- Library items share a common lifecycle and versioning pattern.
-- Status values mirror curriculum publication: draft → published → superseded.
-- ─────────────────────────────────────────────────────────────────────────────

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Questions                                                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.questions (
  id            uuid primary key default gen_random_uuid(),
  stable_key    text not null unique,
  title         text not null,
  question_text text not null,
  question_type text not null,
  difficulty    smallint not null default 3,
  marks         numeric(8,2) not null default 1,
  estimated_time_minutes integer,
  family_id     text,
  subject       text,
  hub_code      text,
  course_key    text,
  topic         text,
  command_word  text,
  exam_board    text,
  tags          text[] not null default '{}',
  status        text not null default 'draft',
  version       text not null default '1.0.0',
  content       jsonb not null default '{}',
  author        text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint question_stable_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint question_type_valid
    check (question_type in (
      'single', 'multiple', 'text', 'matching', 'order',
      'predict-output', 'code-gap', 'line-select', 'code-order',
      'code-editor', 'classification', 'short-response', 'reflection'
    )),
  constraint question_difficulty_valid
    check (difficulty between 1 and 5),
  constraint question_marks_valid
    check (marks > 0),
  constraint question_status_valid
    check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint question_version_semver
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

create index questions_type_idx on library.questions (question_type);
create index questions_difficulty_idx on library.questions (difficulty);
create index questions_subject_idx on library.questions (subject) where subject is not null;
create index questions_topic_idx on library.questions (topic) where topic is not null;
create index questions_status_idx on library.questions (status);
create index questions_family_idx on library.questions (family_id) where family_id is not null;
create index questions_tags_idx on library.questions using gin (tags);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Question Learning Outcomes (many-to-many)                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.question_learning_outcomes (
  question_id       uuid not null references library.questions (id) on delete cascade,
  learning_outcome  text not null,
  primary key (question_id, learning_outcome)
);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Activities                                                              ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.activities (
  id               uuid primary key default gen_random_uuid(),
  stable_key       text not null unique,
  title            text not null,
  activity_type    text not null,
  difficulty       text not null default 'standard',
  family_id        text,
  summary          text,
  subject          text,
  hub_code         text,
  course_key       text,
  topic            text,
  exam_board       text,
  estimated_time_minutes integer,
  tags             text[] not null default '{}',
  status           text not null default 'draft',
  version          text not null default '1.0.0',
  content          jsonb not null default '{}',
  author           text not null default '',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint activity_stable_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint activity_difficulty_valid
    check (difficulty in ('foundation', 'standard', 'challenge')),
  constraint activity_status_valid
    check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint activity_version_semver
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

create index activities_type_idx on library.activities (activity_type);
create index activities_difficulty_idx on library.activities (difficulty);
create index activities_status_idx on library.activities (status);
create index activities_family_idx on library.activities (family_id) where family_id is not null;
create index activities_tags_idx on library.activities using gin (tags);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Activity–Question link (many-to-many)                                   ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.activity_questions (
  activity_id  uuid not null references library.activities (id) on delete cascade,
  question_id  uuid not null references library.questions (id) on delete restrict,
  sort_order   integer not null default 0,
  primary key (activity_id, question_id),
  constraint sort_order_valid check (sort_order >= 0)
);

create index activity_questions_question_idx
  on library.activity_questions (question_id);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Activity Learning Outcomes (many-to-many)                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.activity_learning_outcomes (
  activity_id       uuid not null references library.activities (id) on delete cascade,
  learning_outcome  text not null,
  primary key (activity_id, learning_outcome)
);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Templates                                                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.templates (
  id            uuid primary key default gen_random_uuid(),
  stable_key    text not null unique,
  title         text not null,
  template_type text not null,
  description   text,
  subject       text,
  tags          text[] not null default '{}',
  status        text not null default 'draft',
  version       text not null default '1.0.0',
  specification jsonb not null default '{}',
  author        text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint template_stable_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint template_type_valid
    check (template_type in (
      'multiple-choice', 'classification', 'coding-exercise',
      'matching', 'short-response', 'reflection', 'diagnostic',
      'retrieval-quiz', 'assessment', 'custom'
    )),
  constraint template_status_valid
    check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint template_version_semver
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

create index templates_type_idx on library.templates (template_type);
create index templates_status_idx on library.templates (status);
create index templates_tags_idx on library.templates using gin (tags);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Resources                                                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.resources (
  id            uuid primary key default gen_random_uuid(),
  stable_key    text not null unique,
  title         text not null,
  resource_type text not null,
  url           text,
  description   text,
  subject       text,
  hub_code      text,
  course_key    text,
  tags          text[] not null default '{}',
  status        text not null default 'draft',
  version       text not null default '1.0.0',
  metadata      jsonb not null default '{}',
  author        text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint resource_stable_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint resource_type_valid
    check (resource_type in (
      'video', 'pdf', 'website', 'github-repo', 'image',
      'document', 'slide-deck', 'interactive', 'custom'
    )),
  constraint resource_status_valid
    check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint resource_version_semver
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

create index resources_type_idx on library.resources (resource_type);
create index resources_status_idx on library.resources (status);
create index resources_tags_idx on library.resources using gin (tags);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Activity–Resource link (many-to-many)                                   ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.activity_resources (
  activity_id  uuid not null references library.activities (id) on delete cascade,
  resource_id  uuid not null references library.resources (id) on delete restrict,
  sort_order   integer not null default 0,
  primary key (activity_id, resource_id),
  constraint sort_order_valid check (sort_order >= 0)
);

create index activity_resources_resource_idx
  on library.activity_resources (resource_id);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Feedback                                                                ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.feedback (
  id            uuid primary key default gen_random_uuid(),
  stable_key    text not null unique,
  title         text not null,
  feedback_type text not null,
  content       jsonb not null default '{}',
  subject       text,
  tags          text[] not null default '{}',
  status        text not null default 'draft',
  version       text not null default '1.0.0',
  author        text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint feedback_stable_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint feedback_type_valid
    check (feedback_type in (
      'correct', 'incorrect', 'misconception',
      'teacher-note', 'hint', 'extension', 'custom'
    )),
  constraint feedback_status_valid
    check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint feedback_version_semver
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

create index feedback_type_idx on library.feedback (feedback_type);
create index feedback_status_idx on library.feedback (status);
create index feedback_tags_idx on library.feedback using gin (tags);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Hints                                                                   ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.hints (
  id            uuid primary key default gen_random_uuid(),
  stable_key    text not null unique,
  title         text not null,
  hint_text     text not null,
  hint_level    smallint not null default 1,
  subject       text,
  tags          text[] not null default '{}',
  status        text not null default 'draft',
  version       text not null default '1.0.0',
  author        text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint hint_stable_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint hint_level_valid
    check (hint_level between 1 and 5),
  constraint hint_status_valid
    check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint hint_version_semver
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

create index hints_status_idx on library.hints (status);
create index hints_tags_idx on library.hints using gin (tags);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Question–Feedback link (many-to-many)                                   ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.question_feedback (
  question_id  uuid not null references library.questions (id) on delete cascade,
  feedback_id  uuid not null references library.feedback (id) on delete restrict,
  primary key (question_id, feedback_id)
);

create index question_feedback_feedback_idx
  on library.question_feedback (feedback_id);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Question–Hint link (many-to-many)                                       ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.question_hints (
  question_id  uuid not null references library.questions (id) on delete cascade,
  hint_id      uuid not null references library.hints (id) on delete restrict,
  sort_order   integer not null default 0,
  primary key (question_id, hint_id),
  constraint sort_order_valid check (sort_order >= 0)
);

create index question_hints_hint_idx
  on library.question_hints (hint_id);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Code Templates                                                          ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.code_templates (
  id               uuid primary key default gen_random_uuid(),
  stable_key       text not null unique,
  title            text not null,
  language         text not null,
  starter_code     text not null default '',
  solution_code    text,
  test_code        text,
  description      text,
  tags             text[] not null default '{}',
  status           text not null default 'draft',
  version          text not null default '1.0.0',
  author           text not null default '',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint code_template_stable_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint code_template_status_valid
    check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint code_template_version_semver
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

create index code_templates_language_idx on library.code_templates (language);
create index code_templates_status_idx on library.code_templates (status);
create index code_templates_tags_idx on library.code_templates using gin (tags);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Assessment Templates                                                    ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.assessment_templates (
  id               uuid primary key default gen_random_uuid(),
  stable_key       text not null unique,
  title            text not null,
  description      text,
  total_marks      numeric(8,2),
  duration_minutes integer,
  subject          text,
  exam_board       text,
  tags             text[] not null default '{}',
  status           text not null default 'draft',
  version          text not null default '1.0.0',
  specification    jsonb not null default '{}',
  author           text not null default '',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint assessment_template_stable_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint assessment_template_status_valid
    check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint assessment_template_version_semver
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

create index assessment_templates_status_idx on library.assessment_templates (status);
create index assessment_templates_tags_idx on library.assessment_templates using gin (tags);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Usage Tracking (for impact analysis)                                    ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.usage_references (
  id               uuid primary key default gen_random_uuid(),
  library_type     text not null,
  library_item_id  uuid not null,
  used_in_type     text not null,
  used_in_id       text not null,
  used_in_context  text,
  created_at       timestamptz not null default now(),

  constraint usage_library_type_valid
    check (library_type in (
      'question', 'activity', 'template', 'resource',
      'feedback', 'hint', 'code-template', 'assessment-template'
    )),
  constraint usage_used_in_type_valid
    check (used_in_type in (
      'curriculum-publication', 'activity', 'assessment', 'quiz'
    )),
  constraint usage_unique
    unique (library_type, library_item_id, used_in_type, used_in_id)
);

create index usage_references_item_idx
  on library.usage_references (library_type, library_item_id);
create index usage_references_used_in_idx
  on library.usage_references (used_in_type, used_in_id);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  RLS Policies                                                            ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

do $$
declare
  _tbl text;
begin
  for _tbl in
    select tablename from pg_tables where schemaname = 'library'
  loop
    execute format('alter table library.%I enable row level security', _tbl);
  end loop;
end $$;

create or replace function library.is_content_author()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from platform.staff_roles sr
    join learning.teachers t on t.id = sr.teacher_id
    where t.auth_user_id = auth.uid()
      and sr.revoked_at is null
      and sr.role in ('platform_admin', 'curriculum_admin')
  )
$$;

do $$
declare
  _tbl text;
begin
  for _tbl in
    select tablename from pg_tables where schemaname = 'library'
  loop
    execute format(
      'create policy %I on library.%I for select to authenticated using (library.is_content_author())',
      _tbl || '_staff_read', _tbl
    );
    execute format(
      'create policy %I on library.%I for insert to authenticated with check (library.is_content_author())',
      _tbl || '_staff_insert', _tbl
    );
    execute format(
      'create policy %I on library.%I for update to authenticated using (library.is_content_author())',
      _tbl || '_staff_update', _tbl
    );
    execute format(
      'create policy %I on library.%I for delete to authenticated using (library.is_content_author())',
      _tbl || '_staff_delete', _tbl
    );
  end loop;
end $$;

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Admin API Views                                                         ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create or replace view admin_api.library_questions as
select
  q.id,
  q.stable_key,
  q.title,
  q.question_type,
  q.difficulty,
  q.marks,
  q.estimated_time_minutes,
  q.family_id,
  q.subject,
  q.hub_code,
  q.course_key,
  q.topic,
  q.command_word,
  q.exam_board,
  q.tags,
  q.status,
  q.version,
  q.author,
  q.created_at,
  q.updated_at,
  coalesce(array_agg(distinct lo.learning_outcome) filter (where lo.learning_outcome is not null), '{}') as learning_outcomes,
  (select count(*) from library.usage_references ur
   where ur.library_type = 'question' and ur.library_item_id = q.id) as used_by_count
from library.questions q
left join library.question_learning_outcomes lo on lo.question_id = q.id
group by q.id;

create or replace view admin_api.library_activities as
select
  a.id,
  a.stable_key,
  a.title,
  a.activity_type,
  a.difficulty,
  a.family_id,
  a.summary,
  a.subject,
  a.hub_code,
  a.course_key,
  a.topic,
  a.exam_board,
  a.estimated_time_minutes,
  a.tags,
  a.status,
  a.version,
  a.author,
  a.created_at,
  a.updated_at,
  coalesce(array_agg(distinct lo.learning_outcome) filter (where lo.learning_outcome is not null), '{}') as learning_outcomes,
  (select count(*) from library.activity_questions aq where aq.activity_id = a.id) as question_count,
  (select count(*) from library.usage_references ur
   where ur.library_type = 'activity' and ur.library_item_id = a.id) as used_by_count
from library.activities a
left join library.activity_learning_outcomes lo on lo.activity_id = a.id
group by a.id;

create or replace view admin_api.library_templates as
select
  t.id,
  t.stable_key,
  t.title,
  t.template_type,
  t.description,
  t.subject,
  t.tags,
  t.status,
  t.version,
  t.author,
  t.created_at,
  t.updated_at,
  (select count(*) from library.usage_references ur
   where ur.library_type = 'template' and ur.library_item_id = t.id) as used_by_count
from library.templates t;

create or replace view admin_api.library_resources as
select
  r.id,
  r.stable_key,
  r.title,
  r.resource_type,
  r.url,
  r.description,
  r.subject,
  r.hub_code,
  r.course_key,
  r.tags,
  r.status,
  r.version,
  r.author,
  r.created_at,
  r.updated_at,
  (select count(*) from library.usage_references ur
   where ur.library_type = 'resource' and ur.library_item_id = r.id) as used_by_count
from library.resources r;

create or replace view admin_api.library_feedback as
select
  f.id,
  f.stable_key,
  f.title,
  f.feedback_type,
  f.subject,
  f.tags,
  f.status,
  f.version,
  f.author,
  f.created_at,
  f.updated_at,
  (select count(*) from library.usage_references ur
   where ur.library_type = 'feedback' and ur.library_item_id = f.id) as used_by_count
from library.feedback f;

create or replace view admin_api.library_hints as
select
  h.id,
  h.stable_key,
  h.title,
  h.hint_level,
  h.subject,
  h.tags,
  h.status,
  h.version,
  h.author,
  h.created_at,
  h.updated_at,
  (select count(*) from library.usage_references ur
   where ur.library_type = 'hint' and ur.library_item_id = h.id) as used_by_count
from library.hints h;

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Admin API RPCs: CRUD for library items                                  ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create or replace function admin_api.save_library_question(
  p_id                     uuid,
  p_stable_key             text,
  p_title                  text,
  p_question_text          text,
  p_question_type          text,
  p_difficulty             smallint default 3,
  p_marks                  numeric default 1,
  p_estimated_time_minutes integer default null,
  p_family_id              text default null,
  p_subject                text default null,
  p_hub_code               text default null,
  p_course_key             text default null,
  p_topic                  text default null,
  p_command_word           text default null,
  p_exam_board             text default null,
  p_tags                   text[] default '{}',
  p_status                 text default 'draft',
  p_version                text default '1.0.0',
  p_content                jsonb default '{}',
  p_learning_outcomes      text[] default '{}'
)
returns table (
  id uuid,
  stable_key text,
  status text,
  version text,
  created boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  select q.id into v_id from library.questions q where q.id = p_id;

  if v_id is null then
    insert into library.questions (
      id, stable_key, title, question_text, question_type, difficulty, marks,
      estimated_time_minutes, family_id, subject, hub_code, course_key,
      topic, command_word, exam_board, tags, status, version, content, author
    ) values (
      coalesce(p_id, gen_random_uuid()), p_stable_key, p_title, p_question_text,
      p_question_type, p_difficulty, p_marks, p_estimated_time_minutes,
      p_family_id, p_subject, p_hub_code, p_course_key, p_topic,
      p_command_word, p_exam_board, p_tags, p_status, p_version, p_content,
      coalesce(
        (select t.display_name from learning.teachers t
         where t.auth_user_id = auth.uid() limit 1),
        'Unknown'
      )
    )
    returning questions.id into v_id;
    v_created := true;
  else
    update library.questions q set
      stable_key = p_stable_key,
      title = p_title,
      question_text = p_question_text,
      question_type = p_question_type,
      difficulty = p_difficulty,
      marks = p_marks,
      estimated_time_minutes = p_estimated_time_minutes,
      family_id = p_family_id,
      subject = p_subject,
      hub_code = p_hub_code,
      course_key = p_course_key,
      topic = p_topic,
      command_word = p_command_word,
      exam_board = p_exam_board,
      tags = p_tags,
      status = p_status,
      version = p_version,
      content = p_content,
      updated_at = now()
    where q.id = v_id and q.status <> 'published';

    if not found then
      raise exception 'Cannot edit a published question. Create a new version instead.';
    end if;
  end if;

  delete from library.question_learning_outcomes where question_id = v_id;
  if array_length(p_learning_outcomes, 1) > 0 then
    insert into library.question_learning_outcomes (question_id, learning_outcome)
    select v_id, unnest(p_learning_outcomes);
  end if;

  return query select v_id, p_stable_key, p_status, p_version, v_created;
end;
$$;

create or replace function admin_api.save_library_activity(
  p_id                     uuid,
  p_stable_key             text,
  p_title                  text,
  p_activity_type          text,
  p_difficulty             text default 'standard',
  p_family_id              text default null,
  p_summary                text default null,
  p_subject                text default null,
  p_hub_code               text default null,
  p_course_key             text default null,
  p_topic                  text default null,
  p_exam_board             text default null,
  p_estimated_time_minutes integer default null,
  p_tags                   text[] default '{}',
  p_status                 text default 'draft',
  p_version                text default '1.0.0',
  p_content                jsonb default '{}',
  p_learning_outcomes      text[] default '{}',
  p_question_ids           uuid[] default '{}'
)
returns table (
  id uuid,
  stable_key text,
  status text,
  version text,
  created boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := false;
  v_qid uuid;
  v_ord integer := 0;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  select a.id into v_id from library.activities a where a.id = p_id;

  if v_id is null then
    insert into library.activities (
      id, stable_key, title, activity_type, difficulty, family_id, summary,
      subject, hub_code, course_key, topic, exam_board, estimated_time_minutes,
      tags, status, version, content, author
    ) values (
      coalesce(p_id, gen_random_uuid()), p_stable_key, p_title, p_activity_type,
      p_difficulty, p_family_id, p_summary, p_subject, p_hub_code, p_course_key,
      p_topic, p_exam_board, p_estimated_time_minutes, p_tags, p_status,
      p_version, p_content,
      coalesce(
        (select t.display_name from learning.teachers t
         where t.auth_user_id = auth.uid() limit 1),
        'Unknown'
      )
    )
    returning activities.id into v_id;
    v_created := true;
  else
    update library.activities a set
      stable_key = p_stable_key,
      title = p_title,
      activity_type = p_activity_type,
      difficulty = p_difficulty,
      family_id = p_family_id,
      summary = p_summary,
      subject = p_subject,
      hub_code = p_hub_code,
      course_key = p_course_key,
      topic = p_topic,
      exam_board = p_exam_board,
      estimated_time_minutes = p_estimated_time_minutes,
      tags = p_tags,
      status = p_status,
      version = p_version,
      content = p_content,
      updated_at = now()
    where a.id = v_id and a.status <> 'published';

    if not found then
      raise exception 'Cannot edit a published activity. Create a new version instead.';
    end if;
  end if;

  delete from library.activity_learning_outcomes where activity_id = v_id;
  if array_length(p_learning_outcomes, 1) > 0 then
    insert into library.activity_learning_outcomes (activity_id, learning_outcome)
    select v_id, unnest(p_learning_outcomes);
  end if;

  delete from library.activity_questions where activity_id = v_id;
  if array_length(p_question_ids, 1) > 0 then
    foreach v_qid in array p_question_ids loop
      insert into library.activity_questions (activity_id, question_id, sort_order)
      values (v_id, v_qid, v_ord);
      v_ord := v_ord + 1;
    end loop;
  end if;

  return query select v_id, p_stable_key, p_status, p_version, v_created;
end;
$$;

create or replace function admin_api.delete_library_item(
  p_library_type text,
  p_id uuid
)
returns table (id uuid, deleted boolean)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  case p_library_type
    when 'question' then
      delete from library.questions q where q.id = p_id and q.status = 'draft';
    when 'activity' then
      delete from library.activities a where a.id = p_id and a.status = 'draft';
    when 'template' then
      delete from library.templates t where t.id = p_id and t.status = 'draft';
    when 'resource' then
      delete from library.resources r where r.id = p_id and r.status = 'draft';
    when 'feedback' then
      delete from library.feedback f where f.id = p_id and f.status = 'draft';
    when 'hint' then
      delete from library.hints h where h.id = p_id and h.status = 'draft';
    when 'code-template' then
      delete from library.code_templates ct where ct.id = p_id and ct.status = 'draft';
    when 'assessment-template' then
      delete from library.assessment_templates at2 where at2.id = p_id and at2.status = 'draft';
    else
      raise exception 'Unknown library type: %', p_library_type;
  end case;

  return query select p_id, found;
end;
$$;

create or replace function admin_api.get_library_question_detail(
  p_id uuid
)
returns table (
  id uuid,
  stable_key text,
  title text,
  question_text text,
  question_type text,
  difficulty smallint,
  marks numeric,
  estimated_time_minutes integer,
  family_id text,
  subject text,
  hub_code text,
  course_key text,
  topic text,
  command_word text,
  exam_board text,
  tags text[],
  status text,
  version text,
  content jsonb,
  author text,
  created_at timestamptz,
  updated_at timestamptz,
  learning_outcomes text[],
  feedback_ids uuid[],
  hint_ids uuid[],
  used_by_count bigint
)
language sql stable
security definer
set search_path = ''
as $$
  select
    q.id, q.stable_key, q.title, q.question_text, q.question_type,
    q.difficulty, q.marks, q.estimated_time_minutes, q.family_id,
    q.subject, q.hub_code, q.course_key, q.topic, q.command_word,
    q.exam_board, q.tags, q.status, q.version, q.content, q.author,
    q.created_at, q.updated_at,
    coalesce(array_agg(distinct lo.learning_outcome) filter (where lo.learning_outcome is not null), '{}'),
    coalesce(array_agg(distinct qf.feedback_id) filter (where qf.feedback_id is not null), '{}'),
    coalesce(array_agg(distinct qh.hint_id) filter (where qh.hint_id is not null), '{}'),
    (select count(*) from library.usage_references ur
     where ur.library_type = 'question' and ur.library_item_id = q.id)
  from library.questions q
  left join library.question_learning_outcomes lo on lo.question_id = q.id
  left join library.question_feedback qf on qf.question_id = q.id
  left join library.question_hints qh on qh.question_id = q.id
  where q.id = p_id
    and library.is_content_author()
  group by q.id;
$$;

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Search helper: full-text across library tables                          ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create or replace function admin_api.search_library(
  p_query          text default '',
  p_library_types  text[] default '{}',
  p_status         text default null,
  p_subject        text default null,
  p_difficulty     text default null,
  p_tags           text[] default '{}',
  p_limit          integer default 50,
  p_offset         integer default 0
)
returns table (
  library_type text,
  id uuid,
  stable_key text,
  title text,
  item_type text,
  status text,
  version text,
  tags text[],
  subject text,
  author text,
  updated_at timestamptz,
  used_by_count bigint
)
language sql stable
security definer
set search_path = ''
as $$
  with items as (
    select 'question' as library_type, q.id, q.stable_key, q.title,
           q.question_type as item_type, q.status, q.version, q.tags,
           q.subject, q.author, q.updated_at
    from library.questions q
    where (p_query = '' or q.title ilike '%' || p_query || '%'
           or q.stable_key ilike '%' || p_query || '%'
           or q.topic ilike '%' || p_query || '%')
      and (array_length(p_library_types, 1) is null or 'question' = any(p_library_types))
      and (p_status is null or q.status = p_status)
      and (p_subject is null or q.subject = p_subject)
      and (p_difficulty is null or q.difficulty = p_difficulty::smallint)
      and (array_length(p_tags, 1) is null or q.tags && p_tags)

    union all

    select 'activity', a.id, a.stable_key, a.title,
           a.activity_type, a.status, a.version, a.tags,
           a.subject, a.author, a.updated_at
    from library.activities a
    where (p_query = '' or a.title ilike '%' || p_query || '%'
           or a.stable_key ilike '%' || p_query || '%'
           or a.topic ilike '%' || p_query || '%')
      and (array_length(p_library_types, 1) is null or 'activity' = any(p_library_types))
      and (p_status is null or a.status = p_status)
      and (p_subject is null or a.subject = p_subject)
      and (p_difficulty is null or a.difficulty = p_difficulty)
      and (array_length(p_tags, 1) is null or a.tags && p_tags)

    union all

    select 'template', t.id, t.stable_key, t.title,
           t.template_type, t.status, t.version, t.tags,
           t.subject, t.author, t.updated_at
    from library.templates t
    where (p_query = '' or t.title ilike '%' || p_query || '%'
           or t.stable_key ilike '%' || p_query || '%')
      and (array_length(p_library_types, 1) is null or 'template' = any(p_library_types))
      and (p_status is null or t.status = p_status)
      and (p_subject is null or t.subject = p_subject)
      and (array_length(p_tags, 1) is null or t.tags && p_tags)

    union all

    select 'resource', r.id, r.stable_key, r.title,
           r.resource_type, r.status, r.version, r.tags,
           r.subject, r.author, r.updated_at
    from library.resources r
    where (p_query = '' or r.title ilike '%' || p_query || '%'
           or r.stable_key ilike '%' || p_query || '%')
      and (array_length(p_library_types, 1) is null or 'resource' = any(p_library_types))
      and (p_status is null or r.status = p_status)
      and (p_subject is null or r.subject = p_subject)
      and (array_length(p_tags, 1) is null or r.tags && p_tags)

    union all

    select 'feedback', f.id, f.stable_key, f.title,
           f.feedback_type, f.status, f.version, f.tags,
           f.subject, f.author, f.updated_at
    from library.feedback f
    where (p_query = '' or f.title ilike '%' || p_query || '%'
           or f.stable_key ilike '%' || p_query || '%')
      and (array_length(p_library_types, 1) is null or 'feedback' = any(p_library_types))
      and (p_status is null or f.status = p_status)
      and (p_subject is null or f.subject = p_subject)
      and (array_length(p_tags, 1) is null or f.tags && p_tags)

    union all

    select 'hint', h.id, h.stable_key, h.title,
           'level-' || h.hint_level, h.status, h.version, h.tags,
           h.subject, h.author, h.updated_at
    from library.hints h
    where (p_query = '' or h.title ilike '%' || p_query || '%'
           or h.stable_key ilike '%' || p_query || '%')
      and (array_length(p_library_types, 1) is null or 'hint' = any(p_library_types))
      and (p_status is null or h.status = p_status)
      and (p_subject is null or h.subject = p_subject)
      and (array_length(p_tags, 1) is null or h.tags && p_tags)
  )
  select
    i.library_type, i.id, i.stable_key, i.title, i.item_type,
    i.status, i.version, i.tags, i.subject, i.author, i.updated_at,
    (select count(*) from library.usage_references ur
     where ur.library_type = i.library_type and ur.library_item_id = i.id) as used_by_count
  from items i
  where library.is_content_author()
  order by i.updated_at desc
  limit p_limit offset p_offset;
$$;

-- Grant schema usage to authenticated role
grant usage on schema library to authenticated;
grant select, insert, update, delete on all tables in schema library to authenticated;
