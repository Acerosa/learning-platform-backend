-- Returning learners who are already linked to auth.uid() must not fail
-- complete_learner_onboarding with ONBOARDING_CONFLICT merely because
-- contact_email is null or names differ slightly. Mistaken client calls
-- (identity form shown for class-key-only join) must be idempotent.
-- Wrong Student ID for an already-linked Auth account still raises
-- AUTH_ACCOUNT_ALREADY_LINKED. STUDENT_NUMBER_ALREADY_LINKED is unchanged
-- for claiming another Auth user's Student ID.

create or replace function api.complete_learner_onboarding(
  p_first_name text,
  p_surname text,
  p_student_number text,
  p_registration_option text
)
returns table (
  student_number text,
  first_name text,
  surname text,
  display_name text,
  contact_email text,
  academic_year text,
  year_group text,
  course_title text,
  group_code text,
  group_name text,
  enrolment_status text,
  idempotent boolean
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_auth_email text;
  v_first_name text;
  v_surname text;
  v_student_number text;
  v_student learning.students%rowtype;
begin
  v_auth_user_id := auth.uid();

  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;

  select lower(btrim(auth_user.email))
  into v_auth_email
  from auth.users as auth_user
  where auth_user.id = v_auth_user_id
    and auth_user.email is not null
    and auth_user.email_confirmed_at is not null;

  if v_auth_email is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;

  v_first_name := nullif(btrim(p_first_name), '');
  v_surname := nullif(btrim(p_surname), '');
  v_student_number := nullif(btrim(p_student_number), '');

  if v_first_name is null or length(v_first_name) > 100 then
    raise exception using errcode = '22023', message = 'INVALID_FIRST_NAME';
  end if;

  if v_surname is null or length(v_surname) > 100 then
    raise exception using errcode = '22023', message = 'INVALID_SURNAME';
  end if;

  if v_student_number is null or length(v_student_number) > 100 then
    raise exception using errcode = '22023', message = 'INVALID_STUDENT_NUMBER';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('learner-onboarding-auth:' || v_auth_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('learner-onboarding-number:' || v_student_number, 0)
  );

  select student.*
  into v_student
  from learning.students as student
  where student.auth_user_id = v_auth_user_id
  for update;

  if found then
    if v_student.student_number <> v_student_number then
      raise exception using errcode = '23000', message = 'AUTH_ACCOUNT_ALREADY_LINKED';
    end if;

    if not v_student.active then
      raise exception using errcode = '23000', message = 'ONBOARDING_CONFLICT';
    end if;

    -- Same Auth + same Student ID: idempotent success. Soft-fill contact_email
    -- when roster rows were linked without an email so later checks stay aligned.
    if v_student.contact_email is null
       or lower(btrim(v_student.contact_email)) = '' then
      update learning.students
      set contact_email = v_auth_email,
          updated_at = clock_timestamp()
      where id = v_student.id
      returning * into v_student;
    end if;

    return query
    select
      v_student.student_number,
      v_student.first_name,
      v_student.surname,
      v_student.display_name,
      v_student.contact_email,
      null::text,
      null::text,
      null::text,
      null::text,
      null::text,
      null::text,
      true;
    return;
  end if;

  select student.*
  into v_student
  from learning.students as student
  where student.student_number = v_student_number
  for update;

  if found then
    if v_student.auth_user_id is not null then
      raise exception using errcode = '23505', message = 'STUDENT_NUMBER_ALREADY_LINKED';
    end if;

    if not v_student.active
       or lower(v_student.first_name) <> lower(v_first_name)
       or lower(coalesce(v_student.surname, '')) <> lower(v_surname)
       or lower(coalesce(v_student.contact_email, '')) <> v_auth_email then
      raise exception using errcode = '23000', message = 'ONBOARDING_CONFLICT';
    end if;

    begin
      update learning.students
      set auth_user_id = v_auth_user_id,
          updated_at = clock_timestamp()
      where id = v_student.id
      returning * into v_student;
    exception
      when unique_violation then
        raise exception using errcode = '23000', message = 'AUTH_ACCOUNT_ALREADY_LINKED';
    end;
  else
    begin
      insert into learning.students (
        auth_user_id,
        student_number,
        first_name,
        surname,
        display_name,
        contact_email,
        active
      ) values (
        v_auth_user_id,
        v_student_number,
        v_first_name,
        v_surname,
        v_first_name || ' ' || v_surname,
        v_auth_email,
        true
      )
      returning * into v_student;
    exception
      when unique_violation then
        if exists (
          select 1
          from learning.students as student
          where student.student_number = v_student_number
        ) then
          raise exception using errcode = '23505', message = 'STUDENT_NUMBER_ALREADY_LINKED';
        end if;
        raise exception using errcode = '23000', message = 'AUTH_ACCOUNT_ALREADY_LINKED';
    end;
  end if;

  return query
  select
    v_student.student_number,
    v_student.first_name,
    v_student.surname,
    v_student.display_name,
    v_student.contact_email,
    null::text,
    null::text,
    null::text,
    null::text,
    null::text,
    null::text,
    false;
end
$$;

comment on function api.complete_learner_onboarding(text, text, text, text) is
  'Creates or safely links the current Auth learner profile. Already-linked Auth+Student ID is idempotent even when contact_email was null. p_registration_option is ignored. Hub access is resolve_learner_hub_access or join_learner_hub_group.';

revoke all on function api.complete_learner_onboarding(text, text, text, text)
  from public, anon, authenticated;
grant execute on function api.complete_learner_onboarding(text, text, text, text)
  to authenticated;
