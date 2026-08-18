-- Phase 4 blocker resolution:
-- - custom composition template CRUD
-- - custom curriculum recipe CRUD
-- - persisted composition reference state for draft reopen

create or replace function admin_api.save_composition_template(
  p_id uuid default null,
  p_stable_key text default null,
  p_title text default null,
  p_template_type text default 'custom',
  p_description text default null,
  p_specification jsonb default '{}'::jsonb,
  p_tags text[] default '{}'::text[],
  p_status text default 'draft',
  p_version text default '1.0.0'
)
returns table (
  id uuid,
  stable_key text,
  title text,
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
  v_author text;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  if coalesce(jsonb_typeof(p_specification), 'null') <> 'object' then
    raise exception 'Template specification must be a JSON object';
  end if;

  select coalesce(
    (select t.display_name from learning.teachers t where t.auth_user_id = auth.uid() limit 1),
    'Unknown'
  ) into v_author;

  if p_id is not null then
    select ct.id into v_id
    from library.composition_templates ct
    where ct.id = p_id;
  end if;

  if v_id is null then
    insert into library.composition_templates (
      id, stable_key, title, template_type, description, specification,
      tags, status, version, author
    ) values (
      coalesce(p_id, gen_random_uuid()),
      p_stable_key,
      p_title,
      coalesce(p_template_type, 'custom'),
      p_description,
      p_specification,
      coalesce(p_tags, '{}'::text[]),
      p_status,
      p_version,
      v_author
    )
    returning composition_templates.id into v_id;
    v_created := true;
  else
    update library.composition_templates ct
    set stable_key = coalesce(p_stable_key, ct.stable_key),
        title = coalesce(p_title, ct.title),
        template_type = coalesce(p_template_type, ct.template_type),
        description = p_description,
        specification = coalesce(p_specification, ct.specification),
        tags = coalesce(p_tags, ct.tags),
        status = coalesce(p_status, ct.status),
        version = coalesce(p_version, ct.version),
        updated_at = now()
    where ct.id = v_id;
  end if;

  return query
  select ct.id, ct.stable_key, ct.title, ct.status, ct.version, v_created
  from library.composition_templates ct
  where ct.id = v_id;
end;
$$;

create or replace function admin_api.archive_composition_template(p_id uuid)
returns table (id uuid, archived boolean)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  update library.composition_templates
  set status = 'archived',
      updated_at = now()
  where composition_templates.id = p_id
    and composition_templates.status <> 'archived';

  return query select p_id, found;
end;
$$;

create or replace function admin_api.restore_composition_template(p_id uuid)
returns table (id uuid, restored boolean)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  update library.composition_templates
  set status = 'draft',
      updated_at = now()
  where composition_templates.id = p_id
    and composition_templates.status = 'archived';

  return query select p_id, found;
end;
$$;

create or replace function admin_api.duplicate_composition_template(
  p_id uuid,
  p_stable_key text,
  p_title text
)
returns table (id uuid, stable_key text, title text, status text, version text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_author text;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  select coalesce(
    (select t.display_name from learning.teachers t where t.auth_user_id = auth.uid() limit 1),
    'Unknown'
  ) into v_author;

  return query
  with duplicated as (
    insert into library.composition_templates (
      stable_key, title, template_type, description, specification,
      tags, status, version, author
    )
    select
      p_stable_key,
      p_title,
      'custom',
      ct.description,
      ct.specification,
      ct.tags,
      'draft',
      '1.0.0',
      v_author
    from library.composition_templates ct
    where ct.id = p_id
    returning composition_templates.id, composition_templates.stable_key,
      composition_templates.title, composition_templates.status, composition_templates.version
  )
  select * from duplicated;
end;
$$;

create or replace function admin_api.list_composition_templates(
  p_include_archived boolean default false
)
returns table (
  id uuid,
  stable_key text,
  title text,
  template_type text,
  description text,
  specification jsonb,
  tags text[],
  status text,
  version text,
  author text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select
    ct.id, ct.stable_key, ct.title, ct.template_type, ct.description,
    ct.specification, ct.tags, ct.status, ct.version, ct.author,
    ct.created_at, ct.updated_at
  from library.composition_templates ct
  where library.is_content_author()
    and (p_include_archived or ct.status <> 'archived')
  order by ct.updated_at desc, ct.title asc;
$$;

create or replace function admin_api.save_curriculum_recipe(
  p_id uuid default null,
  p_stable_key text default null,
  p_title text default null,
  p_recipe_type text default 'custom',
  p_description text default null,
  p_specification jsonb default '{}'::jsonb,
  p_tags text[] default '{}'::text[],
  p_status text default 'draft',
  p_version text default '1.0.0'
)
returns table (
  id uuid,
  stable_key text,
  title text,
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
  v_author text;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  if coalesce(jsonb_typeof(p_specification), 'null') <> 'object' then
    raise exception 'Recipe specification must be a JSON object';
  end if;

  select coalesce(
    (select t.display_name from learning.teachers t where t.auth_user_id = auth.uid() limit 1),
    'Unknown'
  ) into v_author;

  if p_id is not null then
    select cr.id into v_id
    from library.curriculum_recipes cr
    where cr.id = p_id;
  end if;

  if v_id is null then
    insert into library.curriculum_recipes (
      id, stable_key, title, recipe_type, description, specification,
      tags, status, version, author
    ) values (
      coalesce(p_id, gen_random_uuid()),
      p_stable_key,
      p_title,
      coalesce(p_recipe_type, 'custom'),
      p_description,
      p_specification,
      coalesce(p_tags, '{}'::text[]),
      p_status,
      p_version,
      v_author
    )
    returning curriculum_recipes.id into v_id;
    v_created := true;
  else
    update library.curriculum_recipes cr
    set stable_key = coalesce(p_stable_key, cr.stable_key),
        title = coalesce(p_title, cr.title),
        recipe_type = coalesce(p_recipe_type, cr.recipe_type),
        description = p_description,
        specification = coalesce(p_specification, cr.specification),
        tags = coalesce(p_tags, cr.tags),
        status = coalesce(p_status, cr.status),
        version = coalesce(p_version, cr.version),
        updated_at = now()
    where cr.id = v_id;
  end if;

  return query
  select cr.id, cr.stable_key, cr.title, cr.status, cr.version, v_created
  from library.curriculum_recipes cr
  where cr.id = v_id;
end;
$$;

create or replace function admin_api.archive_curriculum_recipe(p_id uuid)
returns table (id uuid, archived boolean)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  update library.curriculum_recipes
  set status = 'archived',
      updated_at = now()
  where curriculum_recipes.id = p_id
    and curriculum_recipes.status <> 'archived';

  return query select p_id, found;
end;
$$;

create or replace function admin_api.restore_curriculum_recipe(p_id uuid)
returns table (id uuid, restored boolean)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  update library.curriculum_recipes
  set status = 'draft',
      updated_at = now()
  where curriculum_recipes.id = p_id
    and curriculum_recipes.status = 'archived';

  return query select p_id, found;
end;
$$;

create or replace function admin_api.duplicate_curriculum_recipe(
  p_id uuid,
  p_stable_key text,
  p_title text
)
returns table (id uuid, stable_key text, title text, status text, version text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_author text;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  select coalesce(
    (select t.display_name from learning.teachers t where t.auth_user_id = auth.uid() limit 1),
    'Unknown'
  ) into v_author;

  return query
  with duplicated as (
    insert into library.curriculum_recipes (
      stable_key, title, recipe_type, description, specification,
      tags, status, version, author
    )
    select
      p_stable_key,
      p_title,
      'custom',
      cr.description,
      cr.specification,
      cr.tags,
      'draft',
      '1.0.0',
      v_author
    from library.curriculum_recipes cr
    where cr.id = p_id
    returning curriculum_recipes.id, curriculum_recipes.stable_key,
      curriculum_recipes.title, curriculum_recipes.status, curriculum_recipes.version
  )
  select * from duplicated;
end;
$$;

create or replace function admin_api.list_curriculum_recipes(
  p_include_archived boolean default false
)
returns table (
  id uuid,
  stable_key text,
  title text,
  recipe_type text,
  description text,
  specification jsonb,
  tags text[],
  status text,
  version text,
  author text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select
    cr.id, cr.stable_key, cr.title, cr.recipe_type, cr.description,
    cr.specification, cr.tags, cr.status, cr.version, cr.author,
    cr.created_at, cr.updated_at
  from library.curriculum_recipes cr
  where library.is_content_author()
    and (p_include_archived or cr.status <> 'archived')
  order by cr.updated_at desc, cr.title asc;
$$;

create or replace function admin_api.save_composition_draft_state(
  p_curriculum_draft_id uuid,
  p_references jsonb default '[]'::jsonb
)
returns table (curriculum_draft_id uuid, saved_count integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_saved_count integer := 0;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  if coalesce(jsonb_typeof(p_references), 'null') <> 'array' then
    raise exception 'Composition references payload must be a JSON array';
  end if;

  delete from library.composition_references cr
  where cr.curriculum_draft_id = p_curriculum_draft_id;

  insert into library.composition_references (
    curriculum_draft_id,
    instance_id,
    library_type,
    library_item_id,
    library_version,
    state,
    overrides,
    detached_at
  )
  select
    p_curriculum_draft_id,
    ref.instance_id,
    ref.library_type,
    ref.library_item_id,
    ref.library_version,
    ref.state,
    coalesce(ref.overrides, '{}'::jsonb),
    case when ref.state = 'detached' then now() else null end
  from jsonb_to_recordset(p_references) as ref(
    instance_id text,
    library_type text,
    library_item_id uuid,
    library_version text,
    state text,
    overrides jsonb
  );

  get diagnostics v_saved_count = row_count;

  return query select p_curriculum_draft_id, v_saved_count;
end;
$$;

create or replace function admin_api.get_composition_draft_state(
  p_curriculum_draft_id uuid
)
returns table (
  instance_id text,
  library_type text,
  library_item_id uuid,
  library_version text,
  state text,
  overrides jsonb,
  detached_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select
    cr.instance_id,
    cr.library_type,
    cr.library_item_id,
    cr.library_version,
    cr.state,
    cr.overrides,
    cr.detached_at,
    cr.updated_at
  from library.composition_references cr
  where cr.curriculum_draft_id = p_curriculum_draft_id
    and library.is_content_author()
  order by cr.created_at asc, cr.instance_id asc;
$$;

grant execute on function admin_api.save_composition_template(uuid, text, text, text, text, jsonb, text[], text, text) to authenticated;
grant execute on function admin_api.archive_composition_template(uuid) to authenticated;
grant execute on function admin_api.restore_composition_template(uuid) to authenticated;
grant execute on function admin_api.duplicate_composition_template(uuid, text, text) to authenticated;
grant execute on function admin_api.list_composition_templates(boolean) to authenticated;
grant execute on function admin_api.save_curriculum_recipe(uuid, text, text, text, text, jsonb, text[], text, text) to authenticated;
grant execute on function admin_api.archive_curriculum_recipe(uuid) to authenticated;
grant execute on function admin_api.restore_curriculum_recipe(uuid) to authenticated;
grant execute on function admin_api.duplicate_curriculum_recipe(uuid, text, text) to authenticated;
grant execute on function admin_api.list_curriculum_recipes(boolean) to authenticated;
grant execute on function admin_api.save_composition_draft_state(uuid, jsonb) to authenticated;
grant execute on function admin_api.get_composition_draft_state(uuid) to authenticated;
