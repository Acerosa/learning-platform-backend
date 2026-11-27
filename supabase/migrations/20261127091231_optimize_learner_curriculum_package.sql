-- Phase A: set-based learner curriculum package construction.
-- Replaces O(n^2) jsonb || accumulation in strip_learner_answer_keys and
-- learner_curriculum_package with jsonb_agg / jsonb_object_agg.
-- Signatures, volatility, search_path, strip rules and teacher-note filtering
-- are unchanged. api.published_curriculum_package is not modified.

create or replace function platform.strip_learner_answer_keys(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if p_value is null then
    return p_value;
  end if;

  if jsonb_typeof(p_value) = 'array' then
    select coalesce(
      jsonb_agg(platform.strip_learner_answer_keys(value) order by ordinality),
      '[]'::jsonb
    )
    into v_result
    from jsonb_array_elements(p_value) with ordinality as item(value, ordinality);
    return v_result;
  end if;

  if jsonb_typeof(p_value) <> 'object' then
    return p_value;
  end if;

  select coalesce(
    jsonb_object_agg(key, platform.strip_learner_answer_keys(value)),
    '{}'::jsonb
  )
  into v_result
  from jsonb_each(p_value)
  where key not in (
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
  )
  and not (
    key = 'correct'
    and jsonb_typeof(value) in ('boolean', 'object')
  );
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
language sql
immutable
set search_path = ''
as $$
  select platform.strip_learner_answer_keys(
    jsonb_set(
      coalesce(p_package, '{}'::jsonb),
      '{activities}',
      coalesce(
        (
          select jsonb_agg(
            jsonb_set(
              activity.value,
              '{blocks}',
              coalesce(
                (
                  select jsonb_agg(block.value order by block.ordinality)
                  from jsonb_array_elements(coalesce(activity.value->'blocks', '[]'::jsonb))
                    with ordinality as block(value, ordinality)
                  where coalesce(block.value->>'type', '') is distinct from 'teacher-note'
                ),
                '[]'::jsonb
              ),
              true
            )
            order by activity.ordinality
          )
          from jsonb_array_elements(coalesce(p_package->'activities', '[]'::jsonb))
            with ordinality as activity(value, ordinality)
        ),
        '[]'::jsonb
      ),
      true
    )
    || jsonb_build_object(
      'schema', 'lp.content.package',
      'schemaVersion', coalesce(p_source_package_version, p_package->>'schemaVersion', '0.1.0'),
      'id', coalesce(p_package->>'id', p_package->'hub'->>'id'),
      'version', p_package_version
    )
  );
$$;

revoke all on function platform.learner_curriculum_package(jsonb, text, text)
  from public, anon, authenticated;

comment on function platform.learner_curriculum_package(jsonb, text, text) is
  'Builds the learner-facing curriculum package: drops teacher-note blocks, stamps package identity fields, and strips protected answer keys. Set-based JSON aggregation; behaviour matches the pre-Phase-A loop implementation.';
