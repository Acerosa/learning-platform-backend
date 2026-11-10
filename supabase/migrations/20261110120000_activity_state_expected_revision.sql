-- Timed written papers compare the revision last confirmed by the server.
-- Other activities, including Timed Knowledge Report 1.1.0, keep saving when
-- the caller omits p_expected_revision.

drop function if exists api.save_activity_state(text, text, jsonb, timestamptz, text);

create or replace function api.save_activity_state(
  p_activity_key text,
  p_activity_version text,
  p_state jsonb,
  p_client_updated_at timestamptz default null,
  p_hub_code text default null,
  p_expected_revision bigint default null
)
returns table (
  activity_key text,
  activity_version text,
  status text,
  state jsonb,
  started_at timestamptz,
  updated_at timestamptz,
  completed_at timestamptz,
  revision bigint,
  save_outcome text
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
  v_spec jsonb;
  v_timed boolean;
  v_outcome text := 'saved';
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

  v_payload := learning.sanitize_activity_state_payload(p_state) - 'knowledgeReportPhase';
  v_spec := learning.timed_knowledge_report_spec(v_target.activity_version_id);
  v_timed := coalesce(v_spec ->> 'assessmentType', '') = 'timed-written-paper';
  if v_timed then
    v_payload := v_payload - 'startedAt';
  end if;
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
    and draft.activity_version_id = v_target.activity_version_id
  for update;

  if found then
    if v_spec is not null and (
      v_existing.status = 'completed'
      or exists (
        select 1
        from learning.attempts as attempt
        where attempt.student_id = v_student_id
          and attempt.activity_version_id = v_target.activity_version_id
      )
    ) then
      v_outcome := 'locked';
      return query
      select
        returned.activity_key,
        returned.activity_version,
        returned.status,
        returned.state,
        returned.started_at,
        returned.updated_at,
        returned.completed_at,
        returned.revision,
        v_outcome
      from learning.activity_state_row(v_student_id, v_target.activity_version_id) as returned;
      return;
    end if;

    if v_spec is not null
       and learning.knowledge_report_now() >= v_existing.started_at
          + pg_catalog.make_interval(
            secs => learning.effective_timed_duration_seconds(
              v_student_id,
              v_target.activity_version_id,
              v_spec
            )
          ) then
      perform learning.freeze_knowledge_report_standard_time(
        v_student_id,
        v_target.activity_version_id
      );
      if not exists (
        select 1
        from learning.knowledge_report_standard_evidence as evidence
        where evidence.student_id = v_student_id
          and evidence.activity_version_id = v_target.activity_version_id
          and evidence.additional_time_started_at is not null
          and learning.knowledge_report_now() < evidence.additional_time_started_at
            + pg_catalog.make_interval(
              secs => coalesce((v_spec ->> 'additionalTimeSeconds')::integer, 0)
            )
      ) then
        v_outcome := 'locked';
        return query
        select
          returned.activity_key,
          returned.activity_version,
          returned.status,
          returned.state,
          returned.started_at,
          returned.updated_at,
          returned.completed_at,
          returned.revision,
          v_outcome
        from learning.activity_state_row(v_student_id, v_target.activity_version_id) as returned;
        return;
      end if;
    end if;

    if v_timed then
      if p_expected_revision is null then
        raise exception using errcode = '22023', message = 'REVISION_REQUIRED';
      end if;
      if p_expected_revision is distinct from v_existing.revision then
        v_outcome := 'conflict';
        return query
        select
          returned.activity_key,
          returned.activity_version,
          returned.status,
          returned.state,
          returned.started_at,
          returned.updated_at,
          returned.completed_at,
          returned.revision,
          v_outcome
        from learning.activity_state_row(v_student_id, v_target.activity_version_id) as returned;
        return;
      end if;
    elsif v_existing.status = 'in_progress'
       and p_client_updated_at is not null
       and v_existing.updated_at > p_client_updated_at then
      v_outcome := 'unchanged';
      return query
      select
        returned.activity_key,
        returned.activity_version,
        returned.status,
        returned.state,
        returned.started_at,
        returned.updated_at,
        returned.completed_at,
        returned.revision,
        v_outcome
      from learning.activity_state_row(v_student_id, v_target.activity_version_id) as returned;
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
        v_outcome := 'unchanged';
        return query
        select
          returned.activity_key,
          returned.activity_version,
          returned.status,
          returned.state,
          returned.started_at,
          returned.updated_at,
          returned.completed_at,
          returned.revision,
          v_outcome
        from learning.activity_state_row(v_student_id, v_target.activity_version_id) as returned;
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
    where draft.id = v_existing.id
      and (not v_timed or draft.revision = p_expected_revision);

    if not found then
      v_outcome := 'conflict';
      return query
      select
        returned.activity_key,
        returned.activity_version,
        returned.status,
        returned.state,
        returned.started_at,
        returned.updated_at,
        returned.completed_at,
        returned.revision,
        v_outcome
      from learning.activity_state_row(v_student_id, v_target.activity_version_id) as returned;
      return;
    end if;
  else
    if v_timed and p_expected_revision is distinct from 0 then
      raise exception using
        errcode = '22023',
        message = case
          when p_expected_revision is null then 'REVISION_REQUIRED'
          else 'REVISION_CONFLICT'
        end;
    end if;

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
  select
    returned.activity_key,
    returned.activity_version,
    returned.status,
    returned.state,
    returned.started_at,
    returned.updated_at,
    returned.completed_at,
    returned.revision,
    v_outcome
  from learning.activity_state_row(v_student_id, v_target.activity_version_id) as returned;
end;
$$;

revoke all on function api.save_activity_state(text, text, jsonb, timestamptz, text, bigint)
from public, anon;
grant execute on function api.save_activity_state(text, text, jsonb, timestamptz, text, bigint)
to authenticated;

comment on function api.save_activity_state(text, text, jsonb, timestamptz, text, bigint) is
  'Saves activity state. A timed written paper accepts the write only when p_expected_revision matches the stored revision. Other activities still save when that argument is omitted.';
