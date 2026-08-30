-- Strip answer keys from learner-facing published packages, ignore client
-- marks when a protected marking spec exists, and drop table DML grants on
-- library objects (writes stay on SECURITY DEFINER staff RPCs).

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
    if v_key = 'correct' and jsonb_typeof(v_item) = 'boolean' then
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

create or replace function platform.learner_curriculum_package(
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
  return platform.strip_learner_answer_keys(v_package);
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

  awarded_score := 0;
  is_correct := null;
  requires_review := true;
  return next;
end;
$$;

revoke all on function learning.mark_evidence_response(uuid, jsonb, numeric)
  from public, anon, authenticated;

create or replace function learning.score_submitted_item(
  p_question_id uuid,
  p_max_score numeric,
  p_payload jsonb,
  p_has_client_mark boolean,
  p_client_score numeric,
  p_client_correct boolean
)
returns table (
  awarded_score numeric(8,2),
  is_correct boolean,
  requires_review boolean,
  marking_source text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_has_spec boolean;
begin
  v_has_spec := exists (
    select 1
    from learning.question_marking as marking
    where marking.question_id = p_question_id
  );

  if v_has_spec then
    return query
    select
      mark.awarded_score,
      mark.is_correct,
      mark.requires_review,
      'server'::text
    from learning.mark_evidence_response(
      p_question_id,
      p_payload,
      p_max_score
    ) as mark;
    return;
  end if;

  if p_has_client_mark then
    if p_client_score is null or p_client_correct is null then
      raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
    end if;
    if p_client_score < 0 or p_client_score > p_max_score then
      raise exception using errcode = '23514', message = 'INVALID_RESPONSE_SCORE';
    end if;
    if (p_client_correct and p_client_score <> p_max_score)
       or (not p_client_correct and p_client_score <> 0) then
      raise exception using errcode = '23514', message = 'INCONSISTENT_CLIENT_MARK';
    end if;
    awarded_score := p_client_score::numeric(8,2);
    is_correct := p_client_correct;
    requires_review := not p_client_correct;
    marking_source := 'client';
    return next;
    return;
  end if;

  return query
  select
    mark.awarded_score,
    mark.is_correct,
    mark.requires_review,
    'server'::text
  from learning.mark_evidence_response(
    p_question_id,
    p_payload,
    p_max_score
  ) as mark;
end;
$$;

revoke all on function learning.score_submitted_item(uuid, numeric, jsonb, boolean, numeric, boolean)
  from public, anon, authenticated;
