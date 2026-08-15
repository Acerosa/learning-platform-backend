-- Database-first curriculum delivery. Canonical packages stay in
-- platform.curriculum_publications. Learner hubs read the current published
-- package. Publication projects a delivery catalogue without becoming a second
-- authoring source.

create extension if not exists "uuid-ossp" with schema extensions;

update platform.contract_versions
set
  compatibility = '{"previousVersion":"0.1.0","mode":"read-models-with-runtime-curriculum-delivery"}'::jsonb,
  contract_document = '{"schema":"api","boundary":"learner-safe and public published curriculum packages without drafts, staff metadata or marking secrets"}'::jsonb
where contract_key = 'learner-api'
  and version = '0.1.0'
  and status = 'active';

create function platform.curriculum_catalogue_id(p_kind text, p_key text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select extensions.uuid_generate_v5(
    'c014a7e0-14e1-4c14-9e14-0a14c0140001'::uuid,
    p_kind || ':' || p_key
  );
$$;

create function platform.posix_js_pattern(p_pattern text)
returns text
language sql
immutable
set search_path = ''
as $$
  select replace(replace(replace(p_pattern, '\s', '[[:space:]]'), '\d', '[[:digit:]]'), '\w', '[[:alnum:]_]');
$$;

create function platform.learner_curriculum_package(
  p_package jsonb,
  p_package_version text,
  p_source_package_version text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_package jsonb;
  v_activities jsonb := '[]'::jsonb;
  v_activity jsonb;
  v_blocks jsonb;
begin
  v_package := coalesce(p_package, '{}'::jsonb);

  for v_activity in
    select value
    from jsonb_array_elements(coalesce(v_package->'activities', '[]'::jsonb)) as value
  loop
    select coalesce(jsonb_agg(block order by ordinality), '[]'::jsonb)
    into v_blocks
    from jsonb_array_elements(coalesce(v_activity->'blocks', '[]'::jsonb))
      with ordinality as block(block, ordinality)
    where coalesce(block->>'type', '') is distinct from 'teacher-note';

    v_activities := v_activities || jsonb_build_array(
      jsonb_set(v_activity, '{blocks}', v_blocks, true)
    );
  end loop;

  v_package := jsonb_set(v_package, '{activities}', v_activities, true);
  v_package := v_package || jsonb_build_object(
    'schema', 'lp.content.package',
    'schemaVersion', coalesce(p_source_package_version, v_package->>'schemaVersion', '0.1.0'),
    'id', coalesce(v_package->>'id', v_package->'hub'->>'id'),
    'version', p_package_version
  );
  return v_package;
end;
$$;

create function platform.project_curriculum_package(
  p_package jsonb,
  p_hub_code text,
  p_course_key text,
  p_package_version text,
  p_publication_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_course_id uuid;
  v_module_id uuid;
  v_module_key text;
  v_module_title text;
  v_sort_order integer;
  v_year_id uuid;
  v_week jsonb;
  v_outcome jsonb;
  v_session jsonb;
  v_session_id text;
  v_activity jsonb;
  v_activity_id text;
  v_activity_version text;
  v_activity_title text;
  v_activity_type text;
  v_requires_python boolean;
  v_delivery jsonb := '{}'::jsonb;
  v_delivery_row jsonb;
  v_week_id uuid;
  v_activity_row_id uuid;
  v_version_id uuid;
  v_question_id uuid;
  v_topic_id uuid;
  v_topic_key text;
  v_ordinal integer;
  v_session_number integer;
  v_sort integer;
  v_block jsonb;
  v_block_type text;
  v_content jsonb;
  v_question_key text;
  v_item jsonb;
  v_item_id text;
  v_marking jsonb;
  v_questions jsonb := '[]'::jsonb;
  v_payload jsonb;
  v_hash text;
  v_count integer;
  v_lo text;
  v_activity_count integer := 0;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('content-package:' || p_hub_code, 0)
  );

  select course.id
  into v_course_id
  from learning.courses as course
  where course.stable_key = p_course_key
    and course.active;

  if v_course_id is null then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;

  select academic_year.id
  into v_year_id
  from learning.academic_years as academic_year
  where academic_year.active
  order by academic_year.code
  limit 1;

  v_module_key := p_hub_code;
  v_module_title := coalesce(
    p_package->'curriculum'->'metadata'->>'title',
    p_package->'hub'->'metadata'->>'name',
    p_hub_code
  );
  v_sort_order := coalesce(substring(p_hub_code from 'unit-([0-9]+)')::int, 0);
  v_module_id := platform.curriculum_catalogue_id('module', p_course_key || ':' || v_module_key);

  insert into learning.modules (id, course_id, stable_key, title, sort_order, active)
  values (v_module_id, v_course_id, v_module_key, v_module_title, v_sort_order, true)
  on conflict (course_id, stable_key) do update set
    title = excluded.title,
    active = true;

  select module.id into v_module_id
  from learning.modules as module
  where module.course_id = v_course_id
    and module.stable_key = v_module_key;

  for v_outcome in
    select value
    from jsonb_array_elements(coalesce(p_package->'learningOutcomes', '[]'::jsonb)) as value
  loop
    v_topic_key := lower(btrim(coalesce(v_outcome->>'id', '')));
    if v_topic_key = '' or v_topic_key !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
      continue;
    end if;
    insert into learning.topics (id, module_id, stable_key, title, sort_order, active)
    values (
      platform.curriculum_catalogue_id('topic', p_course_key || ':' || v_module_key || ':' || v_topic_key),
      v_module_id,
      v_topic_key,
      coalesce(v_outcome->'metadata'->>'title', v_topic_key),
      coalesce((v_outcome->'metadata'->>'sortOrder')::int, 0),
      true
    )
    on conflict (module_id, stable_key) do update set
      title = excluded.title,
      active = true;
  end loop;

  for v_week in
    select value
    from jsonb_array_elements(coalesce(p_package->'weeks', '[]'::jsonb)) as value
  loop
    if coalesce(v_week->>'id', '') = '' then
      continue;
    end if;
    insert into learning.curriculum_weeks (
      id, module_id, stable_key, title, week_number, sort_order, active
    )
    values (
      platform.curriculum_catalogue_id('week', p_course_key || ':' || v_module_key || ':' || (v_week->>'id')),
      v_module_id,
      v_week->>'id',
      coalesce(v_week->'metadata'->>'title', v_week->>'id'),
      coalesce((v_week->'metadata'->>'teachingWeek')::int, 1),
      coalesce((v_week->'metadata'->>'teachingWeek')::int, 1),
      true
    )
    on conflict (module_id, stable_key) do update set
      title = excluded.title,
      week_number = excluded.week_number,
      sort_order = excluded.sort_order,
      active = true;
  end loop;

  for v_week in
    select value
    from jsonb_array_elements(coalesce(p_package->'weeks', '[]'::jsonb)) as value
  loop
    for v_session_id in
      select jsonb_array_elements_text(coalesce(v_week->'relationships'->'sessions', '[]'::jsonb))
    loop
      select value
      into v_session
      from jsonb_array_elements(coalesce(p_package->'sessions', '[]'::jsonb)) as value
      where value->>'id' = v_session_id
      limit 1;

      if v_session is null then
        continue;
      end if;

      v_session_number := case
        when coalesce(v_session->'metadata'->>'sortOrder', '') ~ '^[0-9]+$'
          and (v_session->'metadata'->>'sortOrder')::int > 0
        then (v_session->'metadata'->>'sortOrder')::int
        else null
      end;

      for v_activity_id, v_sort in
        select activity_ref, ordinality::int
        from jsonb_array_elements_text(
          coalesce(v_session->'relationships'->'activities', '[]'::jsonb)
        ) with ordinality as refs(activity_ref, ordinality)
      loop
        v_delivery := v_delivery || jsonb_build_object(
          v_activity_id,
          jsonb_build_object(
            'weekKey', v_week->>'id',
            'weekNumber', coalesce((v_week->'metadata'->>'teachingWeek')::int, 1),
            'sessionNumber', v_session_number,
            'sortOrder', v_sort
          )
        );
      end loop;
    end loop;
  end loop;

  for v_activity in
    select value
    from jsonb_array_elements(coalesce(p_package->'activities', '[]'::jsonb)) as value
  loop
    v_activity_id := v_activity->>'id';
    v_activity_version := coalesce(v_activity->>'version', '');
    v_delivery_row := v_delivery->v_activity_id;
    if v_activity_id is null
       or v_activity_id !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
       or v_activity_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$'
       or v_delivery_row is null then
      continue;
    end if;

    v_questions := '[]'::jsonb;
    v_ordinal := 0;
    v_requires_python := false;

    for v_block in
      select value
      from jsonb_array_elements(coalesce(v_activity->'blocks', '[]'::jsonb)) as value
    loop
      v_block_type := coalesce(v_block->>'type', '');
      v_content := case
        when jsonb_typeof(v_block->'content') = 'object' then v_block->'content'
        else '{}'::jsonb
      end;

      if v_block_type in (
        'heading', 'paragraph', 'markdown', 'image', 'video', 'callout',
        'accordion', 'reference', 'hint', 'quote', 'divider', 'teacher-note'
      ) then
        continue;
      end if;

      if v_block_type not in (
        'single-choice', 'classification', 'short-response',
        'reflection', 'code-editor', 'python-exercise'
      ) then
        continue;
      end if;

      if v_block_type in ('code-editor', 'python-exercise') then
        v_requires_python := true;
      end if;

      v_question_key := coalesce(v_content->>'questionId', '');
      if v_question_key = '' or v_question_key !~ '^[A-Za-z0-9._:-]+$' then
        raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
      end if;

      if v_block_type = 'classification' then
        if jsonb_typeof(v_content->'items') is distinct from 'array'
           or jsonb_array_length(v_content->'items') = 0 then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;
        for v_item in
          select value from jsonb_array_elements(v_content->'items') as value
        loop
          v_item_id := coalesce(v_item->>'id', '');
          if v_item_id = '' or v_item_id !~ '^[A-Za-z0-9._:-]+$' then
            raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
          end if;
          v_ordinal := v_ordinal + 1;
          if coalesce(v_item->>'correctCategoryId', '') <> '' then
            v_marking := jsonb_build_object(
              'mode', 'classification',
              'correctCategoryId', v_item->>'correctCategoryId'
            );
          else
            v_marking := jsonb_build_object('mode', 'completion');
          end if;
          v_questions := v_questions || jsonb_build_array(
            jsonb_build_object(
              'stableKey', v_question_key || ':' || v_item_id,
              'questionType', 'matching',
              'ordinal', v_ordinal,
              'marking', v_marking
            )
          );
        end loop;
        continue;
      end if;

      v_ordinal := v_ordinal + 1;
      if v_block_type = 'single-choice' and coalesce(v_content->>'correctOptionId', '') <> '' then
        v_marking := jsonb_build_object(
          'mode', 'single-choice',
          'correctOptionId', v_content->>'correctOptionId'
        );
      elsif v_block_type in ('code-editor', 'python-exercise') then
        v_marking := jsonb_build_object(
          'mode', case
            when coalesce(v_content->'checks'->'required', '[]'::jsonb) <> '[]'::jsonb
              or coalesce(v_content->'checks'->'prohibited', '[]'::jsonb) <> '[]'::jsonb
            then 'python-patterns'
            else 'completion'
          end,
          'required', coalesce((
            select jsonb_agg(platform.posix_js_pattern(item->>'pattern'))
            from jsonb_array_elements(coalesce(v_content->'checks'->'required', '[]'::jsonb)) as item
            where coalesce(item->>'pattern', '') <> ''
          ), '[]'::jsonb),
          'prohibited', coalesce((
            select jsonb_agg(platform.posix_js_pattern(item->>'pattern'))
            from jsonb_array_elements(coalesce(v_content->'checks'->'prohibited', '[]'::jsonb)) as item
            where coalesce(item->>'pattern', '') <> ''
          ), '[]'::jsonb)
        );
        if v_marking->>'mode' = 'completion' then
          v_marking := jsonb_build_object('mode', 'completion');
        end if;
      else
        v_marking := jsonb_build_object('mode', 'completion');
      end if;

      v_questions := v_questions || jsonb_build_array(
        jsonb_build_object(
          'stableKey', v_question_key,
          'questionType', case v_block_type
            when 'single-choice' then 'single'
            when 'short-response' then 'text'
            when 'reflection' then 'text'
            else 'code-editor'
          end,
          'ordinal', v_ordinal,
          'marking', v_marking
        )
      );
    end loop;

    v_count := jsonb_array_length(v_questions);
    if v_count = 0 then
      continue;
    end if;

    v_activity_title := coalesce(v_activity->'metadata'->>'title', v_activity_id);
    v_activity_type := case
      when v_activity_id like '%diagnostic%' then 'diagnostic'
      when v_requires_python then 'coding-exercise'
      when exists (
        select 1
        from jsonb_array_elements(coalesce(v_activity->'blocks', '[]'::jsonb)) as block
        where block->>'type' = 'classification'
      ) then 'classification'
      when exists (
        select 1
        from jsonb_array_elements(coalesce(v_activity->'blocks', '[]'::jsonb)) as block
        where block->>'type' = 'single-choice'
      ) then 'diagnostic'
      else 'reflection'
    end;

    v_activity_row_id := platform.curriculum_catalogue_id('activity', v_activity_id);
    v_version_id := platform.curriculum_catalogue_id('version', v_activity_id || ':' || v_activity_version);
    v_week_id := platform.curriculum_catalogue_id(
      'week',
      p_course_key || ':' || v_module_key || ':' || (v_delivery_row->>'weekKey')
    );
    v_payload := (
      select jsonb_agg(
        jsonb_build_object(
          'stableKey', question->>'stableKey',
          'questionType', question->>'questionType',
          'ordinal', question->'ordinal',
          'marking', question->'marking'
        )
        order by (question->>'ordinal')::int
      )
      from jsonb_array_elements(v_questions) as question
    );
    v_hash := encode(
      extensions.digest(
        convert_to(
          jsonb_build_object(
            'activityKey', v_activity_id,
            'questions', v_payload,
            'version', v_activity_version
          )::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );

    insert into learning.activities (
      id, module_id, stable_key, title, activity_type, git_path, active
    )
    values (
      v_activity_row_id,
      v_module_id,
      v_activity_id,
      v_activity_title,
      v_activity_type,
      'content/activities/' || v_activity_id,
      true
    )
    on conflict (stable_key) do update set
      title = excluded.title,
      activity_type = excluded.activity_type,
      active = true;

    insert into learning.activity_versions (
      id, activity_id, version, content_hash, max_score, question_count, published_at
    )
    values (
      v_version_id,
      v_activity_row_id,
      v_activity_version,
      v_hash,
      v_count,
      v_count,
      null
    )
    on conflict (activity_id, version) do nothing;

    if v_requires_python then
      insert into learning.activity_version_languages (activity_version_id, coding_language_id)
      select version.id, coding_language.id
      from learning.activity_versions as version
      join learning.coding_languages as coding_language
        on coding_language.stable_key = 'python'
        and coding_language.active
      where version.id = v_version_id
        and version.published_at is null
      on conflict (activity_version_id, coding_language_id) do nothing;
    end if;

    for v_block in
      select value from jsonb_array_elements(v_questions) as value
    loop
      v_question_id := platform.curriculum_catalogue_id(
        'question',
        v_activity_id || ':' || v_activity_version || ':' || (v_block->>'stableKey')
      );
      insert into learning.questions (
        id, activity_version_id, stable_key, section_key, section_title,
        question_type, analytics_title, ordinal, max_score
      )
      select
        v_question_id,
        v_version_id,
        v_block->>'stableKey',
        v_delivery_row->>'weekKey',
        'Week ' || (v_delivery_row->>'weekNumber'),
        v_block->>'questionType',
        v_block->>'stableKey',
        (v_block->>'ordinal')::int,
        1
      from learning.activity_versions as version
      where version.id = v_version_id
        and version.published_at is null
      on conflict (activity_version_id, stable_key) do nothing;

      insert into learning.question_marking (question_id, spec)
      select question.id, v_block->'marking'
      from learning.questions as question
      join learning.activity_versions as version
        on version.id = question.activity_version_id
      where question.id = v_question_id
        and version.published_at is null
      on conflict (question_id) do nothing;

      for v_lo in
        select lower(btrim(outcome_id))
        from jsonb_array_elements_text(
          coalesce(v_activity->'relationships'->'learningOutcomes', '[]'::jsonb)
        ) as outcome_id
      loop
        if v_lo = '' or v_lo !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
          continue;
        end if;
        v_topic_id := platform.curriculum_catalogue_id(
          'topic',
          p_course_key || ':' || v_module_key || ':' || v_lo
        );
        insert into learning.question_topics (question_id, topic_id, weight)
        select question.id, v_topic_id, 1
        from learning.questions as question
        join learning.activity_versions as version
          on version.id = question.activity_version_id
        where question.id = v_question_id
          and version.published_at is null
        on conflict (question_id, topic_id) do nothing;
      end loop;
    end loop;

    update learning.activity_versions
    set published_at = clock_timestamp()
    where id = v_version_id
      and published_at is null;

    if v_year_id is not null then
      if exists (
        select 1
        from learning.activity_delivery as delivery
        where delivery.activity_version_id = v_version_id
          and delivery.academic_year_id = v_year_id
          and delivery.group_id is null
      ) then
        update learning.activity_delivery
        set
          curriculum_week_id = v_week_id,
          week_number = (v_delivery_row->>'weekNumber')::int,
          session_number = nullif(v_delivery_row->>'sessionNumber', '')::int,
          sort_order = (v_delivery_row->>'sortOrder')::int,
          active = true,
          updated_at = clock_timestamp()
        where activity_version_id = v_version_id
          and academic_year_id = v_year_id
          and group_id is null;
      else
        insert into learning.activity_delivery (
          activity_version_id, academic_year_id, curriculum_week_id,
          week_number, session_number, sort_order, active
        )
        values (
          v_version_id,
          v_year_id,
          v_week_id,
          (v_delivery_row->>'weekNumber')::int,
          nullif(v_delivery_row->>'sessionNumber', '')::int,
          (v_delivery_row->>'sortOrder')::int,
          true
        );
      end if;

      insert into learning.activity_assignments (
        id, group_id, activity_version_id, required, active
      )
      select
        platform.curriculum_catalogue_id(
          'assignment',
          learner_group.code || ':' || v_activity_id || ':' || v_activity_version
        ),
        learner_group.id,
        v_version_id,
        true,
        true
      from learning.groups as learner_group
      where learner_group.course_id = v_course_id
        and learner_group.active
        and exists (
          select 1
          from learning.activity_assignments as existing
          join learning.activity_versions as existing_version
            on existing_version.id = existing.activity_version_id
          join learning.activities as existing_activity
            on existing_activity.id = existing_version.activity_id
          where existing.group_id = learner_group.id
            and existing.active
            and existing_activity.module_id = v_module_id
        )
      on conflict (group_id, activity_version_id) do update set
        required = excluded.required,
        active = true;
    end if;

    v_activity_count := v_activity_count + 1;
  end loop;

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'curriculum.catalogue.projected',
    auth.uid(),
    case when auth.uid() is null then 'system' else 'staff' end,
    'curriculum-publication',
    coalesce(p_publication_id::text, p_hub_code),
    'succeeded',
    jsonb_build_object(
      'hubCode', p_hub_code,
      'courseKey', p_course_key,
      'version', p_package_version,
      'activityCount', v_activity_count
    )
  );
end;
$$;

create function platform.project_current_curriculum_catalogue(
  p_hub_code text,
  p_course_key text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_publication platform.curriculum_publications%rowtype;
begin
  select publication.*
  into v_publication
  from platform.curriculum_publications as publication
  where publication.hub_code = p_hub_code
    and publication.course_key = p_course_key
    and publication.status = 'published'
  limit 1;

  if not found then
    return;
  end if;

  perform platform.project_curriculum_package(
    v_publication.package,
    v_publication.hub_code,
    v_publication.course_key,
    v_publication.package_version,
    v_publication.id
  );
end;
$$;

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

create function api.published_curriculum_package(
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
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hub_code text;
  v_course_key text;
  v_publication platform.curriculum_publications%rowtype;
begin
  v_hub_code := lower(nullif(btrim(p_hub_code), ''));
  v_course_key := lower(nullif(btrim(p_course_key), ''));

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

  select publication.*
  into v_publication
  from platform.curriculum_publications as publication
  where publication.hub_code = v_hub_code
    and publication.course_key = v_course_key
    and publication.status = 'published'
  limit 1;

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

revoke all on function platform.curriculum_catalogue_id(text, text)
  from public, anon, authenticated;
revoke all on function platform.posix_js_pattern(text)
  from public, anon, authenticated;
revoke all on function platform.learner_curriculum_package(jsonb, text, text)
  from public, anon, authenticated;
revoke all on function platform.project_curriculum_package(jsonb, text, text, text, uuid)
  from public, anon, authenticated;
revoke all on function platform.project_current_curriculum_catalogue(text, text)
  from public, anon, authenticated;
revoke all on function api.published_curriculum_package(text, text)
  from public, anon, authenticated;

grant execute on function api.published_curriculum()
  to anon, authenticated;
grant execute on function api.published_curriculum_package(text, text)
  to anon, authenticated;

comment on function api.published_curriculum() is
  'Public metadata for currently published curriculum packages. Drafts and package bodies are not included.';
comment on function api.published_curriculum_package(text, text) is
  'Public current published teaching package for a hub and course. Never returns drafts, superseded rows, staff publication fields or learning.question_marking.';
comment on function platform.project_curriculum_package(jsonb, text, text, text, uuid) is
  'Idempotent delivery-catalogue projection from a canonical published package. Published activity versions remain immutable.';
comment on function platform.learner_curriculum_package(jsonb, text, text) is
  'Learner-safe teaching package projection. Teacher-note blocks are removed. Marking tables are never joined.';
