-- Add a synthetic QA learner that joins the existing TLEVEL-DSD-Y2 teaching
-- group without converting it, without exclusive-smoke restrictions, and
-- without creating a second T Level QA group. TLEVEL-TEST-A stays exclusive.

begin;

alter table learning.synthetic_qa_fixtures
  add column if not exists join_existing_group boolean not null default false;

alter table learning.synthetic_qa_fixtures
  drop constraint if exists synthetic_qa_join_existing_not_exclusive;

alter table learning.synthetic_qa_fixtures
  add constraint synthetic_qa_join_existing_not_exclusive
  check (not join_existing_group or not exclusive_smoke);

comment on column learning.synthetic_qa_fixtures.join_existing_group is
  'When true, ensure/provision reuse an existing teaching group as-is. The group is not marked synthetic, registration is unchanged, and assignments are not upserted or deactivated.';

insert into learning.synthetic_qa_fixtures (
  persona,
  group_code,
  student_number,
  first_name,
  surname,
  display_name,
  course_key,
  module_key,
  hub_code,
  smoke_activity_key,
  exclusive_smoke,
  join_existing_group,
  group_name,
  purpose,
  group_id_stable
) values (
  'TLEVEL_DSD_Y2_TEST_LEARNER',
  'TLEVEL-DSD-Y2',
  'QA-TLEVEL-DSD-Y2',
  'Synthetic',
  'T Level DSD Y2 Learner',
  'Synthetic T Level DSD Y2 Learner',
  't-level-digital-software-development',
  'tlevel-software-development',
  'tlevel-software-development',
  'week-1-lesson-1-ex-07',
  false,
  true,
  'T Level Digital Software Development - Year 2',
  'formative-smoke-test',
  '60000000-0000-4000-8000-000000000014'
)
on conflict (persona) do update
set
  group_code = excluded.group_code,
  student_number = excluded.student_number,
  first_name = excluded.first_name,
  surname = excluded.surname,
  display_name = excluded.display_name,
  course_key = excluded.course_key,
  module_key = excluded.module_key,
  hub_code = excluded.hub_code,
  smoke_activity_key = excluded.smoke_activity_key,
  exclusive_smoke = excluded.exclusive_smoke,
  join_existing_group = excluded.join_existing_group,
  group_name = excluded.group_name,
  purpose = excluded.purpose,
  group_id_stable = excluded.group_id_stable;

create or replace function learning.ensure_synthetic_qa_groups()
returns table (
  persona text,
  group_code text,
  created_or_reused text,
  assignment_count integer,
  skipped_reason text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fixture learning.synthetic_qa_fixtures%rowtype;
  v_course_id uuid;
  v_module_id uuid;
  v_year_id uuid;
  v_group_id uuid;
  v_existing_id uuid;
  v_created text;
  v_assignments integer;
  v_activity_key text;
  v_smoke_version_id uuid;
  v_allowed_version_ids uuid[] := '{}'::uuid[];
begin
  select candidate.id
  into v_year_id
  from learning.academic_years as candidate
  where candidate.active
  order by candidate.code
  limit 1;

  if v_year_id is null then
    raise exception using errcode = '22023', message = 'ACADEMIC_YEAR_INACTIVE';
  end if;

  for v_fixture in
    select *
    from learning.synthetic_qa_fixtures
    order by persona
  loop
    persona := v_fixture.persona;
    group_code := v_fixture.group_code;
    skipped_reason := null;
    created_or_reused := null;
    assignment_count := 0;
    v_allowed_version_ids := '{}'::uuid[];

    select course.id
    into v_course_id
    from learning.courses as course
    where course.stable_key = v_fixture.course_key
      and course.active;

    if v_course_id is null then
      skipped_reason := 'COURSE_NOT_FOUND';
      return next;
      continue;
    end if;

    select module.id
    into v_module_id
    from learning.modules as module
    where module.course_id = v_course_id
      and module.stable_key = v_fixture.module_key
      and module.active;

    if v_module_id is null then
      skipped_reason := 'MODULE_NOT_FOUND';
      return next;
      continue;
    end if;

    select learner_group.id
    into v_existing_id
    from learning.groups as learner_group
    where learner_group.academic_year_id = v_year_id
      and learner_group.course_id = v_course_id
      and learner_group.code = v_fixture.group_code;

    if v_fixture.join_existing_group then
      if v_existing_id is null then
        skipped_reason := 'TEACHING_GROUP_NOT_FOUND';
        return next;
        continue;
      end if;

      v_group_id := v_existing_id;
      v_created := 'joined';

      select count(*)::integer
      into v_assignments
      from learning.activity_assignments as assignment
      where assignment.group_id = v_group_id
        and assignment.active;

      created_or_reused := v_created;
      assignment_count := v_assignments;
      return next;
      continue;
    end if;

    if v_existing_id is null then
      insert into learning.groups (
        id,
        academic_year_id,
        course_id,
        code,
        name,
        active,
        year_group,
        registration_key,
        registration_open,
        is_synthetic,
        synthetic_purpose
      ) values (
        v_fixture.group_id_stable,
        v_year_id,
        v_course_id,
        v_fixture.group_code,
        v_fixture.group_name,
        true,
        'Year 1',
        lower(replace(v_fixture.group_code, '_', '-')) || '-reg',
        false,
        true,
        v_fixture.purpose
      )
      on conflict (academic_year_id, course_id, code) do update
      set
        name = excluded.name,
        active = true,
        year_group = excluded.year_group,
        registration_open = false,
        is_synthetic = true,
        synthetic_purpose = excluded.synthetic_purpose,
        updated_at = clock_timestamp()
      returning id into v_group_id;
      v_created := 'created';
    else
      update learning.groups
      set
        active = true,
        registration_open = false,
        is_synthetic = true,
        synthetic_purpose = v_fixture.purpose,
        year_group = coalesce(year_group, 'Year 1'),
        updated_at = clock_timestamp()
      where id = v_existing_id;
      v_group_id := v_existing_id;
      v_created := 'reused';
    end if;

    for v_activity_key in
      select allowed.activity_key
      from learning.synthetic_qa_allowed_activity_keys(v_fixture.persona) as allowed
      order by allowed.activity_key
    loop
      select latest.id
      into v_smoke_version_id
      from learning.activities as activity
      join lateral (
        select activity_version.id
        from learning.activity_versions as activity_version
        where activity_version.activity_id = activity.id
          and activity_version.published_at is not null
          and activity_version.retired_at is null
        order by activity_version.published_at desc, activity_version.version desc
        limit 1
      ) as latest on true
      where activity.module_id = v_module_id
        and activity.stable_key = v_activity_key
        and activity.active;

      if v_smoke_version_id is null then
        continue;
      end if;

      v_allowed_version_ids := array_append(v_allowed_version_ids, v_smoke_version_id);

      insert into learning.activity_assignments (
        id,
        group_id,
        activity_version_id,
        required,
        active
      )
      values (
        md5(
          'synthetic-qa:'
          || v_group_id::text
          || ':'
          || v_smoke_version_id::text
        )::uuid,
        v_group_id,
        v_smoke_version_id,
        true,
        true
      )
      on conflict (group_id, activity_version_id) do update
      set
        required = excluded.required,
        active = excluded.active;
    end loop;

    if v_fixture.exclusive_smoke and coalesce(array_length(v_allowed_version_ids, 1), 0) > 0 then
      update learning.activity_assignments as assignment
      set active = false
      where assignment.group_id = v_group_id
        and assignment.active
        and not (assignment.activity_version_id = any (v_allowed_version_ids));
    end if;

    select count(*)::integer
    into v_assignments
    from learning.activity_assignments as assignment
    where assignment.group_id = v_group_id
      and assignment.active;

    created_or_reused := v_created;
    assignment_count := v_assignments;
    return next;
  end loop;
end
$$;

comment on function learning.ensure_synthetic_qa_groups() is
  'Creates or reuses closed synthetic QA groups and upserts the catalogued smoke activity allowlist. exclusive_smoke groups keep only that allowlist active. join_existing_group fixtures reuse a teaching group as-is and do not create, convert, or reassign it.';

comment on table learning.synthetic_qa_fixtures is
  'Catalog of permanent synthetic QA learners. exclusive_smoke groups receive only catalogued smoke activities. join_existing_group personas enrol into an existing teaching group without converting it.';

create or replace function learning.provision_synthetic_qa_learner(
  p_auth_user_id uuid,
  p_persona text
)
returns table (
  persona text,
  student_number text,
  display_name text,
  group_code text,
  enrolment_status text,
  idempotent boolean
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_fixture learning.synthetic_qa_fixtures%rowtype;
  v_group_id uuid;
  v_student learning.students%rowtype;
  v_enrolment learning.enrolments%rowtype;
  v_idempotent boolean := false;
begin
  if p_auth_user_id is null then
    raise exception using errcode = '22023', message = 'AUTH_USER_REQUIRED';
  end if;

  select fixture.*
  into v_fixture
  from learning.synthetic_qa_fixtures as fixture
  where fixture.persona = p_persona;

  if not found then
    raise exception using errcode = '22023', message = 'UNKNOWN_QA_PERSONA';
  end if;

  if not exists (
    select 1
    from auth.users as auth_user
    where auth_user.id = p_auth_user_id
  ) then
    raise exception using errcode = '22023', message = 'AUTH_USER_NOT_FOUND';
  end if;

  if exists (
    select 1
    from learning.teachers as teacher
    where teacher.auth_user_id = p_auth_user_id
  ) then
    raise exception using errcode = '42501', message = 'SYNTHETIC_STAFF_FORBIDDEN';
  end if;

  select learner_group.id
  into v_group_id
  from learning.groups as learner_group
  join learning.courses as course on course.id = learner_group.course_id
  where learner_group.code = v_fixture.group_code
    and course.stable_key = v_fixture.course_key
    and learner_group.active
    and (
      learner_group.is_synthetic
      or v_fixture.join_existing_group
    );

  if v_group_id is null then
    raise exception using errcode = '22023', message = 'QA_GROUP_NOT_FOUND';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('synthetic-qa:' || v_fixture.persona, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('synthetic-qa-auth:' || p_auth_user_id::text, 0)
  );

  select student.*
  into v_student
  from learning.students as student
  where student.auth_user_id = p_auth_user_id
  for update;

  if found then
    if not v_student.is_synthetic
       or v_student.student_number <> v_fixture.student_number then
      raise exception using errcode = '23000', message = 'AUTH_ACCOUNT_ALREADY_LINKED';
    end if;
    v_idempotent := true;
  else
    select student.*
    into v_student
    from learning.students as student
    where student.student_number = v_fixture.student_number
    for update;

    if found then
      if not v_student.is_synthetic then
        raise exception using errcode = '23000', message = 'STUDENT_NUMBER_ALREADY_LINKED';
      end if;
      if v_student.auth_user_id is not null
         and v_student.auth_user_id <> p_auth_user_id then
        raise exception using errcode = '23000', message = 'AUTH_ACCOUNT_ALREADY_LINKED';
      end if;
      update learning.students
      set auth_user_id = p_auth_user_id,
          updated_at = clock_timestamp()
      where id = v_student.id
      returning * into v_student;
      v_idempotent := true;
    else
      insert into learning.students (
        auth_user_id,
        student_number,
        first_name,
        surname,
        display_name,
        contact_email,
        active,
        is_synthetic,
        synthetic_purpose
      ) values (
        p_auth_user_id,
        v_fixture.student_number,
        v_fixture.first_name,
        v_fixture.surname,
        v_fixture.display_name,
        null,
        true,
        true,
        v_fixture.purpose
      )
      returning * into v_student;
    end if;
  end if;

  update learning.students
  set first_name = v_fixture.first_name,
      surname = v_fixture.surname,
      display_name = v_fixture.display_name,
      contact_email = null,
      active = true,
      is_synthetic = true,
      synthetic_purpose = v_fixture.purpose,
      updated_at = clock_timestamp()
  where id = v_student.id
  returning * into v_student;

  select enrolment.*
  into v_enrolment
  from learning.enrolments as enrolment
  where enrolment.student_id = v_student.id
    and enrolment.group_id = v_group_id
  for update;

  if found then
    if v_enrolment.status <> 'active' then
      update learning.enrolments
      set status = 'active',
          left_on = null,
          updated_at = clock_timestamp()
      where id = v_enrolment.id
      returning * into v_enrolment;
    end if;
    v_idempotent := true;
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
    returning * into v_enrolment;
  end if;

  update learning.enrolments
  set status = 'withdrawn',
      left_on = coalesce(left_on, current_date),
      updated_at = clock_timestamp()
  where student_id = v_student.id
    and status = 'active'
    and group_id <> v_group_id
    and group_id in (
      select learner_group.id
      from learning.groups as learner_group
      join learning.synthetic_qa_fixtures as other
        on other.group_code = learner_group.code
      where other.persona <> v_fixture.persona
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
    'learning.synthetic-qa.provisioned',
    auth.uid(),
    case
      when coalesce(auth.role(), '') = 'service_role' then 'service'
      when auth.uid() is null then 'system'
      else 'staff'
    end,
    'student',
    v_fixture.persona,
    'succeeded',
    jsonb_build_object(
      'persona', v_fixture.persona,
      'groupCode', v_fixture.group_code,
      'studentNumber', v_fixture.student_number,
      'idempotent', v_idempotent
    )
  );

  persona := v_fixture.persona;
  student_number := v_student.student_number;
  display_name := v_student.display_name;
  group_code := v_fixture.group_code;
  enrolment_status := v_enrolment.status;
  idempotent := v_idempotent;
  return next;
end
$$;

comment on function learning.provision_synthetic_qa_learner(uuid, text) is
  'Links an existing Auth user to one synthetic QA learner and one catalogued group. join_existing_group personas may enrol in a matching active teaching group. Identity is auth_user_id; email is not stored.';

select * from learning.ensure_synthetic_qa_groups();

commit;
