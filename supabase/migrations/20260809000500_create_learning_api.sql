create view api.my_profile
with (security_invoker = true)
as
select
  student.student_number,
  student.first_name,
  student.display_name
from learning.students as student
where student.id = (select learning.current_student_id());

create view api.my_enrolments
with (security_invoker = true)
as
select
  enrolment.id as enrolment_id,
  learner_group.code as group_code,
  learner_group.name as group_name,
  academic_year.code as academic_year,
  course.title as course_title,
  enrolment.joined_on,
  enrolment.left_on,
  enrolment.status
from learning.enrolments as enrolment
join learning.groups as learner_group on learner_group.id = enrolment.group_id
join learning.academic_years as academic_year
  on academic_year.id = learner_group.academic_year_id
join learning.courses as course on course.id = learner_group.course_id
where enrolment.student_id = (select learning.current_student_id());

create view api.my_assignments
with (security_invoker = true)
as
select
  assignment.id as assignment_id,
  activity.stable_key as activity_key,
  activity.title as activity_title,
  activity_version.version as activity_version,
  activity_version.max_score,
  assignment.opens_at,
  assignment.due_at,
  assignment.required
from learning.enrolments as enrolment
join learning.activity_assignments as assignment
  on assignment.group_id = enrolment.group_id
 and assignment.active
join learning.activity_versions as activity_version
  on activity_version.id = assignment.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
where enrolment.student_id = (select learning.current_student_id())
  and enrolment.status = 'active'
  and (assignment.opens_at is null or assignment.opens_at <= now())
  and (assignment.due_at is null or assignment.due_at >= now());

create view api.my_attempts
with (security_invoker = true)
as
select
  attempt.id as attempt_id,
  attempt.client_attempt_id,
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  attempt.attempt_number,
  attempt.status,
  attempt.score,
  attempt.max_score,
  attempt.marking_source,
  attempt.evidence_level,
  attempt.received_at,
  attempt.completed_at
from learning.attempts as attempt
join learning.activity_versions as activity_version
  on activity_version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
where attempt.student_id = (select learning.current_student_id());

create view api.my_responses
with (security_invoker = true)
as
select
  response.id as response_id,
  response.attempt_id,
  question.stable_key as question_key,
  question.section_key,
  response.response_payload,
  response.awarded_score,
  response.max_score,
  response.is_correct,
  response.marking_source,
  response.marked_at
from learning.responses as response
join learning.attempts as attempt on attempt.id = response.attempt_id
join learning.questions as question on question.id = response.question_id
where attempt.student_id = (select learning.current_student_id());

create view api.teacher_group_attempts
with (security_invoker = true)
as
select
  learner_group.code as group_code,
  student.student_number,
  student.display_name,
  attempt.id as attempt_id,
  attempt.client_attempt_id,
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  attempt.attempt_number,
  attempt.score,
  attempt.max_score,
  attempt.marking_source,
  attempt.evidence_level,
  attempt.received_at
from learning.attempts as attempt
join learning.students as student on student.id = attempt.student_id
join learning.enrolments as enrolment on enrolment.id = attempt.enrolment_id
join learning.groups as learner_group on learner_group.id = enrolment.group_id
join learning.activity_versions as activity_version
  on activity_version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
where learning.current_teacher_id() is not null;

create view api.teacher_group_learners
with (security_invoker = true)
as
select
  learner_group.code as group_code,
  learner_group.name as group_name,
  student.student_number,
  student.display_name,
  enrolment.id as enrolment_id,
  enrolment.joined_on,
  enrolment.left_on,
  enrolment.status
from learning.enrolments as enrolment
join learning.students as student on student.id = enrolment.student_id
join learning.groups as learner_group on learner_group.id = enrolment.group_id
where learning.current_teacher_id() is not null;

create view api.teacher_group_responses
with (security_invoker = true)
as
select
  learner_group.code as group_code,
  student.student_number,
  student.display_name,
  response.attempt_id,
  question.stable_key as question_key,
  question.section_key,
  response.response_payload,
  response.awarded_score,
  response.max_score,
  response.is_correct,
  response.marked_at
from learning.responses as response
join learning.attempts as attempt on attempt.id = response.attempt_id
join learning.students as student on student.id = attempt.student_id
join learning.enrolments as enrolment on enrolment.id = attempt.enrolment_id
join learning.groups as learner_group on learner_group.id = enrolment.group_id
join learning.questions as question on question.id = response.question_id
where learning.current_teacher_id() is not null;

create view api.teacher_group_topic_analytics
with (security_invoker = true)
as
select
  learner_group.code as group_code,
  topic.stable_key as topic_key,
  topic.title as topic_title,
  count(distinct attempt.student_id) as students_contributing,
  count(*) as response_count,
  round(
    100 * sum(response.awarded_score * question_topic.weight)
      / nullif(sum(response.max_score * question_topic.weight), 0),
    2
  ) as average_percentage
from learning.responses as response
join learning.attempts as attempt on attempt.id = response.attempt_id
join learning.enrolments as enrolment on enrolment.id = attempt.enrolment_id
join learning.groups as learner_group on learner_group.id = enrolment.group_id
join learning.question_topics as question_topic
  on question_topic.question_id = response.question_id
join learning.topics as topic on topic.id = question_topic.topic_id
where attempt.status = 'completed'
  and learning.current_teacher_id() is not null
group by learner_group.id, learner_group.code, topic.id, topic.stable_key, topic.title;

create view api.teacher_group_question_analytics
with (security_invoker = true)
as
select
  learner_group.code as group_code,
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  question.stable_key as question_key,
  question.analytics_title,
  count(*) as response_count,
  round(100 * avg((response.is_correct)::integer), 2) as success_rate
from learning.responses as response
join learning.attempts as attempt on attempt.id = response.attempt_id
join learning.enrolments as enrolment on enrolment.id = attempt.enrolment_id
join learning.groups as learner_group on learner_group.id = enrolment.group_id
join learning.questions as question on question.id = response.question_id
join learning.activity_versions as activity_version
  on activity_version.id = question.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
where attempt.status = 'completed'
  and response.is_correct is not null
  and learning.current_teacher_id() is not null
group by
  learner_group.id,
  learner_group.code,
  activity.id,
  activity.stable_key,
  activity_version.id,
  activity_version.version,
  question.id,
  question.stable_key,
  question.analytics_title;

revoke all on
  api.my_profile,
  api.my_enrolments,
  api.my_assignments,
  api.my_attempts,
  api.my_responses,
  api.teacher_group_learners,
  api.teacher_group_attempts,
  api.teacher_group_responses,
  api.teacher_group_topic_analytics,
  api.teacher_group_question_analytics
from public, anon;

grant select on
  api.my_profile,
  api.my_enrolments,
  api.my_assignments,
  api.my_attempts,
  api.my_responses,
  api.teacher_group_learners,
  api.teacher_group_attempts,
  api.teacher_group_responses,
  api.teacher_group_topic_analytics,
  api.teacher_group_question_analytics
to authenticated;

create function api.submit_attempt(
  p_activity_key text,
  p_activity_version text,
  p_client_attempt_id text,
  p_responses jsonb
)
returns table (
  attempt_id uuid,
  client_attempt_id text,
  activity_key text,
  activity_version text,
  attempt_number integer,
  score numeric(8,2),
  max_score numeric(8,2),
  marking_source text,
  evidence_level text,
  received_at timestamptz,
  idempotent boolean
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_student_id uuid;
  v_enrolment_id uuid;
  v_group_id uuid;
  v_active_enrolment_count integer;
  v_activity_version_id uuid;
  v_assignment_id uuid;
  v_question_count integer;
  v_activity_max_score numeric(8,2);
  v_attempt_id uuid;
  v_attempt_number integer;
  v_submission_hash text;
  v_existing learning.attempts%rowtype;
  v_item jsonb;
  v_question learning.questions%rowtype;
  v_question_key text;
  v_awarded_score numeric(8,2);
  v_is_correct boolean;
  v_total_score numeric(8,2) := 0;
  v_received_at timestamptz;
begin
  v_auth_user_id := auth.uid();

  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if p_activity_key is null or btrim(p_activity_key) = ''
     or p_activity_version is null or btrim(p_activity_version) = '' then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_VERSION';
  end if;

  if p_client_attempt_id is null
     or length(p_client_attempt_id) not between 1 and 128
     or p_client_attempt_id !~ '^[A-Za-z0-9._:-]+$' then
    raise exception using errcode = '22023', message = 'INVALID_CLIENT_ATTEMPT_ID';
  end if;

  if p_responses is null
     or jsonb_typeof(p_responses) <> 'array'
     or jsonb_array_length(p_responses) = 0
     or octet_length(p_responses::text) > 131072 then
    raise exception using errcode = '22023', message = 'INVALID_RESPONSES';
  end if;

  select student.id
  into v_student_id
  from learning.students as student
  where student.auth_user_id = v_auth_user_id
    and student.active;

  if v_student_id is null then
    raise exception using errcode = '28000', message = 'STUDENT_IDENTITY_NOT_FOUND';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_student_id::text, 0)
  );

  v_submission_hash := encode(
    extensions.digest(
      pg_catalog.convert_to(
        p_activity_key || chr(31) || p_activity_version || chr(31) || p_responses::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select attempt.*
  into v_existing
  from learning.attempts as attempt
  where attempt.student_id = v_student_id
    and attempt.client_attempt_id = p_client_attempt_id;

  if found then
    if v_existing.submission_hash <> v_submission_hash then
      raise exception using errcode = '23505', message = 'CLIENT_ATTEMPT_ID_CONFLICT';
    end if;

    return query
    select
      attempt.id,
      attempt.client_attempt_id,
      activity.stable_key,
      version.version,
      attempt.attempt_number,
      attempt.score,
      attempt.max_score,
      attempt.marking_source,
      attempt.evidence_level,
      attempt.received_at,
      true
    from learning.attempts as attempt
    join learning.activity_versions as version
      on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where attempt.id = v_existing.id;
    return;
  end if;

  select count(*)
  into v_active_enrolment_count
  from learning.enrolments as enrolment
  join learning.groups as learner_group
    on learner_group.id = enrolment.group_id
   and learner_group.active
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  if v_active_enrolment_count <> 1 then
    raise exception using errcode = '23514', message = 'ACTIVE_ENROLMENT_NOT_UNIQUE';
  end if;

  select enrolment.id, enrolment.group_id
  into v_enrolment_id, v_group_id
  from learning.enrolments as enrolment
  join learning.groups as learner_group
    on learner_group.id = enrolment.group_id
   and learner_group.active
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  select version.id, version.question_count, version.max_score
  into v_activity_version_id, v_question_count, v_activity_max_score
  from learning.activity_versions as version
  join learning.activities as activity on activity.id = version.activity_id
  where activity.stable_key = p_activity_key
    and activity.active
    and version.version = p_activity_version
    and version.published_at is not null
    and version.retired_at is null;

  if v_activity_version_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_VERSION';
  end if;

  select assignment.id
  into v_assignment_id
  from learning.activity_assignments as assignment
  where assignment.group_id = v_group_id
    and assignment.activity_version_id = v_activity_version_id
    and assignment.active
    and (assignment.opens_at is null or assignment.opens_at <= clock_timestamp())
    and (assignment.due_at is null or assignment.due_at >= clock_timestamp());

  if v_assignment_id is null then
    raise exception using errcode = '42501', message = 'ACTIVITY_NOT_ASSIGNED';
  end if;

  if jsonb_array_length(p_responses) <> v_question_count then
    raise exception using errcode = '22023', message = 'INCOMPLETE_RESPONSE_SET';
  end if;

  if (
    select count(distinct item ->> 'question_id')
    from jsonb_array_elements(p_responses) as response_item(item)
  ) <> v_question_count then
    raise exception using errcode = '22023', message = 'DUPLICATE_OR_MISSING_QUESTION';
  end if;

  for v_item in select value from jsonb_array_elements(p_responses)
  loop
    if jsonb_typeof(v_item) <> 'object'
       or jsonb_typeof(v_item -> 'question_id') <> 'string'
       or not (v_item ? 'response_payload')
       or v_item -> 'response_payload' = 'null'::jsonb
       or jsonb_typeof(v_item -> 'response_payload') <> 'string'
       or btrim(v_item ->> 'response_payload') = ''
       or jsonb_typeof(v_item -> 'awarded_score') <> 'number'
       or jsonb_typeof(v_item -> 'is_correct') <> 'boolean'
       or octet_length((v_item -> 'response_payload')::text) > 4096 then
      raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
    end if;

    v_question_key := v_item ->> 'question_id';

    select question.*
    into v_question
    from learning.questions as question
    where question.activity_version_id = v_activity_version_id
      and question.stable_key = v_question_key;

    if not found then
      if exists (
        select 1 from learning.questions as other_question
        where other_question.stable_key = v_question_key
      ) then
        raise exception using
          errcode = '23514',
          message = 'QUESTION_WRONG_ACTIVITY_VERSION';
      end if;
      raise exception using errcode = '22023', message = 'UNKNOWN_QUESTION';
    end if;

    begin
      v_awarded_score := (v_item ->> 'awarded_score')::numeric(8,2);
      v_is_correct := (v_item ->> 'is_correct')::boolean;
    exception when others then
      raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
    end;

    if v_awarded_score < 0 or v_awarded_score > v_question.max_score then
      raise exception using errcode = '23514', message = 'INVALID_RESPONSE_SCORE';
    end if;

    if (v_is_correct and v_awarded_score <> v_question.max_score)
       or (not v_is_correct and v_awarded_score <> 0) then
      raise exception using errcode = '23514', message = 'INCONSISTENT_CLIENT_MARK';
    end if;

    v_total_score := v_total_score + v_awarded_score;
  end loop;

  if v_total_score > v_activity_max_score then
    raise exception using
      errcode = '23514',
      message = 'ATTEMPT_SCORE_EXCEEDS_ACTIVITY_MAXIMUM';
  end if;

  select coalesce(max(attempt.attempt_number), 0) + 1
  into v_attempt_number
  from learning.attempts as attempt
  where attempt.student_id = v_student_id
    and attempt.assignment_id = v_assignment_id;

  v_attempt_id := gen_random_uuid();
  v_received_at := clock_timestamp();

  insert into learning.attempts (
    id,
    client_attempt_id,
    student_id,
    enrolment_id,
    assignment_id,
    activity_version_id,
    attempt_number,
    status,
    score,
    max_score,
    marking_source,
    evidence_level,
    source_system,
    submission_hash,
    received_at,
    completed_at
  ) values (
    v_attempt_id,
    p_client_attempt_id,
    v_student_id,
    v_enrolment_id,
    v_assignment_id,
    v_activity_version_id,
    v_attempt_number,
    'completed',
    v_total_score,
    v_activity_max_score,
    'client',
    'question_level',
    'supabase',
    v_submission_hash,
    v_received_at,
    v_received_at
  );

  for v_item in select value from jsonb_array_elements(p_responses)
  loop
    select question.*
    into strict v_question
    from learning.questions as question
    where question.activity_version_id = v_activity_version_id
      and question.stable_key = v_item ->> 'question_id';

    insert into learning.responses (
      attempt_id,
      question_id,
      response_payload,
      awarded_score,
      max_score,
      is_correct,
      marking_source,
      marked_at
    ) values (
      v_attempt_id,
      v_question.id,
      v_item -> 'response_payload',
      (v_item ->> 'awarded_score')::numeric(8,2),
      v_question.max_score,
      (v_item ->> 'is_correct')::boolean,
      'client',
      v_received_at
    );
  end loop;

  return query
  select
    attempt.id,
    attempt.client_attempt_id,
    activity.stable_key,
    version.version,
    attempt.attempt_number,
    attempt.score,
    attempt.max_score,
    attempt.marking_source,
    attempt.evidence_level,
    attempt.received_at,
    false
  from learning.attempts as attempt
  join learning.activity_versions as version
    on version.id = attempt.activity_version_id
  join learning.activities as activity on activity.id = version.activity_id
  where attempt.id = v_attempt_id;
end;
$$;

revoke all on function api.submit_attempt(text, text, text, jsonb)
from public, anon;

grant execute on function api.submit_attempt(text, text, text, jsonb)
to authenticated;
