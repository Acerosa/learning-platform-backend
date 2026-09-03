-- One anonymous diagnostic sitting per hub, course, diagnostic version, and
-- trimmed student ID. Duplicate prevention is deduplication, not authentication.
-- Does not use auth.uid(). Does not delete existing diagnostic rows.

comment on table learning.diagnostic_sessions is
  'Anonymous readiness diagnostic sessions. Student name and student ID are reporting identifiers, not authentication. One sitting per hub, course, diagnostic version, and trimmed student ID.';

alter table learning.diagnostic_sessions
  add column diagnostic_key text,
  add column diagnostic_version text not null default '1.0.0';

comment on column learning.diagnostic_sessions.diagnostic_key is
  'Stable diagnostic product identity, derived from the registered hub code. Not a client-chosen version.';

comment on column learning.diagnostic_sessions.diagnostic_version is
  'Sitting version from registered hub features.diagnosticVersion, default 1.0.0. Independent of hub_version and content package version so a future diagnostic release can permit a new sitting.';

comment on column learning.diagnostic_sessions.student_id is
  'Self-declared reporting identifier, stored trimmed. Deduplication key with diagnostic identity; not authenticated identity.';

update learning.diagnostic_sessions as session
set
  diagnostic_key = hub.hub_code,
  diagnostic_version = coalesce(
    nullif(btrim(hub.features ->> 'diagnosticVersion'), ''),
    '1.0.0'
  )
from platform.hubs as hub
where hub.id = session.hub_id
  and session.diagnostic_key is null;

alter table learning.diagnostic_sessions
  alter column diagnostic_key set not null;

alter table learning.diagnostic_sessions
  add constraint diagnostic_session_diagnostic_key_valid
    check (diagnostic_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  add constraint diagnostic_session_diagnostic_version_valid
    check (
      diagnostic_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
    );

do $$
declare
  v_duplicate_count integer;
begin
  select count(*)
  into v_duplicate_count
  from (
    select 1
    from learning.diagnostic_sessions
    group by hub_id, course_id, diagnostic_key, diagnostic_version, student_id
    having count(*) > 1
  ) as duplicates;

  if v_duplicate_count > 0 then
    raise exception using
      errcode = '23505',
      message = 'DIAGNOSTIC_SESSION_DUPLICATES_EXIST';
  end if;
end
$$;

create unique index diagnostic_sessions_one_sitting_idx
  on learning.diagnostic_sessions (
    hub_id,
    course_id,
    diagnostic_key,
    diagnostic_version,
    student_id
  );

comment on index learning.diagnostic_sessions_one_sitting_idx is
  'Prevents concurrent Start requests from creating two equivalent diagnostic sittings.';

update platform.hubs
set
  features = features || jsonb_build_object('diagnosticVersion', '1.0.0'),
  updated_at = clock_timestamp()
where hub_code = 'level-3-it-year-1-readiness'
  and coalesce(nullif(btrim(features ->> 'diagnosticVersion'), ''), '') = '';

create or replace function api.start_diagnostic(
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
  v_diagnostic_key text;
  v_diagnostic_version text;
  v_session_id uuid;
  v_started_at timestamptz;
  v_status text;
  v_resumed boolean;
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

  v_diagnostic_key := v_hub.hub_code;
  v_diagnostic_version := coalesce(
    nullif(btrim(v_hub.features ->> 'diagnosticVersion'), ''),
    '1.0.0'
  );
  if v_diagnostic_version !~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' then
    raise exception using errcode = '22023', message = 'DIAGNOSTIC_VERSION_INVALID';
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
    diagnostic_key,
    diagnostic_version,
    status
  ) values (
    v_hub.id,
    v_course.id,
    v_name,
    v_student_id,
    v_diagnostic_key,
    v_diagnostic_version,
    'started'
  )
  on conflict (hub_id, course_id, diagnostic_key, diagnostic_version, student_id)
  do nothing
  returning id, started_at, status
  into v_session_id, v_started_at, v_status;

  if found then
    v_resumed := false;
  else
    select session.id, session.started_at, session.status
    into v_session_id, v_started_at, v_status
    from learning.diagnostic_sessions as session
    where session.hub_id = v_hub.id
      and session.course_id = v_course.id
      and session.diagnostic_key = v_diagnostic_key
      and session.diagnostic_version = v_diagnostic_version
      and session.student_id = v_student_id;

    if not found then
      raise exception using errcode = '22023', message = 'DIAGNOSTIC_START_FAILED';
    end if;

    if v_status = 'completed' then
      raise exception using
        errcode = '22023',
        message = 'DIAGNOSTIC_ALREADY_COMPLETED';
    end if;

    if v_status = 'abandoned' then
      update learning.diagnostic_sessions
      set
        status = 'started',
        updated_at = clock_timestamp()
      where id = v_session_id
      returning started_at, status into v_started_at, v_status;
    end if;

    v_resumed := true;
  end if;

  return jsonb_build_object(
    'id', v_session_id,
    'started_at', v_started_at,
    'status', v_status,
    'hub_code', v_hub.hub_code,
    'course_key', v_course.stable_key,
    'resumed', coalesce(v_resumed, false)
  );
end
$$;

comment on function api.start_diagnostic(text, text, text, text) is
  'Start or resume one anonymous readiness diagnostic sitting per student ID and diagnostic version. Deduplication, not authentication. Completed sittings raise DIAGNOSTIC_ALREADY_COMPLETED without returning a session id.';

create or replace view admin_api.diagnostic_sessions
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
  ) as not_sure_count,
  session.diagnostic_key,
  session.diagnostic_version
from learning.diagnostic_sessions as session
join platform.hubs as hub on hub.id = session.hub_id
join learning.courses as course on course.id = session.course_id
where (select platform.current_staff_has_role('platform_admin'));

comment on view admin_api.diagnostic_sessions is
  'Platform-admin Readiness Diagnostic session list. Not academic attainment. diagnostic_key and diagnostic_version identify the sitting version.';
