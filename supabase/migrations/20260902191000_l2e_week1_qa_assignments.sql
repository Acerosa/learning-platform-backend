-- Expand exclusive synthetic QA catalogues from a single smoke activity
-- to an explicit activity allowlist. L2E-TEST-A covers published Week 1
-- deterministic Check-answer activities. Assignment enforcement is unchanged.

begin;

create table if not exists learning.synthetic_qa_smoke_activities (
  persona text not null,
  activity_key text not null,
  sort_order integer not null default 0,
  primary key (persona, activity_key),
  constraint synthetic_qa_smoke_activities_persona_fk
    foreign key (persona) references learning.synthetic_qa_fixtures (persona)
    on update cascade on delete cascade,
  constraint synthetic_qa_smoke_activity_key_valid
    check (activity_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

comment on table learning.synthetic_qa_smoke_activities is
  'Explicit published activities assigned to exclusive synthetic QA groups. Curriculum publication cannot silently enlarge this set.';

alter table learning.synthetic_qa_smoke_activities enable row level security;

revoke all on table learning.synthetic_qa_smoke_activities
  from public, anon, authenticated;

grant select on table learning.synthetic_qa_smoke_activities to authenticated;

drop policy if exists synthetic_qa_smoke_activities_staff_read
  on learning.synthetic_qa_smoke_activities;

create policy synthetic_qa_smoke_activities_staff_read
on learning.synthetic_qa_smoke_activities
for select
to authenticated
using ((select platform.current_staff_has_role('platform_admin')));

insert into learning.synthetic_qa_smoke_activities (persona, activity_key, sort_order)
values
  ('UNIT3_TEST_LEARNER', 'week2-malware-symptoms', 1),
  ('TLEVEL_TEST_LEARNER', 'week-1-lesson-1-retrieval', 1),
  ('UNIT14_TEST_LEARNER', 'week-1-variables-and-data-types', 1),
  ('L2E_TEST_LEARNER', 'week-1-welcome', 1),
  ('L2E_TEST_LEARNER', 'week-1-digital-technology', 2),
  ('L2E_TEST_LEARNER', 'week-1-current-emerging', 3),
  ('L2E_TEST_LEARNER', 'week-1-mobile', 4),
  ('L2E_TEST_LEARNER', 'week-1-intelligent-computing', 5),
  ('L2E_TEST_LEARNER', 'week-1-iot', 6),
  ('L2E_TEST_LEARNER', 'week-1-cloud', 7),
  ('L2E_TEST_LEARNER', 'week-1-industry', 8),
  ('L2E_TEST_LEARNER', 'week-1-knowledge-check', 9),
  ('L2E_TEST_LEARNER', 'week-1-exit-ticket', 10)
on conflict (persona, activity_key) do update
set sort_order = excluded.sort_order;

create or replace function learning.synthetic_qa_allowed_activity_keys(p_persona text)
returns table (activity_key text)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct catalogued.activity_key
  from (
    select fixture.smoke_activity_key as activity_key
    from learning.synthetic_qa_fixtures as fixture
    where fixture.persona = p_persona
    union all
    select smoke.activity_key
    from learning.synthetic_qa_smoke_activities as smoke
    where smoke.persona = p_persona
  ) as catalogued
  where btrim(catalogued.activity_key) <> ''
$$;

comment on function learning.synthetic_qa_allowed_activity_keys(text) is
  'Catalogued synthetic QA activity keys for a persona, including the primary smoke activity.';

revoke all on function learning.synthetic_qa_allowed_activity_keys(text)
  from public, anon, authenticated;

create or replace function learning.guard_synthetic_qa_smoke_assignments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_exclusive boolean;
  v_persona text;
  v_activity_key text;
begin
  select fixture.exclusive_smoke, fixture.persona
  into v_exclusive, v_persona
  from learning.groups as learner_group
  join learning.synthetic_qa_fixtures as fixture
    on fixture.group_code = learner_group.code
  where learner_group.id = new.group_id;

  if not found or coalesce(v_exclusive, false) = false then
    return new;
  end if;

  select activity.stable_key
  into v_activity_key
  from learning.activity_versions as activity_version
  join learning.activities as activity
    on activity.id = activity_version.activity_id
  where activity_version.id = new.activity_version_id;

  if not exists (
    select 1
    from learning.synthetic_qa_allowed_activity_keys(v_persona) as allowed
    where allowed.activity_key = v_activity_key
  ) then
    if tg_op = 'UPDATE' and new.active is false then
      return new;
    end if;
    return null;
  end if;

  return new;
end
$$;

comment on function learning.guard_synthetic_qa_smoke_assignments() is
  'Prevents curriculum publication from silently enlarging exclusive synthetic QA groups beyond the catalogued activity allowlist.';

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
  'Creates or reuses closed synthetic QA groups and upserts the catalogued smoke activity allowlist at the latest published non-retired version. exclusive_smoke groups keep only that allowlist active.';

comment on table learning.synthetic_qa_fixtures is
  'Catalog of permanent hub-isolated synthetic QA learners and groups. Not a second authorisation path. exclusive_smoke groups receive only catalogued smoke activities.';

select * from learning.ensure_synthetic_qa_groups();

commit;
