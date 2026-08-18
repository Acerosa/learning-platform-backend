-- Composition Engine: references, overrides, detach tracking, composition
-- templates, and recipes for curriculum composition from library objects.

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Composition References                                                  ║
-- ║  Tracks which library item each curriculum instance came from.           ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.composition_references (
  id                  uuid primary key default gen_random_uuid(),
  curriculum_draft_id uuid not null,
  instance_id         text not null,
  library_type        text not null,
  library_item_id     uuid not null,
  library_version     text not null,
  state               text not null default 'inherited',
  overrides           jsonb not null default '{}',
  detached_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint comp_ref_library_type_valid
    check (library_type in ('question', 'activity', 'resource', 'template', 'feedback', 'hint')),
  constraint comp_ref_state_valid
    check (state in ('inherited', 'overridden', 'detached')),
  constraint comp_ref_unique
    unique (curriculum_draft_id, instance_id, library_type)
);

create index comp_ref_draft_idx
  on library.composition_references (curriculum_draft_id);
create index comp_ref_library_item_idx
  on library.composition_references (library_type, library_item_id);
create index comp_ref_state_idx
  on library.composition_references (state);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Composition Templates (Week/Session templates)                          ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.composition_templates (
  id              uuid primary key default gen_random_uuid(),
  stable_key      text not null unique,
  title           text not null,
  template_type   text not null,
  description     text,
  specification   jsonb not null default '{}',
  tags            text[] not null default '{}',
  status          text not null default 'draft',
  version         text not null default '1.0.0',
  author          text not null default '',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint comp_template_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint comp_template_type_valid
    check (template_type in (
      'weekly-lesson', 'practical-lesson', 'revision-lesson',
      'assessment-week', 'project-week', 'custom'
    )),
  constraint comp_template_status_valid
    check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint comp_template_version_semver
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

create index comp_templates_type_idx on library.composition_templates (template_type);
create index comp_templates_status_idx on library.composition_templates (status);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Curriculum Recipes (session layout presets)                              ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create table library.curriculum_recipes (
  id              uuid primary key default gen_random_uuid(),
  stable_key      text not null unique,
  title           text not null,
  recipe_type     text not null,
  description     text,
  specification   jsonb not null default '{}',
  tags            text[] not null default '{}',
  status          text not null default 'draft',
  version         text not null default '1.0.0',
  author          text not null default '',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint recipe_key_valid
    check (stable_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint recipe_type_valid
    check (recipe_type in (
      'revision-session', 'retrieval-session', 'practical-session',
      'assessment-session', 'homework-session', 'project-session', 'custom'
    )),
  constraint recipe_status_valid
    check (status in ('draft', 'published', 'superseded', 'archived')),
  constraint recipe_version_semver
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

create index recipes_type_idx on library.curriculum_recipes (recipe_type);
create index recipes_status_idx on library.curriculum_recipes (status);

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  RLS for new tables                                                      ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

alter table library.composition_references enable row level security;
alter table library.composition_templates enable row level security;
alter table library.curriculum_recipes enable row level security;

do $$
declare
  _tbl text;
begin
  for _tbl in values ('composition_references'), ('composition_templates'), ('curriculum_recipes')
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

create or replace view admin_api.composition_references as
select
  cr.id,
  cr.curriculum_draft_id,
  cr.instance_id,
  cr.library_type,
  cr.library_item_id,
  cr.library_version,
  cr.state,
  cr.overrides,
  cr.detached_at,
  cr.created_at,
  cr.updated_at
from library.composition_references cr;

create or replace view admin_api.composition_templates as
select
  ct.id,
  ct.stable_key,
  ct.title,
  ct.template_type,
  ct.description,
  ct.specification,
  ct.tags,
  ct.status,
  ct.version,
  ct.author,
  ct.created_at,
  ct.updated_at
from library.composition_templates ct;

create or replace view admin_api.curriculum_recipes as
select
  r.id,
  r.stable_key,
  r.title,
  r.recipe_type,
  r.description,
  r.specification,
  r.tags,
  r.status,
  r.version,
  r.author,
  r.created_at,
  r.updated_at
from library.curriculum_recipes r;

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Admin API RPCs                                                          ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

create or replace function admin_api.save_composition_reference(
  p_curriculum_draft_id  uuid,
  p_instance_id          text,
  p_library_type         text,
  p_library_item_id      uuid,
  p_library_version      text,
  p_state                text default 'inherited',
  p_overrides            jsonb default '{}'
)
returns table (id uuid, instance_id text, state text, created boolean)
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

  select cr.id into v_id
  from library.composition_references cr
  where cr.curriculum_draft_id = p_curriculum_draft_id
    and cr.instance_id = p_instance_id
    and cr.library_type = p_library_type;

  if v_id is null then
    insert into library.composition_references (
      curriculum_draft_id, instance_id, library_type,
      library_item_id, library_version, state, overrides
    ) values (
      p_curriculum_draft_id, p_instance_id, p_library_type,
      p_library_item_id, p_library_version, p_state, p_overrides
    )
    returning composition_references.id into v_id;
    v_created := true;
  else
    update library.composition_references cr set
      library_item_id = p_library_item_id,
      library_version = p_library_version,
      state = p_state,
      overrides = p_overrides,
      detached_at = case when p_state = 'detached' then coalesce(cr.detached_at, now()) else null end,
      updated_at = now()
    where cr.id = v_id;
  end if;

  return query select v_id, p_instance_id, p_state, v_created;
end;
$$;

create or replace function admin_api.detach_composition_reference(
  p_curriculum_draft_id uuid,
  p_instance_id text,
  p_library_type text
)
returns table (id uuid, instance_id text, detached boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  update library.composition_references cr set
    state = 'detached',
    detached_at = now(),
    updated_at = now()
  where cr.curriculum_draft_id = p_curriculum_draft_id
    and cr.instance_id = p_instance_id
    and cr.library_type = p_library_type
    and cr.state <> 'detached'
  returning cr.id into v_id;

  return query select coalesce(v_id, '00000000-0000-0000-0000-000000000000'::uuid),
    p_instance_id, v_id is not null;
end;
$$;

create or replace function admin_api.composition_update_check(
  p_curriculum_draft_id uuid
)
returns table (
  instance_id text,
  library_type text,
  library_item_id uuid,
  current_version text,
  latest_version text,
  update_available boolean
)
language sql stable
security definer
set search_path = ''
as $$
  select
    cr.instance_id,
    cr.library_type,
    cr.library_item_id,
    cr.library_version as current_version,
    coalesce(
      case cr.library_type
        when 'question' then (select q.version from library.questions q where q.id = cr.library_item_id)
        when 'activity' then (select a.version from library.activities a where a.id = cr.library_item_id)
        when 'resource' then (select r.version from library.resources r where r.id = cr.library_item_id)
        when 'template' then (select t.version from library.templates t where t.id = cr.library_item_id)
        when 'feedback' then (select f.version from library.feedback f where f.id = cr.library_item_id)
        when 'hint' then (select h.version from library.hints h where h.id = cr.library_item_id)
      end,
      cr.library_version
    ) as latest_version,
    cr.library_version <> coalesce(
      case cr.library_type
        when 'question' then (select q.version from library.questions q where q.id = cr.library_item_id)
        when 'activity' then (select a.version from library.activities a where a.id = cr.library_item_id)
        when 'resource' then (select r.version from library.resources r where r.id = cr.library_item_id)
        when 'template' then (select t.version from library.templates t where t.id = cr.library_item_id)
        when 'feedback' then (select f.version from library.feedback f where f.id = cr.library_item_id)
        when 'hint' then (select h.version from library.hints h where h.id = cr.library_item_id)
      end,
      cr.library_version
    ) as update_available
  from library.composition_references cr
  where cr.curriculum_draft_id = p_curriculum_draft_id
    and cr.state <> 'detached'
    and library.is_content_author();
$$;

create or replace function admin_api.composition_impact_analysis(
  p_library_type text,
  p_library_item_id uuid
)
returns table (
  curriculum_draft_count bigint,
  curriculum_publication_count bigint,
  total_usage_count bigint,
  attempt_count bigint
)
language sql stable
security definer
set search_path = ''
as $$
  select
    (select count(distinct cr.curriculum_draft_id)
     from library.composition_references cr
     where cr.library_type = p_library_type and cr.library_item_id = p_library_item_id),
    (select count(*)
     from library.usage_references ur
     where ur.library_type = p_library_type and ur.library_item_id = p_library_item_id
       and ur.used_in_type = 'curriculum-publication'),
    (select count(*)
     from library.usage_references ur
     where ur.library_type = p_library_type and ur.library_item_id = p_library_item_id),
    0::bigint
  where library.is_content_author();
$$;

-- Grant access to new tables
grant select, insert, update, delete on library.composition_references to authenticated;
grant select, insert, update, delete on library.composition_templates to authenticated;
grant select, insert, update, delete on library.curriculum_recipes to authenticated;
