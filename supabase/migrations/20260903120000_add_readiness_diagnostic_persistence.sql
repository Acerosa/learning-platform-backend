-- Anonymous readiness diagnostics.
-- Separate from learning.attempts: no auth.uid(), no learner accounts, no
-- academic grades. Browsers write only through api RPCs.

create table learning.diagnostic_sessions (
  id uuid primary key default gen_random_uuid(),
  hub_id uuid not null
    references platform.hubs (id) on delete restrict,
  course_id uuid not null
    references learning.courses (id) on delete restrict,
  student_name text not null,
  student_id text not null,
  status text not null default 'started',
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint diagnostic_session_student_name_valid check (
    char_length(btrim(student_name)) between 2 and 80
    and student_name !~ '[[:cntrl:]]'
  ),
  constraint diagnostic_session_student_id_valid check (
    student_id ~ '^[A-Za-z0-9][A-Za-z0-9/_-]{1,31}$'
  ),
  constraint diagnostic_session_status_valid
    check (status in ('started', 'completed', 'abandoned')),
  constraint diagnostic_session_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  constraint diagnostic_session_metadata_size_valid
    check (octet_length(metadata::text) <= 2048),
  constraint diagnostic_session_completed_timestamp_valid check (
    (status = 'completed' and completed_at is not null and completed_at >= started_at)
    or (status <> 'completed' and completed_at is null)
  )
);

comment on table learning.diagnostic_sessions is
  'Anonymous readiness diagnostic sessions. Student name and student ID are reporting identifiers, not authentication.';

create index diagnostic_sessions_hub_started_idx
  on learning.diagnostic_sessions (hub_id, started_at desc);

create index diagnostic_sessions_course_status_idx
  on learning.diagnostic_sessions (course_id, status);

create index diagnostic_sessions_student_id_started_idx
  on learning.diagnostic_sessions (student_id, started_at desc);

create table learning.diagnostic_responses (
  id uuid primary key default gen_random_uuid(),
  diagnostic_session_id uuid not null
    references learning.diagnostic_sessions (id) on delete cascade,
  activity_id text not null,
  unit_key text not null,
  topic_key text,
  question_key text not null,
  evidence jsonb not null,
  is_correct boolean,
  is_not_sure boolean not null default false,
  confidence text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint diagnostic_responses_session_question_unique
    unique (diagnostic_session_id, activity_id, question_key),
  constraint diagnostic_response_activity_id_valid check (
    activity_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
  ),
  constraint diagnostic_response_question_key_valid check (
    question_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
  ),
  constraint diagnostic_response_unit_key_valid check (
    unit_key in (
      'general',
      'global-information',
      'fundamentals-of-it',
      'cyber-security',
      'web-design'
    )
  ),
  constraint diagnostic_response_topic_key_valid check (
    topic_key is null
    or topic_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
  ),
  constraint diagnostic_response_evidence_type_valid check (
    jsonb_typeof(evidence) in ('object', 'array', 'string', 'number', 'boolean')
  ),
  constraint diagnostic_response_evidence_size_valid
    check (octet_length(evidence::text) <= 4096),
  constraint diagnostic_response_confidence_valid check (
    confidence is null
    or (
      char_length(confidence) between 1 and 64
      and confidence !~ '[[:cntrl:]]'
    )
  )
);

comment on table learning.diagnostic_responses is
  'Question-level readiness diagnostic evidence. is_correct is server-derived only and stays null without an authoritative marking spec.';

create index diagnostic_responses_session_idx
  on learning.diagnostic_responses (diagnostic_session_id);

create index diagnostic_responses_unit_idx
  on learning.diagnostic_responses (unit_key, question_key);

alter table learning.diagnostic_sessions enable row level security;
alter table learning.diagnostic_responses enable row level security;

revoke all on table learning.diagnostic_sessions from public, anon, authenticated;
revoke all on table learning.diagnostic_responses from public, anon, authenticated;

grant select on table learning.diagnostic_sessions to authenticated;
grant select on table learning.diagnostic_responses to authenticated;

create policy diagnostic_sessions_platform_admin_read
on learning.diagnostic_sessions
for select
to authenticated
using ((select platform.current_staff_has_role('platform_admin')));

create policy diagnostic_responses_platform_admin_read
on learning.diagnostic_responses
for select
to authenticated
using ((select platform.current_staff_has_role('platform_admin')));

create function learning.diagnostic_not_sure_from_evidence(
  p_evidence jsonb,
  p_flag boolean
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_value text;
begin
  if coalesce(p_flag, false) then
    return true;
  end if;
  if p_evidence is null then
    return false;
  end if;
  if jsonb_typeof(p_evidence) = 'string' then
    return (p_evidence #>> '{}') = 'not-sure';
  end if;
  if jsonb_typeof(p_evidence) = 'object' then
    if p_evidence ->> 'optionId' = 'not-sure' then
      return true;
    end if;
    for v_value in
      select value
      from jsonb_each_text(p_evidence)
    loop
      if v_value = 'not-sure' then
        return true;
      end if;
    end loop;
  end if;
  return false;
end
$$;

revoke all on function learning.diagnostic_not_sure_from_evidence(jsonb, boolean)
  from public, anon, authenticated;

create function api.start_diagnostic(
  p_hub_code text,
  p_student_name text,
  p_student_id text,
  p_course_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hub platform.hubs%rowtype;
  v_course learning.courses%rowtype;
  v_course_key text;
  v_name text;
  v_student_id text;
  v_session_id uuid;
  v_started_at timestamptz;
begin
  v_name := btrim(coalesce(p_student_name, ''));
  v_student_id := btrim(coalesce(p_student_id, ''));
  v_course_key := nullif(btrim(coalesce(p_course_key, '')), '');

  if coalesce(p_hub_code, '') !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception using errcode = '22023', message = 'INVALID_HUB_CODE';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 or v_name ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'INVALID_STUDENT_NAME';
  end if;
  if v_student_id !~ '^[A-Za-z0-9][A-Za-z0-9/_-]{1,31}$' then
    raise exception using errcode = '22023', message = 'INVALID_STUDENT_ID';
  end if;
  if v_course_key is not null and v_course_key !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception using errcode = '22023', message = 'INVALID_COURSE_KEY';
  end if;

  select hub.*
  into v_hub
  from platform.hubs as hub
  where hub.hub_code = p_hub_code;

  if not found then
    raise exception using errcode = '22023', message = 'DIAGNOSTIC_HUB_UNKNOWN';
  end if;
  if not v_hub.active or v_hub.status in ('deprecated', 'archived') then
    raise exception using errcode = '22023', message = 'DIAGNOSTIC_HUB_INACTIVE';
  end if;

  if v_course_key is null then
    select course.*
    into v_course
    from platform.hub_course_links as link
    join learning.courses as course on course.id = link.course_id
    where link.hub_id = v_hub.id
      and link.active
      and course.active
    order by course.stable_key
    limit 1;

    if not found then
      raise exception using errcode = '22023', message = 'DIAGNOSTIC_HUB_COURSE_NOT_LINKED';
    end if;

    if (
      select count(*)
      from platform.hub_course_links as link
      join learning.courses as course on course.id = link.course_id
      where link.hub_id = v_hub.id
        and link.active
        and course.active
    ) <> 1 then
      raise exception using errcode = '22023', message = 'DIAGNOSTIC_COURSE_REQUIRED';
    end if;
  else
    select course.*
    into v_course
    from learning.courses as course
    where course.stable_key = v_course_key;

    if not found or not v_course.active then
      raise exception using errcode = '22023', message = 'DIAGNOSTIC_COURSE_UNKNOWN';
    end if;

    if not exists (
      select 1
      from platform.hub_course_links as link
      where link.hub_id = v_hub.id
        and link.course_id = v_course.id
        and link.active
    ) then
      raise exception using errcode = '22023', message = 'DIAGNOSTIC_HUB_COURSE_NOT_LINKED';
    end if;
  end if;

  insert into learning.diagnostic_sessions (
    hub_id,
    course_id,
    student_name,
    student_id,
    status
  ) values (
    v_hub.id,
    v_course.id,
    v_name,
    v_student_id,
    'started'
  )
  returning id, started_at into v_session_id, v_started_at;

  return jsonb_build_object(
    'id', v_session_id,
    'started_at', v_started_at,
    'status', 'started',
    'hub_code', v_hub.hub_code,
    'course_key', v_course.stable_key
  );
end
$$;

create function api.submit_diagnostic_response(
  p_session_id uuid,
  p_activity_id text,
  p_unit_key text,
  p_question_key text,
  p_evidence jsonb,
  p_is_not_sure boolean default false,
  p_confidence text default null,
  p_topic_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session learning.diagnostic_sessions%rowtype;
  v_activity_id text;
  v_question_key text;
  v_unit_key text;
  v_topic_key text;
  v_confidence text;
  v_is_not_sure boolean;
  v_response_id uuid;
begin
  if p_session_id is null then
    raise exception using errcode = '22023', message = 'INVALID_SESSION_ID';
  end if;

  select session.*
  into v_session
  from learning.diagnostic_sessions as session
  where session.id = p_session_id;

  if not found then
    raise exception using errcode = '22023', message = 'DIAGNOSTIC_SESSION_NOT_FOUND';
  end if;
  if v_session.status = 'completed' then
    raise exception using errcode = '22023', message = 'DIAGNOSTIC_SESSION_COMPLETED';
  end if;

  v_activity_id := btrim(coalesce(p_activity_id, ''));
  v_question_key := btrim(coalesce(p_question_key, ''));
  v_unit_key := btrim(coalesce(p_unit_key, ''));
  v_topic_key := nullif(btrim(coalesce(p_topic_key, '')), '');
  v_confidence := nullif(btrim(coalesce(p_confidence, '')), '');

  if v_activity_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_ID';
  end if;
  if v_question_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
    raise exception using errcode = '22023', message = 'INVALID_QUESTION_KEY';
  end if;
  if v_unit_key not in (
    'general',
    'global-information',
    'fundamentals-of-it',
    'cyber-security',
    'web-design'
  ) then
    raise exception using errcode = '22023', message = 'INVALID_UNIT_KEY';
  end if;
  if v_topic_key is not null and v_topic_key !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception using errcode = '22023', message = 'INVALID_TOPIC_KEY';
  end if;
  if p_evidence is null
     or jsonb_typeof(p_evidence) not in ('object', 'array', 'string', 'number', 'boolean')
     or octet_length(p_evidence::text) > 4096 then
    raise exception using errcode = '22023', message = 'INVALID_EVIDENCE';
  end if;
  if v_confidence is not null
     and (
       char_length(v_confidence) > 64
       or v_confidence ~ '[[:cntrl:]]'
     ) then
    raise exception using errcode = '22023', message = 'INVALID_CONFIDENCE';
  end if;

  v_is_not_sure := learning.diagnostic_not_sure_from_evidence(p_evidence, p_is_not_sure);

  insert into learning.diagnostic_responses (
    diagnostic_session_id,
    activity_id,
    unit_key,
    topic_key,
    question_key,
    evidence,
    is_correct,
    is_not_sure,
    confidence
  ) values (
    v_session.id,
    v_activity_id,
    v_unit_key,
    v_topic_key,
    v_question_key,
    p_evidence,
    null,
    v_is_not_sure,
    v_confidence
  )
  on conflict (diagnostic_session_id, activity_id, question_key)
  do update set
    unit_key = excluded.unit_key,
    topic_key = excluded.topic_key,
    evidence = excluded.evidence,
    is_correct = null,
    is_not_sure = excluded.is_not_sure,
    confidence = excluded.confidence,
    updated_at = clock_timestamp()
  returning id into v_response_id;

  update learning.diagnostic_sessions
  set updated_at = clock_timestamp()
  where id = v_session.id;

  return jsonb_build_object(
    'id', v_response_id,
    'activity_id', v_activity_id,
    'question_key', v_question_key,
    'is_not_sure', v_is_not_sure
  );
end
$$;

create function api.complete_diagnostic(
  p_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session learning.diagnostic_sessions%rowtype;
begin
  if p_session_id is null then
    raise exception using errcode = '22023', message = 'INVALID_SESSION_ID';
  end if;

  select session.*
  into v_session
  from learning.diagnostic_sessions as session
  where session.id = p_session_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'DIAGNOSTIC_SESSION_NOT_FOUND';
  end if;

  if v_session.status = 'completed' then
    return jsonb_build_object(
      'id', v_session.id,
      'completed_at', v_session.completed_at,
      'status', v_session.status
    );
  end if;

  update learning.diagnostic_sessions
  set
    status = 'completed',
    completed_at = clock_timestamp(),
    updated_at = clock_timestamp()
  where id = v_session.id
  returning * into v_session;

  return jsonb_build_object(
    'id', v_session.id,
    'completed_at', v_session.completed_at,
    'status', v_session.status
  );
end
$$;

revoke all on function api.start_diagnostic(text, text, text, text)
  from public, anon, authenticated;
revoke all on function api.submit_diagnostic_response(uuid, text, text, text, jsonb, boolean, text, text)
  from public, anon, authenticated;
revoke all on function api.complete_diagnostic(uuid)
  from public, anon, authenticated;

grant execute on function api.start_diagnostic(text, text, text, text)
  to anon, authenticated;
grant execute on function api.submit_diagnostic_response(uuid, text, text, text, jsonb, boolean, text, text)
  to anon, authenticated;
grant execute on function api.complete_diagnostic(uuid)
  to anon, authenticated;

create view admin_api.diagnostic_sessions
with (security_invoker = true)
as
select
  session.id as session_id,
  session.student_name,
  session.student_id,
  hub.hub_code,
  hub.hub_name,
  course.stable_key as course_key,
  course.title as course_title,
  session.status,
  session.started_at,
  session.completed_at,
  (
    select count(*)
    from learning.diagnostic_responses as response
    where response.diagnostic_session_id = session.id
  ) as response_count,
  (
    select count(*)
    from learning.diagnostic_responses as response
    where response.diagnostic_session_id = session.id
      and response.is_not_sure
  ) as not_sure_count
from learning.diagnostic_sessions as session
join platform.hubs as hub on hub.id = session.hub_id
join learning.courses as course on course.id = session.course_id
where (select platform.current_staff_has_role('platform_admin'));

create view admin_api.diagnostic_responses
with (security_invoker = true)
as
select
  response.id as response_id,
  response.diagnostic_session_id as session_id,
  session.student_name,
  session.student_id,
  hub.hub_code,
  course.stable_key as course_key,
  response.activity_id,
  response.unit_key,
  response.topic_key,
  response.question_key,
  response.evidence,
  response.is_not_sure,
  response.confidence,
  response.is_correct,
  response.created_at,
  response.updated_at
from learning.diagnostic_responses as response
join learning.diagnostic_sessions as session
  on session.id = response.diagnostic_session_id
join platform.hubs as hub on hub.id = session.hub_id
join learning.courses as course on course.id = session.course_id
where (select platform.current_staff_has_role('platform_admin'));

create view admin_api.diagnostic_summary
with (security_invoker = true)
as
select
  hub.hub_code,
  course.stable_key as course_key,
  count(*) as started_count,
  count(*) filter (where session.status = 'completed') as completed_count,
  round(
    100.0 * count(*) filter (where session.status = 'completed')
      / nullif(count(*), 0),
    2
  ) as completion_percentage,
  (
    select count(*)
    from learning.diagnostic_responses as response
    join learning.diagnostic_sessions as inner_session
      on inner_session.id = response.diagnostic_session_id
    where inner_session.hub_id = hub.id
      and inner_session.course_id = course.id
  ) as response_count,
  (
    select count(*)
    from learning.diagnostic_responses as response
    join learning.diagnostic_sessions as inner_session
      on inner_session.id = response.diagnostic_session_id
    where inner_session.hub_id = hub.id
      and inner_session.course_id = course.id
      and response.is_not_sure
  ) as not_sure_count,
  (
    select round(
      100.0 * count(*) filter (where response.is_not_sure)
        / nullif(count(*), 0),
      2
    )
    from learning.diagnostic_responses as response
    join learning.diagnostic_sessions as inner_session
      on inner_session.id = response.diagnostic_session_id
    where inner_session.hub_id = hub.id
      and inner_session.course_id = course.id
  ) as not_sure_percentage
from learning.diagnostic_sessions as session
join platform.hubs as hub on hub.id = session.hub_id
join learning.courses as course on course.id = session.course_id
where (select platform.current_staff_has_role('platform_admin'))
group by hub.id, hub.hub_code, course.id, course.stable_key;

comment on view admin_api.diagnostic_sessions is
  'Platform-admin Readiness Diagnostic session list. Not academic attainment.';
comment on view admin_api.diagnostic_responses is
  'Platform-admin Readiness Diagnostic response detail. is_correct is null without authoritative marking.';
comment on view admin_api.diagnostic_summary is
  'Platform-admin Readiness Diagnostic group counts. Completion and Not sure rates only; not grades.';

revoke all on
  admin_api.diagnostic_sessions,
  admin_api.diagnostic_responses,
  admin_api.diagnostic_summary
from public, anon, authenticated;

grant select on
  admin_api.diagnostic_sessions,
  admin_api.diagnostic_responses,
  admin_api.diagnostic_summary
to authenticated;

comment on function api.start_diagnostic(text, text, text, text) is
  'Create an anonymous readiness diagnostic session. Student ID is not authentication.';
comment on function api.submit_diagnostic_response(uuid, text, text, text, jsonb, boolean, text, text) is
  'Persist one diagnostic response. Client scores and is_correct are not accepted.';
comment on function api.complete_diagnostic(uuid) is
  'Mark a readiness diagnostic session complete. Idempotent. Does not accept a client score.';
