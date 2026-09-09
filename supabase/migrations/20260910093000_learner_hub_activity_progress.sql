-- Phase 1A: additive learner-facing hub-scoped progress read API.
-- Completed official attempts only. Does not change submit/mark/draft writers.
-- Does not expose formative_checks, activity_states, or response_payload.

create function api.my_hub_activity_progress(p_hub_code text)
returns table (
  hub_code text,
  activity_key text,
  activity_title text,
  activity_version text,
  week_key text,
  week_number integer,
  session_number integer,
  attempt_count bigint,
  first_score numeric,
  latest_score numeric,
  best_score numeric,
  max_score numeric,
  first_percentage numeric,
  latest_percentage numeric,
  best_percentage numeric,
  improvement numeric,
  improvement_percentage_points numeric,
  completed boolean,
  first_attempt_at timestamptz,
  latest_attempt_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid;
  v_hub_code text;
  v_hub_id uuid;
  v_student_id uuid;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;

  if not exists (
    select 1
    from auth.users as auth_user
    where auth_user.id = v_auth_user_id
      and auth_user.email is not null
      and auth_user.email_confirmed_at is not null
  ) then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;

  v_hub_code := nullif(btrim(p_hub_code), '');
  if v_hub_code is null
     or v_hub_code !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     or length(v_hub_code) > 80 then
    raise exception using errcode = '22023', message = 'INVALID_HUB_CODE';
  end if;

  select hub.id
  into v_hub_id
  from platform.hubs as hub
  where hub.hub_code = v_hub_code
    and hub.active;

  if v_hub_id is null then
    raise exception using errcode = '22023', message = 'HUB_UNKNOWN';
  end if;

  v_student_id := learning.current_student_id();
  if v_student_id is null then
    return;
  end if;

  return query
  with hub_assignments as (
    select
      v_hub_code as hub_code,
      activity.stable_key as activity_key,
      activity.title as activity_title,
      activity_version.version as activity_version,
      activity_version.id as activity_version_id,
      activity_version.max_score as version_max_score,
      assignment.id as assignment_id,
      enrolment.group_id as group_id
    from learning.enrolments as enrolment
    join learning.hub_access_bound_groups(v_hub_id) as bound
      on bound.group_id = enrolment.group_id
    join learning.activity_assignments as assignment
      on assignment.group_id = enrolment.group_id
     and assignment.active
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where enrolment.student_id = v_student_id
      and enrolment.status = 'active'
      and (assignment.opens_at is null or assignment.opens_at <= clock_timestamp())
      and (assignment.due_at is null or assignment.due_at >= clock_timestamp())
  ),
  attempt_progress as (
    select
      hub_assignment.assignment_id,
      count(*)::bigint as attempt_count,
      (array_agg(attempt.score order by attempt.received_at, attempt.id))[1]
        as first_score,
      (array_agg(attempt.score order by attempt.received_at desc, attempt.id desc))[1]
        as latest_score,
      max(attempt.score) as best_score,
      (array_agg(attempt.max_score order by attempt.received_at desc, attempt.id desc))[1]
        as latest_max_score,
      (array_agg(
        round((attempt.score / nullif(attempt.max_score, 0)) * 100, 2)
        order by attempt.received_at, attempt.id
      ))[1] as first_percentage,
      (array_agg(
        round((attempt.score / nullif(attempt.max_score, 0)) * 100, 2)
        order by attempt.received_at desc, attempt.id desc
      ))[1] as latest_percentage,
      max(round((attempt.score / nullif(attempt.max_score, 0)) * 100, 2))
        as best_percentage,
      min(attempt.received_at) as first_attempt_at,
      max(attempt.received_at) as latest_attempt_at
    from hub_assignments as hub_assignment
    join learning.attempts as attempt
      on attempt.assignment_id = hub_assignment.assignment_id
     and attempt.student_id = v_student_id
     and attempt.status = 'completed'
    group by hub_assignment.assignment_id
  )
  select
    hub_assignment.hub_code,
    hub_assignment.activity_key,
    hub_assignment.activity_title,
    hub_assignment.activity_version,
    week_context.week_key,
    week_context.week_number,
    week_context.session_number,
    coalesce(progress.attempt_count, 0::bigint) as attempt_count,
    progress.first_score,
    progress.latest_score,
    progress.best_score,
    coalesce(progress.latest_max_score, hub_assignment.version_max_score) as max_score,
    progress.first_percentage,
    progress.latest_percentage,
    progress.best_percentage,
    case
      when progress.first_score is null or progress.latest_score is null then null
      else progress.latest_score - progress.first_score
    end as improvement,
    case
      when progress.first_percentage is null or progress.latest_percentage is null then null
      else round(progress.latest_percentage - progress.first_percentage, 2)
    end as improvement_percentage_points,
    coalesce(progress.attempt_count, 0::bigint) > 0 as completed,
    progress.first_attempt_at,
    progress.latest_attempt_at
  from hub_assignments as hub_assignment
  left join attempt_progress as progress
    on progress.assignment_id = hub_assignment.assignment_id
  left join lateral (
    select
      week.stable_key as week_key,
      coalesce(week.week_number, delivery.week_number) as week_number,
      delivery.session_number
    from learning.activity_delivery as delivery
    left join learning.curriculum_weeks as week
      on week.id = delivery.curriculum_week_id
    where delivery.activity_version_id = hub_assignment.activity_version_id
      and delivery.active
      and (
        delivery.group_id = hub_assignment.group_id
        or delivery.group_id is null
      )
    order by
      delivery.group_id nulls last,
      delivery.sort_order,
      delivery.id
    limit 1
  ) as week_context on true
  order by hub_assignment.activity_key, hub_assignment.activity_version;
end
$$;

comment on function api.my_hub_activity_progress(text) is
  'Phase 1A learner reporting: hub-scoped completed-attempt progress for the authenticated learner. Identity is auth.uid() via learning.current_student_id(). Hub scope uses platform.hub_group_links through learning.hub_access_bound_groups, matching api.my_hub_assignments. Excludes formative_checks and activity_states. Does not accept learner identifiers. Does not expose response_payload.';

revoke all on function api.my_hub_activity_progress(text)
  from public, anon, authenticated;
grant execute on function api.my_hub_activity_progress(text)
  to authenticated;
