-- Phase B stage 4: public curriculum RPC reads precomputed learner packages.
-- Stored packages are used only when learner_package_sanitisation_version matches
-- the current platform.learner_package_sanitisation_version(). Otherwise the RPC
-- rebuilds with Phase A rules so outdated sanitisation cannot leak restricted keys.

create or replace function api.published_curriculum_package(
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
  if v_publication.learner_package is not null
     and v_publication.learner_package_sanitisation_version
       is not distinct from platform.learner_package_sanitisation_version() then
    package := v_publication.learner_package;
  else
    package := platform.learner_curriculum_package(
      v_publication.package,
      v_publication.package_version,
      v_publication.source_package_version
    );
  end if;
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
revoke all on function api.published_curriculum_package(text, text)
  from public, anon, authenticated;
grant execute on function api.published_curriculum_package(text, text, text)
  to anon, authenticated;
grant execute on function api.published_curriculum_package(text, text)
  to anon, authenticated;

comment on function api.published_curriculum_package(text, text, text) is
  'Public teaching package for a hub, course and optional package version. Uses precomputed learner_package only when sanitisation_version matches the current rules; otherwise rebuilds with Phase A. Never returns drafts, staff publication fields or learning.question_marking.';
comment on function api.published_curriculum_package(text, text) is
  'Public current published teaching package for a hub and course. Uses a current-version precomputed learner_package when present. Never returns drafts, superseded rows, staff publication fields or learning.question_marking.';

create or replace view admin_api.publications_missing_learner_packages
with (security_invoker = true)
as
select
  publication.id,
  publication.hub_code,
  publication.course_key,
  publication.package_version,
  publication.status,
  publication.published_at,
  publication.learner_package_sanitisation_version,
  platform.learner_package_sanitisation_version() as expected_sanitisation_version
from platform.curriculum_publications as publication
where (
  publication.learner_package is null
  or publication.learner_package_sanitisation_version
    is distinct from platform.learner_package_sanitisation_version()
)
and (select platform.current_staff_has_any_role(
  array['platform_admin', 'curriculum_admin', 'operations', 'auditor']
));

revoke all on admin_api.publications_missing_learner_packages
  from public, anon, authenticated;
grant select on admin_api.publications_missing_learner_packages to authenticated;

comment on view admin_api.publications_missing_learner_packages is
  'Staff diagnostic of publications missing a current learner_package. Does not expose package bodies.';
