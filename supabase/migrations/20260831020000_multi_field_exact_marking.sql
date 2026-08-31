-- Shared multi-field-exact marking and answer-key stripping.
-- Existing single-choice, classification, python-patterns, completion and
-- requires_review semantics are unchanged. Published specs are not mutated.

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

comment on function platform.strip_learner_answer_keys(jsonb) is
  'Removes learner-facing answer keys, including structured multi-field-exact correctValues. Teaching requiredFields lists are preserved.';

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
  'Server formative marking. Modes: single-choice, classification, python-patterns, multi-field-exact, completion, requires_review. Malformed multi-field-exact specs stay pending evidence. Extra learner fields are ignored for correctness.';
