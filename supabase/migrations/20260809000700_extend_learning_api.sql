alter table learning.attempts
  add column client_started_at timestamptz,
  add column client_completed_at timestamptz,
  add column source_page text,
  add column programming_language_id uuid
    references learning.coding_languages (id) on delete restrict;

alter table learning.attempts
  add constraint attempt_client_timestamps_valid check (
    (client_started_at is null and client_completed_at is null)
    or (
      client_started_at is not null
      and client_completed_at is not null
      and client_completed_at >= client_started_at
      and client_completed_at - client_started_at <= interval '30 days'
    )
  ),
  add constraint attempt_source_page_valid check (
    source_page is null
    or (
      length(source_page) between 1 and 300
      and source_page ~ '^/'
      and source_page !~ '[[:cntrl:]]'
    )
  );

create index attempts_programming_language_idx
  on learning.attempts (programming_language_id)
  where programming_language_id is not null;

drop view api.my_attempts;

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
  attempt.client_started_at,
  attempt.client_completed_at,
  attempt.source_page,
  coding_language.stable_key as programming_language,
  attempt.received_at,
  attempt.completed_at
from learning.attempts as attempt
join learning.activity_versions as activity_version
  on activity_version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
left join learning.coding_languages as coding_language
  on coding_language.id = attempt.programming_language_id
where attempt.student_id = (select learning.current_student_id());

create view api.my_activity_progress
with (security_invoker = true)
as
select
  activity.stable_key as activity_key,
  activity.title as activity_title,
  activity_version.version as activity_version,
  count(*) as attempt_count,
  (array_agg(attempt.score order by attempt.received_at, attempt.id))[1]
    as first_score,
  (array_agg(attempt.score order by attempt.received_at desc, attempt.id desc))[1]
    as latest_score,
  max(attempt.score) as best_score,
  (array_agg(attempt.score order by attempt.received_at desc, attempt.id desc))[1]
    - (array_agg(attempt.score order by attempt.received_at, attempt.id))[1]
    as improvement,
  attempt.max_score,
  min(attempt.received_at) as first_attempt_at,
  max(attempt.received_at) as latest_attempt_at
from learning.attempts as attempt
join learning.activity_versions as activity_version
  on activity_version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
where attempt.student_id = (select learning.current_student_id())
  and attempt.status = 'completed'
group by
  activity.id,
  activity.stable_key,
  activity.title,
  activity_version.id,
  activity_version.version,
  attempt.max_score;

create view api.teacher_group_activity_analytics
with (security_invoker = true)
as
with ranked_attempts as (
  select
    attempt.*,
    enrolment.group_id,
    row_number() over (
      partition by attempt.student_id, attempt.activity_version_id
      order by attempt.received_at desc, attempt.id desc
    ) as latest_rank
  from learning.attempts as attempt
  join learning.enrolments as enrolment on enrolment.id = attempt.enrolment_id
  where attempt.status = 'completed'
)
select
  learner_group.code as group_code,
  activity.stable_key as activity_key,
  activity.title as activity_title,
  activity_version.version as activity_version,
  count(*) as students_completed,
  round(avg(100 * ranked_attempts.score / ranked_attempts.max_score), 2)
    as latest_group_average_percentage,
  round(
    100 * count(*)::numeric
      / nullif((
        select count(*)
        from learning.enrolments as active_enrolment
        where active_enrolment.group_id = learner_group.id
          and active_enrolment.status = 'active'
      ), 0),
    2
  ) as completion_percentage
from ranked_attempts
join learning.groups as learner_group on learner_group.id = ranked_attempts.group_id
join learning.activity_versions as activity_version
  on activity_version.id = ranked_attempts.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
where ranked_attempts.latest_rank = 1
  and learning.current_teacher_id() is not null
group by
  learner_group.id,
  learner_group.code,
  activity.id,
  activity.stable_key,
  activity.title,
  activity_version.id,
  activity_version.version;

create view api.teacher_group_student_progress
with (security_invoker = true)
as
with assignment_counts as (
  select assignment.group_id, count(*) as assigned_activities
  from learning.activity_assignments as assignment
  where assignment.active
    and (assignment.opens_at is null or assignment.opens_at <= now())
    and (assignment.due_at is null or assignment.due_at >= now())
  group by assignment.group_id
),
latest_attempts as (
  select distinct on (attempt.student_id, attempt.activity_version_id)
    attempt.student_id,
    attempt.activity_version_id,
    attempt.score,
    attempt.max_score,
    attempt.received_at
  from learning.attempts as attempt
  where attempt.status = 'completed'
  order by
    attempt.student_id,
    attempt.activity_version_id,
    attempt.received_at desc,
    attempt.id desc
)
select
  learner_group.code as group_code,
  student.student_number,
  student.display_name,
  coalesce(assignment_counts.assigned_activities, 0) as assigned_activities,
  count(latest_attempts.activity_version_id) as completed_activities,
  case
    when coalesce(assignment_counts.assigned_activities, 0) = 0 then 0
    else round(
      100 * count(latest_attempts.activity_version_id)::numeric
        / assignment_counts.assigned_activities,
      2
    )
  end as completion_percentage,
  round(avg(100 * latest_attempts.score / latest_attempts.max_score), 2)
    as latest_average_percentage,
  (
    count(latest_attempts.activity_version_id) = 0
    or avg(100 * latest_attempts.score / latest_attempts.max_score) < 50
  ) as requires_support
from learning.enrolments as enrolment
join learning.students as student on student.id = enrolment.student_id
join learning.groups as learner_group on learner_group.id = enrolment.group_id
left join assignment_counts on assignment_counts.group_id = learner_group.id
left join latest_attempts on latest_attempts.student_id = student.id
where enrolment.status = 'active'
  and learning.current_teacher_id() is not null
group by
  learner_group.id,
  learner_group.code,
  student.id,
  student.student_number,
  student.display_name,
  assignment_counts.assigned_activities;

revoke all on
  api.my_attempts,
  api.my_activity_progress,
  api.teacher_group_activity_analytics,
  api.teacher_group_student_progress
from public, anon;

grant select on
  api.my_attempts,
  api.my_activity_progress,
  api.teacher_group_activity_analytics,
  api.teacher_group_student_progress
to authenticated;

drop function api.submit_attempt(text, text, text, jsonb);

create function api.submit_attempt(
  p_activity_key text,
  p_activity_version text,
  p_client_attempt_id text,
  p_responses jsonb,
  p_source_page text default null,
  p_started_at timestamptz default null,
  p_completed_at timestamptz default null,
  p_programming_language text default null
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
  client_started_at timestamptz,
  client_completed_at timestamptz,
  source_page text,
  programming_language text,
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
  v_programming_language_id uuid;
  v_declared_language_count integer;
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
  v_source_page text;
begin
  v_auth_user_id := auth.uid();
  v_received_at := clock_timestamp();
  v_source_page := nullif(btrim(p_source_page), '');

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

  if (p_started_at is null) <> (p_completed_at is null)
     or (
       p_started_at is not null
       and (
         p_completed_at < p_started_at
         or p_completed_at - p_started_at > interval '30 days'
         or p_started_at > v_received_at + interval '5 minutes'
         or p_completed_at > v_received_at + interval '5 minutes'
       )
     ) then
    raise exception using errcode = '22023', message = 'INVALID_CLIENT_TIMESTAMPS';
  end if;

  if v_source_page is not null
     and (
       length(v_source_page) > 300
       or v_source_page !~ '^/'
       or v_source_page ~ '[[:cntrl:]]'
     ) then
    raise exception using errcode = '22023', message = 'INVALID_SOURCE_PAGE';
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
        jsonb_build_object(
          'activity_key', p_activity_key,
          'activity_version', p_activity_version,
          'responses', p_responses,
          'source_page', v_source_page,
          'started_at', p_started_at,
          'completed_at', p_completed_at,
          'programming_language', p_programming_language
        )::text,
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
      attempt.client_started_at,
      attempt.client_completed_at,
      attempt.source_page,
      coding_language.stable_key,
      attempt.received_at,
      true
    from learning.attempts as attempt
    join learning.activity_versions as version
      on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    left join learning.coding_languages as coding_language
      on coding_language.id = attempt.programming_language_id
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

  select count(*)
  into v_declared_language_count
  from learning.activity_version_languages as version_language
  where version_language.activity_version_id = v_activity_version_id;

  if v_declared_language_count = 0 and p_programming_language is not null then
    raise exception using errcode = '22023', message = 'PROGRAMMING_LANGUAGE_NOT_APPLICABLE';
  end if;

  if v_declared_language_count > 0 then
    if p_programming_language is null or btrim(p_programming_language) = '' then
      raise exception using errcode = '22023', message = 'PROGRAMMING_LANGUAGE_REQUIRED';
    end if;

    select coding_language.id
    into v_programming_language_id
    from learning.activity_version_languages as version_language
    join learning.coding_languages as coding_language
      on coding_language.id = version_language.coding_language_id
     and coding_language.active
    where version_language.activity_version_id = v_activity_version_id
      and coding_language.stable_key = p_programming_language;

    if v_programming_language_id is null then
      raise exception using errcode = '22023', message = 'INVALID_PROGRAMMING_LANGUAGE';
    end if;
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
       or jsonb_typeof(v_item -> 'response_payload')
          not in ('string', 'array', 'object')
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'string'
         and btrim(v_item ->> 'response_payload') = ''
       )
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'array'
         and jsonb_array_length(v_item -> 'response_payload') = 0
       )
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'object'
         and v_item -> 'response_payload' = '{}'::jsonb
       )
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
    client_started_at,
    client_completed_at,
    source_page,
    programming_language_id,
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
    p_started_at,
    p_completed_at,
    v_source_page,
    v_programming_language_id,
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
      requires_review,
      marking_source,
      marked_at
    ) values (
      v_attempt_id,
      v_question.id,
      v_item -> 'response_payload',
      (v_item ->> 'awarded_score')::numeric(8,2),
      v_question.max_score,
      (v_item ->> 'is_correct')::boolean,
      not (v_item ->> 'is_correct')::boolean,
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
    attempt.client_started_at,
    attempt.client_completed_at,
    attempt.source_page,
    coding_language.stable_key,
    attempt.received_at,
    false
  from learning.attempts as attempt
  join learning.activity_versions as version
    on version.id = attempt.activity_version_id
  join learning.activities as activity on activity.id = version.activity_id
  left join learning.coding_languages as coding_language
    on coding_language.id = attempt.programming_language_id
  where attempt.id = v_attempt_id;
end;
$$;

revoke all on function api.submit_attempt(
  text,
  text,
  text,
  jsonb,
  text,
  timestamptz,
  timestamptz,
  text
)
from public, anon;

grant execute on function api.submit_attempt(
  text,
  text,
  text,
  jsonb,
  text,
  timestamptz,
  timestamptz,
  text
)
to authenticated;
