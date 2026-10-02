-- Timed knowledge reports sit outside week/session delivery.
-- Finished written evidence may be up to 128 KiB.
-- The server started_at is the sitting clock. One attempt. Manual submit
-- requires the configured minimum word count. Timer expiry accepts any length.

alter table learning.responses
  drop constraint response_payload_size_valid;

alter table learning.responses
  add constraint response_payload_size_valid
  check (octet_length(response_payload::text) <= 131072);

create function learning.count_words(p_text text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select count(*)::integer
  from pg_catalog.regexp_matches(coalesce(p_text, ''), '\S+', 'g')
$$;

create function learning.knowledge_report_draft_text(p_state jsonb)
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

create function learning.timed_knowledge_report_spec(p_activity_version_id uuid)
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

create function learning.prepare_timed_knowledge_report_submission(
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
  v_question_key text;
  v_duration integer;
  v_min_words integer;
  v_started timestamptz;
  v_state jsonb;
  v_expired boolean;
  v_elapsed integer;
  v_item jsonb;
  v_submitted text;
  v_text text;
  v_words integer;
  v_out jsonb := '[]'::jsonb;
  v_seen boolean := false;
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

  v_duration := coalesce((v_spec ->> 'durationSeconds')::integer, 0);
  v_min_words := coalesce((v_spec ->> 'minWords')::integer, 0);
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

  v_expired := pg_catalog.clock_timestamp() >= v_started + pg_catalog.make_interval(secs => v_duration);
  v_elapsed := least(
    v_duration,
    greatest(
      0,
      floor(extract(epoch from (pg_catalog.clock_timestamp() - v_started)))::integer
    )
  );

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

    if v_expired
       and pg_catalog.jsonb_typeof(v_state -> 'responses' -> v_question_key) = 'string' then
      v_text := v_state -> 'responses' ->> v_question_key;
    else
      v_text := v_submitted;
    end if;

    v_words := learning.count_words(v_text);
    if not v_expired and v_words < v_min_words then
      raise exception using errcode = '22023', message = 'MINIMUM_WORDS_NOT_MET';
    end if;

    v_item := pg_catalog.jsonb_set(
      v_item,
      '{response_payload}',
      pg_catalog.jsonb_build_object(
        'text', v_text,
        'wordCount', v_words,
        'minimumMet', v_words >= v_min_words,
        'elapsedSeconds', v_elapsed,
        'durationSeconds', v_duration,
        'submissionMethod', case when v_expired then 'timer_expired' else 'manual' end
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

create function platform.project_knowledge_report_activities(
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
        )
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
      )
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

revoke all on function learning.count_words(text) from public, anon, authenticated;
revoke all on function learning.knowledge_report_draft_text(jsonb) from public, anon, authenticated;
revoke all on function learning.timed_knowledge_report_spec(uuid) from public, anon, authenticated;
revoke all on function learning.prepare_timed_knowledge_report_submission(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function platform.project_knowledge_report_activities(jsonb, text, text, text) from public, anon, authenticated;

comment on function learning.prepare_timed_knowledge_report_submission(uuid, uuid, jsonb) is
  'Rewrites a timed knowledge report submission with server word count, elapsed time, duration and submission method. Manual submit below the minimum is rejected. Timer expiry keeps the latest accepted draft.';

comment on function platform.project_knowledge_report_activities(jsonb, text, text, text) is
  'Catalogues knowledge-report activities that are not listed on a session. Delivery week and session stay null. Does not change week or session activities.';

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
    v_spec := learning.timed_knowledge_report_spec(v_target.activity_version_id);
    if v_spec is not null
       and (
         v_existing.status = 'completed'
         or exists (
           select 1
           from learning.attempts as attempt
           where attempt.student_id = v_student_id
             and attempt.activity_version_id = v_target.activity_version_id
         )
         or pg_catalog.clock_timestamp() >= v_existing.started_at
            + pg_catalog.make_interval(
              secs => coalesce((v_spec ->> 'durationSeconds')::integer, 0)
            )
       ) then
      return query
      select *
      from learning.activity_state_row(v_student_id, v_target.activity_version_id);
      return;
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

create or replace function api.submit_attempt(
  p_activity_key text,
  p_activity_version text,
  p_client_attempt_id text,
  p_responses jsonb,
  p_source_page text default null,
  p_started_at timestamptz default null,
  p_completed_at timestamptz default null,
  p_programming_language text default null
)
returns table (
  attempt_id uuid,
  client_attempt_id text,
  activity_key text,
  activity_version text,
  attempt_number integer,
  score numeric(8,2),
  max_score numeric(8,2),
  marking_source text,
  evidence_level text,
  client_started_at timestamptz,
  client_completed_at timestamptz,
  source_page text,
  programming_language text,
  received_at timestamptz,
  idempotent boolean
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_student_id uuid;
  v_enrolment_id uuid;
  v_matching_assignment_count integer;
  v_activity_version_id uuid;
  v_assignment_id uuid;
  v_question_count integer;
  v_activity_max_score numeric(8,2);
  v_programming_language_id uuid;
  v_declared_language_count integer;
  v_attempt_id uuid;
  v_attempt_number integer;
  v_submission_hash text;
  v_existing learning.attempts%rowtype;
  v_item jsonb;
  v_question learning.questions%rowtype;
  v_question_key text;
  v_awarded_score numeric(8,2);
  v_is_correct boolean;
  v_requires_review boolean;
  v_has_score boolean;
  v_has_correct boolean;
  v_marking_source text;
  v_item_source text;
  v_marked jsonb := '[]'::jsonb;
  v_mark jsonb;
  v_total_score numeric(8,2) := 0;
  v_received_at timestamptz;
  v_source_page text;
begin
  v_auth_user_id := auth.uid();
  v_received_at := clock_timestamp();
  v_source_page := nullif(btrim(p_source_page), '');

  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if p_activity_key is null or btrim(p_activity_key) = ''
     or p_activity_version is null or btrim(p_activity_version) = '' then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_VERSION';
  end if;

  if p_client_attempt_id is null
     or length(p_client_attempt_id) not between 1 and 128
     or p_client_attempt_id !~ '^[A-Za-z0-9._:-]+$' then
    raise exception using errcode = '22023', message = 'INVALID_CLIENT_ATTEMPT_ID';
  end if;

  if p_responses is null
     or jsonb_typeof(p_responses) <> 'array'
     or jsonb_array_length(p_responses) = 0
     or octet_length(p_responses::text) > 131072 then
    raise exception using errcode = '22023', message = 'INVALID_RESPONSES';
  end if;

  if (p_started_at is null) <> (p_completed_at is null)
     or (
       p_started_at is not null
       and (
         p_completed_at < p_started_at
         or p_completed_at - p_started_at > interval '30 days'
         or p_started_at > v_received_at + interval '5 minutes'
         or p_completed_at > v_received_at + interval '5 minutes'
       )
     ) then
    raise exception using errcode = '22023', message = 'INVALID_CLIENT_TIMESTAMPS';
  end if;

  if v_source_page is not null
     and (
       length(v_source_page) > 300
       or v_source_page !~ '^/'
       or v_source_page ~ '[[:cntrl:]]'
     ) then
    raise exception using errcode = '22023', message = 'INVALID_SOURCE_PAGE';
  end if;

  select student.id
  into v_student_id
  from learning.students as student
  where student.auth_user_id = v_auth_user_id
    and student.active;

  if v_student_id is null then
    raise exception using errcode = '28000', message = 'STUDENT_IDENTITY_NOT_FOUND';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_student_id::text, 0)
  );

  v_submission_hash := encode(
    extensions.digest(
      pg_catalog.convert_to(
        jsonb_build_object(
          'activity_key', p_activity_key,
          'activity_version', p_activity_version,
          'responses', p_responses,
          'source_page', v_source_page,
          'started_at', p_started_at,
          'completed_at', p_completed_at,
          'programming_language', p_programming_language
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select attempt.*
  into v_existing
  from learning.attempts as attempt
  where attempt.student_id = v_student_id
    and attempt.client_attempt_id = p_client_attempt_id;

  if found then
    if v_existing.submission_hash <> v_submission_hash then
      raise exception using errcode = '23505', message = 'CLIENT_ATTEMPT_ID_CONFLICT';
    end if;

    return query
    select
      attempt.id,
      attempt.client_attempt_id,
      activity.stable_key,
      version.version,
      attempt.attempt_number,
      attempt.score,
      attempt.max_score,
      attempt.marking_source,
      attempt.evidence_level,
      attempt.client_started_at,
      attempt.client_completed_at,
      attempt.source_page,
      coding_language.stable_key,
      attempt.received_at,
      true
    from learning.attempts as attempt
    join learning.activity_versions as version
      on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    left join learning.coding_languages as coding_language
      on coding_language.id = attempt.programming_language_id
    where attempt.id = v_existing.id;
    return;
  end if;

  select version.id, version.question_count, version.max_score
  into v_activity_version_id, v_question_count, v_activity_max_score
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
  into v_declared_language_count
  from learning.activity_version_languages as version_language
  where version_language.activity_version_id = v_activity_version_id;

  if v_declared_language_count = 0 and p_programming_language is not null then
    raise exception using errcode = '22023', message = 'PROGRAMMING_LANGUAGE_NOT_APPLICABLE';
  end if;

  if v_declared_language_count > 0 then
    if p_programming_language is null or btrim(p_programming_language) = '' then
      raise exception using errcode = '22023', message = 'PROGRAMMING_LANGUAGE_REQUIRED';
    end if;

    select coding_language.id
    into v_programming_language_id
    from learning.activity_version_languages as version_language
    join learning.coding_languages as coding_language
      on coding_language.id = version_language.coding_language_id
     and coding_language.active
    where version_language.activity_version_id = v_activity_version_id
      and coding_language.stable_key = p_programming_language;

    if v_programming_language_id is null then
      raise exception using errcode = '22023', message = 'INVALID_PROGRAMMING_LANGUAGE';
    end if;
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
   and (assignment.opens_at is null or assignment.opens_at <= v_received_at)
   and (assignment.due_at is null or assignment.due_at >= v_received_at)
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  if v_matching_assignment_count = 0 then
    raise exception using errcode = '42501', message = 'ACTIVITY_NOT_ASSIGNED';
  end if;

  if v_matching_assignment_count > 1 then
    raise exception using errcode = '23514', message = 'ACTIVITY_ASSIGNMENT_AMBIGUOUS';
  end if;

  select enrolment.id, assignment.id
  into v_enrolment_id, v_assignment_id
  from learning.enrolments as enrolment
  join learning.groups as learner_group
    on learner_group.id = enrolment.group_id
   and learner_group.active
  join learning.activity_assignments as assignment
    on assignment.group_id = enrolment.group_id
   and assignment.activity_version_id = v_activity_version_id
   and assignment.active
   and (assignment.opens_at is null or assignment.opens_at <= v_received_at)
   and (assignment.due_at is null or assignment.due_at >= v_received_at)
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  p_responses := learning.prepare_timed_knowledge_report_submission(
    v_student_id,
    v_activity_version_id,
    p_responses
  );

  if jsonb_array_length(p_responses) <> v_question_count then
    raise exception using errcode = '22023', message = 'INCOMPLETE_RESPONSE_SET';
  end if;

  if (
    select count(distinct item ->> 'question_id')
    from jsonb_array_elements(p_responses) as response_item(item)
  ) <> v_question_count then
    raise exception using errcode = '22023', message = 'DUPLICATE_OR_MISSING_QUESTION';
  end if;

  for v_item in select value from jsonb_array_elements(p_responses)
  loop
    v_has_score := (v_item ? 'awarded_score');
    v_has_correct := (v_item ? 'is_correct');

    if jsonb_typeof(v_item) <> 'object'
       or jsonb_typeof(v_item -> 'question_id') <> 'string'
       or not (v_item ? 'response_payload')
       or v_item -> 'response_payload' = 'null'::jsonb
       or jsonb_typeof(v_item -> 'response_payload')
          not in ('string', 'array', 'object')
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'string'
         and btrim(v_item ->> 'response_payload') = ''
       )
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'array'
         and jsonb_array_length(v_item -> 'response_payload') = 0
       )
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'object'
         and v_item -> 'response_payload' = '{}'::jsonb
       )
       or v_has_score <> v_has_correct
       or (
         v_has_score
         and (
           jsonb_typeof(v_item -> 'awarded_score') <> 'number'
           or jsonb_typeof(v_item -> 'is_correct') <> 'boolean'
         )
       )
       or octet_length((v_item -> 'response_payload')::text) > 131072 then
      raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
    end if;

    v_question_key := v_item ->> 'question_id';

    select question.*
    into v_question
    from learning.questions as question
    where question.activity_version_id = v_activity_version_id
      and question.stable_key = v_question_key;

    if not found then
      if exists (
        select 1 from learning.questions as other_question
        where other_question.stable_key = v_question_key
      ) then
        raise exception using
          errcode = '23514',
          message = 'QUESTION_WRONG_ACTIVITY_VERSION';
      end if;
      raise exception using errcode = '22023', message = 'UNKNOWN_QUESTION';
    end if;

    v_awarded_score := null;
    v_is_correct := null;
    if v_has_score then
      begin
        v_awarded_score := (v_item ->> 'awarded_score')::numeric(8,2);
        v_is_correct := (v_item ->> 'is_correct')::boolean;
      exception when others then
        raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
      end;
    end if;

    select
      mark.awarded_score,
      mark.is_correct,
      mark.requires_review,
      mark.marking_source
    into
      v_awarded_score,
      v_is_correct,
      v_requires_review,
      v_item_source
    from learning.score_submitted_item(
      v_question.id,
      v_question.max_score,
      v_item -> 'response_payload',
      v_has_score,
      v_awarded_score,
      v_is_correct
    ) as mark;

    if v_marking_source is null then
      v_marking_source := v_item_source;
    elsif v_marking_source <> v_item_source then
      v_marking_source := 'server';
    end if;

    v_total_score := v_total_score + v_awarded_score;
    v_marked := v_marked || jsonb_build_array(
      jsonb_strip_nulls(
        jsonb_build_object(
          'question_id', v_question.id,
          'payload', v_item -> 'response_payload',
          'awarded_score', v_awarded_score,
          'is_correct', v_is_correct,
          'requires_review', v_requires_review,
          'marking_source', v_item_source
        )
      )
    );
  end loop;

  if v_total_score > v_activity_max_score then
    raise exception using
      errcode = '23514',
      message = 'ATTEMPT_SCORE_EXCEEDS_ACTIVITY_MAXIMUM';
  end if;

  select coalesce(max(attempt.attempt_number), 0) + 1
  into v_attempt_number
  from learning.attempts as attempt
  where attempt.student_id = v_student_id
    and attempt.assignment_id = v_assignment_id;

  v_attempt_id := gen_random_uuid();

  insert into learning.attempts (
    id,
    client_attempt_id,
    student_id,
    enrolment_id,
    assignment_id,
    activity_version_id,
    attempt_number,
    status,
    score,
    max_score,
    marking_source,
    evidence_level,
    source_system,
    submission_hash,
    client_started_at,
    client_completed_at,
    source_page,
    programming_language_id,
    received_at,
    completed_at
  ) values (
    v_attempt_id,
    p_client_attempt_id,
    v_student_id,
    v_enrolment_id,
    v_assignment_id,
    v_activity_version_id,
    v_attempt_number,
    'completed',
    v_total_score,
    v_activity_max_score,
    v_marking_source,
    'question_level',
    'supabase',
    v_submission_hash,
    p_started_at,
    p_completed_at,
    v_source_page,
    v_programming_language_id,
    v_received_at,
    v_received_at
  );

  for v_mark in select value from jsonb_array_elements(v_marked)
  loop
    insert into learning.responses (
      attempt_id,
      question_id,
      response_payload,
      awarded_score,
      max_score,
      is_correct,
      requires_review,
      marking_source,
      marked_at
    )
    select
      v_attempt_id,
      (v_mark ->> 'question_id')::uuid,
      v_mark -> 'payload',
      (v_mark ->> 'awarded_score')::numeric(8,2),
      question.max_score,
      case
        when v_mark ? 'is_correct' then (v_mark ->> 'is_correct')::boolean
        else null
      end,
      coalesce((v_mark ->> 'requires_review')::boolean, true),
      v_mark ->> 'marking_source',
      v_received_at
    from learning.questions as question
    where question.id = (v_mark ->> 'question_id')::uuid;
  end loop;

  return query
  select
    attempt.id,
    attempt.client_attempt_id,
    activity.stable_key,
    version.version,
    attempt.attempt_number,
    attempt.score,
    attempt.max_score,
    attempt.marking_source,
    attempt.evidence_level,
    attempt.client_started_at,
    attempt.client_completed_at,
    attempt.source_page,
    coding_language.stable_key,
    attempt.received_at,
    false
  from learning.attempts as attempt
  join learning.activity_versions as version
    on version.id = attempt.activity_version_id
  join learning.activities as activity on activity.id = version.activity_id
  left join learning.coding_languages as coding_language
    on coding_language.id = attempt.programming_language_id
  where attempt.id = v_attempt_id;
end
$$;

comment on function api.submit_attempt(
  text,
  text,
  text,
  jsonb,
  text,
  timestamptz,
  timestamptz,
  text
) is
  'Stores an idempotent learner attempt. Identity is always auth.uid(). Timed knowledge reports are enriched after the idempotency hash with server word count, elapsed time and submission method. Finished response items may be up to 128 KiB.';


create or replace function platform.project_curriculum_package(
  p_package jsonb,
  p_hub_code text,
  p_course_key text,
  p_package_version text,
  p_publication_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_course_id uuid;
  v_module_id uuid;
  v_module_key text;
  v_module_title text;
  v_sort_order integer;
  v_year_id uuid;
  v_week jsonb;
  v_outcome jsonb;
  v_session jsonb;
  v_session_id text;
  v_activity jsonb;
  v_activity_id text;
  v_activity_version text;
  v_activity_title text;
  v_activity_type text;
  v_requires_python boolean;
  v_delivery jsonb := '{}'::jsonb;
  v_delivery_row jsonb;
  v_week_id uuid;
  v_activity_row_id uuid;
  v_version_id uuid;
  v_question_id uuid;
  v_topic_id uuid;
  v_topic_key text;
  v_ordinal integer;
  v_session_number integer;
  v_sort integer;
  v_block jsonb;
  v_block_type text;
  v_content jsonb;
  v_question_key text;
  v_item jsonb;
  v_item_id text;
  v_target_id text;
  v_marking jsonb;
  v_questions jsonb := '[]'::jsonb;
  v_payload jsonb;
  v_hash text;
  v_count integer;
  v_gap_count integer;
  v_correct_option text;
  v_stable_key text;
  v_lo text;
  v_activity_count integer := 0;
  v_week_stable_key text;
  v_week_number integer;
  v_week_title text;
  v_week_sort integer;
  v_existing_by_key uuid;
  v_existing_by_number uuid;
  v_target_week_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('content-package:' || p_hub_code, 0)
  );

  select course.id
  into v_course_id
  from learning.courses as course
  where course.stable_key = p_course_key
    and course.active;

  if v_course_id is null then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;

  select academic_year.id
  into v_year_id
  from learning.academic_years as academic_year
  where academic_year.active
  order by academic_year.code
  limit 1;

  v_module_key := p_hub_code;
  v_module_title := coalesce(
    p_package->'curriculum'->'metadata'->>'title',
    p_package->'hub'->'metadata'->>'name',
    p_hub_code
  );
  v_sort_order := coalesce(substring(p_hub_code from 'unit-([0-9]+)')::int, 0);
  v_module_id := platform.curriculum_catalogue_id('module', p_course_key || ':' || v_module_key);

  insert into learning.modules (id, course_id, stable_key, title, sort_order, active)
  values (v_module_id, v_course_id, v_module_key, v_module_title, v_sort_order, true)
  on conflict (course_id, stable_key) do update set
    title = excluded.title,
    active = true;

  select module.id into v_module_id
  from learning.modules as module
  where module.course_id = v_course_id
    and module.stable_key = v_module_key;

  for v_outcome in
    select value
    from jsonb_array_elements(coalesce(p_package->'learningOutcomes', '[]'::jsonb)) as value
  loop
    v_topic_key := lower(btrim(coalesce(v_outcome->>'id', '')));
    if v_topic_key = '' or v_topic_key !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
      continue;
    end if;
    insert into learning.topics (id, module_id, stable_key, title, sort_order, active)
    values (
      platform.curriculum_catalogue_id('topic', p_course_key || ':' || v_module_key || ':' || v_topic_key),
      v_module_id,
      v_topic_key,
      coalesce(v_outcome->'metadata'->>'title', v_topic_key),
      coalesce((v_outcome->'metadata'->>'sortOrder')::int, 0),
      true
    )
    on conflict (module_id, stable_key) do update set
      title = excluded.title,
      active = true;
  end loop;

  for v_week in
    select value
    from jsonb_array_elements(coalesce(p_package->'weeks', '[]'::jsonb)) as value
  loop
    v_week_stable_key := coalesce(v_week->>'id', '');
    if v_week_stable_key = '' then
      continue;
    end if;

    v_week_number := coalesce((v_week->'metadata'->>'teachingWeek')::int, 1);
    v_week_title := coalesce(v_week->'metadata'->>'title', v_week_stable_key);
    v_week_sort := v_week_number;

    select week.id
    into v_existing_by_key
    from learning.curriculum_weeks as week
    where week.module_id = v_module_id
      and week.stable_key = v_week_stable_key;

    select week.id
    into v_existing_by_number
    from learning.curriculum_weeks as week
    where week.module_id = v_module_id
      and week.week_number = v_week_number;

    if v_existing_by_key is not null
       and v_existing_by_number is not null
       and v_existing_by_key is distinct from v_existing_by_number then
      raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_CONFLICT';
    end if;

    v_target_week_id := coalesce(v_existing_by_key, v_existing_by_number);

    if v_target_week_id is not null then
      update learning.curriculum_weeks
      set
        stable_key = v_week_stable_key,
        title = v_week_title,
        week_number = v_week_number,
        sort_order = v_week_sort,
        active = true,
        updated_at = clock_timestamp()
      where id = v_target_week_id;
    else
      begin
        insert into learning.curriculum_weeks (
          id, module_id, stable_key, title, week_number, sort_order, active
        )
        values (
          platform.curriculum_catalogue_id(
            'week', p_course_key || ':' || v_module_key || ':' || v_week_stable_key
          ),
          v_module_id,
          v_week_stable_key,
          v_week_title,
          v_week_number,
          v_week_sort,
          true
        );
      exception
        when unique_violation then
          select week.id
          into v_target_week_id
          from learning.curriculum_weeks as week
          where week.module_id = v_module_id
            and (
              week.stable_key = v_week_stable_key
              or week.week_number = v_week_number
            )
          order by case when week.stable_key = v_week_stable_key then 0 else 1 end
          limit 1;

          if v_target_week_id is null then
            raise;
          end if;

          if exists (
            select 1
            from learning.curriculum_weeks as week
            where week.module_id = v_module_id
              and week.stable_key = v_week_stable_key
              and week.id <> v_target_week_id
          ) or exists (
            select 1
            from learning.curriculum_weeks as week
            where week.module_id = v_module_id
              and week.week_number = v_week_number
              and week.id <> v_target_week_id
          ) then
            raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_CONFLICT';
          end if;

          update learning.curriculum_weeks
          set
            stable_key = v_week_stable_key,
            title = v_week_title,
            week_number = v_week_number,
            sort_order = v_week_sort,
            active = true,
            updated_at = clock_timestamp()
          where id = v_target_week_id;
      end;
    end if;
  end loop;

  for v_week in
    select value
    from jsonb_array_elements(coalesce(p_package->'weeks', '[]'::jsonb)) as value
  loop
    for v_session_id in
      select jsonb_array_elements_text(coalesce(v_week->'relationships'->'sessions', '[]'::jsonb))
    loop
      select value
      into v_session
      from jsonb_array_elements(coalesce(p_package->'sessions', '[]'::jsonb)) as value
      where value->>'id' = v_session_id
      limit 1;

      if v_session is null then
        continue;
      end if;

      v_session_number := case
        when coalesce(v_session->'metadata'->>'sortOrder', '') ~ '^[0-9]+$'
          and (v_session->'metadata'->>'sortOrder')::int > 0
        then (v_session->'metadata'->>'sortOrder')::int
        else null
      end;

      for v_activity_id, v_sort in
        select activity_ref, ordinality::int
        from jsonb_array_elements_text(
          coalesce(v_session->'relationships'->'activities', '[]'::jsonb)
        ) with ordinality as refs(activity_ref, ordinality)
      loop
        v_delivery := v_delivery || jsonb_build_object(
          v_activity_id,
          jsonb_build_object(
            'weekKey', v_week->>'id',
            'weekNumber', coalesce((v_week->'metadata'->>'teachingWeek')::int, 1),
            'sessionNumber', v_session_number,
            'sortOrder', v_sort
          )
        );
      end loop;
    end loop;
  end loop;

  for v_activity in
    select value
    from jsonb_array_elements(coalesce(p_package->'activities', '[]'::jsonb)) as value
  loop
    v_activity_id := v_activity->>'id';
    v_activity_version := coalesce(v_activity->>'version', '');
    v_delivery_row := v_delivery->v_activity_id;
    if v_activity_id is null
       or v_activity_id !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
       or v_activity_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$'
       or v_delivery_row is null then
      continue;
    end if;

    v_questions := '[]'::jsonb;
    v_ordinal := 0;
    v_requires_python := false;

    for v_block in
      select value
      from jsonb_array_elements(coalesce(v_activity->'blocks', '[]'::jsonb)) as value
    loop
      v_block_type := coalesce(v_block->>'type', '');
      v_content := case
        when jsonb_typeof(v_block->'content') = 'object' then v_block->'content'
        else '{}'::jsonb
      end;

      if v_block_type in (
        'heading', 'paragraph', 'markdown', 'image', 'video', 'callout',
        'accordion', 'reference', 'hint', 'quote', 'divider', 'teacher-note'
      ) then
        continue;
      end if;

      if v_block_type not in (
        'single-choice', 'classification', 'drag-drop', 'short-response',
        'reflection', 'code-editor', 'python-exercise',
        'fill-gap', 'phrase-completion', 'ordering', 'sequence'
      ) then
        -- Checkable / interactive blocks must never be silently omitted.
        raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
      end if;

      if v_block_type in ('code-editor', 'python-exercise') then
        v_requires_python := true;
      end if;

      v_question_key := coalesce(v_content->>'questionId', '');
      if v_question_key = '' or v_question_key !~ '^[A-Za-z0-9._:-]+$' then
        raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
      end if;


      if v_block_type = 'drag-drop' then
        if jsonb_typeof(v_content->'items') is distinct from 'array'
           or jsonb_array_length(v_content->'items') = 0
           or jsonb_typeof(v_content->'targets') is distinct from 'array'
           or jsonb_array_length(v_content->'targets') = 0 then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;

        if exists (
          select 1
          from jsonb_array_elements(v_content->'items') as item
          where coalesce(item->>'id', '') = ''
             or item->>'id' !~ '^[A-Za-z0-9._:-]+$'
        ) or exists (
          select 1
          from jsonb_array_elements(v_content->'targets') as target
          where coalesce(target->>'id', '') = ''
             or target->>'id' !~ '^[A-Za-z0-9._:-]+$'
        ) then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;

        if (
          select count(*) <> count(distinct item->>'id')
          from jsonb_array_elements(v_content->'items') as item
        ) or (
          select count(*) <> count(distinct target->>'id')
          from jsonb_array_elements(v_content->'targets') as target
        ) then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;

        if v_content ? 'correct' then
          if jsonb_typeof(v_content->'correct') is distinct from 'object'
             or exists (
               select 1
               from jsonb_each_text(v_content->'correct') as mapping(item_id, target_id)
               where mapping.item_id !~ '^[A-Za-z0-9._:-]+$'
                  or mapping.target_id !~ '^[A-Za-z0-9._:-]+$'
                  or not exists (
                    select 1
                    from jsonb_array_elements(v_content->'items') as item
                    where item->>'id' = mapping.item_id
                  )
                  or not exists (
                    select 1
                    from jsonb_array_elements(v_content->'targets') as target
                    where target->>'id' = mapping.target_id
                  )
             ) then
            raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
          end if;
        end if;

        for v_item in
          select value from jsonb_array_elements(v_content->'items') as value
        loop
          v_item_id := coalesce(v_item->>'id', '');
          v_ordinal := v_ordinal + 1;
          v_target_id := '';
          if jsonb_typeof(v_content->'correct') = 'object' then
            v_target_id := coalesce(v_content->'correct'->>v_item_id, '');
          end if;
          if v_target_id <> '' then
            v_marking := jsonb_build_object(
              'mode', 'classification',
              'correctCategoryId', v_target_id
            );
          else
            v_marking := jsonb_build_object('mode', 'completion');
          end if;
          v_questions := v_questions || jsonb_build_array(
            jsonb_build_object(
              'stableKey', v_question_key || ':' || v_item_id,
              'questionType', 'matching',
              'ordinal', v_ordinal,
              'marking', v_marking
            )
          );
        end loop;
        continue;
      end if;

      if v_block_type = 'classification' then
        if jsonb_typeof(v_content->'items') is distinct from 'array'
           or jsonb_array_length(v_content->'items') = 0 then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;
        for v_item in
          select value from jsonb_array_elements(v_content->'items') as value
        loop
          v_item_id := coalesce(v_item->>'id', '');
          if v_item_id = '' or v_item_id !~ '^[A-Za-z0-9._:-]+$' then
            raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
          end if;
          v_ordinal := v_ordinal + 1;
          if coalesce(v_item->>'correctCategoryId', '') <> '' then
            v_marking := jsonb_build_object(
              'mode', 'classification',
              'correctCategoryId', v_item->>'correctCategoryId'
            );
          else
            v_marking := jsonb_build_object('mode', 'completion');
          end if;
          v_questions := v_questions || jsonb_build_array(
            jsonb_build_object(
              'stableKey', v_question_key || ':' || v_item_id,
              'questionType', 'matching',
              'ordinal', v_ordinal,
              'marking', v_marking
            )
          );
        end loop;
        continue;
      end if;

      if v_block_type in ('fill-gap', 'phrase-completion') then
        -- Canonical identity matches Core evidence:
        --   single-gap block  → package questionId
        --   multi-gap block   → questionId:gapId
        if jsonb_typeof(v_content->'gaps') = 'array'
           and jsonb_array_length(v_content->'gaps') > 0 then
          v_gap_count := jsonb_array_length(v_content->'gaps');
          for v_item in select value from jsonb_array_elements(v_content->'gaps')
          loop
            v_item_id := coalesce(nullif(btrim(v_item->>'id'), ''), 'gap');
            if v_item_id !~ '^[A-Za-z0-9._:-]+$' then
              raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
            end if;
            v_correct_option := coalesce(
              nullif(btrim(v_item->>'correctOptionId'), ''),
              nullif(btrim(v_content->>'correctOptionId'), ''),
              ''
            );
            v_stable_key := case
              when v_gap_count = 1 then v_question_key
              else v_question_key || ':' || v_item_id
            end;
            v_ordinal := v_ordinal + 1;
            if v_correct_option <> '' then
              v_marking := jsonb_build_object(
                'mode', 'single-choice',
                'correctOptionId', v_correct_option
              );
            else
              v_marking := jsonb_build_object('mode', 'completion');
            end if;
            v_questions := v_questions || jsonb_build_array(
              jsonb_build_object(
                'stableKey', v_stable_key,
                'questionType', 'single',
                'ordinal', v_ordinal,
                'marking', v_marking
              )
            );
          end loop;
        else
          v_correct_option := coalesce(nullif(btrim(v_content->>'correctOptionId'), ''), '');
          v_ordinal := v_ordinal + 1;
          if v_correct_option <> '' then
            v_marking := jsonb_build_object(
              'mode', 'single-choice',
              'correctOptionId', v_correct_option
            );
          else
            v_marking := jsonb_build_object('mode', 'completion');
          end if;
          v_questions := v_questions || jsonb_build_array(
            jsonb_build_object(
              'stableKey', v_question_key,
              'questionType', 'single',
              'ordinal', v_ordinal,
              'marking', v_marking
            )
          );
        end if;
        continue;
      end if;

      if v_block_type in ('ordering', 'sequence') then
        -- One question at package questionId. Scored only when correctOrder is authored.
        -- Item ids may include spaces (authored labels used as ids); they are not
        -- catalogue stable_keys, so do not apply the questionId charset constraint.
        if jsonb_typeof(v_content->'items') is distinct from 'array'
           or jsonb_array_length(v_content->'items') = 0 then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;
        if exists (
          select 1
          from jsonb_array_elements(v_content->'items') as item
          where coalesce(btrim(item->>'id'), '') = ''
        ) then
          raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
        end if;

        v_ordinal := v_ordinal + 1;
        if jsonb_typeof(v_content->'correctOrder') = 'array'
           and jsonb_array_length(v_content->'correctOrder') > 0 then
          if jsonb_array_length(v_content->'correctOrder')
               is distinct from jsonb_array_length(v_content->'items')
             or exists (
               select 1
               from jsonb_array_elements_text(v_content->'correctOrder') as item_id
               where btrim(item_id) = ''
                  or not exists (
                    select 1
                    from jsonb_array_elements(v_content->'items') as item
                    where item->>'id' = item_id
                  )
             ) then
            raise exception using errcode = '22023', message = 'CATALOGUE_PROJECTION_FAILED';
          end if;
          v_marking := jsonb_build_object(
            'mode', 'ordering-exact',
            'correctOrder', v_content->'correctOrder'
          );
        else
          v_marking := jsonb_build_object('mode', 'completion');
        end if;
        v_questions := v_questions || jsonb_build_array(
          jsonb_build_object(
            'stableKey', v_question_key,
            'questionType', 'order',
            'ordinal', v_ordinal,
            'marking', v_marking
          )
        );
        continue;
      end if;

      v_ordinal := v_ordinal + 1;
      if v_block_type = 'single-choice' and coalesce(v_content->>'correctOptionId', '') <> '' then
        v_marking := jsonb_build_object(
          'mode', 'single-choice',
          'correctOptionId', v_content->>'correctOptionId'
        );
      elsif v_block_type in ('code-editor', 'python-exercise') then
        v_marking := jsonb_build_object(
          'mode', case
            when coalesce(v_content->'checks'->'required', '[]'::jsonb) <> '[]'::jsonb
              or coalesce(v_content->'checks'->'prohibited', '[]'::jsonb) <> '[]'::jsonb
            then 'python-patterns'
            else 'completion'
          end,
          'required', coalesce((
            select jsonb_agg(platform.posix_js_pattern(item->>'pattern'))
            from jsonb_array_elements(coalesce(v_content->'checks'->'required', '[]'::jsonb)) as item
            where coalesce(item->>'pattern', '') <> ''
          ), '[]'::jsonb),
          'prohibited', coalesce((
            select jsonb_agg(platform.posix_js_pattern(item->>'pattern'))
            from jsonb_array_elements(coalesce(v_content->'checks'->'prohibited', '[]'::jsonb)) as item
            where coalesce(item->>'pattern', '') <> ''
          ), '[]'::jsonb)
        );
        if v_marking->>'mode' = 'completion' then
          v_marking := jsonb_build_object('mode', 'completion');
        end if;
      else
        v_marking := jsonb_build_object('mode', 'completion');
      end if;

      v_questions := v_questions || jsonb_build_array(
        jsonb_build_object(
          'stableKey', v_question_key,
          'questionType', case v_block_type
            when 'single-choice' then 'single'
            when 'short-response' then 'text'
            when 'reflection' then 'text'
            else 'code-editor'
          end,
          'ordinal', v_ordinal,
          'marking', v_marking
        )
      );
    end loop;

    v_count := jsonb_array_length(v_questions);
    if v_count = 0 then
      continue;
    end if;

    v_activity_title := coalesce(v_activity->'metadata'->>'title', v_activity_id);
    v_activity_type := case
      when v_activity_id like '%diagnostic%' then 'diagnostic'
      when v_requires_python then 'coding-exercise'
      when exists (
        select 1
        from jsonb_array_elements(coalesce(v_activity->'blocks', '[]'::jsonb)) as block
        where block->>'type' in ('classification', 'drag-drop')
      ) then 'classification'
      when exists (
        select 1
        from jsonb_array_elements(coalesce(v_activity->'blocks', '[]'::jsonb)) as block
        where block->>'type' in ('single-choice', 'fill-gap', 'phrase-completion', 'ordering', 'sequence')
      ) then 'diagnostic'
      else 'reflection'
    end;

    v_activity_row_id := platform.curriculum_catalogue_id('activity', v_activity_id);
    v_version_id := platform.curriculum_catalogue_id('version', v_activity_id || ':' || v_activity_version);
    v_week_id := platform.curriculum_catalogue_id(
      'week',
      p_course_key || ':' || v_module_key || ':' || (v_delivery_row->>'weekKey')
    );

    select week.id
    into v_week_id
    from learning.curriculum_weeks as week
    where week.module_id = v_module_id
      and week.stable_key = v_delivery_row->>'weekKey';

    v_payload := (
      select jsonb_agg(
        jsonb_build_object(
          'stableKey', question->>'stableKey',
          'questionType', question->>'questionType',
          'ordinal', question->'ordinal',
          'marking', question->'marking'
        )
        order by (question->>'ordinal')::int
      )
      from jsonb_array_elements(v_questions) as question
    );
    v_hash := encode(
      extensions.digest(
        convert_to(
          jsonb_build_object(
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

    insert into learning.activities (
      id, module_id, stable_key, title, activity_type, git_path, active
    )
    values (
      v_activity_row_id,
      v_module_id,
      v_activity_id,
      v_activity_title,
      v_activity_type,
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

    select version.id
    into v_version_id
    from learning.activity_versions as version
    where version.activity_id = v_activity_row_id
      and version.version = v_activity_version;

    if v_version_id is null then
      v_version_id := platform.curriculum_catalogue_id(
        'version',
        v_activity_id || ':' || v_activity_version
      );
    end if;

    insert into learning.activity_versions (
      id, activity_id, version, content_hash, max_score, question_count, published_at
    )
    values (
      v_version_id,
      v_activity_row_id,
      v_activity_version,
      v_hash,
      v_count,
      v_count,
      null
    )
    on conflict (activity_id, version) do nothing;

    select version.id
    into v_version_id
    from learning.activity_versions as version
    where version.activity_id = v_activity_row_id
      and version.version = v_activity_version;

    if v_requires_python then
      insert into learning.activity_version_languages (activity_version_id, coding_language_id)
      select version.id, coding_language.id
      from learning.activity_versions as version
      join learning.coding_languages as coding_language
        on coding_language.stable_key = 'python'
        and coding_language.active
      where version.id = v_version_id
        and version.published_at is null
      on conflict (activity_version_id, coding_language_id) do nothing;
    end if;

    for v_block in
      select value from jsonb_array_elements(v_questions) as value
    loop
      v_question_id := platform.curriculum_catalogue_id(
        'question',
        v_activity_id || ':' || v_activity_version || ':' || (v_block->>'stableKey')
      );
      insert into learning.questions (
        id, activity_version_id, stable_key, section_key, section_title,
        question_type, analytics_title, ordinal, max_score
      )
      select
        v_question_id,
        v_version_id,
        v_block->>'stableKey',
        v_delivery_row->>'weekKey',
        'Week ' || (v_delivery_row->>'weekNumber'),
        v_block->>'questionType',
        v_block->>'stableKey',
        (v_block->>'ordinal')::int,
        1
      from learning.activity_versions as version
      where version.id = v_version_id
        and version.published_at is null
      on conflict (activity_version_id, stable_key) do nothing;

      insert into learning.question_marking (question_id, spec)
      select question.id, v_block->'marking'
      from learning.questions as question
      join learning.activity_versions as version
        on version.id = question.activity_version_id
      where question.id = v_question_id
        and version.published_at is null
      on conflict (question_id) do nothing;

      for v_lo in
        select lower(btrim(outcome_id))
        from jsonb_array_elements_text(
          coalesce(v_activity->'relationships'->'learningOutcomes', '[]'::jsonb)
        ) as outcome_id
      loop
        if v_lo = '' or v_lo !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
          continue;
        end if;
        v_topic_id := platform.curriculum_catalogue_id(
          'topic',
          p_course_key || ':' || v_module_key || ':' || v_lo
        );
        insert into learning.question_topics (question_id, topic_id, weight)
        select question.id, v_topic_id, 1
        from learning.questions as question
        join learning.activity_versions as version
          on version.id = question.activity_version_id
        where question.id = v_question_id
          and version.published_at is null
        on conflict (question_id, topic_id) do nothing;
      end loop;
    end loop;

    update learning.activity_versions
    set published_at = clock_timestamp()
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
          curriculum_week_id = v_week_id,
          week_number = (v_delivery_row->>'weekNumber')::int,
          session_number = nullif(v_delivery_row->>'sessionNumber', '')::int,
          sort_order = (v_delivery_row->>'sortOrder')::int,
          active = true,
          updated_at = clock_timestamp()
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
          v_week_id,
          (v_delivery_row->>'weekNumber')::int,
          nullif(v_delivery_row->>'sessionNumber', '')::int,
          (v_delivery_row->>'sortOrder')::int,
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

    v_activity_count := v_activity_count + 1;
  end loop;

  v_activity_count := v_activity_count + platform.project_knowledge_report_activities(
    p_package,
    p_hub_code,
    p_course_key,
    p_package_version
  );

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'curriculum.catalogue.projected',
    auth.uid(),
    case when auth.uid() is null then 'system' else 'staff' end,
    'curriculum-publication',
    coalesce(p_publication_id::text, p_hub_code),
    'succeeded',
    jsonb_build_object(
      'hubCode', p_hub_code,
      'courseKey', p_course_key,
      'version', p_package_version,
      'activityCount', v_activity_count
    )
  );
end;
$$;
