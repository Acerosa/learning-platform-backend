-- Two-phase timed knowledge reports.
-- A published version without additionalTimeSeconds keeps the original
-- single-phase contract. Historical response payloads are not rewritten.

alter table learning.activity_states
  add column if not exists revision bigint not null default 1;

create or replace function learning.count_words(p_text text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select count(*)::integer
  from pg_catalog.regexp_matches(coalesce(p_text, ''), '\S+', 'g')
$$;

create or replace function learning.knowledge_report_draft_text(p_state jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce((
    select item.value #>> '{}'
    from pg_catalog.jsonb_each(coalesce(p_state -> 'responses', '{}'::jsonb)) as item(key, value)
    where pg_catalog.jsonb_typeof(item.value) = 'string'
    limit 1
  ), '')
$$;

create or replace function learning.timed_knowledge_report_spec(p_activity_version_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select marking.spec
  from learning.question_marking as marking
  join learning.questions as question
    on question.id = marking.question_id
  where question.activity_version_id = p_activity_version_id
    and coalesce(marking.spec ->> 'mode', '') = 'timed-knowledge-report'
  order by question.ordinal
  limit 1
$$;

create table if not exists learning.knowledge_report_standard_evidence (
  student_id uuid not null references learning.students (id) on delete restrict,
  activity_version_id uuid not null references learning.activity_versions (id) on delete restrict,
  standard_text text not null,
  standard_word_count integer not null,
  standard_ended_at timestamptz,
  additional_time_eligible boolean not null,
  additional_time_started_at timestamptz,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (student_id, activity_version_id),
  constraint knowledge_report_standard_word_count_valid
    check (standard_word_count >= 0),
  constraint knowledge_report_additional_start_after_standard
    check (
      additional_time_started_at is null
      or standard_ended_at is null
      or additional_time_started_at >= standard_ended_at
    )
);

comment on table learning.knowledge_report_standard_evidence is
  'Immutable standard-time snapshot for a timed knowledge report sitting. Additional time may start once. Draft text and the final response stay separate.';

alter table learning.knowledge_report_standard_evidence enable row level security;

revoke all on learning.knowledge_report_standard_evidence
from public, anon, authenticated;

create function learning.protect_knowledge_report_standard_evidence()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.standard_text is distinct from old.standard_text
     or new.standard_word_count is distinct from old.standard_word_count
     or new.standard_ended_at is distinct from old.standard_ended_at
     or new.additional_time_eligible is distinct from old.additional_time_eligible
     or new.student_id is distinct from old.student_id
     or new.activity_version_id is distinct from old.activity_version_id
     or (
       old.additional_time_started_at is not null
       and new.additional_time_started_at is distinct from old.additional_time_started_at
     ) then
    raise exception using errcode = '55000', message = 'STANDARD_TIME_EVIDENCE_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger knowledge_report_standard_evidence_immutable
before update on learning.knowledge_report_standard_evidence
for each row
execute function learning.protect_knowledge_report_standard_evidence();

create function learning.knowledge_report_timing_spec(p_spec jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce((p_spec ->> 'additionalTimeSeconds')::integer, 0) > 0
     and coalesce((p_spec ->> 'additionalTimeThresholdWords')::integer, 0) > 0
    then pg_catalog.jsonb_build_object(
      'durationSeconds', coalesce((p_spec ->> 'durationSeconds')::integer, 0),
      'minWords', coalesce((p_spec ->> 'minWords')::integer, 0),
      'additionalTimeSeconds', (p_spec ->> 'additionalTimeSeconds')::integer,
      'additionalTimeThresholdWords', (p_spec ->> 'additionalTimeThresholdWords')::integer,
      'twoPhase', true
    )
    else pg_catalog.jsonb_build_object(
      'durationSeconds', coalesce((p_spec ->> 'durationSeconds')::integer, 0),
      'minWords', coalesce((p_spec ->> 'minWords')::integer, 0),
      'additionalTimeSeconds', 0,
      'additionalTimeThresholdWords', 0,
      'twoPhase', false
    )
  end
$$;

create table if not exists learning.knowledge_report_test_clock (
  singleton boolean primary key default true check (singleton),
  frozen_at timestamptz not null
);

alter table learning.knowledge_report_test_clock enable row level security;
revoke all on table learning.knowledge_report_test_clock from public, anon, authenticated;

comment on table learning.knowledge_report_test_clock is
  'Empty in production, so knowledge report timing uses the real clock. Only the database owner can insert a row, and only tests do that. Learners have no grant and no policy.';

create or replace function learning.knowledge_report_now()
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select clock_row.frozen_at from learning.knowledge_report_test_clock as clock_row),
    pg_catalog.clock_timestamp()
  );
$$;

revoke all on function learning.knowledge_report_now() from public, anon, authenticated;

comment on function learning.knowledge_report_now() is
  'Real clock unless the owner has frozen knowledge_report_test_clock. Authenticated cannot set or read that table.';

create or replace function learning.freeze_knowledge_report_standard_time(
  p_student_id uuid,
  p_activity_version_id uuid
)
returns learning.knowledge_report_standard_evidence
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing learning.knowledge_report_standard_evidence%rowtype;
  v_state learning.activity_states%rowtype;
  v_spec jsonb;
  v_timing jsonb;
  v_question_key text;
  v_text text;
  v_words integer;
  v_end timestamptz;
begin
  select *
  into v_existing
  from learning.knowledge_report_standard_evidence as evidence
  where evidence.student_id = p_student_id
    and evidence.activity_version_id = p_activity_version_id
  for update;

  if found then
    return v_existing;
  end if;

  select question.stable_key, marking.spec
  into v_question_key, v_spec
  from learning.questions as question
  join learning.question_marking as marking
    on marking.question_id = question.id
  where question.activity_version_id = p_activity_version_id
    and coalesce(marking.spec ->> 'mode', '') = 'timed-knowledge-report'
  order by question.ordinal
  limit 1;

  v_timing := learning.knowledge_report_timing_spec(v_spec);
  if coalesce((v_timing ->> 'twoPhase')::boolean, false) is not true then
    return null;
  end if;

  select *
  into v_state
  from learning.activity_states as draft
  where draft.student_id = p_student_id
    and draft.activity_version_id = p_activity_version_id
  for update;

  if v_state.started_at is null then
    return null;
  end if;

  v_end := v_state.started_at + pg_catalog.make_interval(
    secs => (v_timing ->> 'durationSeconds')::integer
  );
  if learning.knowledge_report_now() < v_end then
    return null;
  end if;

  v_text := '';
  if pg_catalog.jsonb_typeof(v_state.state_payload -> 'responses' -> v_question_key) = 'string' then
    v_text := v_state.state_payload -> 'responses' ->> v_question_key;
  else
    v_text := learning.knowledge_report_draft_text(v_state.state_payload);
  end if;
  v_words := learning.count_words(v_text);

  insert into learning.knowledge_report_standard_evidence (
    student_id,
    activity_version_id,
    standard_text,
    standard_word_count,
    standard_ended_at,
    additional_time_eligible
  ) values (
    p_student_id,
    p_activity_version_id,
    v_text,
    v_words,
    v_end,
    v_words < (v_timing ->> 'additionalTimeThresholdWords')::integer
  )
  returning * into v_existing;

  return v_existing;
end;
$$;

create function learning.record_knowledge_report_manual_standard(
  p_student_id uuid,
  p_activity_version_id uuid,
  p_text text,
  p_ended_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into learning.knowledge_report_standard_evidence (
    student_id,
    activity_version_id,
    standard_text,
    standard_word_count,
    standard_ended_at,
    additional_time_eligible
  ) values (
    p_student_id,
    p_activity_version_id,
    coalesce(p_text, ''),
    learning.count_words(p_text),
    p_ended_at,
    false
  )
  on conflict (student_id, activity_version_id) do nothing;
end;
$$;

create or replace function learning.knowledge_report_phase_overlay(
  p_student_id uuid,
  p_activity_version_id uuid,
  p_state jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_spec jsonb;
  v_timing jsonb;
  v_started timestamptz;
  v_evidence learning.knowledge_report_standard_evidence%rowtype;
  v_now timestamptz := learning.knowledge_report_now();
  v_standard_end timestamptz;
  v_additional_end timestamptz;
  v_phase text := 'standard';
begin
  v_spec := learning.timed_knowledge_report_spec(p_activity_version_id);
  v_timing := learning.knowledge_report_timing_spec(v_spec);
  if v_spec is null or coalesce((v_timing ->> 'twoPhase')::boolean, false) is not true then
    return p_state;
  end if;

  select draft.started_at
  into v_started
  from learning.activity_states as draft
  where draft.student_id = p_student_id
    and draft.activity_version_id = p_activity_version_id;

  select *
  into v_evidence
  from learning.knowledge_report_standard_evidence as evidence
  where evidence.student_id = p_student_id
    and evidence.activity_version_id = p_activity_version_id;

  if v_started is not null then
    v_standard_end := v_started + pg_catalog.make_interval(
      secs => (v_timing ->> 'durationSeconds')::integer
    );
  end if;
  if v_evidence.additional_time_started_at is not null then
    v_additional_end := v_evidence.additional_time_started_at + pg_catalog.make_interval(
      secs => (v_timing ->> 'additionalTimeSeconds')::integer
    );
  end if;

  if exists (
    select 1
    from learning.attempts as attempt
    where attempt.student_id = p_student_id
      and attempt.activity_version_id = p_activity_version_id
  ) then
    v_phase := 'submitted';
  elsif v_evidence.additional_time_started_at is not null and v_now >= v_additional_end then
    v_phase := 'additional_expired';
  elsif v_evidence.additional_time_started_at is not null then
    v_phase := 'additional';
  elsif v_evidence.student_id is not null and v_evidence.additional_time_eligible then
    v_phase := 'additional_available';
  elsif v_evidence.student_id is not null then
    v_phase := 'standard_complete';
  elsif v_standard_end is not null and v_now >= v_standard_end then
    v_phase := 'standard_expired';
  end if;

  return coalesce(p_state, '{}'::jsonb) || pg_catalog.jsonb_build_object(
    'knowledgeReportPhase',
    pg_catalog.jsonb_build_object(
      'phase', v_phase,
      'standardDurationSeconds', (v_timing ->> 'durationSeconds')::integer,
      'additionalTimeSeconds', (v_timing ->> 'additionalTimeSeconds')::integer,
      'additionalTimeStartedAt', v_evidence.additional_time_started_at,
      'additionalTimeEligible', coalesce(v_evidence.additional_time_eligible, false),
      'serverNow', v_now
    )
  );
end;
$$;

revoke all on function learning.freeze_knowledge_report_standard_time(uuid, uuid)
from public, anon, authenticated;
revoke all on function learning.record_knowledge_report_manual_standard(uuid, uuid, text, timestamptz)
from public, anon, authenticated;
revoke all on function learning.knowledge_report_phase_overlay(uuid, uuid, jsonb)
from public, anon, authenticated;

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
security definer
set search_path = ''
as $$
  select
    activity.stable_key,
    version.version,
    draft.status,
    learning.knowledge_report_phase_overlay(
      draft.student_id,
      draft.activity_version_id,
      draft.state_payload
    ),
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

create or replace function learning.prepare_timed_knowledge_report_submission(
  p_student_id uuid,
  p_activity_version_id uuid,
  p_responses jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_spec jsonb;
  v_timing jsonb;
  v_question_key text;
  v_duration integer;
  v_min_words integer;
  v_additional_seconds integer;
  v_started timestamptz;
  v_state jsonb;
  v_standard_expired boolean;
  v_elapsed integer;
  v_item jsonb;
  v_submitted text;
  v_text text;
  v_words integer;
  v_out jsonb := '[]'::jsonb;
  v_seen boolean := false;
  v_evidence learning.knowledge_report_standard_evidence%rowtype;
  v_method text;
  v_additional_used integer := null;
  v_now timestamptz := learning.knowledge_report_now();
begin
  select question.stable_key, marking.spec
  into v_question_key, v_spec
  from learning.questions as question
  join learning.question_marking as marking
    on marking.question_id = question.id
  where question.activity_version_id = p_activity_version_id
    and coalesce(marking.spec ->> 'mode', '') = 'timed-knowledge-report'
  order by question.ordinal
  limit 1;

  if v_spec is null then
    return p_responses;
  end if;

  v_timing := learning.knowledge_report_timing_spec(v_spec);
  v_duration := (v_timing ->> 'durationSeconds')::integer;
  v_min_words := (v_timing ->> 'minWords')::integer;
  v_additional_seconds := (v_timing ->> 'additionalTimeSeconds')::integer;
  if v_duration <= 0 or v_min_words <= 0 then
    raise exception using errcode = '22023', message = 'TIMED_REPORT_NOT_CONFIGURED';
  end if;

  if exists (
    select 1
    from learning.attempts as attempt
    where attempt.student_id = p_student_id
      and attempt.activity_version_id = p_activity_version_id
  ) then
    raise exception using errcode = '23514', message = 'TIMED_REPORT_ALREADY_SUBMITTED';
  end if;

  select draft.started_at, draft.state_payload
  into v_started, v_state
  from learning.activity_states as draft
  where draft.student_id = p_student_id
    and draft.activity_version_id = p_activity_version_id;

  if v_started is null then
    raise exception using errcode = '22023', message = 'TIMED_REPORT_NOT_STARTED';
  end if;

  v_standard_expired := v_now >= v_started + pg_catalog.make_interval(secs => v_duration);
  v_elapsed := least(
    v_duration,
    greatest(0, floor(extract(epoch from (v_now - v_started)))::integer)
  );

  if coalesce((v_timing ->> 'twoPhase')::boolean, false) and v_standard_expired then
    v_evidence := learning.freeze_knowledge_report_standard_time(
      p_student_id,
      p_activity_version_id
    );
  else
    select *
    into v_evidence
    from learning.knowledge_report_standard_evidence as evidence
    where evidence.student_id = p_student_id
      and evidence.activity_version_id = p_activity_version_id;
  end if;

  for v_item in
    select value
    from pg_catalog.jsonb_array_elements(p_responses)
  loop
    if v_item ->> 'question_id' is distinct from v_question_key then
      v_out := v_out || pg_catalog.jsonb_build_array(v_item);
      continue;
    end if;

    v_seen := true;
    if pg_catalog.jsonb_typeof(v_item -> 'response_payload') = 'string' then
      v_submitted := coalesce(v_item ->> 'response_payload', '');
    else
      v_submitted := coalesce(v_item -> 'response_payload' ->> 'text', '');
    end if;

    if not coalesce((v_timing ->> 'twoPhase')::boolean, false) then
      if v_standard_expired
         and pg_catalog.jsonb_typeof(v_state -> 'responses' -> v_question_key) = 'string' then
        v_text := v_state -> 'responses' ->> v_question_key;
      else
        v_text := v_submitted;
      end if;
      v_words := learning.count_words(v_text);
      if not v_standard_expired and v_words < v_min_words then
        raise exception using errcode = '22023', message = 'MINIMUM_WORDS_NOT_MET';
      end if;
      v_method := case when v_standard_expired then 'timer_expired' else 'manual' end;
    elsif not v_standard_expired then
      v_text := v_submitted;
      v_words := learning.count_words(v_text);
      if v_words < v_min_words then
        raise exception using errcode = '22023', message = 'MINIMUM_WORDS_NOT_MET';
      end if;
      v_method := 'manual';
      perform learning.record_knowledge_report_manual_standard(
        p_student_id, p_activity_version_id, v_text, null
      );
      select * into v_evidence
      from learning.knowledge_report_standard_evidence as evidence
      where evidence.student_id = p_student_id
        and evidence.activity_version_id = p_activity_version_id;
    elsif v_evidence.additional_time_started_at is not null
          and v_now >= v_evidence.additional_time_started_at
            + pg_catalog.make_interval(secs => v_additional_seconds) then
      if pg_catalog.jsonb_typeof(v_state -> 'responses' -> v_question_key) = 'string' then
        v_text := v_state -> 'responses' ->> v_question_key;
      else
        v_text := learning.knowledge_report_draft_text(v_state);
      end if;
      v_words := learning.count_words(v_text);
      v_method := 'additional_time_expired';
      v_additional_used := v_additional_seconds;
    elsif v_evidence.additional_time_started_at is not null then
      v_text := v_submitted;
      v_words := learning.count_words(v_text);
      if v_words < v_min_words then
        raise exception using errcode = '22023', message = 'MINIMUM_WORDS_NOT_MET';
      end if;
      v_method := 'manual';
      v_additional_used := least(
        v_additional_seconds,
        greatest(
          0,
          floor(extract(epoch from (v_now - v_evidence.additional_time_started_at)))::integer
        )
      );
    elsif coalesce(v_evidence.additional_time_eligible, false) then
      raise exception using errcode = '22023', message = 'ADDITIONAL_TIME_NOT_STARTED';
    else
      v_text := v_evidence.standard_text;
      v_words := v_evidence.standard_word_count;
      v_method := 'standard_time_complete';
    end if;

    v_item := pg_catalog.jsonb_set(
      v_item,
      '{response_payload}',
      pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'text', v_text,
        'wordCount', v_words,
        'minimumMet', v_words >= v_min_words,
        'elapsedSeconds', v_elapsed,
        'durationSeconds', v_duration,
        'submissionMethod', v_method,
        'standardTimeWordCount', case
          when coalesce((v_timing ->> 'twoPhase')::boolean, false) then v_evidence.standard_word_count
        end,
        'standardTimeText', case
          when coalesce((v_timing ->> 'twoPhase')::boolean, false) then v_evidence.standard_text
        end,
        'standardEndedAt', v_evidence.standard_ended_at,
        'additionalTimeEligible', case
          when coalesce((v_timing ->> 'twoPhase')::boolean, false) then coalesce(v_evidence.additional_time_eligible, false)
        end,
        'additionalTimeOffered', case
          when coalesce((v_timing ->> 'twoPhase')::boolean, false) then coalesce(v_evidence.additional_time_eligible, false)
        end,
        'additionalTimeStarted', case
          when coalesce((v_timing ->> 'twoPhase')::boolean, false) then v_evidence.additional_time_started_at is not null
        end,
        'additionalTimeStartedAt', v_evidence.additional_time_started_at,
        'additionalTimeSeconds', case
          when coalesce((v_timing ->> 'twoPhase')::boolean, false) and coalesce(v_evidence.additional_time_eligible, false)
          then v_additional_seconds
        end,
        'additionalTimeUsedSeconds', v_additional_used,
        'wordsAddedDuringAdditionalTime', case
          when v_evidence.additional_time_started_at is not null
          then v_words - v_evidence.standard_word_count
        end
      )),
      true
    );
    v_out := v_out || pg_catalog.jsonb_build_array(v_item);
  end loop;

  if not v_seen then
    raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
  end if;

  return v_out;
end;
$$;
drop function if exists api.save_activity_state(text, text, jsonb, timestamptz, text);

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
  v_spec jsonb;
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
    v_payload := v_payload - 'knowledgeReportPhase';
    v_spec := learning.timed_knowledge_report_spec(v_target.activity_version_id);
    if v_spec is not null and (
      v_existing.status = 'completed'
      or exists (
        select 1
        from learning.attempts as attempt
        where attempt.student_id = v_student_id
          and attempt.activity_version_id = v_target.activity_version_id
      )
    ) then
      return query
      select *
      from learning.activity_state_row(v_student_id, v_target.activity_version_id);
      return;
    end if;

    if v_spec is not null
       and learning.knowledge_report_now() >= v_existing.started_at
          + pg_catalog.make_interval(
            secs => coalesce((v_spec ->> 'durationSeconds')::integer, 0)
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
        return query
        select *
        from learning.activity_state_row(v_student_id, v_target.activity_version_id);
        return;
      end if;
    end if;

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


drop function if exists api.get_activity_state(text, text);

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

  perform learning.freeze_knowledge_report_standard_time(
    v_student_id,
    v_target.activity_version_id
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

create or replace function api.start_knowledge_report_additional_time(
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
  v_evidence learning.knowledge_report_standard_evidence%rowtype;
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

  v_evidence := learning.freeze_knowledge_report_standard_time(
    v_student_id,
    v_target.activity_version_id
  );

  if v_evidence.student_id is null
     or v_evidence.additional_time_eligible is not true
     or v_evidence.additional_time_started_at is not null then
    raise exception using errcode = '22023', message = 'ADDITIONAL_TIME_NOT_AVAILABLE';
  end if;

  update learning.knowledge_report_standard_evidence as evidence
  set additional_time_started_at = learning.knowledge_report_now()
  where evidence.student_id = v_student_id
    and evidence.activity_version_id = v_target.activity_version_id
    and evidence.additional_time_started_at is null;

  if not found then
    raise exception using errcode = '22023', message = 'ADDITIONAL_TIME_NOT_AVAILABLE';
  end if;

  return query
  select *
  from learning.activity_state_row(v_student_id, v_target.activity_version_id);
end;
$$;

revoke all on function api.start_knowledge_report_additional_time(text, text)
from public, anon;
grant execute on function api.start_knowledge_report_additional_time(text, text)
to authenticated;

comment on function api.start_knowledge_report_additional_time(text, text) is
  'Starts the single additional-time period after the server has captured a below-threshold standard-time snapshot. Does not start automatically.';

create or replace function platform.project_knowledge_report_activities(
  p_package jsonb,
  p_hub_code text,
  p_course_key text,
  p_package_version text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_course_id uuid;
  v_module_id uuid;
  v_year_id uuid;
  v_activity jsonb;
  v_report jsonb;
  v_activity_id text;
  v_activity_version text;
  v_duration integer;
  v_min_words integer;
  v_block jsonb;
  v_question_key text;
  v_activity_row_id uuid;
  v_version_id uuid;
  v_payload jsonb;
  v_hash text;
  v_count integer := 0;
  v_linked boolean;
begin
  select course.id
  into v_course_id
  from learning.courses as course
  where course.stable_key = p_course_key
    and course.active;

  if v_course_id is null then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;

  select module.id
  into v_module_id
  from learning.modules as module
  where module.course_id = v_course_id
    and module.stable_key = p_hub_code;

  if v_module_id is null then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;

  select academic_year.id
  into v_year_id
  from learning.academic_years as academic_year
  where academic_year.active
  order by academic_year.code
  limit 1;

  for v_activity in
    select value
    from pg_catalog.jsonb_array_elements(coalesce(p_package -> 'activities', '[]'::jsonb))
  loop
    v_report := v_activity -> 'metadata' -> 'knowledgeReport';
    if pg_catalog.jsonb_typeof(v_report) is distinct from 'object'
       or coalesce(v_report ->> 'placement', '') is distinct from 'knowledge-report' then
      continue;
    end if;

    v_activity_id := v_activity ->> 'id';
    v_activity_version := coalesce(v_activity ->> 'version', '');
    if v_activity_id is null
       or v_activity_id !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
       or v_activity_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;

    select exists (
      select 1
      from pg_catalog.jsonb_array_elements(coalesce(p_package -> 'sessions', '[]'::jsonb)) as session
      where session -> 'relationships' -> 'activities' ? v_activity_id
    )
    into v_linked;

    if v_linked then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;

    v_duration := coalesce((v_report ->> 'durationMinutes')::integer, 0) * 60;
    v_min_words := coalesce((v_report ->> 'minWords')::integer, 0);
    if v_duration <= 0 or v_min_words <= 0 then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;

    v_question_key := null;
    for v_block in
      select value
      from pg_catalog.jsonb_array_elements(coalesce(v_activity -> 'blocks', '[]'::jsonb))
    loop
      if coalesce(v_block ->> 'type', '') = 'short-response'
         and coalesce(v_block -> 'content' ->> 'questionId', '') ~ '^[A-Za-z0-9._:-]+$' then
        v_question_key := v_block -> 'content' ->> 'questionId';
        exit;
      end if;
    end loop;

    if v_question_key is null then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;

    v_payload := pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'stableKey', v_question_key,
        'questionType', 'text',
        'ordinal', 1,
        'marking', pg_catalog.jsonb_build_object(
          'mode', 'timed-knowledge-report',
          'durationSeconds', v_duration,
          'minWords', v_min_words
        ) || case
          when coalesce((v_report ->> 'additionalTimeMinutes')::integer, 0) > 0
           and coalesce((v_report ->> 'additionalTimeThresholdWords')::integer, 0) > 0
          then pg_catalog.jsonb_build_object(
            'additionalTimeSeconds', (v_report ->> 'additionalTimeMinutes')::integer * 60,
            'additionalTimeThresholdWords', (v_report ->> 'additionalTimeThresholdWords')::integer
          )
          else '{}'::jsonb
        end
      )
    );
    v_hash := encode(
      extensions.digest(
        pg_catalog.convert_to(
          pg_catalog.jsonb_build_object(
            'activityKey', v_activity_id,
            'questions', v_payload,
            'version', v_activity_version
          )::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );

    v_activity_row_id := platform.curriculum_catalogue_id('activity', v_activity_id);
    insert into learning.activities (
      id, module_id, stable_key, title, activity_type, git_path, active
    )
    values (
      v_activity_row_id,
      v_module_id,
      v_activity_id,
      coalesce(v_activity -> 'metadata' ->> 'title', v_activity_id),
      'knowledge-report',
      'content/activities/' || v_activity_id,
      true
    )
    on conflict (stable_key) do update set
      title = excluded.title,
      activity_type = excluded.activity_type,
      active = true;

    select activity.id
    into v_activity_row_id
    from learning.activities as activity
    where activity.stable_key = v_activity_id;

    v_version_id := platform.curriculum_catalogue_id(
      'version',
      v_activity_id || ':' || v_activity_version
    );

    insert into learning.activity_versions (
      id, activity_id, version, content_hash, max_score, question_count, published_at
    )
    values (
      v_version_id,
      v_activity_row_id,
      v_activity_version,
      v_hash,
      1,
      1,
      null
    )
    on conflict (activity_id, version) do nothing;

    select version.id
    into v_version_id
    from learning.activity_versions as version
    where version.activity_id = v_activity_row_id
      and version.version = v_activity_version;

    insert into learning.questions (
      id, activity_version_id, stable_key, section_key, section_title,
      question_type, analytics_title, ordinal, max_score
    )
    select
      platform.curriculum_catalogue_id(
        'question',
        v_activity_id || ':' || v_activity_version || ':' || v_question_key
      ),
      v_version_id,
      v_question_key,
      'knowledge-report',
      'Knowledge Report',
      'text',
      v_question_key,
      1,
      1
    from learning.activity_versions as version
    where version.id = v_version_id
      and version.published_at is null
    on conflict (activity_version_id, stable_key) do nothing;

    insert into learning.question_marking (question_id, spec)
    select
      question.id,
      pg_catalog.jsonb_build_object(
        'mode', 'timed-knowledge-report',
        'durationSeconds', v_duration,
        'minWords', v_min_words
      ) || case
          when coalesce((v_report ->> 'additionalTimeMinutes')::integer, 0) > 0
           and coalesce((v_report ->> 'additionalTimeThresholdWords')::integer, 0) > 0
          then pg_catalog.jsonb_build_object(
            'additionalTimeSeconds', (v_report ->> 'additionalTimeMinutes')::integer * 60,
            'additionalTimeThresholdWords', (v_report ->> 'additionalTimeThresholdWords')::integer
          )
          else '{}'::jsonb
        end
    from learning.questions as question
    join learning.activity_versions as version
      on version.id = question.activity_version_id
    where question.activity_version_id = v_version_id
      and question.stable_key = v_question_key
      and version.published_at is null
    on conflict (question_id) do nothing;

    update learning.activity_versions
    set published_at = pg_catalog.clock_timestamp()
    where id = v_version_id
      and published_at is null;

    if v_year_id is not null then
      if exists (
        select 1
        from learning.activity_delivery as delivery
        where delivery.activity_version_id = v_version_id
          and delivery.academic_year_id = v_year_id
          and delivery.group_id is null
      ) then
        update learning.activity_delivery
        set
          curriculum_week_id = null,
          week_number = null,
          session_number = null,
          sort_order = 0,
          active = true,
          updated_at = pg_catalog.clock_timestamp()
        where activity_version_id = v_version_id
          and academic_year_id = v_year_id
          and group_id is null;
      else
        insert into learning.activity_delivery (
          activity_version_id, academic_year_id, curriculum_week_id,
          week_number, session_number, sort_order, active
        )
        values (
          v_version_id,
          v_year_id,
          null,
          null,
          null,
          0,
          true
        );
      end if;

      insert into learning.activity_assignments (
        id, group_id, activity_version_id, required, active
      )
      select
        platform.curriculum_catalogue_id(
          'assignment',
          learner_group.code || ':' || v_activity_id || ':' || v_activity_version
        ),
        learner_group.id,
        v_version_id,
        true,
        true
      from learning.groups as learner_group
      where learner_group.course_id = v_course_id
        and learner_group.active
        and (
          exists (
            select 1
            from learning.activity_assignments as existing
            join learning.activity_versions as existing_version
              on existing_version.id = existing.activity_version_id
            join learning.activities as existing_activity
              on existing_activity.id = existing_version.activity_id
            where existing.group_id = learner_group.id
              and existing.active
              and existing_activity.module_id = v_module_id
          )
          or not exists (
            select 1
            from learning.activity_assignments as existing
            join learning.activity_versions as existing_version
              on existing_version.id = existing.activity_version_id
            join learning.activities as existing_activity
              on existing_activity.id = existing_version.activity_id
            join learning.modules as existing_module
              on existing_module.id = existing_activity.module_id
            where existing.group_id = learner_group.id
              and existing.active
              and existing_module.course_id = v_course_id
          )
        )
      on conflict (group_id, activity_version_id) do update set
        required = excluded.required,
        active = true;
    end if;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function platform.project_knowledge_report_activities(jsonb, text, text, text) from public, anon, authenticated;


drop function if exists admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, text, integer, integer
);
create or replace function admin_api.list_knowledge_report_cohort(
  p_hub_code text,
  p_course_key text default null,
  p_group_code text default null,
  p_student_number text default null,
  p_activity_key text default null,
  p_completion_status text default null,
  p_minimum_met text default null,
  p_review_status text default null,
  p_relevance text default null,
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  student_id uuid,
  student_number text,
  learner_name text,
  group_id uuid,
  group_code text,
  group_name text,
  course_key text,
  activity_id uuid,
  activity_key text,
  activity_version_id uuid,
  report_title text,
  assignment_id uuid,
  completion_status text,
  started_at timestamptz,
  duration_seconds integer,
  word_count integer,
  minimum_words integer,
  minimum_met boolean,
  elapsed_seconds integer,
  submission_method text,
  requires_review boolean,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  response_id uuid,
  overall_relevance text,
  repetition_flag boolean,
  standard_time_word_count integer,
  additional_time_eligible boolean,
  additional_time_started boolean,
  additional_time_used_seconds integer,
  words_added integer,
  additional_time_threshold_words integer,
  additional_time_allowance_seconds integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with visible as (
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
      )
      and (
        platform.current_staff_has_role('platform_admin')
        or exists (
          select 1
          from platform.hubs as readable_hub
          join platform.hub_group_links as readable_link
            on readable_link.hub_id = readable_hub.id
           and readable_link.active
          where readable_hub.hub_code = nullif(btrim(p_hub_code), '')
            and learning.teacher_can_access_group(readable_link.group_id)
        )
      )
  ),
  reports as (
    select
      activity.id as activity_id,
      activity.stable_key as activity_key,
      activity.title as report_title,
      version.id as activity_version_id,
      course.stable_key as course_key,
      (marking.spec ->> 'durationSeconds')::integer as duration_seconds,
      (marking.spec ->> 'minWords')::integer as minimum_words,
      coalesce((marking.spec ->> 'additionalTimeSeconds')::integer, 0) as additional_time_seconds,
      case
        when marking.spec ? 'additionalTimeThresholdWords'
          and (marking.spec ->> 'additionalTimeThresholdWords') ~ '^[0-9]+$'
          and (marking.spec ->> 'additionalTimeThresholdWords')::integer > 0
        then (marking.spec ->> 'additionalTimeThresholdWords')::integer
      end as additional_time_threshold_words,
      case
        when marking.spec ? 'additionalTimeSeconds'
          and (marking.spec ->> 'additionalTimeSeconds') ~ '^[0-9]+$'
          and (marking.spec ->> 'additionalTimeSeconds')::integer > 0
        then (marking.spec ->> 'additionalTimeSeconds')::integer
      end as additional_time_allowance_seconds
    from learning.activities as activity
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.retired_at is null
    join learning.questions as question
      on question.activity_version_id = version.id
    join learning.question_marking as marking
      on marking.question_id = question.id
     and marking.spec ->> 'mode' = 'timed-knowledge-report'
    join learning.modules as module
      on module.id = activity.module_id
    join learning.courses as course
      on course.id = module.course_id
    join platform.hub_course_links as course_link
      on course_link.course_id = course.id
     and course_link.active
    join platform.hubs as hub
      on hub.id = course_link.hub_id
     and hub.hub_code = nullif(btrim(p_hub_code), '')
     and hub.active
  ),
  cohort as (
    select
      student.id as student_id,
      student.student_number,
      student.display_name as learner_name,
      learner_group.id as group_id,
      learner_group.code as group_code,
      learner_group.name as group_name,
      report.course_key,
      report.activity_id,
      report.activity_key,
      report.activity_version_id,
      report.report_title,
      assignment.id as assignment_id,
      case
        when attempt.status = 'completed' and response.requires_review is false then 'reviewed'
        when attempt.status = 'completed' then 'submitted'
        when standard_evidence.additional_time_started_at is not null
          and report.additional_time_seconds > 0
          and standard_evidence.additional_time_started_at
            + make_interval(secs => report.additional_time_seconds) > pg_catalog.now()
          then 'in_progress'
        when standard_evidence.additional_time_eligible is true
          and standard_evidence.additional_time_started_at is null
          then 'in_progress'
        when sitting.started_at is not null
          and report.duration_seconds is not null
          and sitting.started_at + make_interval(secs => report.duration_seconds) <= pg_catalog.now()
          then 'time_elapsed'
        when sitting.student_id is not null
          or attempt.id is not null
          or coalesce(formative.formative_check_count, 0) > 0
          then 'in_progress'
        else 'not_started'
      end as completion_status,
      sitting.started_at,
      report.duration_seconds,
      report.additional_time_threshold_words,
      report.additional_time_allowance_seconds,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'wordCount')::integer
      end as word_count,
      report.minimum_words,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'minimumMet')::boolean
      end as minimum_met,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'elapsedSeconds')::integer
      end as elapsed_seconds,
      case
        when attempt.status = 'completed' then response.response_payload ->> 'submissionMethod'
      end as submission_method,
      case
        when attempt.status = 'completed' then response.requires_review
      end as requires_review,
      case
        when attempt.status = 'completed' then attempt.received_at
      end as submitted_at,
      case
        when attempt.status = 'completed' and response.requires_review is false then response.marked_at
      end as reviewed_at,
      case
        when attempt.status = 'completed' then response.id
      end as response_id,
      case when attempt.status = 'completed' then content_review.overall_relevance end as overall_relevance,
      case when attempt.status = 'completed' then content_review.repetition_flag end as repetition_flag,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'standardTimeWordCount')::integer
      end as standard_time_word_count,
      case
        when attempt.status = 'completed' and response.response_payload ? 'additionalTimeEligible'
          then (response.response_payload ->> 'additionalTimeEligible')::boolean
      end as additional_time_eligible,
      case
        when attempt.status = 'completed' and response.response_payload ? 'additionalTimeStarted'
          then (response.response_payload ->> 'additionalTimeStarted')::boolean
      end as additional_time_started,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'additionalTimeUsedSeconds')::integer
      end as additional_time_used_seconds,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'wordsAddedDuringAdditionalTime')::integer
      end as words_added
    from reports as report
    join learning.groups as learner_group
      on learner_group.active
    join visible
      on visible.group_id = learner_group.id
    join learning.enrolments as enrolment
      on enrolment.group_id = learner_group.id
     and enrolment.status = 'active'
    join learning.students as student
      on student.id = enrolment.student_id
     and student.active
    join learning.activity_assignments as assignment
      on assignment.id = coalesce(
        (
          select version_assignment.id
          from learning.activity_assignments as version_assignment
          where version_assignment.group_id = learner_group.id
            and version_assignment.activity_version_id = report.activity_version_id
            and version_assignment.active
          order by version_assignment.id
          limit 1
        ),
        learning.current_activity_assignment_id(learner_group.id, report.activity_id)
      )
     and assignment.active
    left join learning.activity_states as sitting
      on sitting.assignment_id = assignment.id
     and sitting.student_id = student.id
     and sitting.activity_version_id = report.activity_version_id
    left join learning.knowledge_report_standard_evidence as standard_evidence
      on standard_evidence.student_id = student.id
     and standard_evidence.activity_version_id = report.activity_version_id
    left join lateral (
      select attempt_row.*
      from learning.attempts as attempt_row
      where attempt_row.assignment_id = assignment.id
        and attempt_row.student_id = student.id
        and attempt_row.activity_version_id = report.activity_version_id
      order by attempt_row.received_at desc
      limit 1
    ) as attempt on true
    left join lateral (
      select response_row.*
      from learning.responses as response_row
      where response_row.attempt_id = attempt.id
      order by response_row.marked_at desc nulls last
      limit 1
    ) as response on true
    left join lateral (
      select count(*)::integer as formative_check_count
      from learning.formative_checks as formative_check
      where formative_check.assignment_id = assignment.id
        and formative_check.student_id = student.id
        and formative_check.activity_version_id = report.activity_version_id
    ) as formative on true
    left join lateral (
      select review.overall_relevance, review.repetition_flag
      from learning.knowledge_report_content_reviews as review
      where review.response_id = response.id
      order by review.analysed_at desc
      limit 1
    ) as content_review on true
    where (p_course_key is null or report.course_key = p_course_key)
      and (p_group_code is null or learner_group.code = p_group_code)
      and (p_student_number is null or student.student_number = p_student_number)
      and (p_activity_key is null or report.activity_key = p_activity_key)
  )
  select
    cohort.student_id,
    cohort.student_number,
    cohort.learner_name,
    cohort.group_id,
    cohort.group_code,
    cohort.group_name,
    cohort.course_key,
    cohort.activity_id,
    cohort.activity_key,
    cohort.activity_version_id,
    cohort.report_title,
    cohort.assignment_id,
    cohort.completion_status,
    cohort.started_at,
    cohort.duration_seconds,
    cohort.word_count,
    cohort.minimum_words,
    cohort.minimum_met,
    cohort.elapsed_seconds,
    cohort.submission_method,
    cohort.requires_review,
    cohort.submitted_at,
    cohort.reviewed_at,
    cohort.response_id,
    cohort.overall_relevance,
    cohort.repetition_flag,
    cohort.standard_time_word_count,
    cohort.additional_time_eligible,
    cohort.additional_time_started,
    cohort.additional_time_used_seconds,
    cohort.words_added,
    cohort.additional_time_threshold_words,
    cohort.additional_time_allowance_seconds
  from cohort
  where (p_completion_status is null or cohort.completion_status = p_completion_status)
    and (
      p_minimum_met is null
      or (p_minimum_met = 'met' and cohort.minimum_met is true)
      or (p_minimum_met = 'not_reached' and cohort.minimum_met is false)
    )
    and (
      p_review_status is null
      or (p_review_status = 'needs_review' and cohort.requires_review is true)
      or (p_review_status = 'reviewed' and cohort.completion_status = 'reviewed')
    )
    and (p_relevance is null or cohort.overall_relevance = p_relevance)
  order by cohort.learner_name, cohort.activity_key, cohort.student_number
  limit least(greatest(coalesce(p_limit, 500), 0), 1000)
  offset greatest(coalesce(p_offset, 0), 0);
$$;


comment on function admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, text, integer, integer
) is
  'Assigned knowledge-report cohort for staff-visible hub groups. Returns sitting timing and submitted metadata only. Never returns draft state_payload or report text.';

revoke all on function admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, text, integer, integer
) from public, anon, authenticated;

grant execute on function admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, text, integer, integer
) to authenticated;

revoke all on function api.save_activity_state(text, text, jsonb, timestamptz, text)
from public, anon;
grant execute on function api.save_activity_state(text, text, jsonb, timestamptz, text)
to authenticated;

revoke all on function api.get_activity_state(text, text)
from public, anon;
grant execute on function api.get_activity_state(text, text)
to authenticated;
