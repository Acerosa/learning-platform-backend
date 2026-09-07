-- Project drag-drop blocks into authoritative marking data and bootstrap
-- module assignments for active course groups that have no existing assignment
-- in any module of that course. Exclusive synthetic QA allowlists stay enforced
-- by learning.guard_synthetic_qa_smoke_assignments.
--
-- Drag-drop is projected as per-item classification specs so existing
-- learning.mark_evidence_response classification marking can score Core matching
-- evidence after api.mark_formative_response expands pairs to item keys.
-- Replay against a current publication uses platform.project_current_curriculum_catalogue.


create or replace function learning.expand_formative_matching_responses(p_responses jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_item jsonb;
  v_pair jsonb;
  v_left text;
  v_right text;
  v_question_key text;
  v_expanded jsonb := '[]'::jsonb;
  v_payload jsonb;
  v_seen text[] := '{}';
begin
  if p_responses is null or jsonb_typeof(p_responses) is distinct from 'array' then
    return p_responses;
  end if;

  for v_item in select value from jsonb_array_elements(p_responses)
  loop
    if lower(coalesce(v_item->>'response_type', '')) is distinct from 'matching' then
      v_expanded := v_expanded || jsonb_build_array(v_item);
      continue;
    end if;

    v_payload := v_item -> 'response_payload';
    v_question_key := btrim(coalesce(v_item->>'question_id', ''));

    if v_question_key = ''
       or jsonb_typeof(v_payload) is distinct from 'object'
       or jsonb_typeof(v_payload->'pairs') is distinct from 'array'
       or jsonb_array_length(v_payload->'pairs') = 0 then
      raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
    end if;

    for v_pair in select value from jsonb_array_elements(v_payload->'pairs')
    loop
      if jsonb_typeof(v_pair) is distinct from 'object' then
        raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
      end if;
      v_left := btrim(coalesce(v_pair->>'left', ''));
      v_right := btrim(coalesce(v_pair->>'right', ''));
      if v_left = '' or v_right = '' then
        raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
      end if;
      if v_left = any (v_seen) then
        raise exception using errcode = '22023', message = 'DUPLICATE_QUESTION';
      end if;
      v_seen := array_append(v_seen, v_left);
      v_expanded := v_expanded || jsonb_build_array(
        jsonb_build_object(
          'question_id', v_question_key || ':' || v_left,
          'response_type', 'classification',
          'response_payload', jsonb_build_object(
            'categoryId', v_right,
            'itemId', v_left
          )
        )
      );
    end loop;
      v_seen := '{}'::text[];
  end loop;

  return v_expanded;
end;
$$;

revoke all on function learning.expand_formative_matching_responses(jsonb)
  from public, anon, authenticated;

comment on function learning.expand_formative_matching_responses(jsonb) is
  'Expands Core drag-drop matching pair evidence into per-item classification responses used by hosted marking specs.';


create or replace function platform.project_curriculum_package(
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
  v_target_id text;
  v_marking jsonb;
  v_questions jsonb := '[]'::jsonb;
  v_payload jsonb;
  v_hash text;
  v_count integer;
  v_lo text;
  v_activity_count integer := 0;
  v_week_stable_key text;
  v_week_number integer;
  v_week_title text;
  v_week_sort integer;
  v_existing_by_key uuid;
  v_existing_by_number uuid;
  v_target_week_id uuid;
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
    v_week_stable_key := coalesce(v_week->>'id', '');
    if v_week_stable_key = '' then
      continue;
    end if;

    v_week_number := coalesce((v_week->'metadata'->>'teachingWeek')::int, 1);
    v_week_title := coalesce(v_week->'metadata'->>'title', v_week_stable_key);
    v_week_sort := v_week_number;

    select week.id
    into v_existing_by_key
    from learning.curriculum_weeks as week
    where week.module_id = v_module_id
      and week.stable_key = v_week_stable_key;

    select week.id
    into v_existing_by_number
    from learning.curriculum_weeks as week
    where week.module_id = v_module_id
      and week.week_number = v_week_number;

    if v_existing_by_key is not null
       and v_existing_by_number is not null
       and v_existing_by_key is distinct from v_existing_by_number then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_CONFLICT';
    end if;

    v_target_week_id := coalesce(v_existing_by_key, v_existing_by_number);

    if v_target_week_id is not null then
      update learning.curriculum_weeks
      set
        stable_key = v_week_stable_key,
        title = v_week_title,
        week_number = v_week_number,
        sort_order = v_week_sort,
        active = true,
        updated_at = clock_timestamp()
      where id = v_target_week_id;
    else
      begin
        insert into learning.curriculum_weeks (
          id, module_id, stable_key, title, week_number, sort_order, active
        )
        values (
          platform.curriculum_catalogue_id(
            'week', p_course_key || ':' || v_module_key || ':' || v_week_stable_key
          ),
          v_module_id,
          v_week_stable_key,
          v_week_title,
          v_week_number,
          v_week_sort,
          true
        );
      exception
        when unique_violation then
          select week.id
          into v_target_week_id
          from learning.curriculum_weeks as week
          where week.module_id = v_module_id
            and (
              week.stable_key = v_week_stable_key
              or week.week_number = v_week_number
            )
          order by case when week.stable_key = v_week_stable_key then 0 else 1 end
          limit 1;

          if v_target_week_id is null then
            raise;
          end if;

          if exists (
            select 1
            from learning.curriculum_weeks as week
            where week.module_id = v_module_id
              and week.stable_key = v_week_stable_key
              and week.id <> v_target_week_id
          ) or exists (
            select 1
            from learning.curriculum_weeks as week
            where week.module_id = v_module_id
              and week.week_number = v_week_number
              and week.id <> v_target_week_id
          ) then
            raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_CONFLICT';
          end if;

          update learning.curriculum_weeks
          set
            stable_key = v_week_stable_key,
            title = v_week_title,
            week_number = v_week_number,
            sort_order = v_week_sort,
            active = true,
            updated_at = clock_timestamp()
          where id = v_target_week_id;
      end;
    end if;
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
        'single-choice', 'classification', 'drag-drop', 'short-response',
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


      if v_block_type = 'drag-drop' then
        if jsonb_typeof(v_content->'items') is distinct from 'array'
           or jsonb_array_length(v_content->'items') = 0
           or jsonb_typeof(v_content->'targets') is distinct from 'array'
           or jsonb_array_length(v_content->'targets') = 0 then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;

        if exists (
          select 1
          from jsonb_array_elements(v_content->'items') as item
          where coalesce(item->>'id', '') = ''
             or item->>'id' !~ '^[A-Za-z0-9._:-]+$'
        ) or exists (
          select 1
          from jsonb_array_elements(v_content->'targets') as target
          where coalesce(target->>'id', '') = ''
             or target->>'id' !~ '^[A-Za-z0-9._:-]+$'
        ) then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;

        if (
          select count(*) <> count(distinct item->>'id')
          from jsonb_array_elements(v_content->'items') as item
        ) or (
          select count(*) <> count(distinct target->>'id')
          from jsonb_array_elements(v_content->'targets') as target
        ) then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;

        if v_content ? 'correct' then
          if jsonb_typeof(v_content->'correct') is distinct from 'object'
             or exists (
               select 1
               from jsonb_each_text(v_content->'correct') as mapping(item_id, target_id)
               where mapping.item_id !~ '^[A-Za-z0-9._:-]+$'
                  or mapping.target_id !~ '^[A-Za-z0-9._:-]+$'
                  or not exists (
                    select 1
                    from jsonb_array_elements(v_content->'items') as item
                    where item->>'id' = mapping.item_id
                  )
                  or not exists (
                    select 1
                    from jsonb_array_elements(v_content->'targets') as target
                    where target->>'id' = mapping.target_id
                  )
             ) then
            raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
          end if;
        end if;

        for v_item in
          select value from jsonb_array_elements(v_content->'items') as value
        loop
          v_item_id := coalesce(v_item->>'id', '');
          v_ordinal := v_ordinal + 1;
          v_target_id := '';
          if jsonb_typeof(v_content->'correct') = 'object' then
            v_target_id := coalesce(v_content->'correct'->>v_item_id, '');
          end if;
          if v_target_id <> '' then
            v_marking := jsonb_build_object(
              'mode', 'classification',
              'correctCategoryId', v_target_id
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
        where block->>'type' in ('classification', 'drag-drop')
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

    select week.id
    into v_week_id
    from learning.curriculum_weeks as week
    where week.module_id = v_module_id
      and week.stable_key = v_delivery_row->>'weekKey';

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

    select activity.id
    into v_activity_row_id
    from learning.activities as activity
    where activity.stable_key = v_activity_id;

    select version.id
    into v_version_id
    from learning.activity_versions as version
    where version.activity_id = v_activity_row_id
      and version.version = v_activity_version;

    if v_version_id is null then
      v_version_id := platform.curriculum_catalogue_id(
        'version',
        v_activity_id || ':' || v_activity_version
      );
    end if;

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

    select version.id
    into v_version_id
    from learning.activity_versions as version
    where version.activity_id = v_activity_row_id
      and version.version = v_activity_version;

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
        and (
          exists (
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
          or not exists (
            select 1
            from learning.activity_assignments as existing
            join learning.activity_versions as existing_version
              on existing_version.id = existing.activity_version_id
            join learning.activities as existing_activity
              on existing_activity.id = existing_version.activity_id
            join learning.modules as existing_module
              on existing_module.id = existing_activity.module_id
            where existing.group_id = learner_group.id
              and existing.active
              and existing_module.course_id = v_course_id
          )
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

create or replace function api.mark_formative_response(
  p_activity_key text,
  p_activity_version text,
  p_responses jsonb,
  p_client_check_id text,
  p_source_page text default null
)
returns table (
  question_id text,
  check_number integer,
  awarded_score numeric(8,2),
  max_score numeric(8,2),
  is_correct boolean,
  requires_review boolean,
  marking_source text,
  remaining_attempts integer,
  can_retry boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_student_id uuid;
  v_activity_version_id uuid;
  v_assignment_id uuid;
  v_matching_assignment_count integer;
  v_item jsonb;
  v_responses jsonb;
  v_question learning.questions%rowtype;
  v_question_key text;
  v_payload jsonb;
  v_response_type text;
  v_mark record;
  v_seen text[] := '{}';
  v_source_page text;
  v_request_hash text;
  v_existing_hash text;
  v_used integer;
  v_max integer;
  v_next_number integer;
  v_remaining integer;
  v_can_retry boolean;
begin
  v_auth_user_id := auth.uid();

  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if p_activity_key is null or btrim(p_activity_key) = ''
     or p_activity_version is null or btrim(p_activity_version) = '' then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_VERSION';
  end if;

  if p_client_check_id is null
     or length(p_client_check_id) not between 1 and 128
     or p_client_check_id !~ '^[A-Za-z0-9._:-]+$' then
    raise exception using errcode = '22023', message = 'INVALID_CLIENT_CHECK_ID';
  end if;

  if p_source_page is not null then
    v_source_page := nullif(btrim(p_source_page), '');
    if v_source_page is not null
       and (
         length(v_source_page) > 512
         or v_source_page ~* '^\s*javascript:'
       ) then
      raise exception using errcode = '22023', message = 'INVALID_SOURCE_PAGE';
    end if;
  end if;

  if p_responses is null
     or jsonb_typeof(p_responses) <> 'array'
     or jsonb_array_length(p_responses) = 0
     or octet_length(p_responses::text) > 131072 then
    raise exception using errcode = '22023', message = 'INVALID_RESPONSES';
  end if;

  select student.id
  into v_student_id
  from learning.students as student
  where student.auth_user_id = v_auth_user_id
    and student.active;

  if v_student_id is null then
    raise exception using errcode = '28000', message = 'STUDENT_IDENTITY_NOT_FOUND';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_student_id::text, 0)
  );

  select version.id
  into v_activity_version_id
  from learning.activity_versions as version
  join learning.activities as activity on activity.id = version.activity_id
  where activity.stable_key = p_activity_key
    and activity.active
    and version.version = p_activity_version
    and version.published_at is not null
    and version.retired_at is null;

  if v_activity_version_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_VERSION';
  end if;

  select count(*)
  into v_matching_assignment_count
  from learning.enrolments as enrolment
  join learning.groups as learner_group
    on learner_group.id = enrolment.group_id
   and learner_group.active
  join learning.activity_assignments as assignment
    on assignment.group_id = enrolment.group_id
   and assignment.activity_version_id = v_activity_version_id
   and assignment.active
   and (assignment.opens_at is null or assignment.opens_at <= clock_timestamp())
   and (assignment.due_at is null or assignment.due_at >= clock_timestamp())
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  if v_matching_assignment_count = 0 then
    raise exception using errcode = '42501', message = 'ACTIVITY_NOT_ASSIGNED';
  end if;

  if v_matching_assignment_count > 1 then
    raise exception using errcode = '23514', message = 'ACTIVITY_ASSIGNMENT_AMBIGUOUS';
  end if;

  select assignment.id
  into v_assignment_id
  from learning.enrolments as enrolment
  join learning.groups as learner_group
    on learner_group.id = enrolment.group_id
   and learner_group.active
  join learning.activity_assignments as assignment
    on assignment.group_id = enrolment.group_id
   and assignment.activity_version_id = v_activity_version_id
   and assignment.active
   and (assignment.opens_at is null or assignment.opens_at <= clock_timestamp())
   and (assignment.due_at is null or assignment.due_at >= clock_timestamp())
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  v_request_hash := encode(
    extensions.digest(
      pg_catalog.convert_to(
        jsonb_build_object(
          'activity_key', p_activity_key,
          'activity_version', p_activity_version,
          'responses', p_responses,
          'source_page', v_source_page
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select check_row.request_hash
  into v_existing_hash
  from learning.formative_checks as check_row
  where check_row.student_id = v_student_id
    and check_row.client_check_id = p_client_check_id
  limit 1;

  if found then
    if v_existing_hash is distinct from v_request_hash then
      raise exception using errcode = '23505', message = 'CLIENT_CHECK_ID_CONFLICT';
    end if;

    return query
    select
      question.stable_key,
      check_row.check_number,
      check_row.awarded_score,
      check_row.max_score,
      check_row.is_correct,
      check_row.requires_review,
      check_row.marking_source,
      case
        when not question.formative_retry then 0
        when question.formative_max_attempts is null then null
        else greatest(question.formative_max_attempts - check_row.check_number, 0)
      end,
      case
        when not question.formative_retry then false
        when question.formative_max_attempts is null then true
        else check_row.check_number < question.formative_max_attempts
      end
    from learning.formative_checks as check_row
    join learning.questions as question
      on question.id = check_row.question_id
    where check_row.student_id = v_student_id
      and check_row.client_check_id = p_client_check_id
    order by question.ordinal, question.stable_key;
    return;
  end if;

  v_responses := learning.expand_formative_matching_responses(p_responses);

  for v_item in select value from jsonb_array_elements(v_responses)
  loop
    if jsonb_typeof(v_item) <> 'object'
       or jsonb_typeof(v_item -> 'question_id') <> 'string'
       or btrim(v_item ->> 'question_id') = ''
       or not (v_item ? 'response_payload')
       or v_item -> 'response_payload' = 'null'::jsonb
       or jsonb_typeof(v_item -> 'response_payload')
          not in ('string', 'array', 'object')
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'string'
         and btrim(v_item ->> 'response_payload') = ''
       )
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'array'
         and jsonb_array_length(v_item -> 'response_payload') = 0
       )
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'object'
         and v_item -> 'response_payload' = '{}'::jsonb
       )
       or octet_length((v_item -> 'response_payload')::text) > 4096 then
      raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
    end if;

    if exists (
      select 1
      from jsonb_object_keys(v_item) as key
      where key not in ('question_id', 'response_payload', 'response_type')
    ) then
      raise exception using errcode = '22023', message = 'FORBIDDEN_SUBMISSION_FIELD';
    end if;

    v_question_key := btrim(v_item ->> 'question_id');

    if v_question_key = any (v_seen) then
      raise exception using errcode = '22023', message = 'DUPLICATE_QUESTION';
    end if;
    v_seen := array_append(v_seen, v_question_key);

    select question.*
    into v_question
    from learning.questions as question
    where question.activity_version_id = v_activity_version_id
      and question.stable_key = v_question_key;

    if not found then
      if exists (
        select 1 from learning.questions as other_question
        where other_question.stable_key = v_question_key
      ) then
        raise exception using
          errcode = '23514',
          message = 'QUESTION_WRONG_ACTIVITY_VERSION';
      end if;
      raise exception using errcode = '22023', message = 'UNKNOWN_QUESTION';
    end if;

    v_max := case
      when not v_question.formative_retry then 1
      else v_question.formative_max_attempts
    end;

    select count(*)
    into v_used
    from learning.formative_checks as check_row
    where check_row.student_id = v_student_id
      and check_row.activity_version_id = v_activity_version_id
      and check_row.question_id = v_question.id;

    if v_max is not null and v_used >= v_max then
      raise exception using errcode = '23514', message = 'FORMATIVE_RETRY_LIMIT';
    end if;

    v_payload := v_item -> 'response_payload';
    v_response_type := nullif(btrim(v_item ->> 'response_type'), '');

    select
      mark.awarded_score,
      mark.is_correct,
      mark.requires_review
    into v_mark
    from learning.mark_evidence_response(
      v_question.id,
      v_payload,
      v_question.max_score
    ) as mark;

    v_next_number := v_used + 1;
    v_remaining := case
      when v_max is null then null
      else greatest(v_max - v_next_number, 0)
    end;
    v_can_retry := (v_max is null) or (v_next_number < v_max);

    insert into learning.formative_checks (
      client_check_id,
      student_id,
      assignment_id,
      activity_version_id,
      question_id,
      check_number,
      response_type,
      response_payload,
      awarded_score,
      max_score,
      is_correct,
      requires_review,
      marking_source,
      request_hash,
      source_page
    ) values (
      p_client_check_id,
      v_student_id,
      v_assignment_id,
      v_activity_version_id,
      v_question.id,
      v_next_number,
      v_response_type,
      v_payload,
      v_mark.awarded_score,
      v_question.max_score,
      v_mark.is_correct,
      v_mark.requires_review,
      'server',
      v_request_hash,
      v_source_page
    );

    question_id := v_question.stable_key;
    check_number := v_next_number;
    awarded_score := v_mark.awarded_score;
    max_score := v_question.max_score;
    is_correct := v_mark.is_correct;
    requires_review := v_mark.requires_review;
    marking_source := 'server';
    remaining_attempts := v_remaining;
    can_retry := v_can_retry;
    return next;
  end loop;
end;
$$;


update learning.synthetic_qa_fixtures
set smoke_activity_key = 'week-1-lesson-1-ex-01'
where persona = 'TLEVEL_TEST_LEARNER'
  and smoke_activity_key = 'week-1-lesson-1-retrieval';

update learning.synthetic_qa_smoke_activities
set activity_key = 'week-1-lesson-1-ex-01'
where persona = 'TLEVEL_TEST_LEARNER'
  and activity_key = 'week-1-lesson-1-retrieval';

insert into learning.synthetic_qa_smoke_activities (persona, activity_key, sort_order)
values ('TLEVEL_TEST_LEARNER', 'week-1-lesson-1-ex-01', 1)
on conflict (persona, activity_key) do update
set sort_order = excluded.sort_order;

delete from learning.synthetic_qa_smoke_activities
where persona = 'TLEVEL_TEST_LEARNER'
  and activity_key = 'week-1-lesson-1-retrieval';

comment on function platform.project_curriculum_package(jsonb, text, text, text, uuid) is
  'Idempotent delivery catalogue projection. Drag-drop blocks become per-item classification specs. Active groups on the published course receive the module when they already take it or have no assignment in any module of that course. Exclusive synthetic QA allowlists remain enforced by trigger.';

comment on function api.mark_formative_response(text, text, jsonb, text, text) is
  'Authenticated formative mark. Expands Core matching/drag-drop pair evidence into per-item classification keys, persists append-only practice checks, and returns safe per-question results. Does not write official attempts or expected answers.';

