-- LO1/LO2 exam practice sittings. Not published to learners until the hub flag is enabled.
-- Deadlines use the database clock. Learner payloads cannot change extra time, marks, or another student's row.

create table learning.lo12_time_allowances (
  student_id uuid not null references learning.students (id) on delete restrict,
  activity_key text not null,
  extra_seconds integer not null,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (student_id, activity_key),
  constraint lo12_extra_seconds_valid check (extra_seconds between 0 and 3600),
  constraint lo12_allowance_activity_valid check (activity_key = 'mini-mock')
);

create table learning.lo12_exam_records (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references learning.students (id) on delete restrict,
  activity_key text not null,
  status text not null default 'draft',
  started_at timestamptz,
  deadline_at timestamptz,
  extra_seconds integer not null default 0,
  responses jsonb not null default '{}'::jsonb,
  submission_method text,
  submitted_at timestamptz,
  marking_status text not null default 'pending',
  awarded jsonb,
  feedback jsonb,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint lo12_exam_activity_valid check (activity_key in ('answer-writing', 'mini-mock', 'reflection')),
  constraint lo12_exam_status_valid check (status in ('draft', 'started', 'submitted')),
  constraint lo12_exam_marking_valid check (marking_status in ('pending', 'finalised')),
  constraint lo12_exam_method_valid check (submission_method is null or submission_method in ('manual', 'automatic')),
  constraint lo12_exam_student_activity_unique unique (student_id, activity_key)
);

alter table learning.lo12_time_allowances enable row level security;
alter table learning.lo12_exam_records enable row level security;
revoke all on learning.lo12_time_allowances from public, anon, authenticated;
revoke all on learning.lo12_exam_records from public, anon, authenticated;

create function learning.lo12_question_max(p_question_id text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_question_id
    when 'mm-1' then 3
    when 'mm-2' then 4
    when 'mm-3' then 3
    when 'mm-4' then 4
    when 'mm-5' then 6
    else null
  end
$$;

create function learning.lo12_learner_record(p_record learning.lo12_exam_records)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'activityKey', p_record.activity_key,
    'status', p_record.status,
    'startedAt', p_record.started_at,
    'deadlineAt', p_record.deadline_at,
    'serverNow', pg_catalog.clock_timestamp(),
    'responses', p_record.responses,
    'submissionMethod', p_record.submission_method,
    'submittedAt', p_record.submitted_at,
    'markingStatus', p_record.marking_status,
    'awarded', case when p_record.marking_status = 'finalised' then p_record.awarded else null end,
    'feedback', case when p_record.marking_status = 'finalised' then p_record.feedback else null end
  )
$$;

create function api.start_lo12_mini_mock()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student uuid;
  v_row learning.lo12_exam_records%rowtype;
  v_extra integer := 0;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  v_student := learning.require_current_student_id();
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_student::text || ':mini-mock', 0));
  select * into v_row
  from learning.lo12_exam_records
  where student_id = v_student and activity_key = 'mini-mock'
  for update;
  if found then
    return learning.lo12_learner_record(v_row);
  end if;
  select coalesce(extra_seconds, 0) into v_extra
  from learning.lo12_time_allowances
  where student_id = v_student and activity_key = 'mini-mock';
  insert into learning.lo12_exam_records (
    student_id, activity_key, status, started_at, deadline_at, extra_seconds
  ) values (
    v_student, 'mini-mock', 'started', v_now, v_now + make_interval(secs => 20 * 60 + v_extra), v_extra
  ) returning * into v_row;
  return learning.lo12_learner_record(v_row);
end;
$$;

create function api.save_lo12_mini_mock(p_responses jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student uuid;
  v_row learning.lo12_exam_records%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  v_student := learning.require_current_student_id();
  select * into v_row
  from learning.lo12_exam_records
  where student_id = v_student and activity_key = 'mini-mock'
  for update;
  if not found or v_row.status <> 'started' then
    if found then return learning.lo12_learner_record(v_row); end if;
    raise exception using errcode = '22023', message = 'EXAM_NOT_STARTED';
  end if;
  if v_now >= v_row.deadline_at then
    update learning.lo12_exam_records
    set status = 'submitted', submission_method = 'automatic', submitted_at = deadline_at, updated_at = v_now
    where id = v_row.id
    returning * into v_row;
    return learning.lo12_learner_record(v_row);
  end if;
  update learning.lo12_exam_records
  set responses = coalesce(p_responses, '{}'::jsonb) - 'awarded' - 'feedback' - 'extraSeconds',
      updated_at = v_now
  where id = v_row.id
  returning * into v_row;
  return learning.lo12_learner_record(v_row);
end;
$$;

create function api.submit_lo12_mini_mock(p_method text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student uuid;
  v_row learning.lo12_exam_records%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_method text;
begin
  v_student := learning.require_current_student_id();
  select * into v_row
  from learning.lo12_exam_records
  where student_id = v_student and activity_key = 'mini-mock'
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'EXAM_NOT_STARTED';
  end if;
  if v_row.status = 'submitted' then
    return learning.lo12_learner_record(v_row);
  end if;
  v_method := case when v_now >= v_row.deadline_at then 'automatic' else 'manual' end;
  update learning.lo12_exam_records
  set status = 'submitted',
      submission_method = v_method,
      submitted_at = case when v_method = 'automatic' then deadline_at else v_now end,
      updated_at = v_now
  where id = v_row.id
  returning * into v_row;
  return learning.lo12_learner_record(v_row);
end;
$$;

create function api.save_lo12_answer_writing(p_responses jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student uuid;
  v_row learning.lo12_exam_records%rowtype;
begin
  v_student := learning.require_current_student_id();
  insert into learning.lo12_exam_records (student_id, activity_key, status, responses)
  values (v_student, 'answer-writing', 'draft', coalesce(p_responses, '{}'::jsonb))
  on conflict (student_id, activity_key) do update
  set responses = excluded.responses, updated_at = pg_catalog.clock_timestamp()
  returning * into v_row;
  return learning.lo12_learner_record(v_row);
end;
$$;

create function api.save_lo12_reflection(p_responses jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student uuid;
  v_row learning.lo12_exam_records%rowtype;
begin
  v_student := learning.require_current_student_id();
  insert into learning.lo12_exam_records (student_id, activity_key, status, responses, submitted_at)
  values (v_student, 'reflection', 'submitted', coalesce(p_responses, '{}'::jsonb), pg_catalog.clock_timestamp())
  on conflict (student_id, activity_key) do update
  set responses = excluded.responses, status = 'submitted', submitted_at = pg_catalog.clock_timestamp(), updated_at = pg_catalog.clock_timestamp()
  returning * into v_row;
  return learning.lo12_learner_record(v_row);
end;
$$;

create function api.get_lo12_exam_practice()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student uuid;
begin
  v_student := learning.require_current_student_id();
  return coalesce((
    select jsonb_agg(learning.lo12_learner_record(record) order by record.activity_key)
    from learning.lo12_exam_records as record
    where record.student_id = v_student
  ), '[]'::jsonb);
end;
$$;

create function admin_api.set_lo12_extra_time(p_student_id uuid, p_extra_seconds integer)
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
  insert into learning.lo12_time_allowances (student_id, activity_key, extra_seconds)
  values (p_student_id, 'mini-mock', greatest(0, least(coalesce(p_extra_seconds, 0), 3600)))
  on conflict (student_id, activity_key) do update
  set extra_seconds = excluded.extra_seconds, updated_at = pg_catalog.clock_timestamp();
end;
$$;

create function admin_api.save_lo12_marks(p_record_id uuid, p_awarded jsonb, p_feedback jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_teacher learning.teachers%rowtype;
  v_row learning.lo12_exam_records%rowtype;
  v_awarded jsonb := '{}'::jsonb;
  v_key text;
  v_max integer;
  v_score numeric;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;
  select * into v_teacher from learning.teachers where auth_user_id = auth.uid() and active;
  if not found then
    raise exception using errcode = '28000', message = 'REVIEW_NOT_AUTHORISED';
  end if;
  select * into v_row from learning.lo12_exam_records where id = p_record_id for update;
  if not found or v_row.activity_key <> 'mini-mock' or v_row.status <> 'submitted' or v_row.marking_status = 'finalised' then
    raise exception using errcode = '22023', message = 'EXAM_NOT_READY_TO_MARK';
  end if;
  for v_key, v_score in
    select key, value::text::numeric from jsonb_each_text(coalesce(p_awarded, '{}'::jsonb))
  loop
    v_max := learning.lo12_question_max(v_key);
    if v_max is null then continue; end if;
    v_awarded := v_awarded || jsonb_build_object(v_key, greatest(0, least(v_max, v_score)));
  end loop;
  update learning.lo12_exam_records
  set awarded = v_awarded, feedback = coalesce(p_feedback, '{}'::jsonb), updated_at = pg_catalog.clock_timestamp()
  where id = v_row.id
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create function admin_api.finalise_lo12_marks(p_record_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_teacher learning.teachers%rowtype;
  v_row learning.lo12_exam_records%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;
  select * into v_teacher from learning.teachers where auth_user_id = auth.uid() and active;
  if not found then
    raise exception using errcode = '28000', message = 'REVIEW_NOT_AUTHORISED';
  end if;
  select * into v_row from learning.lo12_exam_records where id = p_record_id for update;
  if not found
     or v_row.awarded is null
     or not (
       pg_catalog.jsonb_exists(v_row.awarded, 'mm-1')
       and pg_catalog.jsonb_exists(v_row.awarded, 'mm-2')
       and pg_catalog.jsonb_exists(v_row.awarded, 'mm-3')
       and pg_catalog.jsonb_exists(v_row.awarded, 'mm-4')
       and pg_catalog.jsonb_exists(v_row.awarded, 'mm-5')
     ) then
    raise exception using errcode = '22023', message = 'EXAM_MARKS_INCOMPLETE';
  end if;
  update learning.lo12_exam_records
  set marking_status = 'finalised', updated_at = pg_catalog.clock_timestamp()
  where id = v_row.id
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

revoke all on function api.start_lo12_mini_mock() from public, anon;
revoke all on function api.save_lo12_mini_mock(jsonb) from public, anon;
revoke all on function api.submit_lo12_mini_mock(text) from public, anon;
revoke all on function api.save_lo12_answer_writing(jsonb) from public, anon;
revoke all on function api.save_lo12_reflection(jsonb) from public, anon;
revoke all on function api.get_lo12_exam_practice() from public, anon;
grant execute on function api.start_lo12_mini_mock() to authenticated;
grant execute on function api.save_lo12_mini_mock(jsonb) to authenticated;
grant execute on function api.submit_lo12_mini_mock(text) to authenticated;
grant execute on function api.save_lo12_answer_writing(jsonb) to authenticated;
grant execute on function api.save_lo12_reflection(jsonb) to authenticated;
grant execute on function api.get_lo12_exam_practice() to authenticated;

create function admin_api.list_lo12_exam_practice()
returns jsonb
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
  return coalesce((
    select jsonb_agg(to_jsonb(record) order by record.updated_at desc)
    from learning.lo12_exam_records as record
  ), '[]'::jsonb);
end;
$$;

revoke all on function admin_api.set_lo12_extra_time(uuid, integer) from public, anon;
revoke all on function admin_api.save_lo12_marks(uuid, jsonb, jsonb) from public, anon;
revoke all on function admin_api.finalise_lo12_marks(uuid) from public, anon;
revoke all on function admin_api.list_lo12_exam_practice() from public, anon;
grant execute on function admin_api.set_lo12_extra_time(uuid, integer) to authenticated;
grant execute on function admin_api.save_lo12_marks(uuid, jsonb, jsonb) to authenticated;
grant execute on function admin_api.finalise_lo12_marks(uuid) to authenticated;
grant execute on function admin_api.list_lo12_exam_practice() to authenticated;
