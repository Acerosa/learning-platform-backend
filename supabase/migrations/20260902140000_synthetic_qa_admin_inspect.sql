-- Admin/ops read boundary for synthetic QA readiness.
-- Does not expose the learning schema through PostgREST.
-- Does not change learner RLS.

grant usage on schema admin_api to service_role;

create or replace function learning.inspect_synthetic_qa_learners()
returns table (
  persona text,
  student_number text,
  display_name text,
  group_code text,
  smoke_activity_key text,
  student_present boolean,
  student_active boolean,
  is_synthetic boolean,
  synthetic_purpose text,
  contact_email_copied boolean,
  linked_auth_user_id uuid,
  enrolment_codes text[],
  smoke_assigned boolean,
  smoke_version text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    fixture.persona,
    fixture.student_number,
    fixture.display_name,
    fixture.group_code,
    fixture.smoke_activity_key,
    (student.id is not null) as student_present,
    student.active as student_active,
    student.is_synthetic,
    student.synthetic_purpose,
    (student.contact_email is not null) as contact_email_copied,
    student.auth_user_id as linked_auth_user_id,
    coalesce(enrolment_summary.group_codes, '{}'::text[]) as enrolment_codes,
    exists (
      select 1
      from learning.activity_assignments as assignment
      join learning.groups as learner_group
        on learner_group.id = assignment.group_id
      join learning.activity_versions as activity_version
        on activity_version.id = assignment.activity_version_id
      join learning.activities as activity
        on activity.id = activity_version.activity_id
      where learner_group.code = fixture.group_code
        and assignment.active
        and activity.stable_key = fixture.smoke_activity_key
        and activity_version.published_at is not null
        and activity_version.retired_at is null
    ) as smoke_assigned,
    (
      select activity_version.version
      from learning.activity_assignments as assignment
      join learning.groups as learner_group
        on learner_group.id = assignment.group_id
      join learning.activity_versions as activity_version
        on activity_version.id = assignment.activity_version_id
      join learning.activities as activity
        on activity.id = activity_version.activity_id
      where learner_group.code = fixture.group_code
        and assignment.active
        and activity.stable_key = fixture.smoke_activity_key
        and activity_version.published_at is not null
        and activity_version.retired_at is null
      order by activity_version.published_at desc, activity_version.version desc
      limit 1
    ) as smoke_version
  from learning.synthetic_qa_fixtures as fixture
  left join learning.students as student
    on student.student_number = fixture.student_number
  left join lateral (
    select
      array_agg(learner_group.code order by learner_group.code)
        filter (where enrolment.status = 'active') as group_codes
    from learning.enrolments as enrolment
    join learning.groups as learner_group
      on learner_group.id = enrolment.group_id
    where enrolment.student_id = student.id
  ) as enrolment_summary on true
  order by fixture.persona;
$$;

create or replace function learning.inspect_synthetic_qa_auth_user(p_auth_user_id uuid)
returns table (
  auth_user_linked boolean,
  student_number text,
  is_synthetic boolean,
  student_active boolean,
  teacher_linked boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (student.id is not null) as auth_user_linked,
    student.student_number,
    student.is_synthetic,
    student.active as student_active,
    exists (
      select 1
      from learning.teachers as teacher
      where teacher.auth_user_id = p_auth_user_id
    ) as teacher_linked
  from (select p_auth_user_id as auth_user_id) as requested
  left join learning.students as student
    on student.auth_user_id = requested.auth_user_id;
$$;

revoke all on function learning.inspect_synthetic_qa_learners()
  from public, anon, authenticated;
revoke all on function learning.inspect_synthetic_qa_auth_user(uuid)
  from public, anon, authenticated;

create or replace function admin_api.inspect_synthetic_qa_learners()
returns table (
  persona text,
  student_number text,
  display_name text,
  group_code text,
  smoke_activity_key text,
  student_present boolean,
  student_active boolean,
  is_synthetic boolean,
  synthetic_purpose text,
  contact_email_copied boolean,
  linked_auth_user_id uuid,
  enrolment_codes text[],
  smoke_assigned boolean,
  smoke_version text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not learning.synthetic_qa_mutation_authorised() then
    raise exception using
      errcode = '42501',
      message = 'SYNTHETIC_QA_NOT_AUTHORISED';
  end if;

  return query
  select *
  from learning.inspect_synthetic_qa_learners();
end
$$;

create or replace function admin_api.inspect_synthetic_qa_auth_user(p_auth_user_id uuid)
returns table (
  auth_user_linked boolean,
  student_number text,
  is_synthetic boolean,
  student_active boolean,
  teacher_linked boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not learning.synthetic_qa_mutation_authorised() then
    raise exception using
      errcode = '42501',
      message = 'SYNTHETIC_QA_NOT_AUTHORISED';
  end if;

  return query
  select *
  from learning.inspect_synthetic_qa_auth_user(p_auth_user_id);
end
$$;

revoke all on function admin_api.inspect_synthetic_qa_learners()
  from public, anon, authenticated;
revoke all on function admin_api.inspect_synthetic_qa_auth_user(uuid)
  from public, anon, authenticated;

grant execute on function admin_api.inspect_synthetic_qa_learners()
  to authenticated, service_role;
grant execute on function admin_api.inspect_synthetic_qa_auth_user(uuid)
  to authenticated, service_role;

comment on function admin_api.inspect_synthetic_qa_learners() is
  'Platform-admin or service-role read of synthetic QA learner, enrolment and smoke-assignment readiness. Does not return emails or change data.';
comment on function admin_api.inspect_synthetic_qa_auth_user(uuid) is
  'Platform-admin or service-role lookup of whether an Auth user is already linked to a learner or staff row.';
