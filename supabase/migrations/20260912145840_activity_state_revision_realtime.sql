-- Learner-scoped activity-state invalidation for cross-device restore.
-- Adds a server revision and a private Realtime Broadcast after genuine writes.

alter table learning.activity_states
  add column if not exists revision bigint not null default 1;

comment on column learning.activity_states.revision is
  'Monotonic per-row write counter. Server-generated. Used for targeted Realtime invalidation, not marking.';

drop function if exists api.get_activity_state(text, text);
drop function if exists api.save_activity_state(text, text, jsonb, timestamptz, text);
drop function if exists api.clear_activity_state(text, text);
drop function if exists learning.activity_state_row(uuid, uuid);

create or replace function learning.activity_state_row(
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
  completed_at timestamptz,
  revision bigint
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
    draft.completed_at,
    draft.revision
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

create or replace function learning.broadcast_activity_state_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid;
  v_activity_key text;
  v_activity_version text;
  v_row learning.activity_states%rowtype;
begin
  v_row := coalesce(NEW, OLD);
  if v_row.student_id is null then
    return coalesce(NEW, OLD);
  end if;

  select student.auth_user_id
  into v_auth_user_id
  from learning.students as student
  where student.id = v_row.student_id;

  if v_auth_user_id is null then
    return coalesce(NEW, OLD);
  end if;

  select activity.stable_key, version.version
  into v_activity_key, v_activity_version
  from learning.activity_versions as version
  join learning.activities as activity
    on activity.id = version.activity_id
  where version.id = v_row.activity_version_id;

  if v_activity_key is null then
    return coalesce(NEW, OLD);
  end if;

  begin
    perform realtime.send(
      jsonb_build_object(
        'activityId', v_activity_key,
        'version', v_activity_version,
        'revision', coalesce(v_row.revision, 0),
        'updatedAt', v_row.updated_at
      ),
      'activity_state_invalidated',
      'learner-state:' || v_auth_user_id::text,
      true
    );
  exception
    when undefined_function then
      null;
    when invalid_schema_name then
      null;
    when undefined_object then
      null;
  end;

  return coalesce(NEW, OLD);
end;
$$;

revoke all on function learning.broadcast_activity_state_invalidation()
from public, anon, authenticated;

drop trigger if exists activity_states_broadcast_invalidation on learning.activity_states;
create trigger activity_states_broadcast_invalidation
after insert or update of state_payload, status, revision, updated_at
on learning.activity_states
for each row execute function learning.broadcast_activity_state_invalidation();

create or replace function api.get_activity_state(
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
  completed_at timestamptz,
  revision bigint
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
    draft.completed_at,
    draft.revision
  from learning.activity_state_row(v_student_id, v_target.activity_version_id) as draft
  where draft.status = 'in_progress';
end;
$$;

revoke all on function api.get_activity_state(text, text) from public, anon;
grant execute on function api.get_activity_state(text, text) to authenticated;

create or replace function api.save_activity_state(
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
  completed_at timestamptz,
  revision bigint
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
  v_client_started timestamptz;
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

    if v_existing.status = 'completed' then
      v_client_started := null;
      begin
        if jsonb_typeof(v_payload->'startedAt') = 'string' then
          v_client_started := (v_payload->>'startedAt')::timestamptz;
        end if;
      exception
        when others then
          v_client_started := null;
      end;
      if v_client_started is null
         or v_client_started <= v_existing.completed_at then
        return query
        select *
        from learning.activity_state_row(v_student_id, v_target.activity_version_id);
        return;
      end if;
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
      completed_at = null,
      revision = draft.revision + 1
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
      updated_at,
      revision
    ) values (
      v_student_id,
      v_target.assignment_id,
      v_target.activity_version_id,
      v_hub_code,
      v_payload,
      'in_progress',
      v_now,
      v_now,
      1
    );
  end if;

  return query
  select *
  from learning.activity_state_row(v_student_id, v_target.activity_version_id);
end;
$$;

revoke all on function api.save_activity_state(text, text, jsonb, timestamptz, text)
from public, anon;
grant execute on function api.save_activity_state(text, text, jsonb, timestamptz, text)
to authenticated;

create or replace function api.clear_activity_state(
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
  completed_at timestamptz,
  revision bigint
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
    updated_at = v_now,
    revision = draft.revision + 1
  where draft.student_id = v_student_id
    and draft.activity_version_id = v_target.activity_version_id
    and draft.status = 'in_progress';

  return query
  select *
  from learning.activity_state_row(v_student_id, v_target.activity_version_id);
end;
$$;

revoke all on function api.clear_activity_state(text, text) from public, anon;
grant execute on function api.clear_activity_state(text, text) to authenticated;

create or replace function learning.complete_activity_state_for_attempt()
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
    updated_at = clock_timestamp(),
    revision = draft.revision + 1
  where draft.student_id = new.student_id
    and draft.activity_version_id = new.activity_version_id
    and draft.status = 'in_progress';
  return new;
end;
$$;

do $policy$
begin
  if to_regclass('realtime.messages') is null then
    return;
  end if;

  execute $sql$
    drop policy if exists learner_receive_own_activity_state_broadcast
    on realtime.messages
  $sql$;

  execute $sql$
    create policy learner_receive_own_activity_state_broadcast
    on realtime.messages
    for select
    to authenticated
    using (
      realtime.messages.extension = 'broadcast'
      and realtime.topic() = 'learner-state:' || (select auth.uid())::text
    )
  $sql$;
exception
  when others then
    null;
end;
$policy$;
