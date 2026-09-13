-- Shared staff hub-learning Results contract.
-- Additive: no new persistence tables, no copies of attempts/responses,
-- no answer-key exposure, no learner_id arguments from the browser.
--
-- Hub isolation uses platform.hub_group_links, not hub_course_links.
-- Unit 3, Unit 14 and Readiness share ocr-level-3-it; course links alone
-- would mix hubs. Current membership is active enrolments with left_on null.
-- Current work uses learning.current_activity_assignment_id.
--
-- Official assignment scores come only from completed attempts.
-- Formative checks and activity_states contribute completion/progress only.

create or replace function learning.staff_can_read_hub_results(p_hub_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    platform.current_staff_has_role('platform_admin')
    or exists (
      select 1
      from platform.hubs as hub
      join platform.hub_group_links as link
        on link.hub_id = hub.id
       and link.active
      where hub.hub_code = nullif(btrim(p_hub_code), '')
        and learning.teacher_can_access_group(link.group_id)
    );
$$;

comment on function learning.staff_can_read_hub_results(text) is
  'True when the caller is platform_admin or a teacher with access to a group bound to the hub.';

revoke all on function learning.staff_can_read_hub_results(text)
  from public, anon, authenticated;

create or replace function learning.staff_visible_hub_group_ids(p_hub_code text)
returns table (group_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
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
    );
$$;

comment on function learning.staff_visible_hub_group_ids(text) is
  'Active hub-bound teaching groups the caller may report on.';

revoke all on function learning.staff_visible_hub_group_ids(text)
  from public, anon, authenticated;

create or replace function admin_api.list_hub_learning_result_filters(
  p_hub_code text
)
returns table (
  course_key text,
  course_title text,
  group_code text,
  group_name text,
  student_number text,
  display_name text,
  week_number integer,
  week_title text,
  session_number integer,
  activity_key text,
  activity_title text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_hub_code is null or btrim(p_hub_code) = '' then
    raise exception 'HUB_CODE_REQUIRED';
  end if;

  if not learning.staff_can_read_hub_results(p_hub_code) then
    return;
  end if;

  return query
  select distinct
    course.stable_key,
    course.title,
    learner_group.code,
    learner_group.name,
    student.student_number,
    student.display_name,
    delivery.week_number,
    week.title,
    delivery.session_number,
    activity.stable_key,
    activity.title
  from learning.staff_visible_hub_group_ids(p_hub_code) as visible
  join learning.groups as learner_group
    on learner_group.id = visible.group_id
  join learning.courses as course
    on course.id = learner_group.course_id
  join learning.enrolments as enrolment
    on enrolment.group_id = learner_group.id
   and enrolment.status = 'active'
   and enrolment.left_on is null
  join learning.students as student
    on student.id = enrolment.student_id
   and student.active
  join learning.activity_assignments as assignment
    on assignment.group_id = learner_group.id
   and assignment.active
  join learning.activity_versions as activity_version
    on activity_version.id = assignment.activity_version_id
  join learning.activities as activity
    on activity.id = activity_version.activity_id
   and assignment.id = learning.current_activity_assignment_id(
     learner_group.id,
     activity.id
   )
  left join lateral (
    select
      delivery_row.week_number,
      delivery_row.session_number,
      delivery_row.curriculum_week_id
    from learning.activity_delivery as delivery_row
    where delivery_row.activity_version_id = activity_version.id
      and delivery_row.active
      and (
        delivery_row.group_id = learner_group.id
        or delivery_row.group_id is null
      )
    order by
      delivery_row.group_id nulls last,
      delivery_row.sort_order,
      delivery_row.id
    limit 1
  ) as delivery on true
  left join learning.curriculum_weeks as week
    on week.id = delivery.curriculum_week_id
  order by
    course.stable_key,
    learner_group.code,
    student.student_number,
    delivery.week_number nulls last,
    delivery.session_number nulls last,
    activity.stable_key;
end;
$$;

comment on function admin_api.list_hub_learning_result_filters(text) is
  'Cascaded filter options for one hub. Staff-only. No payloads or answer keys.';

revoke all on function admin_api.list_hub_learning_result_filters(text)
  from public, anon;
grant execute on function admin_api.list_hub_learning_result_filters(text)
  to authenticated;

create or replace function admin_api.list_hub_learning_results(
  p_hub_code text,
  p_course_key text default null,
  p_group_code text default null,
  p_student_number text default null,
  p_week_number integer default null,
  p_session_number integer default null,
  p_activity_key text default null,
  p_completion_status text default null,
  p_limit integer default 500
)
returns table (
  hub_code text,
  course_key text,
  course_title text,
  group_code text,
  group_name text,
  student_number text,
  display_name text,
  assignment_id uuid,
  activity_key text,
  activity_title text,
  activity_version text,
  week_number integer,
  week_title text,
  session_number integer,
  completion_status text,
  result_source text,
  scored boolean,
  attempt_id uuid,
  attempt_status text,
  score numeric,
  max_score numeric,
  score_percentage numeric,
  correct_count bigint,
  incorrect_count bigint,
  attempt_count bigint,
  formative_check_count bigint,
  last_activity_at timestamptz,
  completed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limit integer;
  v_status text;
begin
  if p_hub_code is null or btrim(p_hub_code) = '' then
    raise exception 'HUB_CODE_REQUIRED';
  end if;

  if not learning.staff_can_read_hub_results(p_hub_code) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 500), 1), 1000);
  v_status := nullif(btrim(coalesce(p_completion_status, '')), '');

  return query
  with scoped as (
    select
      hub.hub_code as hub_code,
      course.stable_key as course_key,
      course.title as course_title,
      learner_group.code as group_code,
      learner_group.name as group_name,
      student.student_number as student_number,
      student.display_name as display_name,
      assignment.id as assignment_id,
      student.id as student_id,
      activity.stable_key as activity_key,
      activity.title as activity_title,
      activity_version.version as activity_version,
      delivery.week_number as week_number,
      week.title as week_title,
      delivery.session_number as session_number,
      latest_attempt.id as attempt_id,
      latest_attempt.status as attempt_status,
      latest_attempt.score as attempt_score,
      latest_attempt.max_score as attempt_max_score,
      latest_attempt.completed_at as attempt_completed_at,
      latest_attempt.received_at as attempt_received_at,
      coalesce(attempt_counts.attempt_count, 0) as attempt_count,
      coalesce(formative_counts.formative_check_count, 0) as formative_check_count,
      state.status as state_status,
      state.updated_at as state_updated_at,
      state.completed_at as state_completed_at,
      response_marks.correct_count,
      response_marks.incorrect_count
    from learning.staff_visible_hub_group_ids(p_hub_code) as visible
    join platform.hubs as hub
      on hub.hub_code = btrim(p_hub_code)
    join learning.groups as learner_group
      on learner_group.id = visible.group_id
    join learning.courses as course
      on course.id = learner_group.course_id
    join learning.enrolments as enrolment
      on enrolment.group_id = learner_group.id
     and enrolment.status = 'active'
     and enrolment.left_on is null
    join learning.students as student
      on student.id = enrolment.student_id
     and student.active
    join learning.activity_assignments as assignment
      on assignment.group_id = learner_group.id
     and assignment.active
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
     and assignment.id = learning.current_activity_assignment_id(
       learner_group.id,
       activity.id
     )
    left join lateral (
      select
        delivery_row.week_number,
        delivery_row.session_number,
        delivery_row.curriculum_week_id
      from learning.activity_delivery as delivery_row
      where delivery_row.activity_version_id = activity_version.id
        and delivery_row.active
        and (
          delivery_row.group_id = learner_group.id
          or delivery_row.group_id is null
        )
      order by
        delivery_row.group_id nulls last,
        delivery_row.sort_order,
        delivery_row.id
      limit 1
    ) as delivery on true
    left join learning.curriculum_weeks as week
      on week.id = delivery.curriculum_week_id
    left join lateral (
      select attempt.*
      from learning.attempts as attempt
      where attempt.student_id = student.id
        and attempt.assignment_id = assignment.id
      order by
        (attempt.status = 'completed') desc,
        attempt.completed_at desc nulls last,
        attempt.attempt_number desc,
        attempt.received_at desc
      limit 1
    ) as latest_attempt on true
    left join lateral (
      select count(*) as attempt_count
      from learning.attempts as attempt
      where attempt.student_id = student.id
        and attempt.assignment_id = assignment.id
    ) as attempt_counts on true
    left join lateral (
      select count(*) as formative_check_count
      from learning.formative_checks as formative
      where formative.student_id = student.id
        and formative.assignment_id = assignment.id
    ) as formative_counts on true
    left join lateral (
      select state_row.status, state_row.updated_at, state_row.completed_at
      from learning.activity_states as state_row
      where state_row.student_id = student.id
        and state_row.assignment_id = assignment.id
      order by state_row.updated_at desc, state_row.id desc
      limit 1
    ) as state on true
    left join lateral (
      select
        count(*) filter (where response.is_correct is true) as correct_count,
        count(*) filter (where response.is_correct is false) as incorrect_count
      from learning.responses as response
      where response.attempt_id = latest_attempt.id
        and latest_attempt.status = 'completed'
    ) as response_marks on true
    where (p_course_key is null or course.stable_key = p_course_key)
      and (p_group_code is null or learner_group.code = p_group_code)
      and (p_student_number is null or student.student_number = p_student_number)
      and (p_week_number is null or delivery.week_number = p_week_number)
      and (p_session_number is null or delivery.session_number = p_session_number)
      and (p_activity_key is null or activity.stable_key = p_activity_key)
  )
  select
    scoped.hub_code,
    scoped.course_key,
    scoped.course_title,
    scoped.group_code,
    scoped.group_name,
    scoped.student_number,
    scoped.display_name,
    scoped.assignment_id,
    scoped.activity_key,
    scoped.activity_title,
    scoped.activity_version,
    scoped.week_number,
    scoped.week_title,
    scoped.session_number,
    case
      when scoped.attempt_status = 'completed' then 'completed'
      when scoped.attempt_id is not null
        or scoped.formative_check_count > 0
        or scoped.state_status is not null then 'in_progress'
      else 'not_started'
    end as completion_status,
    case
      when scoped.attempt_status = 'completed' then 'official_attempt'
      when scoped.attempt_id is not null then 'official_attempt'
      when scoped.formative_check_count > 0 then 'formative'
      when scoped.state_status is not null then 'activity_state'
      else 'none'
    end as result_source,
    (
      scoped.attempt_status = 'completed'
      and scoped.attempt_max_score is not null
      and scoped.attempt_max_score > 0
    ) as scored,
    scoped.attempt_id,
    scoped.attempt_status,
    case
      when scoped.attempt_status = 'completed'
        and scoped.attempt_max_score is not null
        and scoped.attempt_max_score > 0
      then scoped.attempt_score
      else null
    end as score,
    case
      when scoped.attempt_status = 'completed'
        and scoped.attempt_max_score is not null
        and scoped.attempt_max_score > 0
      then scoped.attempt_max_score
      else null
    end as max_score,
    case
      when scoped.attempt_status = 'completed'
        and scoped.attempt_max_score is not null
        and scoped.attempt_max_score > 0
      then round((scoped.attempt_score / scoped.attempt_max_score) * 100, 2)
      else null
    end as score_percentage,
    case
      when scoped.attempt_status = 'completed' then scoped.correct_count
      else null
    end as correct_count,
    case
      when scoped.attempt_status = 'completed' then scoped.incorrect_count
      else null
    end as incorrect_count,
    scoped.attempt_count,
    scoped.formative_check_count,
    greatest(
      scoped.attempt_completed_at,
      scoped.attempt_received_at,
      scoped.state_updated_at,
      scoped.state_completed_at
    ) as last_activity_at,
    case
      when scoped.attempt_status = 'completed' then scoped.attempt_completed_at
      else null
    end as completed_at
  from scoped
  where (
    v_status is null
    or case
      when scoped.attempt_status = 'completed' then 'completed'
      when scoped.attempt_id is not null
        or scoped.formative_check_count > 0
        or scoped.state_status is not null then 'in_progress'
      else 'not_started'
    end = v_status
  )
  order by
    scoped.group_code,
    scoped.display_name,
    scoped.week_number nulls last,
    scoped.activity_key
  limit v_limit;
end;
$$;

comment on function admin_api.list_hub_learning_results(text, text, text, text, integer, integer, text, text, integer) is
  'Staff hub-learning result rows. Hub isolation via hub_group_links. Scores only from completed official attempts. No answer keys.';

revoke all on function admin_api.list_hub_learning_results(text, text, text, text, integer, integer, text, text, integer)
  from public, anon;
grant execute on function admin_api.list_hub_learning_results(text, text, text, text, integer, integer, text, text, integer)
  to authenticated;

create or replace function admin_api.summarise_hub_learning_results(
  p_hub_code text,
  p_course_key text default null,
  p_group_code text default null,
  p_student_number text default null,
  p_week_number integer default null,
  p_session_number integer default null,
  p_activity_key text default null,
  p_completion_status text default null
)
returns table (
  learner_count bigint,
  activity_count bigint,
  row_count bigint,
  started_count bigint,
  completed_count bigint,
  in_progress_count bigint,
  not_started_count bigint,
  scored_completed_count bigint,
  average_score_percentage numeric,
  completion_percentage numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_hub_code is null or btrim(p_hub_code) = '' then
    raise exception 'HUB_CODE_REQUIRED';
  end if;

  if not learning.staff_can_read_hub_results(p_hub_code) then
    return query
    select 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint, null::numeric, null::numeric;
    return;
  end if;

  return query
  select
    count(distinct row.student_number)::bigint,
    count(distinct row.activity_key)::bigint,
    count(*)::bigint,
    count(*) filter (where row.completion_status <> 'not_started')::bigint,
    count(*) filter (where row.completion_status = 'completed')::bigint,
    count(*) filter (where row.completion_status = 'in_progress')::bigint,
    count(*) filter (where row.completion_status = 'not_started')::bigint,
    count(*) filter (where row.scored)::bigint,
    round(avg(row.score_percentage) filter (where row.scored), 2),
    case
      when count(*) = 0 then null
      else round(
        (count(*) filter (where row.completion_status = 'completed')::numeric / count(*)::numeric) * 100,
        2
      )
    end
  from admin_api.list_hub_learning_results(
    p_hub_code,
    p_course_key,
    p_group_code,
    p_student_number,
    p_week_number,
    p_session_number,
    p_activity_key,
    p_completion_status,
    1000
  ) as row;
end;
$$;

comment on function admin_api.summarise_hub_learning_results(text, text, text, text, integer, integer, text, text) is
  'Server-side hub result aggregates. Average score uses only genuinely scored completed attempts.';

revoke all on function admin_api.summarise_hub_learning_results(text, text, text, text, integer, integer, text, text)
  from public, anon;
grant execute on function admin_api.summarise_hub_learning_results(text, text, text, text, integer, integer, text, text)
  to authenticated;

create or replace function admin_api.list_hub_learning_result_evidence(
  p_hub_code text,
  p_student_number text,
  p_assignment_id uuid
)
returns table (
  source text,
  question_key text,
  question_type text,
  response_payload jsonb,
  is_correct boolean,
  awarded_score numeric,
  max_score numeric,
  feedback_summary text,
  feedback_next_step text,
  recorded_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
  v_assignment_id uuid;
  v_group_id uuid;
begin
  if p_hub_code is null or btrim(p_hub_code) = '' then
    raise exception 'HUB_CODE_REQUIRED';
  end if;
  if p_student_number is null or btrim(p_student_number) = '' then
    raise exception 'STUDENT_NUMBER_REQUIRED';
  end if;
  if p_assignment_id is null then
    raise exception 'ASSIGNMENT_ID_REQUIRED';
  end if;

  if not learning.staff_can_read_hub_results(p_hub_code) then
    return;
  end if;

  select student.id
  into v_student_id
  from learning.students as student
  where student.student_number = btrim(p_student_number)
    and student.active;

  if v_student_id is null then
    return;
  end if;

  select assignment.id, assignment.group_id
  into v_assignment_id, v_group_id
  from learning.activity_assignments as assignment
  join learning.staff_visible_hub_group_ids(p_hub_code) as visible
    on visible.group_id = assignment.group_id
  where assignment.id = p_assignment_id;

  if v_assignment_id is null then
    return;
  end if;

  if not exists (
    select 1
    from learning.enrolments as enrolment
    where enrolment.student_id = v_student_id
      and enrolment.group_id = v_group_id
      and enrolment.status = 'active'
      and enrolment.left_on is null
  ) then
    return;
  end if;

  return query
  select
    'attempt'::text,
    question.stable_key,
    question.question_type,
    response.response_payload,
    response.is_correct,
    response.awarded_score,
    response.max_score,
    response.feedback_summary,
    response.feedback_next_step,
    response.marked_at
  from learning.attempts as attempt
  join learning.responses as response
    on response.attempt_id = attempt.id
  join learning.questions as question
    on question.id = response.question_id
  where attempt.student_id = v_student_id
    and attempt.assignment_id = v_assignment_id
    and attempt.id = (
      select latest.id
      from learning.attempts as latest
      where latest.student_id = v_student_id
        and latest.assignment_id = v_assignment_id
      order by
        (latest.status = 'completed') desc,
        latest.completed_at desc nulls last,
        latest.attempt_number desc
      limit 1
    )
  union all
  select
    'formative'::text,
    question.stable_key,
    question.question_type,
    formative.response_payload,
    formative.is_correct,
    formative.awarded_score,
    formative.max_score,
    null::text,
    null::text,
    formative.created_at
  from learning.formative_checks as formative
  join learning.questions as question
    on question.id = formative.question_id
  where formative.student_id = v_student_id
    and formative.assignment_id = v_assignment_id
    and not exists (
      select 1
      from learning.attempts as attempt
      where attempt.student_id = v_student_id
        and attempt.assignment_id = v_assignment_id
        and attempt.status = 'completed'
    )
    and formative.id = (
      select latest.id
      from learning.formative_checks as latest
      where latest.student_id = v_student_id
        and latest.assignment_id = v_assignment_id
        and latest.question_id = formative.question_id
      order by latest.check_number desc, latest.created_at desc
      limit 1
    )
  order by 2, 1;
end;
$$;

comment on function admin_api.list_hub_learning_result_evidence(text, text, uuid) is
  'Staff drill-down of learner evidence for one current assignment. Resolves the learner by student_number. Does not return marking specs or answer keys.';

revoke all on function admin_api.list_hub_learning_result_evidence(text, text, uuid)
  from public, anon;
grant execute on function admin_api.list_hub_learning_result_evidence(text, text, uuid)
  to authenticated;
