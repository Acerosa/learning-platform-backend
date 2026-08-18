create function api.published_curriculum_package(
  p_hub_code text,
  p_course_key text,
  p_package_version text
)
returns table (
  hub_code text,
  course_key text,
  package_version text,
  schema_version text,
  source_package_version text,
  published_at timestamptz,
  content_hash text,
  package jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hub_code text;
  v_course_key text;
  v_package_version text;
  v_publication platform.curriculum_publications%rowtype;
begin
  v_hub_code := lower(nullif(btrim(p_hub_code), ''));
  v_course_key := lower(nullif(btrim(p_course_key), ''));
  v_package_version := nullif(btrim(p_package_version), '');

  if v_hub_code is null
     or v_hub_code !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     or v_course_key is null
     or v_course_key !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
  end if;

  if not exists (
    select 1
    from platform.hubs as hub
    where hub.hub_code = v_hub_code
      and hub.active
  ) then
    raise exception using errcode = '22023', message = 'HUB_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from learning.courses as course
    where course.stable_key = v_course_key
  ) then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from platform.hub_course_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.courses as course on course.id = link.course_id
    where hub.hub_code = v_hub_code
      and course.stable_key = v_course_key
      and link.active
  ) then
    raise exception using errcode = '22023', message = 'PUBLICATION_CONTEXT_MISMATCH';
  end if;

  if v_package_version is null then
    select publication.*
    into v_publication
    from platform.curriculum_publications as publication
    where publication.hub_code = v_hub_code
      and publication.course_key = v_course_key
      and publication.status = 'published'
    limit 1;
  else
    select publication.*
    into v_publication
    from platform.curriculum_publications as publication
    where publication.hub_code = v_hub_code
      and publication.course_key = v_course_key
      and publication.package_version = v_package_version
    limit 1;
  end if;

  if not found then
    raise exception using errcode = '22023', message = 'PUBLICATION_NOT_FOUND';
  end if;

  hub_code := v_publication.hub_code;
  course_key := v_publication.course_key;
  package_version := v_publication.package_version;
  schema_version := v_publication.schema_version;
  source_package_version := v_publication.source_package_version;
  published_at := v_publication.published_at;
  content_hash := v_publication.content_hash;
  package := platform.learner_curriculum_package(
    v_publication.package,
    v_publication.package_version,
    v_publication.source_package_version
  );
  return next;
end;
$$;

create or replace function api.published_curriculum_package(
  p_hub_code text,
  p_course_key text
)
returns table (
  hub_code text,
  course_key text,
  package_version text,
  schema_version text,
  source_package_version text,
  published_at timestamptz,
  content_hash text,
  package jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select *
  from api.published_curriculum_package(p_hub_code, p_course_key, null::text);
$$;

revoke all on function api.published_curriculum_package(text, text, text)
  from public, anon, authenticated;
grant execute on function api.published_curriculum_package(text, text, text)
  to anon, authenticated;
grant execute on function api.published_curriculum_package(text, text)
  to anon, authenticated;

comment on function api.published_curriculum_package(text, text, text) is
  'Public teaching package for a hub, course and optional package version. Null version returns the current published row. Explicit versions may be superseded. Never returns drafts, staff publication fields or learning.question_marking.';
comment on function api.published_curriculum_package(text, text) is
  'Public current published teaching package for a hub and course. Never returns drafts, superseded rows, staff publication fields or learning.question_marking.';
