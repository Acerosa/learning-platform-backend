-- Staff cohort read and feedback-only review for timed knowledge reports.
-- Reads assignment membership the same way as hub learning results.
-- Does not select activity_states.state_payload and does not mark a report correct or scored.

create or replace function admin_api.list_knowledge_report_cohort(
  p_hub_code text,
  p_course_key text default null,
  p_group_code text default null,
  p_student_number text default null,
  p_activity_key text default null,
  p_completion_status text default null,
  p_minimum_met text default null,
  p_review_status text default null,
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  student_id uuid,
  student_number text,
  learner_name text,
  group_id uuid,
  group_code text,
  group_name text,
  course_key text,
  activity_id uuid,
  activity_key text,
  activity_version_id uuid,
  report_title text,
  assignment_id uuid,
  completion_status text,
  started_at timestamptz,
  duration_seconds integer,
  word_count integer,
  minimum_words integer,
  minimum_met boolean,
  elapsed_seconds integer,
  submission_method text,
  requires_review boolean,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  response_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  with visible as (
    select link.group_id
    from platform.hubs as hub
    join platform.hub_group_links as link
      on link.hub_id = hub.id
     and link.active
    join learning.groups as learner_group
      on learner_group.id = link.group_id
     and learner_group.active
    where hub.hub_code = nullif(btrim(p_hub_code), '')
      and hub.active
      and (
        platform.current_staff_has_role('platform_admin')
        or learning.teacher_can_access_group(link.group_id)
      )
      and (
        platform.current_staff_has_role('platform_admin')
        or exists (
          select 1
          from platform.hubs as readable_hub
          join platform.hub_group_links as readable_link
            on readable_link.hub_id = readable_hub.id
           and readable_link.active
          where readable_hub.hub_code = nullif(btrim(p_hub_code), '')
            and learning.teacher_can_access_group(readable_link.group_id)
        )
      )
  ),
  reports as (
    select
      activity.id as activity_id,
      activity.stable_key as activity_key,
      activity.title as report_title,
      version.id as activity_version_id,
      course.stable_key as course_key,
      (marking.spec ->> 'durationSeconds')::integer as duration_seconds,
      (marking.spec ->> 'minWords')::integer as minimum_words
    from learning.activities as activity
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.retired_at is null
    join learning.questions as question
      on question.activity_version_id = version.id
    join learning.question_marking as marking
      on marking.question_id = question.id
     and marking.spec ->> 'mode' = 'timed-knowledge-report'
    join learning.modules as module
      on module.id = activity.module_id
    join learning.courses as course
      on course.id = module.course_id
    join platform.hub_course_links as course_link
      on course_link.course_id = course.id
     and course_link.active
    join platform.hubs as hub
      on hub.id = course_link.hub_id
     and hub.hub_code = nullif(btrim(p_hub_code), '')
     and hub.active
  ),
  cohort as (
    select
      student.id as student_id,
      student.student_number,
      student.display_name as learner_name,
      learner_group.id as group_id,
      learner_group.code as group_code,
      learner_group.name as group_name,
      report.course_key,
      report.activity_id,
      report.activity_key,
      report.activity_version_id,
      report.report_title,
      assignment.id as assignment_id,
      case
        when attempt.status = 'completed' and response.requires_review is false then 'reviewed'
        when attempt.status = 'completed' then 'submitted'
        when sitting.started_at is not null
          and report.duration_seconds is not null
          and sitting.started_at + make_interval(secs => report.duration_seconds) <= pg_catalog.now()
          then 'time_elapsed'
        when sitting.student_id is not null
          or attempt.id is not null
          or coalesce(formative.formative_check_count, 0) > 0
          then 'in_progress'
        else 'not_started'
      end as completion_status,
      sitting.started_at,
      report.duration_seconds,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'wordCount')::integer
      end as word_count,
      report.minimum_words,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'minimumMet')::boolean
      end as minimum_met,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'elapsedSeconds')::integer
      end as elapsed_seconds,
      case
        when attempt.status = 'completed' then response.response_payload ->> 'submissionMethod'
      end as submission_method,
      case
        when attempt.status = 'completed' then response.requires_review
      end as requires_review,
      case
        when attempt.status = 'completed' then attempt.received_at
      end as submitted_at,
      case
        when attempt.status = 'completed' and response.requires_review is false then response.marked_at
      end as reviewed_at,
      case
        when attempt.status = 'completed' then response.id
      end as response_id
    from reports as report
    join learning.groups as learner_group
      on learner_group.active
    join visible
      on visible.group_id = learner_group.id
    join learning.enrolments as enrolment
      on enrolment.group_id = learner_group.id
     and enrolment.status = 'active'
    join learning.students as student
      on student.id = enrolment.student_id
     and student.active
    join learning.activity_assignments as assignment
      on assignment.id = learning.current_activity_assignment_id(learner_group.id, report.activity_id)
     and assignment.active
    left join learning.activity_states as sitting
      on sitting.assignment_id = assignment.id
     and sitting.student_id = student.id
     and sitting.activity_version_id = report.activity_version_id
    left join lateral (
      select attempt_row.*
      from learning.attempts as attempt_row
      where attempt_row.assignment_id = assignment.id
        and attempt_row.student_id = student.id
        and attempt_row.activity_version_id = report.activity_version_id
      order by attempt_row.received_at desc
      limit 1
    ) as attempt on true
    left join lateral (
      select response_row.*
      from learning.responses as response_row
      where response_row.attempt_id = attempt.id
      order by response_row.marked_at desc nulls last
      limit 1
    ) as response on true
    left join lateral (
      select count(*)::integer as formative_check_count
      from learning.formative_checks as formative_check
      where formative_check.assignment_id = assignment.id
        and formative_check.student_id = student.id
        and formative_check.activity_version_id = report.activity_version_id
    ) as formative on true
    where (p_course_key is null or report.course_key = p_course_key)
      and (p_group_code is null or learner_group.code = p_group_code)
      and (p_student_number is null or student.student_number = p_student_number)
      and (p_activity_key is null or report.activity_key = p_activity_key)
  )
  select
    cohort.student_id,
    cohort.student_number,
    cohort.learner_name,
    cohort.group_id,
    cohort.group_code,
    cohort.group_name,
    cohort.course_key,
    cohort.activity_id,
    cohort.activity_key,
    cohort.activity_version_id,
    cohort.report_title,
    cohort.assignment_id,
    cohort.completion_status,
    cohort.started_at,
    cohort.duration_seconds,
    cohort.word_count,
    cohort.minimum_words,
    cohort.minimum_met,
    cohort.elapsed_seconds,
    cohort.submission_method,
    cohort.requires_review,
    cohort.submitted_at,
    cohort.reviewed_at,
    cohort.response_id
  from cohort
  where (p_completion_status is null or cohort.completion_status = p_completion_status)
    and (
      p_minimum_met is null
      or (p_minimum_met = 'met' and cohort.minimum_met is true)
      or (p_minimum_met = 'not_reached' and cohort.minimum_met is false)
    )
    and (
      p_review_status is null
      or (p_review_status = 'needs_review' and cohort.requires_review is true)
      or (p_review_status = 'reviewed' and cohort.completion_status = 'reviewed')
    )
  order by cohort.learner_name, cohort.activity_key, cohort.student_number
  limit least(greatest(coalesce(p_limit, 500), 0), 1000)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

comment on function admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, integer, integer
) is
  'Assigned knowledge-report cohort for staff-visible hub groups. Returns sitting timing and submitted metadata only. Never returns draft state_payload or report text.';

revoke all on function admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, integer, integer
) from public, anon, authenticated;

grant execute on function admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, integer, integer
) to authenticated;

create or replace function admin_api.review_knowledge_report(
  p_response_id uuid,
  p_feedback_summary text,
  p_feedback_next_step text default null
)
returns table (
  response_id uuid,
  attempt_id uuid,
  is_correct boolean,
  requires_review boolean,
  marking_source text,
  feedback_summary text,
  feedback_next_step text,
  marked_at timestamptz,
  response_payload jsonb
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
  v_now timestamptz := timezone('utc', pg_catalog.now());
  v_before jsonb;
  v_mode text;
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

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_response_id::text, 0));

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

  select marking.spec ->> 'mode'
  into v_mode
  from learning.question_marking as marking
  where marking.question_id = v_response.question_id;

  if v_mode is distinct from 'timed-knowledge-report' then
    raise exception using errcode = '22023', message = 'REVIEW_NOT_KNOWLEDGE_REPORT';
  end if;

  v_feedback := nullif(btrim(coalesce(p_feedback_summary, '')), '');
  if v_feedback is null then
    raise exception using errcode = '22023', message = 'REVIEW_FEEDBACK_REQUIRED';
  end if;
  if pg_catalog.char_length(v_feedback) > 2000 then
    raise exception using errcode = '22023', message = 'REVIEW_FEEDBACK_TOO_LONG';
  end if;

  v_next_step := nullif(btrim(coalesce(p_feedback_next_step, '')), '');
  if v_next_step is not null and pg_catalog.char_length(v_next_step) > 500 then
    raise exception using errcode = '22023', message = 'REVIEW_NEXT_STEP_TOO_LONG';
  end if;

  v_before := pg_catalog.jsonb_build_object(
    'requiresReview', v_response.requires_review,
    'isCorrect', v_response.is_correct,
    'awardedScore', v_response.awarded_score,
    'responsePayload', v_response.response_payload,
    'feedbackSummary', v_response.feedback_summary,
    'markedAt', v_response.marked_at
  );

  perform pg_catalog.set_config('learning.allow_teacher_review', '1', true);

  update learning.responses as response
  set
    requires_review = false,
    marking_source = 'teacher',
    marked_at = v_now,
    feedback_summary = v_feedback,
    feedback_next_step = v_next_step
  where response.id = v_response.id
  returning response.* into v_response;

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
    pg_catalog.jsonb_build_object(
      'staffReference', v_teacher.staff_reference,
      'reviewMode', 'knowledge-report-feedback',
      'attemptId', v_attempt.id,
      'responseId', v_response.id,
      'questionId', v_response.question_id,
      'before', v_before,
      'after', pg_catalog.jsonb_build_object(
        'requiresReview', v_response.requires_review,
        'isCorrect', v_response.is_correct,
        'awardedScore', v_response.awarded_score,
        'feedbackSummary', v_response.feedback_summary,
        'markedAt', v_response.marked_at
      )
    )
  );

  return query
  select
    v_response.id,
    v_response.attempt_id,
    v_response.is_correct,
    v_response.requires_review,
    v_response.marking_source,
    v_response.feedback_summary,
    v_response.feedback_next_step,
    v_response.marked_at,
    v_response.response_payload;
end;
$$;

comment on function admin_api.review_knowledge_report(uuid, text, text) is
  'Feedback-only review for a submitted timed knowledge report. Leaves the frozen response payload, score and is_correct unchanged.';

revoke all on function admin_api.review_knowledge_report(uuid, text, text)
  from public, anon, authenticated;

grant execute on function admin_api.review_knowledge_report(uuid, text, text)
  to authenticated;
