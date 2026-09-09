-- Additive hub ↔ group binding, hub access resolver, and hub-scoped assignments.
-- Does not replace api.registration_options, api.complete_learner_onboarding,
-- or api.my_assignments.
--
-- Authority for hub-scoped assignment reads:
--   auth.uid()
--   → learning.students
--   → active learning.enrolments
--   → platform.hub_group_links (which groups this hub may use)
--   → learning.activity_assignments for those groups
-- Course links (platform.hub_course_links) are necessary but not sufficient:
-- Unit 3, Unit 14 and Readiness all use ocr-level-3-it.

create table platform.hub_group_links (
  hub_id uuid not null references platform.hubs (id) on delete restrict,
  group_id uuid not null references learning.groups (id) on delete restrict,
  active boolean not null default true,
  join_policy text not null default 'closed',
  linked_at timestamptz not null default now(),
  primary key (hub_id, group_id),
  constraint hub_group_join_policy_valid
    check (join_policy in ('open_auto', 'open_explicit', 'closed'))
);

comment on table platform.hub_group_links is
  'Authoritative many-to-many mapping of which course/year cohorts a hub may use. Groups are course-year teaching cohorts, not hub-owned containers. Course links are not sufficient: Unit 3, Unit 14 and Readiness share ocr-level-3-it.';

comment on column platform.hub_group_links.join_policy is
  'open_auto: resolver may auto-enrol or reactivate this hub-bound group when it is eligible. Other-hub enrolments do not block that write. open_explicit: JoinClass / complete_learner_onboarding only; opening the hub does not reactivate. closed: access only if already actively enrolled.';

create index hub_group_links_group_idx
  on platform.hub_group_links (group_id, active);

alter table platform.hub_group_links enable row level security;

revoke all on table platform.hub_group_links from public, anon, authenticated;
grant select on table platform.hub_group_links to authenticated;

create policy hub_group_links_staff_read on platform.hub_group_links
for select to authenticated
using ((select platform.current_staff_has_any_role(
  array['platform_admin', 'curriculum_admin', 'operations', 'auditor']
)));

create function platform.hub_group_link_matches_hub_course()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from learning.groups as learner_group
    join platform.hub_course_links as link
      on link.hub_id = new.hub_id
     and link.course_id = learner_group.course_id
     and link.active
    where learner_group.id = new.group_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'HUB_GROUP_COURSE_NOT_LINKED';
  end if;
  return new;
end
$$;

revoke all on function platform.hub_group_link_matches_hub_course()
  from public, anon, authenticated;

create trigger hub_group_links_course_consistent
before insert or update on platform.hub_group_links
for each row
execute function platform.hub_group_link_matches_hub_course();

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
)
select
  '60000000-0000-4000-8000-0000000000b2'::uuid,
  academic_year.id,
  course.id,
  'TLEVEL-DSD-Y2',
  'T Level Digital Software Development - Year 2',
  true,
  'Year 2',
  'tlevel-dsd-y2',
  true,
  false,
  null
from learning.courses as course
join lateral (
  select candidate.id
  from learning.academic_years as candidate
  where candidate.active
  order by candidate.code
  limit 1
) as academic_year on true
where course.stable_key = 't-level-digital-software-development'
  and course.active
  and not exists (
    select 1
    from learning.groups as existing
    where existing.code = 'TLEVEL-DSD-Y2'
  );

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
select hub.id, learner_group.id, true, mapping.join_policy
from (
  values
    ('tlevel-software-development', 'TLEVEL-DSD-Y2', 'open_auto'),
    ('l2e-exploring-emerging-digital-technologies', 'L2E-DELIVERY-A', 'open_auto'),
    ('unit-3-cyber-security', 'CYBER-TEST-A', 'open_explicit'),
    ('unit-3-cyber-security', 'CYBER-TEST-QA', 'closed'),
    ('unit-14-software-engineering-for-business', 'UNIT14-TEST-A', 'closed')
) as mapping(hub_code, group_code, join_policy)
join platform.hubs as hub
  on hub.hub_code = mapping.hub_code
join learning.groups as learner_group
  on learner_group.code = mapping.group_code
on conflict (hub_id, group_id) do nothing;

create function learning.hub_access_bound_groups(p_hub_id uuid)
returns table (
  group_id uuid,
  join_policy text,
  registration_open boolean,
  group_active boolean,
  academic_year_active boolean,
  course_active boolean,
  registration_key text,
  group_code text,
  group_name text,
  year_group text,
  academic_year text,
  course_title text,
  course_key text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    learner_group.id,
    link.join_policy,
    learner_group.registration_open,
    learner_group.active,
    academic_year.active,
    course.active,
    learner_group.registration_key,
    learner_group.code,
    learner_group.name,
    learner_group.year_group,
    academic_year.code,
    course.title,
    course.stable_key
  from platform.hub_group_links as link
  join learning.groups as learner_group
    on learner_group.id = link.group_id
  join learning.academic_years as academic_year
    on academic_year.id = learner_group.academic_year_id
  join learning.courses as course
    on course.id = learner_group.course_id
  where link.hub_id = p_hub_id
    and link.active
$$;

revoke all on function learning.hub_access_bound_groups(uuid)
  from public, anon, authenticated;

create function api.resolve_learner_hub_access(
  p_hub_code text,
  p_course_key text
)
returns table (
  status text,
  idempotent boolean,
  academic_year text,
  year_group text,
  course_title text,
  group_code text,
  group_name text,
  enrolment_status text,
  registration_option text
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_hub_code text;
  v_course_key text;
  v_hub_id uuid;
  v_hub_active boolean;
  v_student_id uuid;
  v_student_active boolean;
  v_bound_count integer := 0;
  v_active_hub_count integer := 0;
  v_eligible_open_count integer := 0;
  v_open_auto_count integer := 0;
  v_group_id uuid;
  v_join_policy text;
  v_registration_open boolean;
  v_group_active boolean;
  v_academic_year_active boolean;
  v_course_active boolean;
  v_registration_key text;
  v_group_code text;
  v_group_name text;
  v_year_group text;
  v_academic_year text;
  v_course_title text;
  v_enrolment learning.enrolments%rowtype;
  v_inactive_id uuid;
  v_eligible_key text;
  v_eligible_code text;
  v_eligible_name text;
  v_eligible_year text;
  v_eligible_academic_year text;
  v_eligible_title text;
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
  v_course_key := nullif(btrim(p_course_key), '');

  if v_hub_code is null
     or v_hub_code !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     or length(v_hub_code) > 80 then
    raise exception using errcode = '22023', message = 'INVALID_HUB_CODE';
  end if;

  if v_course_key is null
     or v_course_key !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     or length(v_course_key) > 80 then
    raise exception using errcode = '22023', message = 'INVALID_COURSE_KEY';
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

  if not exists (
    select 1
    from platform.hub_course_links as link
    join learning.courses as course
      on course.id = link.course_id
    where link.hub_id = v_hub_id
      and link.active
      and course.active
      and course.stable_key = v_course_key
  ) then
    raise exception using errcode = '22023', message = 'HUB_COURSE_NOT_LINKED';
  end if;

  select student.id, student.active
  into v_student_id, v_student_active
  from learning.students as student
  where student.auth_user_id = v_auth_user_id;

  select count(*)
  into v_bound_count
  from learning.hub_access_bound_groups(v_hub_id);

  select count(*)
  into v_eligible_open_count
  from learning.hub_access_bound_groups(v_hub_id) as bound
  where bound.join_policy in ('open_auto', 'open_explicit')
    and bound.registration_open
    and bound.group_active
    and bound.academic_year_active
    and bound.course_active
    and bound.registration_key is not null;

  select bound.registration_key, bound.group_code, bound.group_name,
         bound.year_group, bound.academic_year, bound.course_title
  into v_eligible_key, v_eligible_code, v_eligible_name,
       v_eligible_year, v_eligible_academic_year, v_eligible_title
  from learning.hub_access_bound_groups(v_hub_id) as bound
  where bound.join_policy in ('open_auto', 'open_explicit')
    and bound.registration_open
    and bound.group_active
    and bound.academic_year_active
    and bound.course_active
    and bound.registration_key is not null
  order by bound.group_code
  limit 1;

  if v_eligible_open_count <> 1 then
    v_eligible_key := null;
    v_eligible_code := null;
    v_eligible_name := null;
    v_eligible_year := null;
    v_eligible_academic_year := null;
    v_eligible_title := null;
  end if;

  if v_student_id is null or not coalesce(v_student_active, false) then
    status := 'profile_required';
    idempotent := true;
    academic_year := v_eligible_academic_year;
    year_group := v_eligible_year;
    course_title := v_eligible_title;
    group_code := v_eligible_code;
    group_name := v_eligible_name;
    enrolment_status := null;
    registration_option := v_eligible_key;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('learner-hub-access:' || v_auth_user_id::text, 0)
  );

  select count(*)
  into v_active_hub_count
  from learning.enrolments as enrolment
  join learning.hub_access_bound_groups(v_hub_id) as bound
    on bound.group_id = enrolment.group_id
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  if v_active_hub_count > 1 then
    select bound.academic_year, bound.year_group, bound.course_title,
           bound.group_code, bound.group_name, enrolment.status
    into academic_year, year_group, course_title,
         group_code, group_name, enrolment_status
    from learning.enrolments as enrolment
    join learning.hub_access_bound_groups(v_hub_id) as bound
      on bound.group_id = enrolment.group_id
    where enrolment.student_id = v_student_id
      and enrolment.status = 'active'
    order by enrolment.joined_on desc, bound.group_code
    limit 1;
    status := 'enrolled';
    idempotent := true;
    registration_option := null;
    return next;
    return;
  end if;

  if v_active_hub_count = 1 then
    select bound.academic_year, bound.year_group, bound.course_title,
           bound.group_code, bound.group_name, enrolment.status
    into academic_year, year_group, course_title,
         group_code, group_name, enrolment_status
    from learning.enrolments as enrolment
    join learning.hub_access_bound_groups(v_hub_id) as bound
      on bound.group_id = enrolment.group_id
    where enrolment.student_id = v_student_id
      and enrolment.status = 'active'
    limit 1;
    status := 'enrolled';
    idempotent := true;
    registration_option := null;
    return next;
    return;
  end if;

  select enrolment.id
  into v_inactive_id
  from learning.enrolments as enrolment
  join learning.hub_access_bound_groups(v_hub_id) as bound
    on bound.group_id = enrolment.group_id
  where enrolment.student_id = v_student_id
    and enrolment.status <> 'active'
    and bound.join_policy = 'open_auto'
    and bound.registration_open
    and bound.group_active
    and bound.academic_year_active
    and bound.course_active
    and bound.registration_key is not null
  order by enrolment.updated_at desc, enrolment.joined_on desc
  limit 1;

  if v_inactive_id is not null then
    select enrolment.*
    into v_enrolment
    from learning.enrolments as enrolment
    where enrolment.id = v_inactive_id
    for update;

    update learning.enrolments
    set status = 'active',
        left_on = null,
        updated_at = clock_timestamp()
    where id = v_enrolment.id
    returning * into v_enrolment;

    select bound.academic_year, bound.year_group, bound.course_title,
           bound.group_code, bound.group_name
    into academic_year, year_group, course_title, group_code, group_name
    from learning.hub_access_bound_groups(v_hub_id) as bound
    where bound.group_id = v_enrolment.group_id;

    status := 'enrolled_reactivated';
    idempotent := false;
    enrolment_status := v_enrolment.status;
    registration_option := null;
    return next;
    return;
  end if;

  select count(*)
  into v_open_auto_count
  from learning.hub_access_bound_groups(v_hub_id) as bound
  where bound.join_policy = 'open_auto'
    and bound.registration_open
    and bound.group_active
    and bound.academic_year_active
    and bound.course_active
    and bound.registration_key is not null;

  if v_open_auto_count > 1 then
    status := 'ambiguous';
    idempotent := true;
    academic_year := null;
    year_group := null;
    course_title := null;
    group_code := null;
    group_name := null;
    enrolment_status := null;
    registration_option := null;
    return next;
    return;
  end if;

  if v_open_auto_count = 1 then
    select bound.group_id, bound.join_policy, bound.registration_open,
           bound.group_active, bound.academic_year_active, bound.course_active,
           bound.registration_key, bound.group_code, bound.group_name,
           bound.year_group, bound.academic_year, bound.course_title
    into v_group_id, v_join_policy, v_registration_open,
         v_group_active, v_academic_year_active, v_course_active,
         v_registration_key, v_group_code, v_group_name,
         v_year_group, v_academic_year, v_course_title
    from learning.hub_access_bound_groups(v_hub_id) as bound
    where bound.join_policy = 'open_auto'
      and bound.registration_open
      and bound.group_active
      and bound.academic_year_active
      and bound.course_active
      and bound.registration_key is not null
    limit 1;

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
        end if;
        status := 'enrolled';
        idempotent := true;
        academic_year := v_academic_year;
        year_group := v_year_group;
        course_title := v_course_title;
        group_code := v_group_code;
        group_name := v_group_name;
        enrolment_status := v_enrolment.status;
        registration_option := null;
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
    registration_option := null;
    return next;
    return;
  end if;

  if v_bound_count = 0 or v_eligible_open_count = 0 then
    status := 'no_open_group';
    idempotent := true;
    academic_year := null;
    year_group := null;
    course_title := null;
    group_code := null;
    group_name := null;
    enrolment_status := null;
    registration_option := null;
    return next;
    return;
  end if;

  status := 'no_enrolment';
  idempotent := true;
  academic_year := v_eligible_academic_year;
  year_group := v_eligible_year;
  course_title := v_eligible_title;
  group_code := v_eligible_code;
  group_name := v_eligible_name;
  enrolment_status := null;
  registration_option := v_eligible_key;
  return next;
end
$$;

comment on function api.resolve_learner_hub_access(text, text) is
  'Resolves the current Auth learner against hub-bound delivery groups. Identity is auth.uid(). Does not accept learner, enrolment or group UUIDs. Automatic create/reactivate writes only into an eligible open_auto group for the requested hub.';

revoke all on function api.resolve_learner_hub_access(text, text)
  from public, anon, authenticated;
grant execute on function api.resolve_learner_hub_access(text, text)
  to authenticated;

create function api.my_hub_assignments(p_hub_code text)
returns table (
  activity_key text,
  activity_title text,
  activity_version text,
  max_score numeric,
  opens_at timestamptz,
  due_at timestamptz,
  required boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid;
  v_hub_code text;
  v_hub_id uuid;
  v_student_id uuid;
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
  if v_hub_code is null
     or v_hub_code !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     or length(v_hub_code) > 80 then
    raise exception using errcode = '22023', message = 'INVALID_HUB_CODE';
  end if;

  select hub.id
  into v_hub_id
  from platform.hubs as hub
  where hub.hub_code = v_hub_code
    and hub.active;

  if v_hub_id is null then
    raise exception using errcode = '22023', message = 'HUB_UNKNOWN';
  end if;

  v_student_id := learning.current_student_id();
  if v_student_id is null then
    return;
  end if;

  return query
  select
    activity.stable_key,
    activity.title,
    activity_version.version,
    activity_version.max_score,
    assignment.opens_at,
    assignment.due_at,
    assignment.required
  from learning.enrolments as enrolment
  join learning.hub_access_bound_groups(v_hub_id) as bound
    on bound.group_id = enrolment.group_id
  join learning.activity_assignments as assignment
    on assignment.group_id = enrolment.group_id
   and assignment.active
  join learning.activity_versions as activity_version
    on activity_version.id = assignment.activity_version_id
  join learning.activities as activity
    on activity.id = activity_version.activity_id
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active'
    and (assignment.opens_at is null or assignment.opens_at <= clock_timestamp())
    and (assignment.due_at is null or assignment.due_at >= clock_timestamp())
  order by activity.stable_key;
end
$$;

comment on function api.my_hub_assignments(text) is
  'Learner-safe assignments for groups bound to the supplied hub. Identity is auth.uid(). Does not accept group UUIDs. api.my_assignments remains the unscoped compatibility view.';

revoke all on function api.my_hub_assignments(text)
  from public, anon, authenticated;
grant execute on function api.my_hub_assignments(text)
  to authenticated;
