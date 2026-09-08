-- Authenticated in-progress activity drafts. Separate from completed attempts,
-- scores, and derived progress. Learners write only through api RPCs.

create table learning.activity_states (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null
    references learning.students (id) on delete restrict,
  assignment_id uuid not null
    references learning.activity_assignments (id) on delete restrict,
  activity_version_id uuid not null
    references learning.activity_versions (id) on delete restrict,
  hub_code text,
  state_payload jsonb not null default '{}'::jsonb,
  status text not null default 'in_progress',
  started_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  constraint activity_states_student_version_unique
    unique (student_id, activity_version_id),
  constraint activity_state_status_valid
    check (status in ('in_progress', 'completed')),
  constraint activity_state_payload_object
    check (jsonb_typeof(state_payload) = 'object'),
  constraint activity_state_payload_size
    check (octet_length(state_payload::text) <= 131072),
  constraint activity_state_timestamps_valid
    check (
      updated_at >= started_at
      and (completed_at is null or completed_at >= started_at)
    ),
  constraint activity_state_completed_consistent
    check (
      (status = 'in_progress' and completed_at is null)
      or (status = 'completed' and completed_at is not null)
    ),
  constraint activity_state_hub_code_valid
    check (
      hub_code is null
      or (
        length(hub_code) between 1 and 80
        and hub_code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
      )
    )
);

create index activity_states_student_status_idx
  on learning.activity_states (student_id, status, updated_at desc);

create index activity_states_version_updated_idx
  on learning.activity_states (activity_version_id, updated_at desc);

comment on table learning.activity_states is
  'Current in-progress learner interaction state. Not official attempts, scores, or derived progress.';

create function learning.sanitize_activity_state_payload(p_state jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_result jsonb := '{}'::jsonb;
  v_key text;
  v_value jsonb;
  v_norm text;
  v_item jsonb;
  v_array jsonb := '[]'::jsonb;
begin
  if p_state is null or jsonb_typeof(p_state) is distinct from 'object' then
    return '{}'::jsonb;
  end if;

  for v_key, v_value in
    select key, value from jsonb_each(p_state)
  loop
    v_norm := lower(regexp_replace(v_key, '[^a-zA-Z0-9]', '', 'g'));
    if v_norm in (
      'score',
      'maxscore',
      'awardedscore',
      'iscorrect',
      'markingsource',
      'totalscore',
      'percentage',
      'correctvalues',
      'correctoptionid',
      'correctcategoryid',
      'correctmapping',
      'answerkey',
      'learnerid',
      'studentid',
      'studentnumber',
      'enrolmentid',
      'assignmentid',
      'attemptnumber',
      'groupid',
      'firstname',
      'surname',
      'email'
    ) then
      continue;
    end if;

    if jsonb_typeof(v_value) = 'object' then
      v_result := v_result || jsonb_build_object(
        v_key,
        learning.sanitize_activity_state_payload(v_value)
      );
    elsif jsonb_typeof(v_value) = 'array' then
      v_array := '[]'::jsonb;
      for v_item in select value from jsonb_array_elements(v_value)
      loop
        v_array := v_array || jsonb_build_array(
          case
            when jsonb_typeof(v_item) = 'object'
              then learning.sanitize_activity_state_payload(v_item)
            else v_item
          end
        );
      end loop;
      v_result := v_result || jsonb_build_object(v_key, v_array);
    else
      v_result := v_result || jsonb_build_object(v_key, v_value);
    end if;
  end loop;

  return v_result;
end;
$$;

revoke all on function learning.sanitize_activity_state_payload(jsonb)
from public, anon, authenticated;

create function learning.activity_state_row(
  p_student_id uuid,
  p_activity_version_id uuid
)
returns table (
  activity_key text,
  activity_version text,
  status text,
  state jsonb,
  started_at timestamptz,
  updated_at timestamptz,
  completed_at timestamptz
)
language sql
stable
set search_path = ''
as $$
  select
    activity.stable_key,
    version.version,
    draft.status,
    draft.state_payload,
    draft.started_at,
    draft.updated_at,
    draft.completed_at
  from learning.activity_states as draft
  join learning.activity_versions as version
    on version.id = draft.activity_version_id
  join learning.activities as activity
    on activity.id = version.activity_id
  where draft.student_id = p_student_id
    and draft.activity_version_id = p_activity_version_id;
$$;

revoke all on function learning.activity_state_row(uuid, uuid)
from public, anon, authenticated;

create function learning.require_current_student_id()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid;
  v_student_id uuid;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  select student.id
  into v_student_id
  from learning.students as student
  where student.auth_user_id = v_auth_user_id
    and student.active;

  if v_student_id is null then
    raise exception using errcode = '28000', message = 'STUDENT_IDENTITY_NOT_FOUND';
  end if;

  return v_student_id;
end;
$$;

revoke all on function learning.require_current_student_id()
from public, anon, authenticated;

create function learning.resolve_activity_state_target(
  p_student_id uuid,
  p_activity_key text,
  p_activity_version text,
  p_require_assignment boolean
)
returns table (
  activity_version_id uuid,
  assignment_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_activity_version_id uuid;
  v_assignment_id uuid;
  v_matching_assignment_count integer;
  v_now timestamptz := clock_timestamp();
begin
  if p_activity_key is null or btrim(p_activity_key) = ''
     or p_activity_version is null or btrim(p_activity_version) = '' then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_VERSION';
  end if;

  select version.id
  into v_activity_version_id
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
  into v_matching_assignment_count
  from learning.enrolments as enrolment
  join learning.groups as learner_group
    on learner_group.id = enrolment.group_id
   and learner_group.active
  join learning.activity_assignments as assignment
    on assignment.group_id = enrolment.group_id
   and assignment.activity_version_id = v_activity_version_id
   and assignment.active
   and (assignment.opens_at is null or assignment.opens_at <= v_now)
   and (assignment.due_at is null or assignment.due_at >= v_now)
  where enrolment.student_id = p_student_id
    and enrolment.status = 'active';

  if p_require_assignment then
    if v_matching_assignment_count = 0 then
      raise exception using errcode = '42501', message = 'ACTIVITY_NOT_ASSIGNED';
    end if;
    if v_matching_assignment_count > 1 then
      raise exception using errcode = '23514', message = 'ACTIVITY_ASSIGNMENT_AMBIGUOUS';
    end if;
  end if;

  if v_matching_assignment_count = 1 then
    select assignment.id
    into v_assignment_id
    from learning.enrolments as enrolment
    join learning.groups as learner_group
      on learner_group.id = enrolment.group_id
     and learner_group.active
    join learning.activity_assignments as assignment
      on assignment.group_id = enrolment.group_id
     and assignment.activity_version_id = v_activity_version_id
     and assignment.active
     and (assignment.opens_at is null or assignment.opens_at <= v_now)
     and (assignment.due_at is null or assignment.due_at >= v_now)
    where enrolment.student_id = p_student_id
      and enrolment.status = 'active';
  end if;

  activity_version_id := v_activity_version_id;
  assignment_id := v_assignment_id;
  return next;
end;
$$;

revoke all on function learning.resolve_activity_state_target(uuid, text, text, boolean)
from public, anon, authenticated;

create function api.get_activity_state(
  p_activity_key text,
  p_activity_version text
)
returns table (
  activity_key text,
  activity_version text,
  status text,
  state jsonb,
  started_at timestamptz,
  updated_at timestamptz,
  completed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
  v_target record;
begin
  v_student_id := learning.require_current_student_id();
  select *
  into v_target
  from learning.resolve_activity_state_target(
    v_student_id,
    p_activity_key,
    p_activity_version,
    false
  );

  return query
  select draft.activity_key,
    draft.activity_version,
    draft.status,
    draft.state,
    draft.started_at,
    draft.updated_at,
    draft.completed_at
  from learning.activity_state_row(v_student_id, v_target.activity_version_id) as draft
  where draft.status = 'in_progress';
end;
$$;

create function api.save_activity_state(
  p_activity_key text,
  p_activity_version text,
  p_state jsonb,
  p_client_updated_at timestamptz default null,
  p_hub_code text default null
)
returns table (
  activity_key text,
  activity_version text,
  status text,
  state jsonb,
  started_at timestamptz,
  updated_at timestamptz,
  completed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
  v_target record;
  v_payload jsonb;
  v_hub_code text;
  v_existing learning.activity_states%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  v_student_id := learning.require_current_student_id();
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_student_id::text, 0)
  );

  select *
  into v_target
  from learning.resolve_activity_state_target(
    v_student_id,
    p_activity_key,
    p_activity_version,
    true
  );

  v_payload := learning.sanitize_activity_state_payload(p_state);
  if octet_length(v_payload::text) > 131072 then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_STATE';
  end if;

  v_hub_code := nullif(btrim(p_hub_code), '');
  if v_hub_code is not null then
    if not exists (
      select 1
      from platform.hubs as hub
      where hub.hub_code = v_hub_code
        and hub.active
    ) then
      v_hub_code := null;
    end if;
  end if;

  select *
  into v_existing
  from learning.activity_states as draft
  where draft.student_id = v_student_id
    and draft.activity_version_id = v_target.activity_version_id;

  if found then
    if v_existing.status = 'in_progress'
       and p_client_updated_at is not null
       and v_existing.updated_at > p_client_updated_at then
      return query
      select *
      from learning.activity_state_row(v_student_id, v_target.activity_version_id);
      return;
    end if;

    update learning.activity_states as draft
    set
      assignment_id = v_target.assignment_id,
      hub_code = coalesce(v_hub_code, draft.hub_code),
      state_payload = v_payload,
      status = 'in_progress',
      started_at = case
        when draft.status = 'completed' then v_now
        else draft.started_at
      end,
      updated_at = v_now,
      completed_at = null
    where draft.id = v_existing.id;
  else
    insert into learning.activity_states (
      student_id,
      assignment_id,
      activity_version_id,
      hub_code,
      state_payload,
      status,
      started_at,
      updated_at
    ) values (
      v_student_id,
      v_target.assignment_id,
      v_target.activity_version_id,
      v_hub_code,
      v_payload,
      'in_progress',
      v_now,
      v_now
    );
  end if;

  return query
  select *
  from learning.activity_state_row(v_student_id, v_target.activity_version_id);
end;
$$;

create function api.clear_activity_state(
  p_activity_key text,
  p_activity_version text
)
returns table (
  activity_key text,
  activity_version text,
  status text,
  state jsonb,
  started_at timestamptz,
  updated_at timestamptz,
  completed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
  v_target record;
  v_now timestamptz := clock_timestamp();
begin
  v_student_id := learning.require_current_student_id();
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_student_id::text, 0)
  );

  select *
  into v_target
  from learning.resolve_activity_state_target(
    v_student_id,
    p_activity_key,
    p_activity_version,
    false
  );

  update learning.activity_states as draft
  set
    status = 'completed',
    completed_at = coalesce(draft.completed_at, v_now),
    updated_at = v_now
  where draft.student_id = v_student_id
    and draft.activity_version_id = v_target.activity_version_id
    and draft.status = 'in_progress';

  return query
  select *
  from learning.activity_state_row(v_student_id, v_target.activity_version_id);
end;
$$;

create function learning.complete_activity_state_for_attempt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update learning.activity_states as draft
  set
    status = 'completed',
    completed_at = coalesce(draft.completed_at, clock_timestamp()),
    updated_at = clock_timestamp()
  where draft.student_id = new.student_id
    and draft.activity_version_id = new.activity_version_id
    and draft.status = 'in_progress';
  return new;
end;
$$;

create trigger attempts_complete_activity_state
after insert on learning.attempts
for each row execute function learning.complete_activity_state_for_attempt();

revoke all on function learning.complete_activity_state_for_attempt()
from public, anon, authenticated;

alter table learning.activity_states enable row level security;

revoke all on table learning.activity_states from public, anon, authenticated;

create policy activity_states_no_direct_access
on learning.activity_states
for all
to authenticated, anon
using (false)
with check (false);

revoke all on function api.get_activity_state(text, text) from public, anon;
revoke all on function api.save_activity_state(text, text, jsonb, timestamptz, text) from public, anon;
revoke all on function api.clear_activity_state(text, text) from public, anon;

grant execute on function api.get_activity_state(text, text) to authenticated;
grant execute on function api.save_activity_state(text, text, jsonb, timestamptz, text) to authenticated;
grant execute on function api.clear_activity_state(text, text) to authenticated;

comment on function api.get_activity_state(text, text) is
  'Returns the authenticated learner''s current in-progress activity draft. Identity is auth.uid().';

comment on function api.save_activity_state(text, text, jsonb, timestamptz, text) is
  'Upserts the current in-progress activity draft. Strips marks, scores, and identity fields. Does not create attempts.';

comment on function api.clear_activity_state(text, text) is
  'Marks the current in-progress activity draft completed. Does not rewrite attempt history.';
