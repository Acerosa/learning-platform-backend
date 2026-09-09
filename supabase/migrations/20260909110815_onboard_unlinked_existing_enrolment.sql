-- Allow an unlinked matching roster learner to complete onboarding when they
-- already have an enrolment in the requested open group.
-- Previously, the student-number link path always inserted a new enrolment and
-- mapped the unique-constraint failure to ONBOARDING_CONFLICT, which also
-- rolled back the Auth link. Reuse or reactivate the existing enrolment instead.

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
  v_registration_option text;
  v_group_id uuid;
  v_group_active boolean;
  v_registration_open boolean;
  v_academic_year_active boolean;
  v_course_active boolean;
  v_student learning.students%rowtype;
  v_existing_enrolment learning.enrolments%rowtype;
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
  v_registration_option := nullif(btrim(p_registration_option), '');

  if v_first_name is null or length(v_first_name) > 100 then
    raise exception using errcode = '22023', message = 'INVALID_FIRST_NAME';
  end if;

  if v_surname is null or length(v_surname) > 100 then
    raise exception using errcode = '22023', message = 'INVALID_SURNAME';
  end if;

  if v_student_number is null or length(v_student_number) > 100 then
    raise exception using errcode = '22023', message = 'INVALID_STUDENT_NUMBER';
  end if;

  if v_registration_option is null then
    raise exception using errcode = '22023', message = 'INVALID_REGISTRATION_OPTION';
  end if;

  select
    learner_group.id,
    learner_group.active,
    learner_group.registration_open,
    academic_year.active,
    course.active
  into
    v_group_id,
    v_group_active,
    v_registration_open,
    v_academic_year_active,
    v_course_active
  from learning.groups as learner_group
  join learning.academic_years as academic_year
    on academic_year.id = learner_group.academic_year_id
  join learning.courses as course
    on course.id = learner_group.course_id
  where learner_group.registration_key = v_registration_option
  for share of learner_group, academic_year, course;

  if v_group_id is null or not v_registration_open or not v_course_active then
    raise exception using errcode = '22023', message = 'INVALID_REGISTRATION_OPTION';
  end if;

  if not v_group_active then
    raise exception using errcode = '22023', message = 'GROUP_INACTIVE';
  end if;

  if not v_academic_year_active then
    raise exception using errcode = '22023', message = 'ACADEMIC_YEAR_INACTIVE';
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

    if not v_student.active
       or v_student.first_name <> v_first_name
       or coalesce(v_student.surname, '') <> v_surname
       or lower(coalesce(v_student.contact_email, '')) <> v_auth_email then
      raise exception using errcode = '23000', message = 'ONBOARDING_CONFLICT';
    end if;

    select enrolment.*
    into v_existing_enrolment
    from learning.enrolments as enrolment
    where enrolment.student_id = v_student.id
      and enrolment.group_id = v_group_id
    order by (enrolment.status = 'active') desc, enrolment.joined_on desc
    limit 1
    for update;

    if found and v_existing_enrolment.status = 'active' then
      return query
      select
        v_student.student_number,
        v_student.first_name,
        v_student.surname,
        v_student.display_name,
        v_student.contact_email,
        academic_year.code,
        learner_group.year_group,
        course.title,
        learner_group.code,
        learner_group.name,
        v_existing_enrolment.status,
        true
      from learning.groups as learner_group
      join learning.academic_years as academic_year
        on academic_year.id = learner_group.academic_year_id
      join learning.courses as course
        on course.id = learner_group.course_id
      where learner_group.id = v_group_id;
      return;
    end if;

    if found and v_existing_enrolment.status <> 'active' then
      update learning.enrolments
      set status = 'active',
          left_on = null,
          updated_at = clock_timestamp()
      where id = v_existing_enrolment.id
      returning * into v_existing_enrolment;
    else
      insert into learning.enrolments (
        student_id,
        group_id,
        joined_on,
        status
      ) values (
        v_student.id,
        v_group_id,
        current_date,
        'active'
      )
      returning * into v_existing_enrolment;
    end if;

    return query
    select
      v_student.student_number,
      v_student.first_name,
      v_student.surname,
      v_student.display_name,
      v_student.contact_email,
      academic_year.code,
      learner_group.year_group,
      course.title,
      learner_group.code,
      learner_group.name,
      v_existing_enrolment.status,
      false
    from learning.groups as learner_group
    join learning.academic_years as academic_year
      on academic_year.id = learner_group.academic_year_id
    join learning.courses as course
      on course.id = learner_group.course_id
    where learner_group.id = v_group_id;
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
      where id = v_student.id;
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

  select enrolment.*
  into v_existing_enrolment
  from learning.enrolments as enrolment
  where enrolment.student_id = v_student.id
    and enrolment.group_id = v_group_id
  order by (enrolment.status = 'active') desc, enrolment.joined_on desc
  limit 1
  for update;

  if found and v_existing_enrolment.status = 'active' then
    return query
    select
      v_student.student_number,
      v_student.first_name,
      v_student.surname,
      v_student.display_name,
      v_student.contact_email,
      academic_year.code,
      learner_group.year_group,
      course.title,
      learner_group.code,
      learner_group.name,
      v_existing_enrolment.status,
      true
    from learning.groups as learner_group
    join learning.academic_years as academic_year
      on academic_year.id = learner_group.academic_year_id
    join learning.courses as course
      on course.id = learner_group.course_id
    where learner_group.id = v_group_id;
    return;
  end if;

  if found and v_existing_enrolment.status <> 'active' then
    update learning.enrolments
    set status = 'active',
        left_on = null,
        updated_at = clock_timestamp()
    where id = v_existing_enrolment.id
    returning * into v_existing_enrolment;
  else
    begin
      insert into learning.enrolments (
        student_id,
        group_id,
        joined_on,
        status
      ) values (
        v_student.id,
        v_group_id,
        current_date,
        'active'
      )
      returning * into v_existing_enrolment;
    exception
      when unique_violation then
        raise exception using errcode = '23000', message = 'ONBOARDING_CONFLICT';
    end;
  end if;

  return query
  select
    v_student.student_number,
    v_student.first_name,
    v_student.surname,
    v_student.display_name,
    v_student.contact_email,
    academic_year.code,
    learner_group.year_group,
    course.title,
    learner_group.code,
    learner_group.name,
    v_existing_enrolment.status,
    false
  from learning.groups as learner_group
  join learning.academic_years as academic_year
    on academic_year.id = learner_group.academic_year_id
  join learning.courses as course
    on course.id = learner_group.course_id
  where learner_group.id = v_group_id;
end
$$;

comment on function api.complete_learner_onboarding(text, text, text, text) is
  'Atomically creates or safely links the current Auth learner and enrols them in one open registration group. Existing linked learners may join an additional open group. Matching unlinked roster learners reuse or reactivate an existing enrolment in the requested group instead of raising ONBOARDING_CONFLICT.';

revoke all on function api.complete_learner_onboarding(text, text, text, text)
  from public, anon, authenticated;
grant execute on function api.complete_learner_onboarding(text, text, text, text)
  to authenticated;
