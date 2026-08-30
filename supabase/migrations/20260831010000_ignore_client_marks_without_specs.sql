-- Client awarded_score / is_correct must never award marks.
--
-- Questions with a protected learning.question_marking row continue to use
-- mark_evidence_response. Questions without a spec now take the same
-- server path (default completion / requires_review: score 0, pending)
-- instead of applying learner-supplied marks.
--
-- Historical attempts are not rewritten. Function signature is unchanged so
-- api.submit_attempt does not need a parallel rewrite.

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
begin
  -- p_has_client_mark / p_client_score / p_client_correct are accepted for
  -- contract compatibility and are never applied.
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

comment on function learning.score_submitted_item(uuid, numeric, jsonb, boolean, numeric, boolean) is
  'Server-only item scoring. Client awarded_score/is_correct arguments are ignored. Specs use mark_evidence_response; unmarked questions stay pending evidence (score 0).';

comment on function api.submit_attempt(
  text,
  text,
  text,
  jsonb,
  text,
  timestamptz,
  timestamptz,
  text
) is
  'Stores an idempotent learner attempt. Identity is always auth.uid(). Client awarded_score/is_correct are never authoritative; learning.score_submitted_item always marks through mark_evidence_response.';
