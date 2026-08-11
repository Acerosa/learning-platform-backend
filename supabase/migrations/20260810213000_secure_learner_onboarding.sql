alter table learning.groups
  add column year_group text,
  add column registration_key text,
  add column registration_open boolean not null default false,
  add constraint groups_year_group_valid
    check (year_group is null or year_group in ('Year 1', 'Year 2')),
  add constraint groups_registration_key_valid
    check (
      registration_key is null
      or registration_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    ),
  add constraint groups_open_registration_configured
    check (
      not registration_open
      or (year_group is not null and registration_key is not null)
    );

create unique index groups_registration_key_unique
  on learning.groups (registration_key)
  where registration_key is not null;

comment on column learning.groups.year_group is
  'Controlled learner stage for this cohort. Null means the group is not configured for self-onboarding.';

comment on column learning.groups.registration_key is
  'Stable learner-safe selector used by the onboarding API instead of an internal group UUID.';

comment on column learning.groups.registration_open is
  'Explicit opt-in for learner self-onboarding. Existing groups remain closed by default.';

create or replace view api.my_profile
with (security_invoker = true)
as
select
  student.student_number,
  student.first_name,
  student.display_name,
  student.surname,
  student.contact_email
from learning.students as student
where student.id = (select learning.current_student_id());

create or replace view api.my_enrolments
with (security_invoker = true)
as
select
  enrolment.id as enrolment_id,
  learner_group.code as group_code,
  learner_group.name as group_name,
  academic_year.code as academic_year,
  course.title as course_title,
  enrolment.joined_on,
  enrolment.left_on,
  enrolment.status,
  learner_group.year_group
from learning.enrolments as enrolment
join learning.groups as learner_group on learner_group.id = enrolment.group_id
join learning.academic_years as academic_year
  on academic_year.id = learner_group.academic_year_id
join learning.courses as course on course.id = learner_group.course_id
where enrolment.student_id = (select learning.current_student_id());

grant select (surname, contact_email) on learning.students to authenticated;

create function api.registration_options()
returns table (
  registration_option text,
  academic_year text,
  year_group text,
  course_key text,
  course_title text,
  group_code text,
  group_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    learner_group.registration_key,
    academic_year.code,
    learner_group.year_group,
    course.stable_key,
    course.title,
    learner_group.code,
    learner_group.name
  from learning.groups as learner_group
  join learning.academic_years as academic_year
    on academic_year.id = learner_group.academic_year_id
  join learning.courses as course
    on course.id = learner_group.course_id
  where learner_group.registration_open
    and learner_group.active
    and academic_year.active
    and course.active
    and learner_group.registration_key is not null
    and learner_group.year_group is not null
  order by
    academic_year.code desc,
    course.title,
    learner_group.year_group,
    learner_group.name
$$;

comment on function api.registration_options() is
  'Returns only explicitly opened, active learner registration choices without private UUIDs.';

create function api.complete_learner_onboarding(
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

    if not found or v_existing_enrolment.status <> 'active' then
      raise exception using errcode = '23000', message = 'ONBOARDING_CONFLICT';
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
      true
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
  'Atomically creates or safely links the current Auth learner and enrols them in one controlled group.';

revoke all on function api.registration_options() from public, anon, authenticated;
revoke all on function api.complete_learner_onboarding(text, text, text, text)
  from public, anon, authenticated;

grant execute on function api.registration_options() to authenticated;
grant execute on function api.complete_learner_onboarding(text, text, text, text)
  to authenticated;
