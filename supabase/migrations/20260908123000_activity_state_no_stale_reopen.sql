-- A late autosave must not reopen a draft that submit_attempt already completed.
-- A genuine retry (startedAt after completed_at) may start a new in-progress row.

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

revoke all on function api.save_activity_state(text, text, jsonb, timestamptz, text)
from public, anon;
grant execute on function api.save_activity_state(text, text, jsonb, timestamptz, text)
to authenticated;

comment on function api.save_activity_state(text, text, jsonb, timestamptz, text) is
  'Upserts the current in-progress activity draft. Strips marks, scores, and identity fields. Does not create attempts. Does not reopen a completed draft unless startedAt is after completed_at.';
