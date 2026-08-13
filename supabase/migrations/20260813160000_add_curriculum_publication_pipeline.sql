-- Controlled curriculum publication catalogue. Admin-local snapshots become
-- immutable platform records through a narrow staff RPC. Learner hubs are not
-- updated by this migration.

update platform.contract_versions
set
  compatibility = '{"previousVersion":"0.1.0","mode":"read-models-with-curriculum-publication"}'::jsonb,
  contract_document = '{"schema":"admin_api","boundary":"authenticated staff read models, one-time administrator bootstrap and curriculum publication"}'::jsonb
where contract_key = 'admin-api'
  and version = '0.2.0'
  and status = 'draft';

create table platform.curriculum_publications (
  id uuid primary key default gen_random_uuid(),
  hub_code text not null,
  course_key text not null,
  package_version text not null,
  schema_version text not null,
  source_package_version text not null,
  status text not null,
  package jsonb not null,
  content_hash text not null,
  author text not null,
  reviewer text not null default '',
  publication_notes text not null default '',
  published_by_auth_user_id uuid not null references auth.users (id) on delete restrict,
  published_by_staff_reference text not null,
  created_at timestamptz not null default clock_timestamp(),
  published_at timestamptz not null default clock_timestamp(),
  constraint curriculum_publication_hub_code_valid
    check (hub_code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint curriculum_publication_course_key_valid
    check (course_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint curriculum_publication_version_semver
    check (package_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint curriculum_publication_schema_version_semver
    check (schema_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint curriculum_publication_source_version_semver
    check (source_package_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint curriculum_publication_status_valid
    check (status in ('published', 'superseded')),
  constraint curriculum_publication_package_object
    check (jsonb_typeof(package) = 'object'),
  constraint curriculum_publication_package_size
    check (octet_length(package::text) <= 4194304),
  constraint curriculum_publication_hash_valid
    check (content_hash ~ '^[a-f0-9]{64}$'),
  constraint curriculum_publication_author_present
    check (btrim(author) <> ''),
  constraint curriculum_publication_staff_present
    check (btrim(published_by_staff_reference) <> ''),
  constraint curriculum_publication_version_unique
    unique (hub_code, course_key, package_version)
);

create index curriculum_publications_current_idx
  on platform.curriculum_publications (hub_code, course_key, status, published_at desc);

create function platform.protect_curriculum_publication()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '22023', message = 'PUBLISHED_CURRICULUM_IMMUTABLE';
  end if;

  if new.status = 'superseded'
     and old.status = 'published'
     and new.hub_code = old.hub_code
     and new.course_key = old.course_key
     and new.package_version = old.package_version
     and new.schema_version = old.schema_version
     and new.source_package_version = old.source_package_version
     and new.package = old.package
     and new.content_hash = old.content_hash
     and new.author = old.author
     and new.reviewer = old.reviewer
     and new.publication_notes = old.publication_notes
     and new.published_by_auth_user_id = old.published_by_auth_user_id
     and new.published_by_staff_reference = old.published_by_staff_reference
     and new.created_at = old.created_at
     and new.published_at = old.published_at
     and new.id = old.id then
    return new;
  end if;

  raise exception using errcode = '22023', message = 'PUBLISHED_CURRICULUM_IMMUTABLE';
end;
$$;

create trigger protect_curriculum_publication
before update or delete on platform.curriculum_publications
for each row
execute function platform.protect_curriculum_publication();

create function platform.curriculum_document_is_valid(p_doc jsonb, p_expected_schema text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select
    jsonb_typeof(p_doc) = 'object'
    and coalesce(p_doc->>'schema', '') = p_expected_schema
    and coalesce(p_doc->>'schemaVersion', '') = '0.1.0'
    and btrim(coalesce(p_doc->>'id', '')) <> ''
    and p_doc ? 'version'
    and jsonb_typeof(p_doc->'metadata') = 'object'
    and jsonb_typeof(p_doc->'relationships') = 'object'
$$;

create function platform.validate_curriculum_package(p_package jsonb)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_doc jsonb;
  v_id text;
  v_ids text[] := '{}';
  v_week_ids text[] := '{}';
  v_session_ids text[] := '{}';
  v_activity_ids text[] := '{}';
  v_ref text;
begin
  if jsonb_typeof(p_package) <> 'object' then
    raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
  end if;

  if not platform.curriculum_document_is_valid(p_package->'hub', 'lp.content.hub')
     or not platform.curriculum_document_is_valid(p_package->'curriculum', 'lp.content.curriculum') then
    raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
  end if;

  if jsonb_typeof(coalesce(p_package->'learningOutcomes', '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_package->'assignments', '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_package->'weeks', '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_package->'sessions', '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_package->'activities', '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_package->'questions', '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_package->'assets', '[]'::jsonb)) <> 'array' then
    raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
  end if;

  v_ids := v_ids || (p_package->'hub'->>'id') || (p_package->'curriculum'->>'id');

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_package->'learningOutcomes', '[]'::jsonb)) as value
  loop
    if not platform.curriculum_document_is_valid(v_doc, 'lp.content.learning-outcome') then
      raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
    end if;
    v_ids := v_ids || (v_doc->>'id');
  end loop;

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_package->'assignments', '[]'::jsonb)) as value
  loop
    if not platform.curriculum_document_is_valid(v_doc, 'lp.content.assignment') then
      raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
    end if;
    v_ids := v_ids || (v_doc->>'id');
  end loop;

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_package->'weeks', '[]'::jsonb)) as value
  loop
    if not platform.curriculum_document_is_valid(v_doc, 'lp.content.week') then
      raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
    end if;
    v_ids := v_ids || (v_doc->>'id');
    v_week_ids := v_week_ids || (v_doc->>'id');
  end loop;

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_package->'sessions', '[]'::jsonb)) as value
  loop
    if not platform.curriculum_document_is_valid(v_doc, 'lp.content.session') then
      raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
    end if;
    v_ids := v_ids || (v_doc->>'id');
    v_session_ids := v_session_ids || (v_doc->>'id');
    v_ref := nullif(btrim(coalesce(v_doc->'relationships'->>'week', '')), '');
    if v_ref is not null and not (v_ref = any (v_week_ids)) then
      raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
    end if;
  end loop;

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_package->'activities', '[]'::jsonb)) as value
  loop
    if not platform.curriculum_document_is_valid(v_doc, 'lp.content.activity') then
      raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
    end if;
    if jsonb_typeof(coalesce(v_doc->'blocks', '[]'::jsonb)) <> 'array' then
      raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
    end if;
    v_ids := v_ids || (v_doc->>'id');
    v_activity_ids := v_activity_ids || (v_doc->>'id');
    for v_id in
      select block->>'id'
      from jsonb_array_elements(coalesce(v_doc->'blocks', '[]'::jsonb)) as block
    loop
      if btrim(coalesce(v_id, '')) = '' then
        raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
      end if;
      v_ids := v_ids || v_id;
    end loop;
  end loop;

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_package->'questions', '[]'::jsonb)) as value
  loop
    if not platform.curriculum_document_is_valid(v_doc, 'lp.content.question') then
      raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
    end if;
    v_ids := v_ids || (v_doc->>'id');
  end loop;

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_package->'assets', '[]'::jsonb)) as value
  loop
    if not platform.curriculum_document_is_valid(v_doc, 'lp.content.asset') then
      raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
    end if;
    v_ids := v_ids || (v_doc->>'id');
  end loop;

  if array_length(v_ids, 1) is not null
     and array_length(v_ids, 1) <> (
       select count(distinct item) from unnest(v_ids) as item
     ) then
    raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
  end if;

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_package->'weeks', '[]'::jsonb)) as value
  loop
    for v_ref in
      select jsonb_array_elements_text(coalesce(v_doc->'relationships'->'sessions', '[]'::jsonb))
    loop
      if not (v_ref = any (v_session_ids)) then
        raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
      end if;
    end loop;
  end loop;

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_package->'sessions', '[]'::jsonb)) as value
  loop
    for v_ref in
      select jsonb_array_elements_text(coalesce(v_doc->'relationships'->'activities', '[]'::jsonb))
    loop
      if not (v_ref = any (v_activity_ids)) then
        raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
      end if;
    end loop;
  end loop;
end;
$$;

create function platform.publish_curriculum(
  p_lifecycle_status text,
  p_hub_code text,
  p_course_key text,
  p_package_version text,
  p_schema_version text,
  p_source_package_version text,
  p_package jsonb,
  p_author text,
  p_reviewer text,
  p_publication_notes text
)
returns table (
  id uuid,
  hub_code text,
  course_key text,
  package_version text,
  status text,
  published_at timestamptz,
  idempotent boolean
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_teacher learning.teachers%rowtype;
  v_hub_code text;
  v_course_key text;
  v_package_version text;
  v_schema_version text;
  v_source_package_version text;
  v_lifecycle_status text;
  v_author text;
  v_reviewer text;
  v_notes text;
  v_hash text;
  v_existing platform.curriculum_publications%rowtype;
  v_latest text;
  v_publication platform.curriculum_publications%rowtype;
begin
  v_auth_user_id := auth.uid();

  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  select teacher.*
  into v_teacher
  from learning.teachers as teacher
  where teacher.auth_user_id = v_auth_user_id
    and teacher.active;

  if not found
     or not platform.current_staff_has_role('platform_admin') then
    raise exception using errcode = '28000', message = 'PUBLICATION_NOT_AUTHORISED';
  end if;

  v_lifecycle_status := lower(nullif(btrim(p_lifecycle_status), ''));
  if v_lifecycle_status is null
     or v_lifecycle_status not in ('approved', 'published') then
    raise exception using errcode = '22023', message = 'PUBLICATION_STATUS_INVALID';
  end if;

  v_hub_code := lower(nullif(btrim(p_hub_code), ''));
  v_course_key := lower(nullif(btrim(p_course_key), ''));
  v_package_version := nullif(btrim(p_package_version), '');
  v_schema_version := nullif(btrim(p_schema_version), '');
  v_source_package_version := nullif(btrim(p_source_package_version), '');
  v_author := nullif(btrim(p_author), '');
  v_reviewer := coalesce(btrim(p_reviewer), '');
  v_notes := coalesce(btrim(p_publication_notes), '');

  if v_hub_code is null
     or v_course_key is null
     or v_package_version is null
     or v_package_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$'
     or v_author is null then
    raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
  end if;

  if v_schema_version is distinct from '0.1.0' then
    raise exception using errcode = '22023', message = 'UNSUPPORTED_SCHEMA_VERSION';
  end if;

  if v_source_package_version is distinct from '0.1.0' then
    raise exception using errcode = '22023', message = 'UNSUPPORTED_PACKAGE_VERSION';
  end if;

  perform platform.validate_curriculum_package(p_package);

  if p_package->'hub'->>'id' is distinct from v_hub_code
     or p_package->'curriculum'->'metadata'->>'course' is distinct from v_course_key then
    raise exception using errcode = '22023', message = 'PUBLICATION_CONTEXT_MISMATCH';
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

  v_hash := encode(extensions.digest(p_package::text, 'sha256'), 'hex');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('curriculum-publication:' || v_hub_code || ':' || v_course_key, 0)
  );

  select publication.*
  into v_existing
  from platform.curriculum_publications as publication
  where publication.hub_code = v_hub_code
    and publication.course_key = v_course_key
    and publication.package_version = v_package_version
  for update;

  if found then
    if v_existing.content_hash = v_hash then
      return query
      select
        v_existing.id,
        v_existing.hub_code,
        v_existing.course_key,
        v_existing.package_version,
        v_existing.status,
        v_existing.published_at,
        true;
      return;
    end if;

    raise exception using errcode = '22023', message = 'DUPLICATE_VERSION';
  end if;

  select publication.package_version
  into v_latest
  from platform.curriculum_publications as publication
  where publication.hub_code = v_hub_code
    and publication.course_key = v_course_key
  order by string_to_array(publication.package_version, '.')::int[] desc
  limit 1;

  if v_latest is not null
     and string_to_array(v_package_version, '.')::int[] <= string_to_array(v_latest, '.')::int[] then
    raise exception using errcode = '22023', message = 'PUBLICATION_VERSION_REGRESSION';
  end if;

  update platform.curriculum_publications
  set status = 'superseded'
  where hub_code = v_hub_code
    and course_key = v_course_key
    and status = 'published';

  insert into platform.curriculum_publications (
    hub_code,
    course_key,
    package_version,
    schema_version,
    source_package_version,
    status,
    package,
    content_hash,
    author,
    reviewer,
    publication_notes,
    published_by_auth_user_id,
    published_by_staff_reference
  ) values (
    v_hub_code,
    v_course_key,
    v_package_version,
    v_schema_version,
    v_source_package_version,
    'published',
    p_package,
    v_hash,
    v_author,
    v_reviewer,
    v_notes,
    v_auth_user_id,
    v_teacher.staff_reference
  )
  returning * into v_publication;

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'curriculum.publication.published',
    v_auth_user_id,
    'staff',
    'curriculum-publication',
    v_publication.id::text,
    'succeeded',
    jsonb_build_object(
      'hubCode', v_hub_code,
      'courseKey', v_course_key,
      'version', v_package_version,
      'schemaVersion', v_schema_version,
      'packageVersion', v_source_package_version,
      'author', v_author,
      'reviewer', v_reviewer,
      'publishedBy', v_teacher.staff_reference,
      'notes', v_notes
    )
  );

  return query
  select
    v_publication.id,
    v_publication.hub_code,
    v_publication.course_key,
    v_publication.package_version,
    v_publication.status,
    v_publication.published_at,
    false;
end;
$$;

create function admin_api.publish_curriculum(
  p_lifecycle_status text,
  p_hub_code text,
  p_course_key text,
  p_package_version text,
  p_schema_version text,
  p_source_package_version text,
  p_package jsonb,
  p_author text,
  p_reviewer text,
  p_publication_notes text
)
returns table (
  id uuid,
  hub_code text,
  course_key text,
  package_version text,
  status text,
  published_at timestamptz,
  idempotent boolean
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from platform.publish_curriculum(
    p_lifecycle_status,
    p_hub_code,
    p_course_key,
    p_package_version,
    p_schema_version,
    p_source_package_version,
    p_package,
    p_author,
    p_reviewer,
    p_publication_notes
  )
$$;

create view admin_api.curriculum_publications
with (security_invoker = true)
as
select
  publication.id,
  publication.hub_code,
  publication.course_key,
  publication.package_version,
  publication.schema_version,
  publication.source_package_version,
  publication.status,
  publication.author,
  publication.reviewer,
  publication.publication_notes,
  publication.published_by_staff_reference,
  publication.created_at,
  publication.published_at,
  publication.content_hash
from platform.curriculum_publications as publication
where (select platform.current_staff_has_any_role(
  array['platform_admin', 'curriculum_admin', 'operations', 'auditor']
));

create function api.published_curriculum()
returns table (
  hub_code text,
  course_key text,
  package_version text,
  schema_version text,
  source_package_version text,
  published_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    publication.hub_code,
    publication.course_key,
    publication.package_version,
    publication.schema_version,
    publication.source_package_version,
    publication.published_at
  from platform.curriculum_publications as publication
  where publication.status = 'published'
  order by publication.hub_code, publication.course_key
$$;

alter table platform.curriculum_publications enable row level security;

revoke all on platform.curriculum_publications
  from public, anon, authenticated;
grant select on platform.curriculum_publications to authenticated;

create policy curriculum_publications_staff_read
on platform.curriculum_publications
for select to authenticated
using ((select platform.current_staff_has_any_role(
  array['platform_admin', 'curriculum_admin', 'operations', 'auditor']
)));

revoke all on function platform.curriculum_document_is_valid(jsonb, text)
  from public, anon, authenticated;
revoke all on function platform.validate_curriculum_package(jsonb)
  from public, anon, authenticated;
revoke all on function platform.protect_curriculum_publication()
  from public, anon, authenticated;
revoke all on function platform.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text)
  from public, anon, authenticated;
revoke all on function admin_api.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text)
  from public, anon, authenticated;
revoke all on function api.published_curriculum()
  from public, anon, authenticated;

grant execute on function platform.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text)
  to authenticated;
grant execute on function admin_api.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text)
  to authenticated;
grant execute on function api.published_curriculum()
  to authenticated;

revoke all on admin_api.curriculum_publications
  from public, anon, authenticated;
grant select on admin_api.curriculum_publications to authenticated;

comment on table platform.curriculum_publications is
  'Immutable published curriculum snapshots. Content changes require a new version.';
comment on function platform.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text) is
  'Publishes an approved or locally published curriculum snapshot after server-side validation. Identity comes from auth.uid().';
comment on function admin_api.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text) is
  'Browser-safe wrapper for controlled curriculum publication.';
comment on function api.published_curriculum() is
  'Learner-safe metadata for currently published curriculum packages. Full packages stay in Admin and the platform catalogue.';
comment on view admin_api.curriculum_publications is
  'Staff publication history without the stored package body.';
