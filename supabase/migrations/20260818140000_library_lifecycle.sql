-- Content Library lifecycle: publish, archive, duplicate (new draft version).
-- Generic admin_api contract for all reusable library item types.

create or replace function library.bump_patch_version(p_version text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_parts text[];
  v_patch integer;
begin
  v_parts := string_to_array(coalesce(p_version, '1.0.0'), '.');
  if coalesce(array_length(v_parts, 1), 0) <> 3 then
    return '1.0.0';
  end if;
  begin
    v_patch := v_parts[3]::integer + 1;
  exception when others then
    return '1.0.0';
  end;
  return v_parts[1] || '.' || v_parts[2] || '.' || v_patch::text;
end;
$$;

create or replace function library.validate_library_item_for_publish(
  p_library_type text,
  p_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stable_key text;
  v_title text;
  v_version text;
  v_status text;
  v_content jsonb;
begin
  case p_library_type
    when 'question' then
      select q.stable_key, q.title, q.version, q.status, q.content
      into v_stable_key, v_title, v_version, v_status, v_content
      from library.questions q
      where q.id = p_id;
      if v_stable_key is null then
        raise exception 'Library question not found';
      end if;
      if v_status <> 'draft' then
        raise exception 'Only draft library items can be published';
      end if;
      if coalesce(btrim(v_stable_key), '') = '' then
        raise exception 'Stable key is required before publish';
      end if;
      if coalesce(btrim(v_title), '') = '' then
        raise exception 'Title is required before publish';
      end if;
      if v_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
        raise exception 'Version must be valid semver before publish';
      end if;
      if coalesce(btrim((select q.question_text from library.questions q where q.id = p_id)), '') = '' then
        raise exception 'Question text is required before publish';
      end if;
      if coalesce(btrim((select q.question_type from library.questions q where q.id = p_id)), '') = '' then
        raise exception 'Question type is required before publish';
      end if;
      if coalesce(jsonb_typeof(v_content), 'object') <> 'object' then
        raise exception 'Question content must be a JSON object';
      end if;

    when 'activity' then
      select a.stable_key, a.title, a.version, a.status, a.content
      into v_stable_key, v_title, v_version, v_status, v_content
      from library.activities a
      where a.id = p_id;
      if v_stable_key is null then
        raise exception 'Library activity not found';
      end if;
      if v_status <> 'draft' then
        raise exception 'Only draft library items can be published';
      end if;
      if coalesce(btrim(v_stable_key), '') = '' then
        raise exception 'Stable key is required before publish';
      end if;
      if coalesce(btrim(v_title), '') = '' then
        raise exception 'Title is required before publish';
      end if;
      if v_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
        raise exception 'Version must be valid semver before publish';
      end if;
      if coalesce(btrim((select a.activity_type from library.activities a where a.id = p_id)), '') = '' then
        raise exception 'Activity type is required before publish';
      end if;
      if coalesce(jsonb_typeof(v_content), 'object') <> 'object' then
        raise exception 'Activity content must be a JSON object';
      end if;

    when 'template' then
      select t.stable_key, t.title, t.version, t.status, t.specification
      into v_stable_key, v_title, v_version, v_status, v_content
      from library.templates t
      where t.id = p_id;
      if v_stable_key is null then
        raise exception 'Library template not found';
      end if;
      if v_status <> 'draft' then
        raise exception 'Only draft library items can be published';
      end if;
      if coalesce(btrim(v_stable_key), '') = '' or coalesce(btrim(v_title), '') = '' then
        raise exception 'Stable key and title are required before publish';
      end if;
      if v_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
        raise exception 'Version must be valid semver before publish';
      end if;
      if coalesce(jsonb_typeof(v_content), 'object') <> 'object' then
        raise exception 'Template specification must be a JSON object';
      end if;

    when 'resource' then
      select r.stable_key, r.title, r.version, r.status, r.metadata
      into v_stable_key, v_title, v_version, v_status, v_content
      from library.resources r
      where r.id = p_id;
      if v_stable_key is null then
        raise exception 'Library resource not found';
      end if;
      if v_status <> 'draft' then
        raise exception 'Only draft library items can be published';
      end if;
      if coalesce(btrim(v_stable_key), '') = '' or coalesce(btrim(v_title), '') = '' then
        raise exception 'Stable key and title are required before publish';
      end if;
      if v_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
        raise exception 'Version must be valid semver before publish';
      end if;
      if coalesce(btrim((select r.resource_type from library.resources r where r.id = p_id)), '') = '' then
        raise exception 'Resource type is required before publish';
      end if;
      if coalesce(jsonb_typeof(v_content), 'object') <> 'object' then
        raise exception 'Resource metadata must be a JSON object';
      end if;

    when 'feedback' then
      select f.stable_key, f.title, f.version, f.status, f.content
      into v_stable_key, v_title, v_version, v_status, v_content
      from library.feedback f
      where f.id = p_id;
      if v_stable_key is null then
        raise exception 'Library feedback not found';
      end if;
      if v_status <> 'draft' then
        raise exception 'Only draft library items can be published';
      end if;
      if coalesce(btrim(v_stable_key), '') = '' or coalesce(btrim(v_title), '') = '' then
        raise exception 'Stable key and title are required before publish';
      end if;
      if v_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
        raise exception 'Version must be valid semver before publish';
      end if;
      if coalesce(jsonb_typeof(v_content), 'object') <> 'object' then
        raise exception 'Feedback content must be a JSON object';
      end if;

    when 'hint' then
      select h.stable_key, h.title, h.version, h.status
      into v_stable_key, v_title, v_version, v_status
      from library.hints h
      where h.id = p_id;
      if v_stable_key is null then
        raise exception 'Library hint not found';
      end if;
      if v_status <> 'draft' then
        raise exception 'Only draft library items can be published';
      end if;
      if coalesce(btrim(v_stable_key), '') = '' or coalesce(btrim(v_title), '') = '' then
        raise exception 'Stable key and title are required before publish';
      end if;
      if v_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
        raise exception 'Version must be valid semver before publish';
      end if;
      if coalesce(btrim((select h.hint_text from library.hints h where h.id = p_id)), '') = '' then
        raise exception 'Hint text is required before publish';
      end if;

    else
      raise exception 'Unknown library type: %', p_library_type;
  end case;
end;
$$;

create or replace function admin_api.publish_library_item(
  p_library_type text,
  p_id uuid
)
returns table (
  id uuid,
  stable_key text,
  status text,
  version text,
  published boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stable_key text;
  v_version text;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  perform library.validate_library_item_for_publish(p_library_type, p_id);

  case p_library_type
    when 'question' then
      update library.questions q
      set status = 'published', updated_at = now()
      where q.id = p_id and q.status = 'draft'
      returning q.stable_key, q.version into v_stable_key, v_version;
    when 'activity' then
      update library.activities a
      set status = 'published', updated_at = now()
      where a.id = p_id and a.status = 'draft'
      returning a.stable_key, a.version into v_stable_key, v_version;
    when 'template' then
      update library.templates t
      set status = 'published', updated_at = now()
      where t.id = p_id and t.status = 'draft'
      returning t.stable_key, t.version into v_stable_key, v_version;
    when 'resource' then
      update library.resources r
      set status = 'published', updated_at = now()
      where r.id = p_id and r.status = 'draft'
      returning r.stable_key, r.version into v_stable_key, v_version;
    when 'feedback' then
      update library.feedback f
      set status = 'published', updated_at = now()
      where f.id = p_id and f.status = 'draft'
      returning f.stable_key, f.version into v_stable_key, v_version;
    when 'hint' then
      update library.hints h
      set status = 'published', updated_at = now()
      where h.id = p_id and h.status = 'draft'
      returning h.stable_key, h.version into v_stable_key, v_version;
    else
      raise exception 'Unknown library type: %', p_library_type;
  end case;

  if not found then
    raise exception 'Library item could not be published';
  end if;

  perform platform.record_audit_event(
    'library.item.published',
    'staff',
    'library-item',
    p_id::text,
    'succeeded',
    jsonb_build_object(
      'libraryType', p_library_type,
      'stableKey', v_stable_key,
      'version', v_version
    )
  );

  return query select p_id, v_stable_key, 'published'::text, v_version, true;
end;
$$;

create or replace function admin_api.archive_library_item(
  p_library_type text,
  p_id uuid
)
returns table (
  id uuid,
  stable_key text,
  status text,
  version text,
  archived boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stable_key text;
  v_version text;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  case p_library_type
    when 'question' then
      update library.questions q
      set status = 'archived', updated_at = now()
      where q.id = p_id and q.status = 'published'
      returning q.stable_key, q.version into v_stable_key, v_version;
    when 'activity' then
      update library.activities a
      set status = 'archived', updated_at = now()
      where a.id = p_id and a.status = 'published'
      returning a.stable_key, a.version into v_stable_key, v_version;
    when 'template' then
      update library.templates t
      set status = 'archived', updated_at = now()
      where t.id = p_id and t.status = 'published'
      returning t.stable_key, t.version into v_stable_key, v_version;
    when 'resource' then
      update library.resources r
      set status = 'archived', updated_at = now()
      where r.id = p_id and r.status = 'published'
      returning r.stable_key, r.version into v_stable_key, v_version;
    when 'feedback' then
      update library.feedback f
      set status = 'archived', updated_at = now()
      where f.id = p_id and f.status = 'published'
      returning f.stable_key, f.version into v_stable_key, v_version;
    when 'hint' then
      update library.hints h
      set status = 'archived', updated_at = now()
      where h.id = p_id and h.status = 'published'
      returning h.stable_key, h.version into v_stable_key, v_version;
    else
      raise exception 'Unknown library type: %', p_library_type;
  end case;

  if not found then
    raise exception 'Only published library items can be archived';
  end if;

  perform platform.record_audit_event(
    'library.item.archived',
    'staff',
    'library-item',
    p_id::text,
    'succeeded',
    jsonb_build_object(
      'libraryType', p_library_type,
      'stableKey', v_stable_key,
      'version', v_version
    )
  );

  return query select p_id, v_stable_key, 'archived'::text, v_version, true;
end;
$$;

create or replace function admin_api.duplicate_library_item(
  p_library_type text,
  p_id uuid,
  p_stable_key text,
  p_title text default null,
  p_version text default null
)
returns table (
  id uuid,
  stable_key text,
  title text,
  status text,
  version text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_author text;
  v_title text;
  v_version text;
  v_new_id uuid;
begin
  if not library.is_content_author() then
    raise exception 'Content authoring requires platform_admin or curriculum_admin role';
  end if;

  if coalesce(btrim(p_stable_key), '') = '' then
    raise exception 'A new stable key is required for the duplicated draft';
  end if;

  select coalesce(
    (select t.display_name from learning.teachers t where t.auth_user_id = auth.uid() limit 1),
    'Unknown'
  ) into v_author;

  case p_library_type
    when 'question' then
      select coalesce(nullif(btrim(p_title), ''), q.title), coalesce(nullif(btrim(p_version), ''), library.bump_patch_version(q.version))
      into v_title, v_version
      from library.questions q
      where q.id = p_id and q.status in ('published', 'archived', 'superseded');
      if v_title is null then
        raise exception 'Published library question not found';
      end if;

      insert into library.questions (
        stable_key, title, question_text, question_type, difficulty, marks,
        estimated_time_minutes, family_id, subject, hub_code, course_key,
        topic, command_word, exam_board, tags, status, version, content, author
      )
      select
        p_stable_key, v_title, q.question_text, q.question_type, q.difficulty, q.marks,
        q.estimated_time_minutes, q.family_id, q.subject, q.hub_code, q.course_key,
        q.topic, q.command_word, q.exam_board, q.tags, 'draft', v_version, q.content, v_author
      from library.questions q
      where q.id = p_id
      returning questions.id into v_new_id;

      insert into library.question_learning_outcomes (question_id, learning_outcome)
      select v_new_id, lo.learning_outcome
      from library.question_learning_outcomes lo
      where lo.question_id = p_id;

    when 'activity' then
      select coalesce(nullif(btrim(p_title), ''), a.title), coalesce(nullif(btrim(p_version), ''), library.bump_patch_version(a.version))
      into v_title, v_version
      from library.activities a
      where a.id = p_id and a.status in ('published', 'archived', 'superseded');
      if v_title is null then
        raise exception 'Published library activity not found';
      end if;

      insert into library.activities (
        stable_key, title, activity_type, difficulty, family_id, summary,
        subject, hub_code, course_key, topic, exam_board, estimated_time_minutes,
        tags, status, version, content, author
      )
      select
        p_stable_key, v_title, a.activity_type, a.difficulty, a.family_id, a.summary,
        a.subject, a.hub_code, a.course_key, a.topic, a.exam_board, a.estimated_time_minutes,
        a.tags, 'draft', v_version, a.content, v_author
      from library.activities a
      where a.id = p_id
      returning activities.id into v_new_id;

      insert into library.activity_learning_outcomes (activity_id, learning_outcome)
      select v_new_id, lo.learning_outcome
      from library.activity_learning_outcomes lo
      where lo.activity_id = p_id;

      insert into library.activity_questions (activity_id, question_id, sort_order)
      select v_new_id, aq.question_id, aq.sort_order
      from library.activity_questions aq
      where aq.activity_id = p_id;

    when 'template' then
      select coalesce(nullif(btrim(p_title), ''), t.title), coalesce(nullif(btrim(p_version), ''), library.bump_patch_version(t.version))
      into v_title, v_version
      from library.templates t
      where t.id = p_id and t.status in ('published', 'archived', 'superseded');
      if v_title is null then
        raise exception 'Published library template not found';
      end if;

      insert into library.templates (
        stable_key, title, template_type, description, subject, tags, status, version, specification, author
      )
      select
        p_stable_key, v_title, t.template_type, t.description, t.subject, t.tags, 'draft', v_version, t.specification, v_author
      from library.templates t
      where t.id = p_id
      returning templates.id into v_new_id;

    when 'resource' then
      select coalesce(nullif(btrim(p_title), ''), r.title), coalesce(nullif(btrim(p_version), ''), library.bump_patch_version(r.version))
      into v_title, v_version
      from library.resources r
      where r.id = p_id and r.status in ('published', 'archived', 'superseded');
      if v_title is null then
        raise exception 'Published library resource not found';
      end if;

      insert into library.resources (
        stable_key, title, resource_type, url, description, subject, hub_code, course_key,
        tags, status, version, metadata, author
      )
      select
        p_stable_key, v_title, r.resource_type, r.url, r.description, r.subject, r.hub_code, r.course_key,
        r.tags, 'draft', v_version, r.metadata, v_author
      from library.resources r
      where r.id = p_id
      returning resources.id into v_new_id;

    when 'feedback' then
      select coalesce(nullif(btrim(p_title), ''), f.title), coalesce(nullif(btrim(p_version), ''), library.bump_patch_version(f.version))
      into v_title, v_version
      from library.feedback f
      where f.id = p_id and f.status in ('published', 'archived', 'superseded');
      if v_title is null then
        raise exception 'Published library feedback not found';
      end if;

      insert into library.feedback (
        stable_key, title, feedback_type, content, subject, tags, status, version, author
      )
      select
        p_stable_key, v_title, f.feedback_type, f.content, f.subject, f.tags, 'draft', v_version, v_author
      from library.feedback f
      where f.id = p_id
      returning feedback.id into v_new_id;

    when 'hint' then
      select coalesce(nullif(btrim(p_title), ''), h.title), coalesce(nullif(btrim(p_version), ''), library.bump_patch_version(h.version))
      into v_title, v_version
      from library.hints h
      where h.id = p_id and h.status in ('published', 'archived', 'superseded');
      if v_title is null then
        raise exception 'Published library hint not found';
      end if;

      insert into library.hints (
        stable_key, title, hint_text, hint_level, subject, tags, status, version, author
      )
      select
        p_stable_key, v_title, h.hint_text, h.hint_level, h.subject, h.tags, 'draft', v_version, v_author
      from library.hints h
      where h.id = p_id
      returning hints.id into v_new_id;

    else
      raise exception 'Unknown library type: %', p_library_type;
  end case;

  perform platform.record_audit_event(
    'library.item.duplicated',
    'staff',
    'library-item',
    v_new_id::text,
    'succeeded',
    jsonb_build_object(
      'libraryType', p_library_type,
      'sourceId', p_id,
      'stableKey', p_stable_key,
      'version', v_version
    )
  );

  return query select v_new_id, p_stable_key, v_title, 'draft'::text, v_version;
end;
$$;

revoke all on function library.bump_patch_version(text) from public, anon, authenticated;
revoke all on function library.validate_library_item_for_publish(text, uuid) from public, anon, authenticated;

revoke all on function admin_api.publish_library_item(text, uuid) from public, anon, authenticated;
revoke all on function admin_api.archive_library_item(text, uuid) from public, anon, authenticated;
revoke all on function admin_api.duplicate_library_item(text, uuid, text, text, text) from public, anon, authenticated;

grant execute on function admin_api.publish_library_item(text, uuid) to authenticated;
grant execute on function admin_api.archive_library_item(text, uuid) to authenticated;
grant execute on function admin_api.duplicate_library_item(text, uuid, text, text, text) to authenticated;
