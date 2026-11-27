-- Rollback for 20261127091231_optimize_learner_curriculum_package.sql
-- Restores the production function bodies captured before Phase A.
-- Apply only this script if Phase A must be reverted. Do not drop publications
-- or change learner records.

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

revoke all on function platform.learner_curriculum_package(jsonb, text, text)
  from public, anon, authenticated;

comment on function platform.learner_curriculum_package(jsonb, text, text) is
  'Builds the learner-facing curriculum package: drops teacher-note blocks, stamps package identity fields, and strips protected answer keys.';
