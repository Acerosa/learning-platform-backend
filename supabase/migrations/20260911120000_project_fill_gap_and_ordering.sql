-- Phase 1 (R1/R2): project fill-gap / phrase-completion / ordering / sequence
-- into authoritative catalogue marking, fail closed on unknown checkable blocks,
-- and add ordering-exact marking for authored correctOrder sequences.
--
-- Fill-gap canonical identity (matches Core evidence after this change):
--   single-gap block  → package questionId
--   multi-gap block   → questionId:gapId
-- Open ordering tasks without correctOrder project as completion (review),
-- not invented answer keys.

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
  v_gap_count integer;
  v_correct_option text;
  v_stable_key text;
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
        'reflection', 'code-editor', 'python-exercise',
        'fill-gap', 'phrase-completion', 'ordering', 'sequence'
      ) then
        -- Checkable / interactive blocks must never be silently omitted.
        raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
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

      if v_block_type in ('fill-gap', 'phrase-completion') then
        -- Canonical identity matches Core evidence:
        --   single-gap block  → package questionId
        --   multi-gap block   → questionId:gapId
        if jsonb_typeof(v_content->'gaps') = 'array'
           and jsonb_array_length(v_content->'gaps') > 0 then
          v_gap_count := jsonb_array_length(v_content->'gaps');
          for v_item in select value from jsonb_array_elements(v_content->'gaps')
          loop
            v_item_id := coalesce(nullif(btrim(v_item->>'id'), ''), 'gap');
            if v_item_id !~ '^[A-Za-z0-9._:-]+$' then
              raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
            end if;
            v_correct_option := coalesce(
              nullif(btrim(v_item->>'correctOptionId'), ''),
              nullif(btrim(v_content->>'correctOptionId'), ''),
              ''
            );
            v_stable_key := case
              when v_gap_count = 1 then v_question_key
              else v_question_key || ':' || v_item_id
            end;
            v_ordinal := v_ordinal + 1;
            if v_correct_option <> '' then
              v_marking := jsonb_build_object(
                'mode', 'single-choice',
                'correctOptionId', v_correct_option
              );
            else
              v_marking := jsonb_build_object('mode', 'completion');
            end if;
            v_questions := v_questions || jsonb_build_array(
              jsonb_build_object(
                'stableKey', v_stable_key,
                'questionType', 'single',
                'ordinal', v_ordinal,
                'marking', v_marking
              )
            );
          end loop;
        else
          v_correct_option := coalesce(nullif(btrim(v_content->>'correctOptionId'), ''), '');
          v_ordinal := v_ordinal + 1;
          if v_correct_option <> '' then
            v_marking := jsonb_build_object(
              'mode', 'single-choice',
              'correctOptionId', v_correct_option
            );
          else
            v_marking := jsonb_build_object('mode', 'completion');
          end if;
          v_questions := v_questions || jsonb_build_array(
            jsonb_build_object(
              'stableKey', v_question_key,
              'questionType', 'single',
              'ordinal', v_ordinal,
              'marking', v_marking
            )
          );
        end if;
        continue;
      end if;

      if v_block_type in ('ordering', 'sequence') then
        -- One question at package questionId. Scored only when correctOrder is authored.
        -- Item ids may include spaces (authored labels used as ids); they are not
        -- catalogue stable_keys, so do not apply the questionId charset constraint.
        if jsonb_typeof(v_content->'items') is distinct from 'array'
           or jsonb_array_length(v_content->'items') = 0 then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;
        if exists (
          select 1
          from jsonb_array_elements(v_content->'items') as item
          where coalesce(btrim(item->>'id'), '') = ''
        ) then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;

        v_ordinal := v_ordinal + 1;
        if jsonb_typeof(v_content->'correctOrder') = 'array'
           and jsonb_array_length(v_content->'correctOrder') > 0 then
          if jsonb_array_length(v_content->'correctOrder')
               is distinct from jsonb_array_length(v_content->'items')
             or exists (
               select 1
               from jsonb_array_elements_text(v_content->'correctOrder') as item_id
               where btrim(item_id) = ''
                  or not exists (
                    select 1
                    from jsonb_array_elements(v_content->'items') as item
                    where item->>'id' = item_id
                  )
             ) then
            raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
          end if;
          v_marking := jsonb_build_object(
            'mode', 'ordering-exact',
            'correctOrder', v_content->'correctOrder'
          );
        else
          v_marking := jsonb_build_object('mode', 'completion');
        end if;
        v_questions := v_questions || jsonb_build_array(
          jsonb_build_object(
            'stableKey', v_question_key,
            'questionType', 'order',
            'ordinal', v_ordinal,
            'marking', v_marking
          )
        );
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
        where block->>'type' in ('single-choice', 'fill-gap', 'phrase-completion', 'ordering', 'sequence')
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

create or replace function learning.mark_evidence_response(
  p_question_id uuid,
  p_payload jsonb,
  p_max_score numeric
)
returns table (
  awarded_score numeric(8,2),
  is_correct boolean,
  requires_review boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_spec jsonb;
  v_mode text;
  v_source text;
  v_pattern text;
  v_ok boolean;
  v_option text;
  v_category text;
  v_fields jsonb;
  v_field text;
  v_item jsonb;
  v_expected text;
  v_actual text;
  v_malformed boolean;
  v_case_insensitive boolean;
begin
  select marking.spec
  into v_spec
  from learning.question_marking as marking
  where marking.question_id = p_question_id;

  v_mode := coalesce(v_spec ->> 'mode', 'completion');
  v_option := coalesce(
    nullif(p_payload ->> 'optionId', ''),
    nullif(p_payload ->> 'selectedOptionId', ''),
    nullif(p_payload ->> 'option_id', ''),
    nullif(p_payload ->> 'selected_option_id', '')
  );
  v_category := coalesce(
    nullif(p_payload ->> 'categoryId', ''),
    nullif(p_payload ->> 'category', ''),
    nullif(p_payload ->> 'category_id', '')
  );

  if v_mode = 'single-choice' then
    v_ok := coalesce(v_option, '') = coalesce(v_spec ->> 'correctOptionId', '');
    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    requires_review := false;
    return next;
    return;
  end if;

  if v_mode = 'classification' then
    v_ok := coalesce(v_category, '') = coalesce(v_spec ->> 'correctCategoryId', '');
    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    requires_review := false;
    return next;
    return;
  end if;

  if v_mode = 'python-patterns' then
    v_source := coalesce(p_payload ->> 'sourceCode', '');
    v_ok := true;
    for v_pattern in
      select jsonb_array_elements_text(coalesce(v_spec -> 'required', '[]'::jsonb))
    loop
      if v_source !~ v_pattern then
        v_ok := false;
      end if;
    end loop;
    for v_pattern in
      select jsonb_array_elements_text(coalesce(v_spec -> 'prohibited', '[]'::jsonb))
    loop
      if v_source ~ v_pattern then
        v_ok := false;
      end if;
    end loop;
    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    requires_review := false;
    return next;
    return;
  end if;

  if v_mode = 'ordering-exact' then
    if jsonb_typeof(coalesce(v_spec -> 'correctOrder', 'null'::jsonb))
         is distinct from 'array'
       or jsonb_array_length(coalesce(v_spec -> 'correctOrder', '[]'::jsonb)) = 0 then
      awarded_score := 0;
      is_correct := null;
      requires_review := true;
      return next;
      return;
    end if;

    if jsonb_typeof(coalesce(p_payload -> 'itemIds', 'null'::jsonb))
         is distinct from 'array' then
      awarded_score := 0;
      is_correct := false;
      requires_review := false;
      return next;
      return;
    end if;

    if jsonb_array_length(p_payload -> 'itemIds')
         is distinct from jsonb_array_length(v_spec -> 'correctOrder') then
      awarded_score := 0;
      is_correct := false;
      requires_review := false;
      return next;
      return;
    end if;

    v_ok := (
      select bool_and(coalesce(actual.val, '') = coalesce(expected.val, ''))
      from jsonb_array_elements_text(v_spec -> 'correctOrder')
           with ordinality as expected(val, ord)
      left join jsonb_array_elements_text(p_payload -> 'itemIds')
           with ordinality as actual(val, ord)
        on actual.ord = expected.ord
    );

    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    requires_review := false;
    return next;
    return;
  end if;

  if v_mode = 'multi-field-exact' then
    if jsonb_typeof(coalesce(v_spec -> 'correctValues', 'null'::jsonb))
         is distinct from 'object'
       or coalesce(v_spec -> 'correctValues', '{}'::jsonb) = '{}'::jsonb then
      awarded_score := 0;
      is_correct := null;
      requires_review := true;
      return next;
      return;
    end if;

    if jsonb_typeof(v_spec -> 'requiredFields') = 'array' then
      v_fields := v_spec -> 'requiredFields';
    else
      select coalesce(jsonb_agg(key), '[]'::jsonb)
      into v_fields
      from jsonb_object_keys(v_spec -> 'correctValues') as key;
    end if;

    if jsonb_typeof(v_fields) is distinct from 'array'
       or jsonb_array_length(v_fields) = 0 then
      awarded_score := 0;
      is_correct := null;
      requires_review := true;
      return next;
      return;
    end if;

    v_malformed := false;
    for v_item in
      select value from jsonb_array_elements(v_fields)
    loop
      if jsonb_typeof(v_item) is distinct from 'string' then
        v_malformed := true;
        exit;
      end if;
      v_field := btrim(v_item #>> '{}');
      if v_field = '' then
        v_malformed := true;
        exit;
      end if;
      if jsonb_typeof(v_spec -> 'correctValues' -> v_field) is null then
        v_malformed := true;
        exit;
      end if;
      v_expected := btrim(coalesce(v_spec -> 'correctValues' ->> v_field, ''));
      if v_expected = '' then
        v_malformed := true;
        exit;
      end if;
    end loop;

    if v_malformed then
      awarded_score := 0;
      is_correct := null;
      requires_review := true;
      return next;
      return;
    end if;

    if jsonb_typeof(p_payload) is distinct from 'object' then
      awarded_score := 0;
      is_correct := false;
      requires_review := false;
      return next;
      return;
    end if;

    v_case_insensitive :=
      lower(coalesce(v_spec ->> 'caseInsensitive', 'false')) in ('true', 't', '1');
    v_ok := true;
    for v_item in
      select value from jsonb_array_elements(v_fields)
    loop
      v_field := btrim(v_item #>> '{}');
      v_expected := btrim(v_spec -> 'correctValues' ->> v_field);
      v_actual := btrim(coalesce(p_payload ->> v_field, ''));
      if v_case_insensitive then
        if lower(v_actual) is distinct from lower(v_expected) then
          v_ok := false;
          exit;
        end if;
      elsif v_actual is distinct from v_expected then
        v_ok := false;
        exit;
      end if;
    end loop;

    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    requires_review := false;
    return next;
    return;
  end if;

  if v_mode in ('completion', 'requires_review') then
    awarded_score := 0;
    is_correct := null;
    requires_review := true;
    return next;
    return;
  end if;

  awarded_score := 0;
  is_correct := null;
  requires_review := true;
  return next;
end;
$$;

revoke all on function learning.mark_evidence_response(uuid, jsonb, numeric)
  from public, anon, authenticated;

comment on function learning.mark_evidence_response(uuid, jsonb, numeric) is
  'Server formative marking. Modes: single-choice, classification, python-patterns, ordering-exact, multi-field-exact, completion, requires_review. Malformed multi-field-exact specs stay pending evidence. Extra learner fields are ignored for correctness.';


comment on function platform.project_curriculum_package(jsonb, text, text, text, uuid) is
  'Projects a published curriculum package into learning catalogue tables. Supports single-choice, classification, drag-drop, fill-gap, phrase-completion, ordering, sequence, short-response, reflection and code exercises. Unknown interactive block types raise CATALOGUE_PROJECTION_FAILED instead of silent skip.';


-- Extend learner-safe stripping for ordering answer keys (correctOrder).
create or replace function platform.strip_learner_answer_keys(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_result jsonb;
  v_key text;
  v_item jsonb;
begin
  if p_value is null then
    return p_value;
  end if;

  if jsonb_typeof(p_value) = 'array' then
    v_result := '[]'::jsonb;
    for v_item in select value from jsonb_array_elements(p_value)
    loop
      v_result := v_result || jsonb_build_array(
        platform.strip_learner_answer_keys(v_item)
      );
    end loop;
    return v_result;
  end if;

  if jsonb_typeof(p_value) <> 'object' then
    return p_value;
  end if;

  v_result := '{}'::jsonb;
  for v_key, v_item in select key, value from jsonb_each(p_value)
  loop
    if v_key in (
      'correctOptionId',
      'correctCategoryId',
      'correctValues',
      'correctOrder',
      'accepted',
      'checks',
      'modelAnswer',
      'markScheme',
      'answerKey',
      'correctAnswers',
      'correctOption',
      'correctOptions'
    ) then
      continue;
    end if;
    if v_key = 'correct' and jsonb_typeof(v_item) in ('boolean', 'object') then
      continue;
    end if;
    v_result := v_result || jsonb_build_object(
      v_key,
      platform.strip_learner_answer_keys(v_item)
    );
  end loop;
  return v_result;
end;
$$;

revoke all on function platform.strip_learner_answer_keys(jsonb)
  from public, anon, authenticated;

comment on function platform.strip_learner_answer_keys(jsonb) is
  'Removes learner-facing answer keys, including drag-drop object correct maps, ordering correctOrder, and structured multi-field-exact correctValues. Teaching requiredFields lists and feedback.correct strings are preserved.';
