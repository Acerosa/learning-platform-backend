-- Phase 8: teacher review and feedback.
-- Additive: widen marking sources, persist staff feedback on responses,
-- allow a narrow security-definer review path past completed-row immutability,
-- and expose admin_api.review_response.

-- ---------------------------------------------------------------------------
-- Schema: marking source + feedback on responses
-- ---------------------------------------------------------------------------

alter table learning.attempts
  drop constraint if exists attempt_marking_source_valid;

alter table learning.attempts
  add constraint attempt_marking_source_valid
  check (marking_source in ('client', 'server', 'imported', 'teacher'));

alter table learning.responses
  drop constraint if exists response_marking_source_valid;

alter table learning.responses
  add constraint response_marking_source_valid
  check (marking_source in ('client', 'server', 'imported', 'teacher'));

alter table learning.responses
  add column if not exists feedback_summary text,
  add column if not exists feedback_next_step text;

alter table learning.responses
  drop constraint if exists response_feedback_summary_length;

alter table learning.responses
  add constraint response_feedback_summary_length
  check (feedback_summary is null or char_length(feedback_summary) <= 2000);

alter table learning.responses
  drop constraint if exists response_feedback_next_step_length;

alter table learning.responses
  add constraint response_feedback_next_step_length
  check (feedback_next_step is null or char_length(feedback_next_step) <= 500);

comment on column learning.responses.feedback_summary is
  'Staff-authored feedback for a reviewed response. Never overwrites response_payload.';
comment on column learning.responses.feedback_next_step is
  'Optional short next-step guidance recorded with teacher feedback.';

-- ---------------------------------------------------------------------------
-- Narrow immutability bypass for controlled teacher review
-- ---------------------------------------------------------------------------

create or replace function learning.prevent_completed_attempt_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'completed'
     and current_setting('learning.allow_teacher_review', true) = '1'
     and tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.client_attempt_id is distinct from old.client_attempt_id
       or new.student_id is distinct from old.student_id
       or new.enrolment_id is distinct from old.enrolment_id
       or new.assignment_id is distinct from old.assignment_id
       or new.activity_version_id is distinct from old.activity_version_id
       or new.attempt_number is distinct from old.attempt_number
       or new.status is distinct from old.status
       or new.max_score is distinct from old.max_score
       or new.evidence_level is distinct from old.evidence_level
       or new.source_system is distinct from old.source_system
       or new.submission_hash is distinct from old.submission_hash
       or new.received_at is distinct from old.received_at
       or new.completed_at is distinct from old.completed_at then
      raise exception using
        errcode = '55000',
        message = 'COMPLETED_ATTEMPT_IMMUTABLE';
    end if;
    return new;
  end if;

  if old.status = 'completed' then
    raise exception using
      errcode = '55000',
      message = 'COMPLETED_ATTEMPT_IMMUTABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function learning.prevent_completed_response_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from learning.attempts as attempt
    where attempt.id = old.attempt_id
      and attempt.status = 'completed'
  ) then
    if current_setting('learning.allow_teacher_review', true) = '1'
       and tg_op = 'UPDATE' then
      if new.id is distinct from old.id
         or new.attempt_id is distinct from old.attempt_id
         or new.question_id is distinct from old.question_id
         or new.response_payload is distinct from old.response_payload
         or new.max_score is distinct from old.max_score then
        raise exception using
          errcode = '55000',
          message = 'COMPLETED_RESPONSE_IMMUTABLE';
      end if;
      return new;
    end if;

    raise exception using
      errcode = '55000',
      message = 'COMPLETED_RESPONSE_IMMUTABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Authoritative review mutation
-- ---------------------------------------------------------------------------

create function platform.review_response(
  p_response_id uuid,
  p_awarded_score numeric,
  p_is_correct boolean,
  p_feedback_summary text,
  p_feedback_next_step text default null
)
returns table (
  response_id uuid,
  attempt_id uuid,
  awarded_score numeric,
  max_score numeric,
  is_correct boolean,
  requires_review boolean,
  marking_source text,
  feedback_summary text,
  feedback_next_step text,
  marked_at timestamptz,
  attempt_score numeric,
  attempt_marking_source text,
  idempotent boolean
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_teacher learning.teachers%rowtype;
  v_response learning.responses%rowtype;
  v_attempt learning.attempts%rowtype;
  v_group_id uuid;
  v_feedback text;
  v_next_step text;
  v_score numeric(8,2);
  v_attempt_score numeric(8,2);
  v_attempt_source text;
  v_before jsonb;
  v_after jsonb;
  v_now timestamptz := timezone('utc', now());
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  select teacher.*
  into v_teacher
  from learning.teachers as teacher
  where teacher.auth_user_id = v_auth_user_id
    and teacher.active;

  if not found then
    raise exception using errcode = '28000', message = 'REVIEW_NOT_AUTHORISED';
  end if;

  if p_response_id is null then
    raise exception using errcode = '22023', message = 'REVIEW_RESPONSE_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_response_id::text, 0));

  select response.*
  into v_response
  from learning.responses as response
  where response.id = p_response_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'REVIEW_RESPONSE_NOT_FOUND';
  end if;

  select attempt.*
  into v_attempt
  from learning.attempts as attempt
  where attempt.id = v_response.attempt_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'REVIEW_ATTEMPT_NOT_FOUND';
  end if;

  select assignment.group_id
  into v_group_id
  from learning.activity_assignments as assignment
  where assignment.id = v_attempt.assignment_id;

  if v_group_id is null then
    raise exception using errcode = '22023', message = 'REVIEW_ATTEMPT_NOT_FOUND';
  end if;

  if not platform.current_staff_has_role('platform_admin')
     and not learning.teacher_can_access_group(v_group_id) then
    raise exception using errcode = '28000', message = 'REVIEW_NOT_AUTHORISED';
  end if;

  begin
    v_score := p_awarded_score::numeric(8,2);
  exception when others then
    raise exception using errcode = '22023', message = 'REVIEW_SCORE_INVALID';
  end;

  if v_score is null or v_score < 0 or v_score > v_response.max_score then
    raise exception using errcode = '22023', message = 'REVIEW_SCORE_INVALID';
  end if;

  v_feedback := nullif(btrim(coalesce(p_feedback_summary, '')), '');
  if v_feedback is null then
    raise exception using errcode = '22023', message = 'REVIEW_FEEDBACK_REQUIRED';
  end if;
  if char_length(v_feedback) > 2000 then
    raise exception using errcode = '22023', message = 'REVIEW_FEEDBACK_TOO_LONG';
  end if;

  v_next_step := nullif(btrim(coalesce(p_feedback_next_step, '')), '');
  if v_next_step is not null and char_length(v_next_step) > 500 then
    raise exception using errcode = '22023', message = 'REVIEW_NEXT_STEP_TOO_LONG';
  end if;

  v_before := jsonb_build_object(
    'awardedScore', v_response.awarded_score,
    'isCorrect', v_response.is_correct,
    'requiresReview', v_response.requires_review,
    'markingSource', v_response.marking_source,
    'feedbackSummary', v_response.feedback_summary,
    'feedbackNextStep', v_response.feedback_next_step,
    'attemptScore', v_attempt.score,
    'attemptMarkingSource', v_attempt.marking_source
  );

  if v_response.requires_review = false
     and v_response.marking_source = 'teacher'
     and v_response.awarded_score = v_score
     and v_response.is_correct is not distinct from p_is_correct
     and v_response.feedback_summary is not distinct from v_feedback
     and v_response.feedback_next_step is not distinct from v_next_step then
    return query
    select
      v_response.id,
      v_response.attempt_id,
      v_response.awarded_score,
      v_response.max_score,
      v_response.is_correct,
      v_response.requires_review,
      v_response.marking_source,
      v_response.feedback_summary,
      v_response.feedback_next_step,
      v_response.marked_at,
      v_attempt.score,
      v_attempt.marking_source,
      true;
    return;
  end if;

  perform set_config('learning.allow_teacher_review', '1', true);

  update learning.responses as response
  set
    awarded_score = v_score,
    is_correct = p_is_correct,
    requires_review = false,
    marking_source = 'teacher',
    marked_at = v_now,
    feedback_summary = v_feedback,
    feedback_next_step = v_next_step
  where response.id = v_response.id
  returning response.* into v_response;

  select coalesce(sum(response.awarded_score), 0)::numeric(8,2)
  into v_attempt_score
  from learning.responses as response
  where response.attempt_id = v_attempt.id;

  if exists (
    select 1
    from learning.responses as response
    where response.attempt_id = v_attempt.id
      and response.marking_source = 'teacher'
  ) then
    v_attempt_source := 'teacher';
  else
    v_attempt_source := v_attempt.marking_source;
  end if;

  update learning.attempts as attempt
  set
    score = v_attempt_score,
    marking_source = v_attempt_source
  where attempt.id = v_attempt.id
  returning attempt.* into v_attempt;

  v_after := jsonb_build_object(
    'awardedScore', v_response.awarded_score,
    'isCorrect', v_response.is_correct,
    'requiresReview', v_response.requires_review,
    'markingSource', v_response.marking_source,
    'feedbackSummary', v_response.feedback_summary,
    'feedbackNextStep', v_response.feedback_next_step,
    'attemptScore', v_attempt.score,
    'attemptMarkingSource', v_attempt.marking_source
  );

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'learning.response.reviewed',
    v_auth_user_id,
    'staff',
    'response',
    v_response.id::text,
    'succeeded',
    jsonb_build_object(
      'staffReference', v_teacher.staff_reference,
      'attemptId', v_attempt.id,
      'responseId', v_response.id,
      'questionId', v_response.question_id,
      'before', v_before,
      'after', v_after
    )
  );

  return query
  select
    v_response.id,
    v_response.attempt_id,
    v_response.awarded_score,
    v_response.max_score,
    v_response.is_correct,
    v_response.requires_review,
    v_response.marking_source,
    v_response.feedback_summary,
    v_response.feedback_next_step,
    v_response.marked_at,
    v_attempt.score,
    v_attempt.marking_source,
    false;
end;
$$;

create function admin_api.review_response(
  p_response_id uuid,
  p_awarded_score numeric,
  p_is_correct boolean,
  p_feedback_summary text,
  p_feedback_next_step text default null
)
returns table (
  response_id uuid,
  attempt_id uuid,
  awarded_score numeric,
  max_score numeric,
  is_correct boolean,
  requires_review boolean,
  marking_source text,
  feedback_summary text,
  feedback_next_step text,
  marked_at timestamptz,
  attempt_score numeric,
  attempt_marking_source text,
  idempotent boolean
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from platform.review_response(
    p_response_id,
    p_awarded_score,
    p_is_correct,
    p_feedback_summary,
    p_feedback_next_step
  )
$$;

revoke all on function platform.review_response(uuid, numeric, boolean, text, text)
  from public, anon, authenticated;
revoke all on function admin_api.review_response(uuid, numeric, boolean, text, text)
  from public, anon, authenticated;

grant execute on function platform.review_response(uuid, numeric, boolean, text, text)
  to authenticated;
grant execute on function admin_api.review_response(uuid, numeric, boolean, text, text)
  to authenticated;

comment on function platform.review_response(uuid, numeric, boolean, text, text) is
  'Records a staff review for one response: updates marks and feedback only, never evidence payload. Identity comes from auth.uid().';
comment on function admin_api.review_response(uuid, numeric, boolean, text, text) is
  'Browser-safe wrapper for teacher review and feedback. Does not expose learning schema tables.';

-- ---------------------------------------------------------------------------
-- Extend staff Results read model
-- ---------------------------------------------------------------------------

create or replace view admin_api.responses
with (security_invoker = true)
as
select
  response.id as response_id,
  response.attempt_id,
  student.student_number,
  learner_group.code as group_code,
  activity.stable_key as activity_key,
  question.stable_key as question_key,
  question.question_type,
  question.section_key,
  question.section_title,
  question.ordinal,
  coalesce(topic_summary.topic_keys, '{}'::text[]) as topic_keys,
  coalesce(skill_summary.skill_keys, '{}'::text[]) as skill_keys,
  response.response_payload,
  response.awarded_score,
  response.max_score,
  response.is_correct,
  response.requires_review,
  response.marking_source,
  response.marked_at,
  response.feedback_summary,
  response.feedback_next_step
from learning.responses as response
join learning.attempts as attempt on attempt.id = response.attempt_id
join learning.students as student on student.id = attempt.student_id
join learning.questions as question on question.id = response.question_id
join learning.activity_versions as activity_version
  on activity_version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
join learning.activity_assignments as assignment
  on assignment.id = attempt.assignment_id
join learning.groups as learner_group on learner_group.id = assignment.group_id
left join lateral (
  select array_agg(topic.stable_key order by topic.stable_key) as topic_keys
  from learning.question_topics as question_topic
  join learning.topics as topic on topic.id = question_topic.topic_id
  where question_topic.question_id = question.id
) as topic_summary on true
left join lateral (
  select array_agg(skill.stable_key order by skill.stable_key) as skill_keys
  from learning.question_skills as question_skill
  join learning.skills as skill on skill.id = question_skill.skill_id
  where question_skill.question_id = question.id
) as skill_summary on true
where (select platform.current_staff_has_role('platform_admin'));

revoke all on admin_api.responses from public, anon, authenticated;
grant select on admin_api.responses to authenticated;

comment on view admin_api.responses is
  'Platform-admin question-level evidence, marks and teacher feedback for Results / Markbook review.';

update platform.contract_versions
set
  compatibility = jsonb_build_object(
    'previousVersion', '0.1.0',
    'mode', 'read-models-with-hub-registration-curriculum-publication-and-teacher-review'
  ),
  contract_document = jsonb_build_object(
    'schema', 'admin_api',
    'boundary', 'authenticated staff read models, hub registration, curriculum publication and teacher response review'
  )
where contract_key = 'admin-api'
  and version = '0.2.0'
  and status = 'draft';
