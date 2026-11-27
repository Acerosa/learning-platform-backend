-- Phase B stage 2: generate and store learner packages at publication time.
-- Reuses platform.learner_curriculum_package (Phase A). Both staff and learner
-- packages are written in the same transaction for every publication entry point.

create or replace function platform.learner_package_sanitisation_version()
returns text
language sql
immutable
set search_path = ''
as $$
  select 'lp.strip.v1'::text;
$$;

revoke all on function platform.learner_package_sanitisation_version()
  from public, anon, authenticated;
grant execute on function platform.learner_package_sanitisation_version()
  to authenticated;

comment on function platform.learner_package_sanitisation_version() is
  'Current learner-package sanitisation rule version. Bump when strip_learner_answer_keys rules change, then regenerate stored learner packages. Read-only constant; granted to authenticated for staff diagnostics.';

create or replace function platform.regenerate_curriculum_learner_packages(
  p_hub_code text default null,
  p_course_key text default null,
  p_force boolean default false
)
returns table (
  publication_id uuid,
  hub_code text,
  course_key text,
  package_version text,
  regenerated boolean
)
language plpgsql
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_row platform.curriculum_publications%rowtype;
  v_learner jsonb;
  v_version text := platform.learner_package_sanitisation_version();
  v_hub text := lower(nullif(btrim(p_hub_code), ''));
  v_course text := lower(nullif(btrim(p_course_key), ''));
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;
  if not platform.current_staff_has_role('platform_admin') then
    raise exception using errcode = '28000', message = 'PUBLICATION_NOT_AUTHORISED';
  end if;

  for v_row in
    select publication.*
    from platform.curriculum_publications as publication
    where (v_hub is null or publication.hub_code = v_hub)
      and (v_course is null or publication.course_key = v_course)
      and (
        p_force
        or publication.learner_package is null
        or publication.learner_package_sanitisation_version is distinct from v_version
      )
    order by publication.hub_code, publication.course_key, publication.package_version
    for update
  loop
    v_learner := platform.learner_curriculum_package(
      v_row.package,
      v_row.package_version,
      v_row.source_package_version
    );
    if v_learner is null or jsonb_typeof(v_learner) <> 'object' then
      raise exception using errcode = '22023', message = 'LEARNER_PACKAGE_GENERATION_FAILED';
    end if;

    update platform.curriculum_publications as publication
    set
      learner_package = v_learner,
      learner_package_sanitisation_version = v_version
    where publication.id = v_row.id;

    publication_id := v_row.id;
    hub_code := v_row.hub_code;
    course_key := v_row.course_key;
    package_version := v_row.package_version;
    regenerated := true;
    return next;
  end loop;
end;
$fn$;

revoke all on function platform.regenerate_curriculum_learner_packages(text, text, boolean)
  from public, anon, authenticated;
grant execute on function platform.regenerate_curriculum_learner_packages(text, text, boolean)
  to authenticated;

comment on function platform.regenerate_curriculum_learner_packages(text, text, boolean) is
  'Platform-admin regeneration of derived learner packages when sanitisation rules change or packages are missing. Does not alter staff packages.';


CREATE OR REPLACE FUNCTION platform.publish_curriculum(p_lifecycle_status text, p_hub_code text, p_course_key text, p_package_version text, p_schema_version text, p_source_package_version text, p_package jsonb, p_author text, p_reviewer text, p_publication_notes text)
 RETURNS TABLE(id uuid, hub_code text, course_key text, package_version text, status text, published_at timestamp with time zone, idempotent boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
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
  v_learner_package jsonb;
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
      perform platform.project_current_curriculum_catalogue(v_hub_code, v_course_key);
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

  v_learner_package := platform.learner_curriculum_package(
    p_package,
    v_package_version,
    v_source_package_version
  );
  if v_learner_package is null or jsonb_typeof(v_learner_package) <> 'object' then
    raise exception using errcode = '22023', message = 'LEARNER_PACKAGE_GENERATION_FAILED';
  end if;

  insert into platform.curriculum_publications (
    hub_code,
    course_key,
    package_version,
    schema_version,
    source_package_version,
    status,
    package,
    learner_package,
    learner_package_sanitisation_version,
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
    v_learner_package,
    platform.learner_package_sanitisation_version(),
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

  perform platform.project_curriculum_package(
    p_package,
    v_hub_code,
    v_course_key,
    v_package_version,
    v_publication.id
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


revoke all on function platform.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text)
  from public, anon, authenticated;
grant execute on function platform.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text)
  to authenticated;

comment on function platform.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text) is
  'Publishes an approved or locally published curriculum snapshot after server-side validation. Stores staff and learner packages in one transaction. Identity comes from auth.uid().';

CREATE OR REPLACE FUNCTION platform.set_session_visibility(p_hub_code text, p_course_key text, p_session_id text, p_status text)
 RETURNS TABLE(publication_id uuid, previous_package_version text, package_version text, session_id text, previous_status text, status text, idempotent boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
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
  v_learner_package jsonb;
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

  v_learner_package := platform.learner_curriculum_package(
    v_package,
    v_next_version,
    v_current.source_package_version
  );
  if v_learner_package is null or jsonb_typeof(v_learner_package) <> 'object' then
    raise exception using errcode = '22023', message = 'LEARNER_PACKAGE_GENERATION_FAILED';
  end if;

  insert into platform.curriculum_publications (
    hub_code,
    course_key,
    package_version,
    schema_version,
    source_package_version,
    status,
    package,
    learner_package,
    learner_package_sanitisation_version,
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
    v_learner_package,
    platform.learner_package_sanitisation_version(),
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


revoke all on function platform.set_session_visibility(text, text, text, text)
  from public, anon, authenticated;
grant execute on function platform.set_session_visibility(text, text, text, text)
  to authenticated, service_role;

comment on function platform.set_session_visibility(text, text, text, text) is
  'Publishes a patch version that updates one session.metadata.status. Stores staff and learner packages in the same transaction.';

