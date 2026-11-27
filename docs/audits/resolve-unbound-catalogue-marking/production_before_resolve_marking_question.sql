CREATE OR REPLACE FUNCTION learning.resolve_marking_question(p_question_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_activity_id uuid;
  v_activity_key text;
  v_version text;
  v_question_key text;
  v_own_fingerprint text;
  v_computed text;
  v_match_count integer;
  v_match_id uuid;
begin
  select activity.id, activity.stable_key, activity_version.version, question.stable_key, marking.structure_fingerprint
  into v_activity_id, v_activity_key, v_version, v_question_key, v_own_fingerprint
  from learning.questions as question
  join learning.activity_versions as activity_version
    on activity_version.id = question.activity_version_id
  join learning.activities as activity
    on activity.id = activity_version.activity_id
  left join learning.question_marking as marking
    on marking.question_id = question.id
  where question.id = p_question_id;

  v_computed := learning.published_question_fingerprint(v_activity_key, v_version, v_question_key);

  if exists (
    select 1 from learning.question_marking as marking
    where marking.question_id = p_question_id
  ) and (
    v_own_fingerprint is null
    or v_computed is null
    or v_own_fingerprint = v_computed
  ) then
    return p_question_id;
  end if;

  if v_computed is null then
    return null;
  end if;

  select count(*)::integer, (array_agg(marking.question_id))[1]
  into v_match_count, v_match_id
  from learning.question_marking as marking
  where marking.bound_activity_id = v_activity_id
    and marking.bound_question_key = v_question_key
    and marking.structure_fingerprint = v_computed;

  if v_match_count = 1 then
    return v_match_id;
  end if;

  return null;
end;
$function$;
