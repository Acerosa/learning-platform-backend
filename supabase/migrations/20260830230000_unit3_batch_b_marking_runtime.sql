-- Batch B marking runtime: explicit requires_review mode and versioned apply helper.
-- Does not invent scoring. requires_review and completion remain pending evidence.
begin;

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

create or replace function learning.apply_unit3_batch_b_marking(catalogue jsonb)
returns void
language plpgsql
set search_path = ''
as $batchb$
declare
  item jsonb;
  expected jsonb;
  source_question learning.questions%rowtype;
  v_activity_id uuid;
  v_source learning.activity_versions%rowtype;
  v_new learning.activity_versions%rowtype;
  v_new_id uuid;
  v_question_id uuid;
  v_type text;
  v_score numeric;
  v_spec jsonb;
  v_expected_count integer;
  v_source_count integer;
  v_week_id uuid;
  v_max numeric;
  v_hash text;
begin
  if jsonb_typeof(catalogue) is distinct from 'array' then
    raise exception 'UNIT3_BATCH_B_CONFLICT: catalogue must be a JSON array';
  end if;

  for item in
    select value from jsonb_array_elements(catalogue)
  loop
    select id into strict v_activity_id
    from learning.activities
    where stable_key = item->>'activityKey';

    select version.* into v_source
    from learning.activity_versions as version
    where version.activity_id = v_activity_id
      and version.version = item->>'sourceVersion';

    if not found or v_source.published_at is null or v_source.retired_at is not null then
      raise exception 'UNIT3_BATCH_B_CONFLICT: missing published source % %', item->>'activityKey', item->>'sourceVersion';
    end if;

    select count(*)::integer into v_source_count
    from learning.questions
    where activity_version_id = v_source.id;
    v_expected_count := jsonb_array_length(item->'questions');
    if v_source_count is distinct from v_expected_count then
      raise exception 'UNIT3_BATCH_B_CONFLICT: % % question count drifted', item->>'activityKey', item->>'sourceVersion';
    end if;

    select count(*)::integer into v_source_count
    from jsonb_array_elements(item->'questions') as expected
    join learning.questions as question
      on question.activity_version_id = v_source.id
     and question.stable_key = expected.value->>'k';
    if v_source_count is distinct from v_expected_count then
      raise exception 'UNIT3_BATCH_B_CONFLICT: % % question keys drifted', item->>'activityKey', item->>'sourceVersion';
    end if;

    v_new_id := extensions.uuid_generate_v5(
      '8c1b6c04-5ac5-4b36-bd1e-f2f8c2b2a0b1'::uuid,
      'version:' || (item->>'activityKey') || ':' || (item->>'newVersion')
    );

    v_max := 0;
    v_hash := encode(
      extensions.digest(item::text, 'sha256'),
      'hex'
    );

    insert into learning.activity_versions (
      id, activity_id, version, content_hash, max_score, question_count, published_at
    )
    values (
      v_new_id,
      v_activity_id,
      item->>'newVersion',
      v_hash,
      v_source.max_score,
      v_expected_count,
      null
    )
    on conflict (activity_id, version) do nothing;

    select * into strict v_new
    from learning.activity_versions
    where id = v_new_id;

    if v_new.published_at is not null then
      continue;
    end if;

    for expected in
      select value from jsonb_array_elements(item->'questions')
    loop
      select * into strict source_question
      from learning.questions
      where activity_version_id = v_source.id
        and stable_key = expected->>'k';

      v_type := coalesce(expected->>'qt', source_question.question_type);
      v_score := coalesce((expected->>'ms')::numeric, source_question.max_score);
      v_max := v_max + v_score;
      v_question_id := extensions.uuid_generate_v5(
        '8c1b6c04-5ac5-4b36-bd1e-f2f8c2b2a0b1'::uuid,
        'question:' || (item->>'activityKey') || ':' || (item->>'newVersion') || ':' || (expected->>'k')
      );

      insert into learning.questions (
        id, activity_version_id, stable_key, section_key, section_title, question_type, analytics_title, ordinal, max_score
      )
      values (
        v_question_id,
        v_new.id,
        source_question.stable_key,
        source_question.section_key,
        source_question.section_title,
        v_type,
        source_question.analytics_title,
        source_question.ordinal,
        v_score
      )
      on conflict (activity_version_id, stable_key) do nothing;

      v_spec := jsonb_build_object('mode', expected->>'m');
      if expected ? 'o' then
        v_spec := v_spec || jsonb_build_object('correctOptionId', expected->>'o');
      end if;
      if expected ? 'c' then
        v_spec := v_spec || jsonb_build_object('correctCategoryId', expected->>'c');
      end if;

      insert into learning.question_marking (question_id, spec)
      values (v_question_id, v_spec)
      on conflict (question_id) do nothing;
    end loop;

    update learning.activity_versions
    set max_score = v_max,
        content_hash = v_hash,
        published_at = '2026-08-30T22:30:00Z'::timestamptz
    where id = v_new.id
      and published_at is null;

    v_week_id := (
      select id
      from learning.curriculum_weeks
      where module_id = (
        select id from learning.modules
        where course_id = (select id from learning.courses where stable_key = 'ocr-level-3-it')
          and stable_key = 'unit-3-cyber-security'
      )
        and stable_key = 'week-' || (item->>'weekNumber')
    );

    insert into learning.activity_delivery (
      activity_version_id, academic_year_id, curriculum_week_id, week_number, session_number, sort_order, active
    )
    select
      v_new.id,
      academic_year.id,
      v_week_id,
      (item->>'weekNumber')::integer,
      coalesce(
        nullif(item->>'sessionNumber', '')::integer,
        (
          select delivery.session_number
          from learning.activity_delivery as delivery
          where delivery.activity_version_id = v_source.id
          order by delivery.active desc
          limit 1
        )
      ),
      0,
      true
    from learning.academic_years as academic_year
    where academic_year.active
      and not exists (
        select 1
        from learning.activity_delivery as delivery
        where delivery.activity_version_id = v_new.id
          and delivery.academic_year_id = academic_year.id
          and delivery.group_id is null
      )
    order by academic_year.code
    limit 1;

    insert into learning.activity_assignments (id, group_id, activity_version_id, required, active)
    select
      extensions.uuid_generate_v5(
        '8c1b6c04-5ac5-4b36-bd1e-f2f8c2b2a0b1'::uuid,
        'assignment:CYBER-TEST-A:' || (item->>'activityKey') || ':' || (item->>'newVersion')
      ),
      learner_group.id,
      v_new.id,
      true,
      true
    from learning.groups as learner_group
    where learner_group.code = 'CYBER-TEST-A'
    on conflict (group_id, activity_version_id) do nothing;
  end loop;
end;
$batchb$;

revoke all on function learning.apply_unit3_batch_b_marking(jsonb) from public, anon, authenticated;

commit;
