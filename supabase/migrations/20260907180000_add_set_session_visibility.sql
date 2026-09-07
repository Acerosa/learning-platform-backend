-- Generic server-authoritative session visibility for any published hub/course.
-- Mutates only session.metadata.status on a server-side copy of the current publication.
-- Does not accept package JSON from the client.

create or replace function platform.bump_patch_version(p_version text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_parts int[];
begin
  if p_version is null or p_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
    raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
  end if;
  v_parts := string_to_array(p_version, '.')::int[];
  return format('%s.%s.%s', v_parts[1], v_parts[2], v_parts[3] + 1);
end;
$$;

comment on function platform.bump_patch_version(text) is
  'Increments the patch segment of a semver catalogue version.';

create or replace function platform.set_session_visibility(
  p_hub_code text,
  p_course_key text,
  p_session_id text,
  p_status text
)
returns table (
  publication_id uuid,
  previous_package_version text,
  package_version text,
  session_id text,
  previous_status text,
  status text,
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
  v_session_id text;
  v_status text;
  v_current platform.curriculum_publications%rowtype;
  v_package jsonb;
  v_session jsonb;
  v_week_id text;
  v_week jsonb;
  v_week_status text;
  v_previous_status text;
  v_next_version text;
  v_notes text;
  v_hash text;
  v_publication platform.curriculum_publications%rowtype;
  v_action text;
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

  v_hub_code := lower(nullif(btrim(p_hub_code), ''));
  v_course_key := lower(nullif(btrim(p_course_key), ''));
  v_session_id := nullif(btrim(p_session_id), '');
  v_status := lower(nullif(btrim(p_status), ''));

  if v_hub_code is null then
    raise exception using errcode = '22023', message = 'HUB_NOT_FOUND';
  end if;
  if v_course_key is null then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;
  if v_session_id is null then
    raise exception using errcode = '22023', message = 'SESSION_NOT_FOUND';
  end if;
  if v_status is null or v_status not in ('available', 'planned') then
    raise exception using errcode = '22023', message = 'SESSION_STATUS_INVALID';
  end if;

  if not exists (
    select 1 from platform.hubs as hub
    where hub.hub_code = v_hub_code and hub.active
  ) then
    raise exception using errcode = '22023', message = 'HUB_NOT_FOUND';
  end if;

  if not exists (
    select 1 from learning.courses as course
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

  -- Same publication lock key as publish_curriculum so visibility and full publishes serialise.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('curriculum-publication:' || v_hub_code || ':' || v_course_key, 0)
  );

  select publication.*
  into v_current
  from platform.curriculum_publications as publication
  where publication.hub_code = v_hub_code
    and publication.course_key = v_course_key
    and publication.status = 'published'
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'PUBLICATION_NOT_FOUND';
  end if;

  v_package := v_current.package;
  select value
  into v_session
  from jsonb_array_elements(coalesce(v_package->'sessions', '[]'::jsonb)) as value
  where value->>'id' = v_session_id
  limit 1;

  if v_session is null then
    raise exception using errcode = '22023', message = 'SESSION_NOT_FOUND';
  end if;

  v_previous_status := lower(nullif(btrim(coalesce(v_session->'metadata'->>'status', '')), ''));
  if v_previous_status is null then
    v_previous_status := 'planned';
  end if;

  -- Idempotent: already at target status → no catalogue noise.
  if v_previous_status = v_status then
    return query
    select
      v_current.id,
      v_current.package_version,
      v_current.package_version,
      v_session_id,
      v_previous_status,
      v_status,
      true;
    return;
  end if;

  v_week_id := nullif(btrim(coalesce(v_session->'relationships'->>'week', '')), '');
  if v_week_id is null then
    select week_doc.value->>'id'
    into v_week_id
    from jsonb_array_elements(coalesce(v_package->'weeks', '[]'::jsonb)) as week_doc(value)
    where exists (
      select 1
      from jsonb_array_elements_text(coalesce(week_doc.value->'relationships'->'sessions', '[]'::jsonb)) as sid(value)
      where sid.value = v_session_id
    )
    limit 1;
  end if;

  if v_week_id is null then
    raise exception using errcode = '22023', message = 'WEEK_NOT_FOUND';
  end if;

  select value
  into v_week
  from jsonb_array_elements(coalesce(v_package->'weeks', '[]'::jsonb)) as value
  where value->>'id' = v_week_id
  limit 1;

  if v_week is null then
    raise exception using errcode = '22023', message = 'WEEK_NOT_FOUND';
  end if;

  v_week_status := lower(nullif(btrim(coalesce(v_week->'metadata'->>'status', '')), ''));
  if v_week_status is null then
    v_week_status := 'planned';
  end if;

  if v_status = 'available' and v_week_status is distinct from 'available' then
    raise exception using errcode = '22023', message = 'WEEK_NOT_AVAILABLE';
  end if;

  v_package := jsonb_set(
    v_package,
    '{sessions}',
    (
      select coalesce(jsonb_agg(
        case
          when sess.value->>'id' = v_session_id then
            jsonb_set(
              sess.value,
              '{metadata,status}',
              to_jsonb(v_status),
              true
            )
          else sess.value
        end
        order by ordinality
      ), '[]'::jsonb)
      from jsonb_array_elements(coalesce(v_package->'sessions', '[]'::jsonb))
        with ordinality as sess(value, ordinality)
    ),
    true
  );

  perform platform.validate_curriculum_package(v_package);

  v_next_version := platform.bump_patch_version(v_current.package_version);
  v_action := case when v_status = 'available' then 'post' else 'remove' end;
  v_notes := format('Session visibility: %s %s', v_action, v_session_id);
  v_hash := encode(extensions.digest(v_package::text, 'sha256'), 'hex');

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
    v_next_version,
    v_current.schema_version,
    v_current.source_package_version,
    'published',
    v_package,
    v_hash,
    coalesce(nullif(btrim(v_teacher.display_name), ''), v_teacher.staff_reference),
    '',
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
      'version', v_next_version,
      'schemaVersion', v_publication.schema_version,
      'packageVersion', v_publication.source_package_version,
      'author', v_publication.author,
      'publishedBy', v_teacher.staff_reference,
      'notes', v_notes,
      'sessionId', v_session_id,
      'sessionStatus', v_status,
      'previousSessionStatus', v_previous_status,
      'previousVersion', v_current.package_version
    )
  );

  perform platform.project_curriculum_package(
    v_package,
    v_hub_code,
    v_course_key,
    v_next_version,
    v_publication.id
  );

  return query
  select
    v_publication.id,
    v_current.package_version,
    v_next_version,
    v_session_id,
    v_previous_status,
    v_status,
    false;
end;
$$;

comment on function platform.set_session_visibility(text, text, text, text) is
  'Server-authoritative session visibility change against the current published curriculum. Idempotent when already at target status; does not accept client package JSON.';

create or replace function admin_api.set_session_visibility(
  p_hub_code text,
  p_course_key text,
  p_session_id text,
  p_status text
)
returns table (
  publication_id uuid,
  previous_package_version text,
  package_version text,
  session_id text,
  previous_status text,
  status text,
  idempotent boolean
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from platform.set_session_visibility(
    p_hub_code,
    p_course_key,
    p_session_id,
    p_status
  )
$$;

comment on function admin_api.set_session_visibility(text, text, text, text) is
  'Staff wrapper for platform.set_session_visibility. Browser must not send package JSON.';

revoke all on function platform.bump_patch_version(text) from public, anon, authenticated;
revoke all on function platform.set_session_visibility(text, text, text, text) from public, anon, authenticated;
revoke all on function admin_api.set_session_visibility(text, text, text, text) from public, anon, authenticated;

grant execute on function platform.bump_patch_version(text) to postgres, service_role;
grant execute on function platform.set_session_visibility(text, text, text, text) to authenticated, service_role;
grant execute on function admin_api.set_session_visibility(text, text, text, text) to authenticated, service_role;
