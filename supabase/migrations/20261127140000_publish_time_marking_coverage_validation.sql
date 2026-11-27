-- Fail new curriculum publications when automatically scored catalogue
-- questions cannot resolve a marking specification after projection.
-- Intentionally non-scored modes (completion / requires_review) remain valid
-- when their protected marking rows resolve. A failed validation aborts the
-- publish transaction so the previously published curriculum stays active.

begin;

create or replace function platform.assert_package_marking_coverage(p_package jsonb)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_gaps integer := 0;
  v_sample text;
begin
  with package_questions as (
    select
      act.value->>'id' as activity_key,
      act.value->>'version' as activity_version,
      question.id as question_id,
      question.stable_key as question_key,
      learning.resolve_marking_question(question.id) as resolved_id
    from jsonb_array_elements(coalesce(p_package->'activities', '[]'::jsonb)) as act(value)
    join learning.activities as activity
      on activity.stable_key = act.value->>'id'
    join learning.activity_versions as activity_version
      on activity_version.activity_id = activity.id
     and activity_version.version = act.value->>'version'
    join learning.questions as question
      on question.activity_version_id = activity_version.id
  )
  select
    count(*)::integer,
    string_agg(activity_key || ':' || question_key, ', ' order by activity_key, question_key)
  into v_gaps, v_sample
  from package_questions
  where resolved_id is null;

  if coalesce(v_gaps, 0) > 0 then
    raise exception using
      errcode = '22023',
      message = 'MARKING_COVERAGE_INVALID',
      detail = format(
        'unresolved_auto_or_missing_specs=%s sample=%s',
        v_gaps,
        left(coalesce(v_sample, ''), 300)
      );
  end if;
end;
$$;

revoke all on function platform.assert_package_marking_coverage(jsonb)
  from public, anon, authenticated;

comment on function platform.assert_package_marking_coverage(jsonb) is
  'Raises MARKING_COVERAGE_INVALID when any catalogue question for package activities cannot resolve a marking specification. Does not expose answer keys.';

create or replace function platform.publish_curriculum(
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
returns table(
  id uuid,
  hub_code text,
  course_key text,
  package_version text,
  status text,
  published_at timestamp with time zone,
  idempotent boolean
)
language plpgsql
security definer
set search_path to ''
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

  -- After catalogue projection/registration, require resolvable marking for
  -- every package question. Failure rolls back this publish transaction.
  perform platform.assert_package_marking_coverage(p_package);

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
  'Publishes an approved or locally published curriculum snapshot after server-side validation, including post-projection marking coverage. Stores staff and learner packages in one transaction. Identity comes from auth.uid().';

commit;
