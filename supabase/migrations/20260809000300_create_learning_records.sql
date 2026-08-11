create table learning.attempts (
  id uuid primary key default gen_random_uuid(),
  client_attempt_id text not null,
  student_id uuid not null
    references learning.students (id) on delete restrict,
  enrolment_id uuid not null
    references learning.enrolments (id) on delete restrict,
  assignment_id uuid not null
    references learning.activity_assignments (id) on delete restrict,
  activity_version_id uuid not null
    references learning.activity_versions (id) on delete restrict,
  attempt_number integer not null,
  status text not null default 'completed',
  score numeric(8,2) not null,
  max_score numeric(8,2) not null,
  marking_source text not null,
  evidence_level text not null,
  source_system text not null default 'supabase',
  submission_hash text not null,
  received_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz not null default clock_timestamp(),
  constraint attempts_student_client_id_unique
    unique (student_id, client_attempt_id),
  constraint attempts_student_assignment_number_unique
    unique (student_id, assignment_id, attempt_number),
  constraint attempt_client_id_valid check (
    length(client_attempt_id) between 1 and 128
    and client_attempt_id ~ '^[A-Za-z0-9._:-]+$'
  ),
  constraint attempt_number_valid check (attempt_number > 0),
  constraint attempt_status_valid
    check (status in ('started', 'submitted', 'completed', 'abandoned', 'invalidated')),
  constraint attempt_score_valid
    check (score >= 0 and max_score > 0 and score <= max_score),
  constraint attempt_marking_source_valid
    check (marking_source in ('client', 'server', 'imported')),
  constraint attempt_evidence_level_valid
    check (evidence_level in ('summary_only', 'question_level', 'imported_summary')),
  constraint attempt_source_system_valid
    check (source_system in ('supabase', 'google_sheets')),
  constraint attempt_submission_hash_valid
    check (submission_hash ~ '^[0-9a-f]{64}$'),
  constraint attempt_timestamps_valid check (completed_at >= received_at)
);

create index attempts_student_version_received_idx
  on learning.attempts (student_id, activity_version_id, received_at, id);

create index attempts_student_received_idx
  on learning.attempts (student_id, received_at desc);

create index attempts_enrolment_received_idx
  on learning.attempts (enrolment_id, received_at);

create index attempts_assignment_status_idx
  on learning.attempts (assignment_id, status);

create table learning.responses (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null
    references learning.attempts (id) on delete cascade,
  question_id uuid not null
    references learning.questions (id) on delete restrict,
  response_payload jsonb not null,
  awarded_score numeric(8,2) not null,
  max_score numeric(8,2) not null,
  is_correct boolean,
  requires_review boolean not null default false,
  marking_source text not null,
  marked_at timestamptz not null default clock_timestamp(),
  constraint responses_attempt_question_unique unique (attempt_id, question_id),
  constraint response_payload_size_valid
    check (octet_length(response_payload::text) <= 4096),
  constraint response_score_valid
    check (awarded_score >= 0 and max_score > 0 and awarded_score <= max_score),
  constraint response_marking_source_valid
    check (marking_source in ('client', 'server', 'imported'))
);

create index responses_question_correct_idx
  on learning.responses (question_id, is_correct);

create index responses_attempt_idx
  on learning.responses (attempt_id);

create index responses_review_marked_idx
  on learning.responses (requires_review, marked_at)
  where requires_review;

create function learning.validate_attempt_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  authoritative_max_score numeric(8,2);
begin
  select activity_version.max_score
  into authoritative_max_score
  from learning.activity_versions as activity_version
  where activity_version.id = new.activity_version_id
    and activity_version.published_at is not null
    and activity_version.retired_at is null;

  if authoritative_max_score is null then
    raise exception using
      errcode = '23514',
      message = 'ATTEMPT_REQUIRES_PUBLISHED_ACTIVITY_VERSION';
  end if;

  if not exists (
    select 1
    from learning.enrolments as enrolment
    join learning.activity_assignments as assignment
      on assignment.id = new.assignment_id
     and assignment.group_id = enrolment.group_id
    where enrolment.id = new.enrolment_id
      and enrolment.student_id = new.student_id
      and assignment.activity_version_id = new.activity_version_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'ATTEMPT_CONTEXT_MISMATCH';
  end if;

  new.max_score := authoritative_max_score;

  if new.score > authoritative_max_score then
    raise exception using
      errcode = '23514',
      message = 'ATTEMPT_SCORE_EXCEEDS_ACTIVITY_MAXIMUM';
  end if;

  return new;
end;
$$;

create trigger attempts_validate_integrity
before insert or update on learning.attempts
for each row execute function learning.validate_attempt_integrity();

create function learning.validate_response_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  attempt_version_id uuid;
  authoritative_max_score numeric(8,2);
  question_version_id uuid;
begin
  select attempt.activity_version_id
  into attempt_version_id
  from learning.attempts as attempt
  where attempt.id = new.attempt_id;

  select question.activity_version_id, question.max_score
  into question_version_id, authoritative_max_score
  from learning.questions as question
  where question.id = new.question_id;

  if attempt_version_id is null or question_version_id is null
     or attempt_version_id <> question_version_id then
    raise exception using
      errcode = '23514',
      message = 'RESPONSE_QUESTION_VERSION_MISMATCH';
  end if;

  new.max_score := authoritative_max_score;

  if new.awarded_score > authoritative_max_score then
    raise exception using
      errcode = '23514',
      message = 'RESPONSE_SCORE_EXCEEDS_QUESTION_MAXIMUM';
  end if;

  return new;
end;
$$;

create trigger responses_validate_integrity
before insert or update on learning.responses
for each row execute function learning.validate_response_integrity();

create function learning.prevent_completed_attempt_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'completed' then
    raise exception using
      errcode = '55000',
      message = 'COMPLETED_ATTEMPT_IMMUTABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger attempts_prevent_completed_mutation
before update or delete on learning.attempts
for each row execute function learning.prevent_completed_attempt_mutation();

create function learning.prevent_completed_response_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from learning.attempts as attempt
    where attempt.id = old.attempt_id
      and attempt.status = 'completed'
  ) then
    raise exception using
      errcode = '55000',
      message = 'COMPLETED_RESPONSE_IMMUTABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger responses_prevent_completed_mutation
before update or delete on learning.responses
for each row execute function learning.prevent_completed_response_mutation();
