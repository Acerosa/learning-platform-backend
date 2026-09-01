-- Formative Check answer: server mark, persist analytics checks, never write
-- learning.attempts. Identity is always auth.uid(). Answer keys are never returned.
-- Authored retry policy: formative_retry default true and formative_max_attempts
-- null means unlimited practice (the current catalogue default). retry=false is
-- one check. All successful checks are auditable.

alter table learning.questions
  add column if not exists formative_retry boolean not null default true,
  add column if not exists formative_max_attempts integer;

alter table learning.questions
  drop constraint if exists question_formative_max_attempts_valid;

alter table learning.questions
  add constraint question_formative_max_attempts_valid
  check (formative_max_attempts is null or formative_max_attempts > 0);

comment on column learning.questions.formative_retry is
  'Authored formative retry policy. false allows one check only. true is the catalogue default.';
comment on column learning.questions.formative_max_attempts is
  'Authored formative check cap. null with formative_retry=true means unlimited auditable practice. Existing published questions keep this default; package maxAttempts is not backfilled here and can be mapped by a future import.';

create table learning.formative_checks (
  id uuid primary key default gen_random_uuid(),
  client_check_id text not null,
  student_id uuid not null
    references learning.students (id) on delete restrict,
  assignment_id uuid not null
    references learning.activity_assignments (id) on delete restrict,
  activity_version_id uuid not null
    references learning.activity_versions (id) on delete restrict,
  question_id uuid not null
    references learning.questions (id) on delete restrict,
  check_number integer not null,
  response_type text,
  response_payload jsonb not null,
  awarded_score numeric(8,2) not null,
  max_score numeric(8,2) not null,
  is_correct boolean,
  requires_review boolean not null default false,
  marking_source text not null default 'server',
  request_hash text not null,
  source_page text,
  created_at timestamptz not null default clock_timestamp(),
  constraint formative_checks_student_client_question_unique
    unique (student_id, client_check_id, question_id),
  constraint formative_checks_student_version_question_number_unique
    unique (student_id, activity_version_id, question_id, check_number),
  constraint formative_check_client_id_valid check (
    length(client_check_id) between 1 and 128
    and client_check_id ~ '^[A-Za-z0-9._:-]+$'
  ),
  constraint formative_check_number_valid check (check_number > 0),
  constraint formative_check_payload_size_valid
    check (octet_length(response_payload::text) <= 4096),
  constraint formative_check_score_valid
    check (awarded_score >= 0 and max_score > 0 and awarded_score <= max_score),
  constraint formative_check_marking_source_valid
    check (marking_source = 'server'),
  constraint formative_check_request_hash_valid
    check (request_hash ~ '^[0-9a-f]{64}$'),
  constraint formative_check_source_page_valid
    check (source_page is null or length(source_page) between 1 and 512)
);

create index formative_checks_student_question_number_idx
  on learning.formative_checks (student_id, question_id, check_number);

create index formative_checks_question_correct_idx
  on learning.formative_checks (question_id, is_correct, check_number);

create index formative_checks_assignment_created_idx
  on learning.formative_checks (assignment_id, created_at desc);

comment on table learning.formative_checks is
  'Append-only formative practice checks. Not official assessment attempts. Written only by api.mark_formative_response.';

create function learning.reject_formative_check_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'FORMATIVE_CHECK_IMMUTABLE';
end;
$$;

create trigger formative_checks_immutable
before update or delete on learning.formative_checks
for each row execute function learning.reject_formative_check_mutation();

revoke all on function learning.reject_formative_check_mutation()
from public, anon, authenticated;

alter table learning.formative_checks enable row level security;

revoke all on table learning.formative_checks from public, anon, authenticated;

grant select on table learning.formative_checks to authenticated;

create policy formative_checks_staff_scoped_read
on learning.formative_checks
for select
to authenticated
using (
  (select learning.current_student_id()) is null
  and (
    (select platform.current_staff_has_role('platform_admin'))
    or exists (
      select 1
      from learning.activity_assignments as assignment
      where assignment.id = formative_checks.assignment_id
        and (select learning.teacher_can_access_group(assignment.group_id))
    )
  )
);

drop function if exists api.mark_formative_response(text, text, jsonb);

create function api.mark_formative_response(
  p_activity_key text,
  p_activity_version text,
  p_responses jsonb,
  p_client_check_id text,
  p_source_page text default null
)
returns table (
  question_id text,
  check_number integer,
  awarded_score numeric(8,2),
  max_score numeric(8,2),
  is_correct boolean,
  requires_review boolean,
  marking_source text,
  remaining_attempts integer,
  can_retry boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_student_id uuid;
  v_activity_version_id uuid;
  v_assignment_id uuid;
  v_matching_assignment_count integer;
  v_item jsonb;
  v_question learning.questions%rowtype;
  v_question_key text;
  v_payload jsonb;
  v_response_type text;
  v_mark record;
  v_seen text[] := '{}';
  v_source_page text;
  v_request_hash text;
  v_existing_hash text;
  v_used integer;
  v_max integer;
  v_next_number integer;
  v_remaining integer;
  v_can_retry boolean;
begin
  v_auth_user_id := auth.uid();

  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if p_activity_key is null or btrim(p_activity_key) = ''
     or p_activity_version is null or btrim(p_activity_version) = '' then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_VERSION';
  end if;

  if p_client_check_id is null
     or length(p_client_check_id) not between 1 and 128
     or p_client_check_id !~ '^[A-Za-z0-9._:-]+$' then
    raise exception using errcode = '22023', message = 'INVALID_CLIENT_CHECK_ID';
  end if;

  if p_source_page is not null then
    v_source_page := nullif(btrim(p_source_page), '');
    if v_source_page is not null
       and (
         length(v_source_page) > 512
         or v_source_page ~* '^\s*javascript:'
       ) then
      raise exception using errcode = '22023', message = 'INVALID_SOURCE_PAGE';
    end if;
  end if;

  if p_responses is null
     or jsonb_typeof(p_responses) <> 'array'
     or jsonb_array_length(p_responses) = 0
     or octet_length(p_responses::text) > 131072 then
    raise exception using errcode = '22023', message = 'INVALID_RESPONSES';
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
   and (assignment.opens_at is null or assignment.opens_at <= clock_timestamp())
   and (assignment.due_at is null or assignment.due_at >= clock_timestamp())
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  if v_matching_assignment_count = 0 then
    raise exception using errcode = '42501', message = 'ACTIVITY_NOT_ASSIGNED';
  end if;

  if v_matching_assignment_count > 1 then
    raise exception using errcode = '23514', message = 'ACTIVITY_ASSIGNMENT_AMBIGUOUS';
  end if;

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
   and (assignment.opens_at is null or assignment.opens_at <= clock_timestamp())
   and (assignment.due_at is null or assignment.due_at >= clock_timestamp())
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  v_request_hash := encode(
    extensions.digest(
      pg_catalog.convert_to(
        jsonb_build_object(
          'activity_key', p_activity_key,
          'activity_version', p_activity_version,
          'responses', p_responses,
          'source_page', v_source_page
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select check_row.request_hash
  into v_existing_hash
  from learning.formative_checks as check_row
  where check_row.student_id = v_student_id
    and check_row.client_check_id = p_client_check_id
  limit 1;

  if found then
    if v_existing_hash is distinct from v_request_hash then
      raise exception using errcode = '23505', message = 'CLIENT_CHECK_ID_CONFLICT';
    end if;

    return query
    select
      question.stable_key,
      check_row.check_number,
      check_row.awarded_score,
      check_row.max_score,
      check_row.is_correct,
      check_row.requires_review,
      check_row.marking_source,
      case
        when not question.formative_retry then 0
        when question.formative_max_attempts is null then null
        else greatest(question.formative_max_attempts - check_row.check_number, 0)
      end,
      case
        when not question.formative_retry then false
        when question.formative_max_attempts is null then true
        else check_row.check_number < question.formative_max_attempts
      end
    from learning.formative_checks as check_row
    join learning.questions as question
      on question.id = check_row.question_id
    where check_row.student_id = v_student_id
      and check_row.client_check_id = p_client_check_id
    order by question.ordinal, question.stable_key;
    return;
  end if;

  for v_item in select value from jsonb_array_elements(p_responses)
  loop
    if jsonb_typeof(v_item) <> 'object'
       or jsonb_typeof(v_item -> 'question_id') <> 'string'
       or btrim(v_item ->> 'question_id') = ''
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
       or octet_length((v_item -> 'response_payload')::text) > 4096 then
      raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
    end if;

    if exists (
      select 1
      from jsonb_object_keys(v_item) as key
      where key not in ('question_id', 'response_payload', 'response_type')
    ) then
      raise exception using errcode = '22023', message = 'FORBIDDEN_SUBMISSION_FIELD';
    end if;

    v_question_key := btrim(v_item ->> 'question_id');

    if v_question_key = any (v_seen) then
      raise exception using errcode = '22023', message = 'DUPLICATE_QUESTION';
    end if;
    v_seen := array_append(v_seen, v_question_key);

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

    v_max := case
      when not v_question.formative_retry then 1
      else v_question.formative_max_attempts
    end;

    select count(*)
    into v_used
    from learning.formative_checks as check_row
    where check_row.student_id = v_student_id
      and check_row.activity_version_id = v_activity_version_id
      and check_row.question_id = v_question.id;

    if v_max is not null and v_used >= v_max then
      raise exception using errcode = '23514', message = 'FORMATIVE_RETRY_LIMIT';
    end if;

    v_payload := v_item -> 'response_payload';
    v_response_type := nullif(btrim(v_item ->> 'response_type'), '');

    select
      mark.awarded_score,
      mark.is_correct,
      mark.requires_review
    into v_mark
    from learning.mark_evidence_response(
      v_question.id,
      v_payload,
      v_question.max_score
    ) as mark;

    v_next_number := v_used + 1;
    v_remaining := case
      when v_max is null then null
      else greatest(v_max - v_next_number, 0)
    end;
    v_can_retry := (v_max is null) or (v_next_number < v_max);

    insert into learning.formative_checks (
      client_check_id,
      student_id,
      assignment_id,
      activity_version_id,
      question_id,
      check_number,
      response_type,
      response_payload,
      awarded_score,
      max_score,
      is_correct,
      requires_review,
      marking_source,
      request_hash,
      source_page
    ) values (
      p_client_check_id,
      v_student_id,
      v_assignment_id,
      v_activity_version_id,
      v_question.id,
      v_next_number,
      v_response_type,
      v_payload,
      v_mark.awarded_score,
      v_question.max_score,
      v_mark.is_correct,
      v_mark.requires_review,
      'server',
      v_request_hash,
      v_source_page
    );

    question_id := v_question.stable_key;
    check_number := v_next_number;
    awarded_score := v_mark.awarded_score;
    max_score := v_question.max_score;
    is_correct := v_mark.is_correct;
    requires_review := v_mark.requires_review;
    marking_source := 'server';
    remaining_attempts := v_remaining;
    can_retry := v_can_retry;
    return next;
  end loop;
end;
$$;

revoke all on function api.mark_formative_response(text, text, jsonb, text, text)
from public, anon;

grant execute on function api.mark_formative_response(text, text, jsonb, text, text)
to authenticated;

comment on function api.mark_formative_response(text, text, jsonb, text, text) is
  'Authenticated formative mark. Persists append-only practice checks, enforces authored retry limits, and returns safe per-question results. Does not write official attempts or expected answers.';

create or replace view admin_api.formative_check_overview
with (security_invoker = true)
as
select
  (select count(*) from learning.formative_checks) as check_count,
  (
    select count(*)
    from learning.formative_checks
    where check_number = 1
  ) as first_check_count,
  (
    select count(*)
    from learning.formative_checks
    where check_number = 1
      and is_correct is true
  ) as first_check_correct_count,
  (
    select round(
      100.0 * count(*) filter (where check_number = 1 and is_correct is true)
        / nullif(count(*) filter (where check_number = 1 and is_correct is not null), 0),
      2
    )
    from learning.formative_checks
  ) as first_check_accuracy_percentage,
  (
    select count(*)
    from learning.formative_checks
    where requires_review
  ) as requires_review_count,
  (
    select count(distinct student_id)
    from learning.formative_checks
  ) as participating_learner_count
where (select platform.current_staff_has_role('platform_admin'));

create or replace view admin_api.formative_question_stats
with (security_invoker = true)
as
select
  activity.stable_key as activity_key,
  version.version as activity_version,
  question.stable_key as question_key,
  question.analytics_title,
  count(*) as check_count,
  count(*) filter (where check_row.check_number = 1) as first_check_count,
  count(*) filter (where check_row.check_number = 1 and check_row.is_correct is true)
    as first_check_correct_count,
  count(*) filter (where check_row.is_correct is true) as correct_check_count,
  round(avg(check_row.check_number) filter (where check_row.is_correct is true), 2)
    as average_checks_before_correct,
  max(check_row.check_number) as max_check_number,
  count(*) filter (where check_row.requires_review) as requires_review_count
from learning.formative_checks as check_row
join learning.questions as question
  on question.id = check_row.question_id
join learning.activity_versions as version
  on version.id = check_row.activity_version_id
join learning.activities as activity
  on activity.id = version.activity_id
where (select platform.current_staff_has_role('platform_admin'))
group by
  activity.stable_key,
  version.version,
  question.stable_key,
  question.analytics_title,
  question.ordinal
order by activity.stable_key, version.version, question.ordinal;

grant select on admin_api.formative_check_overview to authenticated;
grant select on admin_api.formative_question_stats to authenticated;
