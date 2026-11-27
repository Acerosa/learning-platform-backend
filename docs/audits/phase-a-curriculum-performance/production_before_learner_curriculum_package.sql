-- Captured from production hubwpkrqndorznwzvaer before Phase A.
CREATE OR REPLACE FUNCTION platform.learner_curriculum_package(p_package jsonb, p_package_version text, p_source_package_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
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
$function$;
