-- Strip drag-drop item-to-target maps from learner-facing packages.
-- Boolean `correct` remains stripped. Teaching strings such as
-- feedback.correct are unchanged.

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
  'Removes learner-facing answer keys, including drag-drop object correct maps and structured multi-field-exact correctValues. Teaching requiredFields lists and feedback.correct strings are preserved.';
