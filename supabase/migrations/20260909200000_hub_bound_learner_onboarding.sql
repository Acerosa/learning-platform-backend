-- Hub-bound learner onboarding: profile linking is not group authority.
-- api.complete_learner_onboarding creates/links learning.students only.
-- Hub enrolment is api.resolve_learner_hub_access (open_auto) or
-- api.join_learner_hub_group (open_explicit class key).
-- Do not apply this migration to hosted production until review.

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

    if not v_student.active
       or v_student.first_name <> v_first_name
       or coalesce(v_student.surname, '') <> v_surname
       or lower(coalesce(v_student.contact_email, '')) <> v_auth_email then
      raise exception using errcode = '23000', message = 'ONBOARDING_CONFLICT';
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
  'Creates or safely links the current Auth learner profile. p_registration_option is accepted for compatibility and is ignored. It does not create, reactivate or choose enrolments. Hub access is api.resolve_learner_hub_access or api.join_learner_hub_group.';

revoke all on function api.complete_learner_onboarding(text, text, text, text)
  from public, anon, authenticated;
grant execute on function api.complete_learner_onboarding(text, text, text, text)
  to authenticated;

create or replace function api.registration_options()
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
    null::text,
    null::text,
    null::text,
    null::text,
    null::text,
    null::text,
    null::text
  where false
$$;

comment on function api.registration_options() is
  'Compatibility stub. Does not list class keys or teaching groups. Hub enrolment is resolved server-side.';

revoke all on function api.registration_options()
  from public, anon, authenticated;
grant execute on function api.registration_options()
  to authenticated;

create function api.join_learner_hub_group(
  p_hub_code text,
  p_class_key text
)
returns table (
  status text,
  idempotent boolean,
  academic_year text,
  year_group text,
  course_title text,
  group_code text,
  group_name text,
  enrolment_status text
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_hub_code text;
  v_class_key text;
  v_hub_id uuid;
  v_hub_active boolean;
  v_student_id uuid;
  v_student_active boolean;
  v_group_id uuid;
  v_academic_year text;
  v_year_group text;
  v_course_title text;
  v_group_code text;
  v_group_name text;
  v_enrolment learning.enrolments%rowtype;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;

  if not exists (
    select 1
    from auth.users as auth_user
    where auth_user.id = v_auth_user_id
      and auth_user.email is not null
      and auth_user.email_confirmed_at is not null
  ) then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;

  v_hub_code := nullif(btrim(p_hub_code), '');
  v_class_key := nullif(btrim(p_class_key), '');

  if v_hub_code is null
     or v_hub_code !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     or length(v_hub_code) > 80 then
    raise exception using errcode = '22023', message = 'INVALID_HUB_CODE';
  end if;

  if v_class_key is null or length(v_class_key) > 100 then
    raise exception using errcode = '22023', message = 'INVALID_CLASS_KEY';
  end if;

  select hub.id, hub.active
  into v_hub_id, v_hub_active
  from platform.hubs as hub
  where hub.hub_code = v_hub_code;

  if v_hub_id is null then
    raise exception using errcode = '22023', message = 'HUB_UNKNOWN';
  end if;

  if not v_hub_active then
    raise exception using errcode = '22023', message = 'HUB_INACTIVE';
  end if;

  select student.id, student.active
  into v_student_id, v_student_active
  from learning.students as student
  where student.auth_user_id = v_auth_user_id;

  if v_student_id is null or not coalesce(v_student_active, false) then
    raise exception using errcode = '22023', message = 'PROFILE_REQUIRED';
  end if;

  select
    learner_group.id,
    academic_year.code,
    learner_group.year_group,
    course.title,
    learner_group.code,
    learner_group.name
  into v_group_id, v_academic_year, v_year_group,
       v_course_title, v_group_code, v_group_name
  from platform.hub_group_links as link
  join learning.groups as learner_group
    on learner_group.id = link.group_id
  join learning.academic_years as academic_year
    on academic_year.id = learner_group.academic_year_id
  join learning.courses as course
    on course.id = learner_group.course_id
  where link.hub_id = v_hub_id
    and link.active
    and link.join_policy = 'open_explicit'
    and learner_group.registration_open
    and learner_group.active
    and academic_year.active
    and course.active
    and learner_group.registration_key = v_class_key
  for share of link, learner_group, academic_year, course;

  if v_group_id is null then
    raise exception using errcode = '22023', message = 'INVALID_CLASS_KEY';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('learner-hub-join:' || v_auth_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('learner-hub-join-group:' || v_group_id::text, 0)
  );

  select enrolment.*
  into v_enrolment
  from learning.enrolments as enrolment
  where enrolment.student_id = v_student_id
    and enrolment.group_id = v_group_id
  order by (enrolment.status = 'active') desc, enrolment.joined_on desc
  limit 1
  for update;

  if found and v_enrolment.status = 'active' then
    status := 'enrolled';
    idempotent := true;
    academic_year := v_academic_year;
    year_group := v_year_group;
    course_title := v_course_title;
    group_code := v_group_code;
    group_name := v_group_name;
    enrolment_status := v_enrolment.status;
    return next;
    return;
  end if;

  if found then
    update learning.enrolments
    set status = 'active',
        left_on = null,
        updated_at = clock_timestamp()
    where id = v_enrolment.id
    returning * into v_enrolment;

    status := 'enrolled_reactivated';
    idempotent := false;
    academic_year := v_academic_year;
    year_group := v_year_group;
    course_title := v_course_title;
    group_code := v_group_code;
    group_name := v_group_name;
    enrolment_status := v_enrolment.status;
    return next;
    return;
  end if;

  begin
    insert into learning.enrolments (
      student_id,
      group_id,
      joined_on,
      status
    ) values (
      v_student_id,
      v_group_id,
      current_date,
      'active'
    )
    returning * into v_enrolment;
  exception
    when unique_violation then
      select enrolment.*
      into v_enrolment
      from learning.enrolments as enrolment
      where enrolment.student_id = v_student_id
        and enrolment.group_id = v_group_id
      order by (enrolment.status = 'active') desc, enrolment.joined_on desc
      limit 1;
      if v_enrolment.status <> 'active' then
        update learning.enrolments
        set status = 'active',
            left_on = null,
            updated_at = clock_timestamp()
        where id = v_enrolment.id
        returning * into v_enrolment;
        status := 'enrolled_reactivated';
        idempotent := false;
      else
        status := 'enrolled';
        idempotent := true;
      end if;
      academic_year := v_academic_year;
      year_group := v_year_group;
      course_title := v_course_title;
      group_code := v_group_code;
      group_name := v_group_name;
      enrolment_status := v_enrolment.status;
      return next;
      return;
  end;

  status := 'enrolled_created';
  idempotent := false;
  academic_year := v_academic_year;
  year_group := v_year_group;
  course_title := v_course_title;
  group_code := v_group_code;
  group_name := v_group_name;
  enrolment_status := v_enrolment.status;
  return next;
end
$$;

comment on function api.join_learner_hub_group(text, text) is
  'Enrols the current Auth learner into an open_explicit group bound to the requested hub when the class key matches that group. Identity is auth.uid(). Does not accept group UUIDs. open_auto groups are not joined here; use api.resolve_learner_hub_access. closed groups cannot be joined.';

revoke all on function api.join_learner_hub_group(text, text)
  from public, anon, authenticated;
grant execute on function api.join_learner_hub_group(text, text)
  to authenticated;

comment on column platform.hub_group_links.join_policy is
  'open_auto: resolver may auto-enrol or reactivate this hub-bound group when it is eligible. Other-hub enrolments do not block that write. open_explicit: api.join_learner_hub_group with a matching class key only; opening the hub does not enrol or reactivate. closed: access only if already actively enrolled.';
