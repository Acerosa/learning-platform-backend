-- Permanent synthetic QA fixtures for hub-isolated immediate-feedback testing.
-- Groups and enrolments use the same authorisation path as ordinary learners.
-- Auth users are never created here; they are linked by admin/service RPC.

alter table learning.students
  add column if not exists is_synthetic boolean not null default false,
  add column if not exists synthetic_purpose text;

alter table learning.students
  drop constraint if exists students_synthetic_purpose_required;

alter table learning.students
  add constraint students_synthetic_purpose_required
  check (
    not is_synthetic
    or (synthetic_purpose is not null and btrim(synthetic_purpose) <> '')
  );

alter table learning.groups
  add column if not exists is_synthetic boolean not null default false,
  add column if not exists synthetic_purpose text;

alter table learning.groups
  drop constraint if exists groups_synthetic_purpose_required;

alter table learning.groups
  add constraint groups_synthetic_purpose_required
  check (
    not is_synthetic
    or (synthetic_purpose is not null and btrim(synthetic_purpose) <> '')
  );

comment on column learning.students.is_synthetic is
  'Marks a long-lived QA fixture learner. Does not change RLS or auth.uid() identity.';
comment on column learning.students.synthetic_purpose is
  'Operational purpose for a synthetic learner, for example formative-smoke-test.';
comment on column learning.groups.is_synthetic is
  'Marks an isolated QA teaching group. Does not change enrolment or assignment RLS.';
comment on column learning.groups.synthetic_purpose is
  'Operational purpose for a synthetic group, for example formative-smoke-test.';

create index if not exists students_synthetic_idx
  on learning.students (is_synthetic)
  where is_synthetic;

create index if not exists groups_synthetic_idx
  on learning.groups (is_synthetic)
  where is_synthetic;

grant select (is_synthetic, synthetic_purpose) on learning.students to authenticated;

create table if not exists learning.synthetic_qa_fixtures (
  persona text primary key,
  group_code text not null unique,
  student_number text not null unique,
  first_name text not null,
  surname text not null,
  display_name text not null,
  course_key text not null,
  module_key text not null,
  hub_code text not null,
  smoke_activity_key text not null,
  group_name text not null,
  purpose text not null default 'formative-smoke-test',
  group_id_stable uuid not null unique,
  constraint synthetic_qa_persona_valid
    check (persona ~ '^[A-Z0-9]+(_[A-Z0-9]+)*$'),
  constraint synthetic_qa_group_code_valid
    check (group_code ~ '^[A-Z0-9]+(-[A-Z0-9]+)*$'),
  constraint synthetic_qa_student_number_valid
    check (btrim(student_number) <> ''),
  constraint synthetic_qa_names_valid
    check (
      btrim(first_name) <> ''
      and btrim(surname) <> ''
      and btrim(display_name) <> ''
      and btrim(group_name) <> ''
    ),
  constraint synthetic_qa_purpose_valid
    check (btrim(purpose) <> '')
);

comment on table learning.synthetic_qa_fixtures is
  'Catalog of permanent hub-isolated synthetic QA learners and groups. Not a second authorisation path.';

alter table learning.synthetic_qa_fixtures enable row level security;

revoke all on table learning.synthetic_qa_fixtures
  from public, anon, authenticated;

grant select on table learning.synthetic_qa_fixtures to authenticated;

create policy synthetic_qa_fixtures_staff_read
on learning.synthetic_qa_fixtures
for select
to authenticated
using ((select platform.current_staff_has_role('platform_admin')));

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
  group_name,
  purpose,
  group_id_stable
) values
  (
    'UNIT3_TEST_LEARNER',
    'CYBER-TEST-QA',
    'QA-UNIT3',
    'Synthetic',
    'Unit 3 Learner',
    'Synthetic Unit 3 Learner',
    'ocr-level-3-it',
    'unit-3-cyber-security',
    'unit-3-cyber-security',
    'week2-malware-symptoms',
    'Cyber Security Synthetic QA Group',
    'formative-smoke-test',
    '60000000-0000-4000-8000-000000000011'
  ),
  (
    'TLEVEL_TEST_LEARNER',
    'TLEVEL-TEST-A',
    'QA-TLEVEL',
    'Synthetic',
    'T Level Learner',
    'Synthetic T Level Learner',
    't-level-digital-software-development',
    'tlevel-software-development',
    'tlevel-software-development',
    'week-1-lesson-1-retrieval',
    'T Level Synthetic Test Group A',
    'formative-smoke-test',
    '60000000-0000-4000-8000-000000000012'
  ),
  (
    'UNIT14_TEST_LEARNER',
    'UNIT14-TEST-A',
    'QA-UNIT14',
    'Synthetic',
    'Unit 14 Learner',
    'Synthetic Unit 14 Learner',
    'ocr-level-3-it',
    'unit-14-software-engineering-for-business',
    'unit-14-software-engineering-for-business',
    'week-1-variables-and-data-types',
    'Unit 14 Synthetic Test Group A',
    'formative-smoke-test',
    '8e3fa246-6ebb-5488-8625-8adb5242fe42'
  ),
  (
    'L2E_TEST_LEARNER',
    'L2E-TEST-A',
    'QA-L2E',
    'Synthetic',
    'L2E Learner',
    'Synthetic L2E Learner',
    'gateway-level-2-digital-it-skills',
    'l2e-exploring-emerging-digital-technologies',
    'l2e-exploring-emerging-digital-technologies',
    'week-1-knowledge-check',
    'L2E Synthetic Test Group A',
    'formative-smoke-test',
    '60000000-0000-4000-8000-000000000013'
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
  group_name = excluded.group_name,
  purpose = excluded.purpose,
  group_id_stable = excluded.group_id_stable;

create or replace function learning.synthetic_qa_mutation_authorised()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(auth.role(), '') = 'service_role'
    or (select platform.current_staff_has_role('platform_admin'))
$$;

revoke all on function learning.synthetic_qa_mutation_authorised()
  from public, anon, authenticated;
grant execute on function learning.synthetic_qa_mutation_authorised() to authenticated;

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

    insert into learning.activity_assignments (
      id,
      group_id,
      activity_version_id,
      required,
      active
    )
    select
      md5(
        'synthetic-qa:'
        || v_group_id::text
        || ':'
        || activity_version.id::text
      )::uuid,
      v_group_id,
      activity_version.id,
      true,
      true
    from learning.activities as activity
    join learning.activity_versions as activity_version
      on activity_version.activity_id = activity.id
    where activity.module_id = v_module_id
      and activity.active
      and activity_version.published_at is not null
      and activity_version.retired_at is null
    on conflict (group_id, activity_version_id) do update
    set
      required = excluded.required,
      active = excluded.active;

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
  'Creates or reuses closed synthetic QA groups and assigns currently published module versions. Skips fixtures whose course or module is absent.';

revoke all on function learning.ensure_synthetic_qa_groups()
  from public, anon, authenticated;

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
    and learner_group.is_synthetic
    and learner_group.active;

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
  'Links an existing Auth user to one synthetic QA learner and one hub-isolated group. Identity is auth_user_id; email is not stored.';

revoke all on function learning.provision_synthetic_qa_learner(uuid, text)
  from public, anon, authenticated;

create or replace function learning.set_synthetic_qa_learner_active(
  p_persona text,
  p_active boolean
)
returns table (
  persona text,
  student_number text,
  active boolean
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_fixture learning.synthetic_qa_fixtures%rowtype;
  v_student learning.students%rowtype;
begin
  select fixture.*
  into v_fixture
  from learning.synthetic_qa_fixtures as fixture
  where fixture.persona = p_persona;

  if not found then
    raise exception using errcode = '22023', message = 'UNKNOWN_QA_PERSONA';
  end if;

  select student.*
  into v_student
  from learning.students as student
  where student.student_number = v_fixture.student_number
    and student.is_synthetic
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'QA_LEARNER_NOT_FOUND';
  end if;

  update learning.students
  set active = coalesce(p_active, false),
      updated_at = clock_timestamp()
  where id = v_student.id
  returning * into v_student;

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'learning.synthetic-qa.active-set',
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
      'active', v_student.active
    )
  );

  persona := v_fixture.persona;
  student_number := v_student.student_number;
  active := v_student.active;
  return next;
end
$$;

comment on function learning.set_synthetic_qa_learner_active(text, boolean) is
  'Temporarily disables or re-enables a synthetic QA learner profile. Does not delete evidence or Auth.';

revoke all on function learning.set_synthetic_qa_learner_active(text, boolean)
  from public, anon, authenticated;

create or replace function learning.reject_synthetic_learner_staff_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from learning.students as student
    where student.auth_user_id = new.auth_user_id
      and student.auth_user_id is not null
      and student.is_synthetic
  ) then
    raise exception using
      errcode = '42501',
      message = 'SYNTHETIC_STAFF_FORBIDDEN';
  end if;
  return new;
end
$$;

drop trigger if exists teachers_reject_synthetic_learner on learning.teachers;
create trigger teachers_reject_synthetic_learner
before insert or update of auth_user_id on learning.teachers
for each row
when (new.auth_user_id is not null)
execute function learning.reject_synthetic_learner_staff_role();

revoke all on function learning.reject_synthetic_learner_staff_role()
  from public, anon, authenticated;

create or replace function admin_api.ensure_synthetic_qa_groups()
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
begin
  if not learning.synthetic_qa_mutation_authorised() then
    raise exception using errcode = '42501', message = 'SYNTHETIC_QA_NOT_AUTHORISED';
  end if;

  return query
  select *
  from learning.ensure_synthetic_qa_groups();
end
$$;

create or replace function admin_api.provision_synthetic_qa_learner(
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
begin
  if not learning.synthetic_qa_mutation_authorised() then
    raise exception using errcode = '42501', message = 'SYNTHETIC_QA_NOT_AUTHORISED';
  end if;

  return query
  select *
  from learning.provision_synthetic_qa_learner(p_auth_user_id, p_persona);
end
$$;

create or replace function admin_api.set_synthetic_qa_learner_active(
  p_persona text,
  p_active boolean
)
returns table (
  persona text,
  student_number text,
  active boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not learning.synthetic_qa_mutation_authorised() then
    raise exception using errcode = '42501', message = 'SYNTHETIC_QA_NOT_AUTHORISED';
  end if;

  return query
  select *
  from learning.set_synthetic_qa_learner_active(p_persona, p_active);
end
$$;

revoke all on function admin_api.ensure_synthetic_qa_groups()
  from public, anon, authenticated;
revoke all on function admin_api.provision_synthetic_qa_learner(uuid, text)
  from public, anon, authenticated;
revoke all on function admin_api.set_synthetic_qa_learner_active(text, boolean)
  from public, anon, authenticated;

grant execute on function admin_api.ensure_synthetic_qa_groups()
  to authenticated, service_role;
grant execute on function admin_api.provision_synthetic_qa_learner(uuid, text)
  to authenticated, service_role;
grant execute on function admin_api.set_synthetic_qa_learner_active(text, boolean)
  to authenticated, service_role;

comment on function admin_api.ensure_synthetic_qa_groups() is
  'Platform-admin or service-role refresh of synthetic QA groups and published assignments.';
comment on function admin_api.provision_synthetic_qa_learner(uuid, text) is
  'Platform-admin or service-role mapping of an existing Auth user onto one synthetic QA learner.';
comment on function admin_api.set_synthetic_qa_learner_active(text, boolean) is
  'Platform-admin or service-role disable/enable for a synthetic QA learner profile.';

create or replace view admin_api.synthetic_qa_fixtures
with (security_invoker = true)
as
select
  fixture.persona,
  fixture.group_code,
  fixture.student_number,
  fixture.display_name,
  fixture.hub_code,
  fixture.course_key,
  fixture.module_key,
  fixture.smoke_activity_key,
  fixture.purpose
from learning.synthetic_qa_fixtures as fixture
where (select platform.current_staff_has_role('platform_admin'));

grant select on admin_api.synthetic_qa_fixtures to authenticated;

drop view if exists admin_api.learners;
create view admin_api.learners
with (security_invoker = true)
as
select
  student.id as learner_id,
  student.student_number,
  student.display_name,
  student.active,
  student.is_synthetic,
  student.synthetic_purpose,
  coalesce(enrolment_summary.group_codes, '{}'::text[]) as group_codes,
  coalesce(enrolment_summary.active_enrolment_count, 0::bigint)
    as active_enrolment_count
from learning.students as student
left join lateral (
  select
    array_agg(learner_group.code order by learner_group.code)
      filter (where enrolment.status = 'active') as group_codes,
    count(*) filter (where enrolment.status = 'active')
      as active_enrolment_count
  from learning.enrolments as enrolment
  join learning.groups as learner_group on learner_group.id = enrolment.group_id
  where enrolment.student_id = student.id
) as enrolment_summary on true
where (select platform.current_staff_has_role('platform_admin'));

drop view if exists admin_api.groups;
create view admin_api.groups
with (security_invoker = true)
as
select
  learner_group.id as group_id,
  learner_group.code as group_code,
  learner_group.name as group_name,
  learner_group.year_group,
  learner_group.registration_open,
  learner_group.active,
  learner_group.is_synthetic,
  learner_group.synthetic_purpose,
  academic_year.id as academic_year_id,
  academic_year.code as academic_year,
  course.id as course_id,
  course.stable_key as course_key,
  course.title as course_title,
  (
    select count(*)
    from learning.enrolments as enrolment
    where enrolment.group_id = learner_group.id
      and enrolment.status = 'active'
  ) as active_learner_count
from learning.groups as learner_group
join learning.academic_years as academic_year
  on academic_year.id = learner_group.academic_year_id
join learning.courses as course on course.id = learner_group.course_id
where (select platform.current_staff_has_role('platform_admin'));

grant select on admin_api.learners to authenticated;
grant select on admin_api.groups to authenticated;

do $$
declare
  v_row record;
begin
  for v_row in select * from learning.ensure_synthetic_qa_groups()
  loop
    null;
  end loop;
end
$$;
