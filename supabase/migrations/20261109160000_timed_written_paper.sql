-- Timed written papers reuse the knowledge-report sitting machinery.
-- The original report path is unchanged: assessmentType is absent, so the
-- word-count rule and 15-minute additional time are not touched.
-- This migration does not create learning.lo12_exam_records.

drop function if exists admin_api.list_lo12_exam_practice();
drop function if exists admin_api.finalise_lo12_marks(uuid);
drop function if exists admin_api.save_lo12_marks(uuid, jsonb, jsonb);
drop function if exists admin_api.set_lo12_extra_time(uuid, integer);
drop function if exists api.get_lo12_exam_practice();
drop function if exists api.save_lo12_reflection(jsonb);
drop function if exists api.save_lo12_answer_writing(jsonb);
drop function if exists api.submit_lo12_mini_mock(text);
drop function if exists api.save_lo12_mini_mock(jsonb);
drop function if exists api.start_lo12_mini_mock();
drop function if exists learning.lo12_learner_record(learning.lo12_exam_records);
drop function if exists learning.lo12_question_max(text);
drop table if exists learning.lo12_exam_records;
drop table if exists learning.lo12_time_allowances;

create table if not exists learning.timed_paper_allowances (
  student_id uuid not null references learning.students (id) on delete restrict,
  activity_version_id uuid not null references learning.activity_versions (id) on delete restrict,
  extra_seconds integer not null,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (student_id, activity_version_id),
  constraint timed_paper_extra_seconds_valid check (extra_seconds between 0 and 3600)
);

create table if not exists learning.timed_paper_releases (
  attempt_id uuid primary key references learning.attempts (id) on delete restrict,
  released_at timestamptz not null default pg_catalog.clock_timestamp()
);

alter table learning.timed_paper_allowances enable row level security;
alter table learning.timed_paper_releases enable row level security;
revoke all on learning.timed_paper_allowances from public, anon, authenticated;
revoke all on learning.timed_paper_releases from public, anon, authenticated;

comment on table learning.timed_paper_allowances is
  'Teacher-set extra seconds for a timed written paper. Not used by the word-count knowledge report.';

create or replace function learning.effective_timed_duration_seconds(
  p_student_id uuid,
  p_activity_version_id uuid,
  p_spec jsonb
)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((p_spec ->> 'durationSeconds')::integer, 0)
    + case
        when coalesce(p_spec ->> 'assessmentType', '') = 'timed-written-paper'
        then coalesce((
          select allowance.extra_seconds
          from learning.timed_paper_allowances as allowance
          where allowance.student_id = p_student_id
            and allowance.activity_version_id = p_activity_version_id
        ), 0)
        else 0
      end
$$;

revoke all on function learning.effective_timed_duration_seconds(uuid, uuid, jsonb)
from public, anon, authenticated;

create or replace function learning.prepare_timed_written_paper(
  p_student_id uuid,
  p_activity_version_id uuid,
  p_responses jsonb,
  p_spec jsonb,
  p_timing_question_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_duration integer;
  v_started timestamptz;
  v_state jsonb;
  v_now timestamptz := learning.knowledge_report_now();
  v_expired boolean;
  v_item jsonb;
  v_key text;
  v_text text;
  v_out jsonb := '[]'::jsonb;
  v_seen boolean := false;
begin
  v_duration := learning.effective_timed_duration_seconds(p_student_id, p_activity_version_id, p_spec);
  if v_duration <= 0 then
    raise exception using errcode = '22023', message = 'TIMED_REPORT_NOT_CONFIGURED';
  end if;
  if exists (
    select 1 from learning.attempts as attempt
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
  v_expired := v_now >= v_started + pg_catalog.make_interval(secs => v_duration);
  for v_item in select value from pg_catalog.jsonb_array_elements(p_responses)
  loop
    v_key := v_item ->> 'question_id';
    if v_key is null or v_key = '' then
      raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
    end if;
    if v_key = p_timing_question_key then
      v_seen := true;
    end if;
    -- Expiry locks every question on the paper, including questions that do not
    -- carry the duration specification. Unsaved questions stay blank.
    if v_expired then
      if pg_catalog.jsonb_typeof(v_state -> 'responses' -> v_key) = 'string' then
        v_text := v_state -> 'responses' ->> v_key;
      else
        v_text := '';
      end if;
    elsif pg_catalog.jsonb_typeof(v_item -> 'response_payload') = 'string' then
      v_text := coalesce(v_item ->> 'response_payload', '');
    else
      v_text := coalesce(v_item -> 'response_payload' ->> 'text', '');
    end if;
    v_item := pg_catalog.jsonb_set(
      v_item,
      '{response_payload}',
      pg_catalog.jsonb_build_object(
        'text', v_text,
        'submissionMethod', case when v_expired then 'timer_expired' else 'manual' end,
        'durationSeconds', v_duration
      ),
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

revoke all on function learning.prepare_timed_written_paper(uuid, uuid, jsonb, jsonb, text)
from public, anon, authenticated;

create or replace function learning.timed_written_paper_phase_overlay(
  p_student_id uuid,
  p_activity_version_id uuid,
  p_state jsonb,
  p_spec jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_started timestamptz;
  v_duration integer;
  v_now timestamptz := learning.knowledge_report_now();
  v_phase text := 'standard';
begin
  v_duration := learning.effective_timed_duration_seconds(p_student_id, p_activity_version_id, p_spec);
  select draft.started_at into v_started
  from learning.activity_states as draft
  where draft.student_id = p_student_id
    and draft.activity_version_id = p_activity_version_id;
  if exists (
    select 1 from learning.attempts as attempt
    where attempt.student_id = p_student_id
      and attempt.activity_version_id = p_activity_version_id
  ) then
    v_phase := 'submitted';
  elsif v_started is not null and v_now >= v_started + make_interval(secs => v_duration) then
    v_phase := 'standard_expired';
  end if;
  return coalesce(p_state, '{}'::jsonb) || jsonb_build_object(
    'knowledgeReportPhase',
    jsonb_build_object(
      'phase', v_phase,
      'assessmentType', 'timed-written-paper',
      'standardDurationSeconds', v_duration,
      'serverNow', v_now,
      'authoritativeStartedAt', v_started
    )
  );
end;
$$;

revoke all on function learning.timed_written_paper_phase_overlay(uuid, uuid, jsonb, jsonb)
from public, anon, authenticated;


create or replace function platform.project_timed_written_papers(
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
declare
  v_course_id uuid;
  v_module_id uuid;
  v_year_id uuid;
  v_activity jsonb;
  v_report jsonb;
  v_block jsonb;
  v_activity_id text;
  v_activity_version text;
  v_duration integer;
  v_question_key text;
  v_ordinal integer;
  v_marks integer;
  v_total integer;
  v_count integer := 0;
  v_questions jsonb;
  v_activity_row_id uuid;
  v_version_id uuid;
  v_first_key text;
  v_linked boolean;
begin
  select course.id into v_course_id
  from learning.courses as course
  where course.stable_key = p_course_key and course.active;
  if v_course_id is null then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;
  select module.id into v_module_id
  from learning.modules as module
  where module.course_id = v_course_id and module.stable_key = p_hub_code;
  if v_module_id is null then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;
  select academic_year.id into v_year_id
  from learning.academic_years as academic_year
  where academic_year.active
  order by academic_year.code
  limit 1;

  for v_activity in
    select value from jsonb_array_elements(coalesce(p_package -> 'activities', '[]'::jsonb))
  loop
    v_report := v_activity -> 'metadata' -> 'knowledgeReport';
    if jsonb_typeof(v_report) is distinct from 'object'
       or coalesce(v_report ->> 'placement', '') is distinct from 'knowledge-report'
       or coalesce(v_report ->> 'assessmentType', '') is distinct from 'timed-written-paper' then
      continue;
    end if;
    if coalesce((v_report ->> 'minWords')::integer, 0) <> 0
       or coalesce((v_report ->> 'additionalTimeMinutes')::integer, 0) <> 0
       or coalesce((v_report ->> 'additionalTimeThresholdWords')::integer, 0) <> 0 then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;
    v_activity_id := v_activity ->> 'id';
    v_activity_version := coalesce(v_activity ->> 'version', '');
    v_duration := coalesce((v_report ->> 'durationMinutes')::integer, 0) * 60;
    if v_activity_id is null or v_duration <= 0 then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;
    select exists (
      select 1 from jsonb_array_elements(coalesce(p_package -> 'sessions', '[]'::jsonb)) as session
      where session -> 'relationships' -> 'activities' ? v_activity_id
    ) into v_linked;
    if v_linked then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;
    v_questions := '[]'::jsonb;
    v_ordinal := 0;
    v_total := 0;
    v_first_key := null;
    for v_block in
      select value from jsonb_array_elements(coalesce(v_activity -> 'blocks', '[]'::jsonb))
    loop
      if coalesce(v_block ->> 'type', '') is distinct from 'short-response' then
        continue;
      end if;
      v_question_key := v_block -> 'content' ->> 'questionId';
      v_marks := coalesce((v_block -> 'content' ->> 'maxMarks')::integer, 0);
      if v_question_key is null or v_question_key !~ '^[A-Za-z0-9._:-]+$' or v_marks <= 0 then
        raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
      end if;
      v_ordinal := v_ordinal + 1;
      v_total := v_total + v_marks;
      if v_first_key is null then
        v_first_key := v_question_key;
      end if;
      v_questions := v_questions || jsonb_build_array(jsonb_build_object(
        'stableKey', v_question_key,
        'ordinal', v_ordinal,
        'maxMarks', v_marks
      ));
    end loop;
    if v_ordinal < 2 or v_first_key is null then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;

    v_activity_row_id := platform.curriculum_catalogue_id('activity', v_activity_id);
    insert into learning.activities (id, module_id, stable_key, title, activity_type, git_path, active)
    values (
      v_activity_row_id, v_module_id, v_activity_id,
      coalesce(v_activity -> 'metadata' ->> 'title', v_activity_id),
      'timed-written-paper', 'content/activities/' || v_activity_id, true
    )
    on conflict (stable_key) do update set title = excluded.title, activity_type = excluded.activity_type, active = true;
    select activity.id into v_activity_row_id from learning.activities as activity where activity.stable_key = v_activity_id;
    v_version_id := platform.curriculum_catalogue_id('version', v_activity_id || ':' || v_activity_version);
    insert into learning.activity_versions (id, activity_id, version, content_hash, max_score, question_count, published_at)
    values (
      v_version_id,
      v_activity_row_id,
      v_activity_version,
      encode(extensions.digest(convert_to(v_activity_id || ':' || v_activity_version || ':' || v_questions::text, 'UTF8'), 'sha256'), 'hex'),
      v_total,
      v_ordinal,
      null
    )
    on conflict (activity_id, version) do nothing;
    select version.id into v_version_id
    from learning.activity_versions as version
    where version.activity_id = v_activity_row_id and version.version = v_activity_version;

    for v_block in select value from jsonb_array_elements(v_questions)
    loop
      insert into learning.questions (
        id, activity_version_id, stable_key, section_key, section_title,
        question_type, analytics_title, ordinal, max_score
      )
      select
        platform.curriculum_catalogue_id('question', v_activity_id || ':' || v_activity_version || ':' || (v_block ->> 'stableKey')),
        v_version_id,
        v_block ->> 'stableKey',
        'timed-written-paper',
        'Timed written paper',
        'text',
        v_block ->> 'stableKey',
        (v_block ->> 'ordinal')::integer,
        (v_block ->> 'maxMarks')::integer
      from learning.activity_versions as version
      where version.id = v_version_id and version.published_at is null
      on conflict (activity_version_id, stable_key) do nothing;

      insert into learning.question_marking (question_id, spec)
      select question.id,
        case
          when question.stable_key = v_first_key then jsonb_build_object(
            'mode', 'timed-knowledge-report',
            'assessmentType', 'timed-written-paper',
            'durationSeconds', v_duration,
            'minWords', 0
          )
          else jsonb_build_object(
            'mode', 'completion',
            'assessmentType', 'timed-written-paper'
          )
        end
      from learning.questions as question
      join learning.activity_versions as version on version.id = question.activity_version_id
      where question.activity_version_id = v_version_id
        and question.stable_key = v_block ->> 'stableKey'
        and version.published_at is null
      on conflict (question_id) do nothing;
    end loop;

    if v_year_id is not null then
      if not exists (
        select 1 from learning.activity_delivery as delivery
        where delivery.activity_version_id = v_version_id
          and delivery.academic_year_id = v_year_id
          and delivery.group_id is null
      ) then
        insert into learning.activity_delivery (
          activity_version_id, academic_year_id, curriculum_week_id,
          week_number, session_number, sort_order, active
        ) values (v_version_id, v_year_id, null, null, null, 0, true);
      end if;
      insert into learning.activity_assignments (
        id, group_id, activity_version_id, required, active
      )
      select
        platform.curriculum_catalogue_id('assignment', learner_group.code || ':' || v_activity_id || ':' || v_activity_version),
        learner_group.id, v_version_id, true, true
      from learning.groups as learner_group
      where learner_group.course_id = v_course_id and learner_group.active
      on conflict (group_id, activity_version_id) do update set active = true;
    end if;

    update learning.activity_versions
    set published_at = clock_timestamp()
    where id = v_version_id and published_at is null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function platform.project_timed_written_papers(jsonb, text, text, text)
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

  if coalesce(v_spec ->> 'assessmentType', '') = 'timed-written-paper' then
    return learning.prepare_timed_written_paper(
      p_student_id,
      p_activity_version_id,
      p_responses,
      v_spec,
      v_question_key
    );
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
  v_spec := learning.timed_knowledge_report_spec(v_target.activity_version_id);
  if coalesce(v_spec ->> 'assessmentType', '') = 'timed-written-paper' then
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
    and draft.activity_version_id = v_target.activity_version_id;

  if found then
    v_payload := v_payload - 'knowledgeReportPhase';
    if coalesce(v_spec ->> 'assessmentType', '') = 'timed-written-paper' then
      v_payload := v_payload - 'startedAt';
    end if;
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
  if coalesce(v_spec ->> 'assessmentType', '') = 'timed-written-paper' then
    return learning.timed_written_paper_phase_overlay(
      p_student_id,
      p_activity_version_id,
      p_state,
      v_spec
    );
  end if;

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

    if coalesce(v_report ->> 'assessmentType', 'timed-knowledge-report') = 'timed-written-paper' then
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

  return v_count + platform.project_timed_written_papers(
    p_package,
    p_hub_code,
    p_course_key,
    p_package_version
  ) + platform.project_unscheduled_activities(
    p_package,
    p_hub_code,
    p_course_key,
    p_package_version
  );
end;
$$;

create or replace function platform.project_unscheduled_activities(
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
declare
  v_course_id uuid;
  v_module_id uuid;
  v_year_id uuid;
  v_activity jsonb;
  v_block jsonb;
  v_activity_id text;
  v_activity_version text;
  v_question_key text;
  v_activity_row_id uuid;
  v_version_id uuid;
  v_ordinal integer;
  v_count integer := 0;
  v_questions jsonb;
begin
  select course.id into v_course_id
  from learning.courses as course
  where course.stable_key = p_course_key and course.active;
  if v_course_id is null then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;
  select module.id into v_module_id
  from learning.modules as module
  where module.course_id = v_course_id and module.stable_key = p_hub_code;
  if v_module_id is null then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;
  select academic_year.id into v_year_id
  from learning.academic_years as academic_year
  where academic_year.active
  order by academic_year.code
  limit 1;

  for v_activity in
    select value from jsonb_array_elements(coalesce(p_package -> 'activities', '[]'::jsonb))
  loop
    if coalesce(v_activity -> 'metadata' ->> 'cataloguePlacement', '') is distinct from 'unscheduled' then
      continue;
    end if;
    if jsonb_typeof(v_activity -> 'metadata' -> 'knowledgeReport') = 'object' then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;
    v_activity_id := v_activity ->> 'id';
    v_activity_version := coalesce(v_activity ->> 'version', '');
    if v_activity_id is null or v_activity_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;
    v_questions := '[]'::jsonb;
    v_ordinal := 0;
    for v_block in
      select value from jsonb_array_elements(coalesce(v_activity -> 'blocks', '[]'::jsonb))
    loop
      if coalesce(v_block ->> 'type', '') not in ('short-response', 'reflection') then
        continue;
      end if;
      v_question_key := v_block -> 'content' ->> 'questionId';
      if v_question_key is null or v_question_key !~ '^[A-Za-z0-9._:-]+$' then
        raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
      end if;
      v_ordinal := v_ordinal + 1;
      v_questions := v_questions || jsonb_build_array(jsonb_build_object(
        'stableKey', v_question_key,
        'ordinal', v_ordinal
      ));
    end loop;
    if v_ordinal < 1 then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
    end if;
    v_activity_row_id := platform.curriculum_catalogue_id('activity', v_activity_id);
    insert into learning.activities (id, module_id, stable_key, title, activity_type, git_path, active)
    values (
      v_activity_row_id, v_module_id, v_activity_id,
      coalesce(v_activity -> 'metadata' ->> 'title', v_activity_id),
      'practice', 'content/activities/' || v_activity_id, true
    )
    on conflict (stable_key) do update set title = excluded.title, active = true;
    select activity.id into v_activity_row_id from learning.activities as activity where activity.stable_key = v_activity_id;
    v_version_id := platform.curriculum_catalogue_id('version', v_activity_id || ':' || v_activity_version);
    insert into learning.activity_versions (id, activity_id, version, content_hash, max_score, question_count, published_at)
    values (
      v_version_id, v_activity_row_id, v_activity_version,
      encode(extensions.digest(convert_to(v_activity_id || ':' || v_activity_version || ':' || v_questions::text, 'UTF8'), 'sha256'), 'hex'),
      v_ordinal, v_ordinal, null
    )
    on conflict (activity_id, version) do nothing;
    select version.id into v_version_id
    from learning.activity_versions as version
    where version.activity_id = v_activity_row_id and version.version = v_activity_version;
    for v_block in select value from jsonb_array_elements(v_questions)
    loop
      insert into learning.questions (
        id, activity_version_id, stable_key, section_key, section_title,
        question_type, analytics_title, ordinal, max_score
      )
      select
        platform.curriculum_catalogue_id('question', v_activity_id || ':' || v_activity_version || ':' || (v_block ->> 'stableKey')),
        v_version_id, v_block ->> 'stableKey', 'practice', 'Practice', 'text', v_block ->> 'stableKey',
        (v_block ->> 'ordinal')::integer, 1
      where exists (
        select 1 from learning.activity_versions as version
        where version.id = v_version_id and version.published_at is null
      )
      on conflict (activity_version_id, stable_key) do nothing;
      insert into learning.question_marking (question_id, spec)
      select question.id, jsonb_build_object('mode', 'completion')
      from learning.questions as question
      join learning.activity_versions as version on version.id = question.activity_version_id
      where question.activity_version_id = v_version_id
        and question.stable_key = v_block ->> 'stableKey'
        and version.published_at is null
      on conflict (question_id) do nothing;
    end loop;
    if v_year_id is not null then
      if not exists (
        select 1 from learning.activity_delivery as delivery
        where delivery.activity_version_id = v_version_id
          and delivery.academic_year_id = v_year_id and delivery.group_id is null
      ) then
        insert into learning.activity_delivery (
          activity_version_id, academic_year_id, curriculum_week_id,
          week_number, session_number, sort_order, active
        ) values (v_version_id, v_year_id, null, null, null, 0, true);
      end if;
      insert into learning.activity_assignments (id, group_id, activity_version_id, required, active)
      select
        platform.curriculum_catalogue_id('assignment', learner_group.code || ':' || v_activity_id || ':' || v_activity_version),
        learner_group.id, v_version_id, false, true
      from learning.groups as learner_group
      where learner_group.course_id = v_course_id and learner_group.active
      on conflict (group_id, activity_version_id) do update set active = true;
    end if;
    update learning.activity_versions
    set published_at = clock_timestamp()
    where id = v_version_id and published_at is null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function platform.project_unscheduled_activities(jsonb, text, text, text) from public, anon, authenticated;



create or replace function admin_api.set_timed_paper_allowance(
  p_activity_key text,
  p_activity_version text,
  p_student_id uuid,
  p_extra_seconds integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_teacher learning.teachers%rowtype;
  v_version_id uuid;
  v_spec jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;
  select * into v_teacher from learning.teachers where auth_user_id = auth.uid() and active;
  if not found then
    raise exception using errcode = '28000', message = 'REVIEW_NOT_AUTHORISED';
  end if;
  select version.id into v_version_id
  from learning.activity_versions as version
  join learning.activities as activity on activity.id = version.activity_id
  where activity.stable_key = p_activity_key and version.version = p_activity_version;
  v_spec := learning.timed_knowledge_report_spec(v_version_id);
  if coalesce(v_spec ->> 'assessmentType', '') is distinct from 'timed-written-paper' then
    raise exception using errcode = '22023', message = 'TIMED_PAPER_ALLOWANCE_NOT_SUPPORTED';
  end if;
  insert into learning.timed_paper_allowances (student_id, activity_version_id, extra_seconds)
  values (p_student_id, v_version_id, greatest(0, least(coalesce(p_extra_seconds, 0), 3600)))
  on conflict (student_id, activity_version_id) do update
  set extra_seconds = excluded.extra_seconds, updated_at = clock_timestamp();
end;
$$;

create or replace function admin_api.release_timed_paper_results(p_attempt_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_teacher learning.teachers%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;
  select * into v_teacher from learning.teachers where auth_user_id = auth.uid() and active;
  if not found then
    raise exception using errcode = '28000', message = 'REVIEW_NOT_AUTHORISED';
  end if;
  insert into learning.timed_paper_releases (attempt_id)
  values (p_attempt_id)
  on conflict (attempt_id) do nothing;
end;
$$;

revoke all on function admin_api.set_timed_paper_allowance(text, text, uuid, integer) from public, anon;
revoke all on function admin_api.release_timed_paper_results(uuid) from public, anon;
grant execute on function admin_api.set_timed_paper_allowance(text, text, uuid, integer) to authenticated;
grant execute on function admin_api.release_timed_paper_results(uuid) to authenticated;

create or replace function learning.timed_paper_results_hidden(p_attempt_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from learning.attempts as attempt
    join learning.questions as question
      on question.activity_version_id = attempt.activity_version_id
    join learning.question_marking as marking
      on marking.question_id = question.id
    where attempt.id = p_attempt_id
      and coalesce(marking.spec ->> 'assessmentType', '') = 'timed-written-paper'
  )
  and not exists (
    select 1 from learning.timed_paper_releases as release
    where release.attempt_id = p_attempt_id
  );
$$;

revoke all on function learning.timed_paper_results_hidden(uuid) from public, anon;
grant execute on function learning.timed_paper_results_hidden(uuid) to authenticated;

create or replace function learning.timed_paper_feedback_visible(p_attempt_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from learning.attempts as attempt
    join learning.questions as question
      on question.activity_version_id = attempt.activity_version_id
    join learning.question_marking as marking
      on marking.question_id = question.id
    where attempt.id = p_attempt_id
      and coalesce(marking.spec ->> 'assessmentType', '') = 'timed-written-paper'
  )
  and exists (
    select 1 from learning.timed_paper_releases as release
    where release.attempt_id = p_attempt_id
  );
$$;

revoke all on function learning.timed_paper_feedback_visible(uuid) from public, anon;
grant execute on function learning.timed_paper_feedback_visible(uuid) to authenticated;

create or replace view api.my_responses
with (security_invoker = true)
as
select
  response.id as response_id,
  response.attempt_id,
  question.stable_key as question_key,
  question.section_key,
  response.response_payload,
  case
    when learning.timed_paper_results_hidden(attempt.id) then null::numeric(8,2)
    else response.awarded_score
  end as awarded_score,
  response.max_score,
  case
    when learning.timed_paper_results_hidden(attempt.id) then null::boolean
    else response.is_correct
  end as is_correct,
  case
    when learning.timed_paper_results_hidden(attempt.id) then null::text
    else response.marking_source
  end as marking_source,
  case
    when learning.timed_paper_results_hidden(attempt.id) then null::timestamptz
    else response.marked_at
  end as marked_at,
  case
    when learning.timed_paper_feedback_visible(attempt.id) then response.feedback_summary
    else null::text
  end as feedback_summary
from learning.responses as response
join learning.attempts as attempt on attempt.id = response.attempt_id
join learning.questions as question on question.id = response.question_id
where attempt.student_id = (select learning.current_student_id());

grant select on api.my_responses to authenticated;
