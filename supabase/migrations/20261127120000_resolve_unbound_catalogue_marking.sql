-- Catalogue Check sends the published package activity version (1.0.0).
-- Batch B registered Week 6/7 marking on 1.1.0 before structure fingerprints
-- existed. Later fingerprint backfill only bound rows whose sourceQuestionId
-- exactly matched the catalogue key, so Week 7 1.0.0 checks resolved to
-- requires_review instead of correct/incorrect.
--
-- Keep the exact-version and fingerprint rules. If those miss, use the single
-- published marking spec for the same activity + question key. Fail closed
-- when more than one spec exists. Do not prefer the newest version.

create or replace function learning.resolve_marking_question(p_question_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
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

  if v_computed is not null then
    select count(*)::integer, (array_agg(marking.question_id))[1]
    into v_match_count, v_match_id
    from learning.question_marking as marking
    where marking.bound_activity_id = v_activity_id
      and marking.bound_question_key = v_question_key
      and marking.structure_fingerprint = v_computed;

    if v_match_count = 1 then
      return v_match_id;
    end if;
  end if;

  if v_activity_id is null or v_question_key is null then
    return null;
  end if;

  select count(*)::integer, (array_agg(marking.question_id))[1]
  into v_match_count, v_match_id
  from learning.question_marking as marking
  join learning.questions as other_question
    on other_question.id = marking.question_id
  join learning.activity_versions as other_version
    on other_version.id = other_question.activity_version_id
  where other_version.activity_id = v_activity_id
    and other_question.stable_key = v_question_key
    and other_question.id is distinct from p_question_id
    and other_version.published_at is not null
    and other_version.retired_at is null;

  if v_match_count = 1 then
    return v_match_id;
  end if;

  return null;
end;
$$;

revoke all on function learning.resolve_marking_question(uuid)
  from public, anon, authenticated;

comment on function learning.resolve_marking_question(uuid) is
  'Uses the exact version rule when it is compatible. Otherwise uses the single fingerprint-compatible rule, then the single published spec for the same activity and question key. Never guesses and never prefers the newest version.';
