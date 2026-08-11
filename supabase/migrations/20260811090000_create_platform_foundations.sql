create schema if not exists platform;
create schema if not exists admin_api;

revoke all on schema platform from public, anon, authenticated;
revoke all on schema admin_api from public, anon, authenticated;

grant usage on schema platform to authenticated;
grant usage on schema admin_api to authenticated;
grant usage on schema api to anon, authenticated;

alter default privileges in schema platform
  revoke all on tables from public, anon, authenticated;
alter default privileges in schema platform
  revoke all on sequences from public, anon, authenticated;
alter default privileges in schema platform
  revoke all on functions from public, anon, authenticated;
alter default privileges in schema admin_api
  revoke all on tables from public, anon, authenticated;

create table platform.hubs (
  id uuid primary key default gen_random_uuid(),
  hub_code text not null unique,
  hub_name text not null,
  hub_version text not null,
  platform_version text not null,
  subject text not null,
  repository_url text not null,
  deployment_url text,
  curriculum_model text not null,
  activity_types text[] not null default '{}',
  features jsonb not null default '{}'::jsonb,
  status text not null default 'planned',
  active boolean not null default false,
  manifest jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hub_code_valid
    check (hub_code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint hub_name_not_blank check (btrim(hub_name) <> ''),
  constraint hub_version_semver_valid
    check (hub_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint hub_platform_version_semver_valid
    check (platform_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint hub_repository_url_valid
    check (repository_url ~ '^https://[^[:space:]]+$'),
  constraint hub_deployment_url_valid
    check (deployment_url is null or deployment_url ~ '^https://[^[:space:]]+$'),
  constraint hub_status_valid
    check (status in (
      'planned',
      'development',
      'testing',
      'production',
      'maintenance',
      'deprecated',
      'archived'
    )),
  constraint hub_features_object check (jsonb_typeof(features) = 'object'),
  constraint hub_manifest_object check (jsonb_typeof(manifest) = 'object')
);

create index hubs_status_active_idx on platform.hubs (status, active);

create table platform.hub_course_links (
  hub_id uuid not null references platform.hubs (id) on delete restrict,
  course_id uuid not null references learning.courses (id) on delete restrict,
  active boolean not null default true,
  linked_at timestamptz not null default now(),
  primary key (hub_id, course_id)
);

create index hub_course_links_course_idx
  on platform.hub_course_links (course_id, active);

create table platform.contract_versions (
  id uuid primary key default gen_random_uuid(),
  contract_key text not null,
  version text not null,
  status text not null default 'draft',
  compatibility jsonb not null default '{}'::jsonb,
  contract_document jsonb not null default '{}'::jsonb,
  published_at timestamptz,
  deprecated_at timestamptz,
  created_at timestamptz not null default now(),
  constraint contract_version_unique unique (contract_key, version),
  constraint contract_key_valid
    check (contract_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint contract_version_semver_valid
    check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  constraint contract_status_valid
    check (status in ('draft', 'active', 'deprecated', 'retired')),
  constraint contract_compatibility_object
    check (jsonb_typeof(compatibility) = 'object'),
  constraint contract_document_object
    check (jsonb_typeof(contract_document) = 'object'),
  constraint contract_publication_valid check (
    (status = 'draft' and published_at is null)
    or (status <> 'draft' and published_at is not null)
  ),
  constraint contract_deprecation_valid check (
    deprecated_at is null
    or (published_at is not null and deprecated_at >= published_at)
  )
);

create index contract_versions_key_status_idx
  on platform.contract_versions (contract_key, status, published_at desc);

create table platform.staff_roles (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references learning.teachers (id) on delete restrict,
  role text not null,
  granted_by uuid references learning.teachers (id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint staff_role_valid check (role in (
    'platform_admin',
    'curriculum_admin',
    'operations',
    'auditor',
    'support'
  )),
  constraint staff_role_dates_valid
    check (revoked_at is null or revoked_at >= granted_at)
);

create unique index staff_roles_one_active_role
  on platform.staff_roles (teacher_id, role)
  where revoked_at is null;

create index staff_roles_teacher_active_idx
  on platform.staff_roles (teacher_id, revoked_at);

create table platform.audit_events (
  id uuid primary key default gen_random_uuid(),
  event_key text not null,
  actor_auth_user_id uuid references auth.users (id) on delete set null,
  actor_type text not null,
  entity_type text not null,
  entity_key text,
  outcome text not null,
  context jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  constraint audit_event_key_valid
    check (event_key ~ '^[a-z0-9]+([.-][a-z0-9]+)*$'),
  constraint audit_actor_type_valid
    check (actor_type in ('learner', 'staff', 'service', 'system')),
  constraint audit_entity_type_valid
    check (entity_type ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint audit_outcome_valid
    check (outcome in ('succeeded', 'failed', 'denied')),
  constraint audit_context_object check (jsonb_typeof(context) = 'object'),
  constraint audit_context_size_valid
    check (octet_length(context::text) <= 16384)
);

create index audit_events_occurred_idx
  on platform.audit_events (occurred_at desc, id);
create index audit_events_entity_idx
  on platform.audit_events (entity_type, entity_key, occurred_at desc);

create table platform.operational_health (
  service_key text primary key,
  status text not null default 'unknown',
  checked_at timestamptz not null default clock_timestamp(),
  valid_until timestamptz,
  public_message text,
  diagnostics jsonb not null default '{}'::jsonb,
  public_visible boolean not null default true,
  constraint operational_service_key_valid
    check (service_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint operational_status_valid
    check (status in ('healthy', 'degraded', 'unavailable', 'unknown')),
  constraint operational_validity_valid
    check (valid_until is null or valid_until >= checked_at),
  constraint operational_diagnostics_object
    check (jsonb_typeof(diagnostics) = 'object'),
  constraint operational_diagnostics_size_valid
    check (octet_length(diagnostics::text) <= 16384)
);

alter table platform.hubs enable row level security;
alter table platform.hub_course_links enable row level security;
alter table platform.contract_versions enable row level security;
alter table platform.staff_roles enable row level security;
alter table platform.audit_events enable row level security;
alter table platform.operational_health enable row level security;

revoke all on all tables in schema platform from public, anon, authenticated;
revoke all on all sequences in schema platform from public, anon, authenticated;
revoke all on all functions in schema platform from public, anon, authenticated;

grant select on
  platform.hubs,
  platform.hub_course_links,
  platform.contract_versions,
  platform.staff_roles,
  platform.audit_events,
  platform.operational_health
to authenticated;

create function platform.current_staff_has_role(p_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from learning.teachers as teacher
    join platform.staff_roles as staff_role
      on staff_role.teacher_id = teacher.id
     and staff_role.revoked_at is null
    where teacher.auth_user_id = (select auth.uid())
      and teacher.active
      and staff_role.role = p_role
  )
$$;

create function platform.current_staff_has_any_role(p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from learning.teachers as teacher
    join platform.staff_roles as staff_role
      on staff_role.teacher_id = teacher.id
     and staff_role.revoked_at is null
    where teacher.auth_user_id = (select auth.uid())
      and teacher.active
      and staff_role.role = any(p_roles)
  )
$$;

revoke all on function platform.current_staff_has_role(text)
  from public, anon, authenticated;
revoke all on function platform.current_staff_has_any_role(text[])
  from public, anon, authenticated;
grant execute on function platform.current_staff_has_role(text) to authenticated;
grant execute on function platform.current_staff_has_any_role(text[]) to authenticated;

create policy hubs_staff_read on platform.hubs
for select to authenticated
using ((select platform.current_staff_has_any_role(
  array['platform_admin', 'curriculum_admin', 'operations', 'auditor', 'support']
)));

create policy hub_course_links_staff_read on platform.hub_course_links
for select to authenticated
using ((select platform.current_staff_has_any_role(
  array['platform_admin', 'curriculum_admin', 'operations', 'auditor']
)));

create policy contract_versions_staff_read on platform.contract_versions
for select to authenticated
using ((select platform.current_staff_has_any_role(
  array['platform_admin', 'curriculum_admin', 'operations', 'auditor', 'support']
)));

create policy staff_roles_own_or_admin_read on platform.staff_roles
for select to authenticated
using (
  teacher_id = (select learning.current_teacher_id())
  or (select platform.current_staff_has_role('platform_admin'))
);

create policy audit_events_authorised_read on platform.audit_events
for select to authenticated
using ((select platform.current_staff_has_any_role(
  array['platform_admin', 'operations', 'auditor']
)));

create policy operational_health_authorised_read on platform.operational_health
for select to authenticated
using ((select platform.current_staff_has_any_role(
  array['platform_admin', 'operations', 'support']
)));

create policy academic_years_platform_admin_read
on learning.academic_years for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy courses_platform_admin_read
on learning.courses for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy groups_platform_admin_read
on learning.groups for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy students_platform_admin_read
on learning.students for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy teachers_platform_admin_read
on learning.teachers for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy enrolments_platform_admin_read
on learning.enrolments for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy teacher_group_access_platform_admin_read
on learning.teacher_group_access for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy modules_platform_admin_read
on learning.modules for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy topics_platform_admin_read
on learning.topics for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy activities_platform_admin_read
on learning.activities for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy activity_versions_platform_admin_read
on learning.activity_versions for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy activity_assignments_platform_admin_read
on learning.activity_assignments for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy questions_platform_admin_read
on learning.questions for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy question_topics_platform_admin_read
on learning.question_topics for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy attempts_platform_admin_read
on learning.attempts for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy responses_platform_admin_read
on learning.responses for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy skills_platform_admin_read
on learning.skills for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy question_skills_platform_admin_read
on learning.question_skills for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy coding_languages_platform_admin_read
on learning.coding_languages for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy activity_version_languages_platform_admin_read
on learning.activity_version_languages for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy activity_delivery_platform_admin_read
on learning.activity_delivery for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));
create policy curriculum_weeks_platform_admin_read
on learning.curriculum_weeks for select to authenticated
using ((select platform.current_staff_has_role('platform_admin')));

create function api.registered_hubs()
returns table (
  hub_code text,
  hub_name text,
  hub_version text,
  platform_version text,
  subject text,
  repository_url text,
  deployment_url text,
  curriculum_model text,
  activity_types text[],
  features jsonb,
  status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    hub.hub_code,
    hub.hub_name,
    hub.hub_version,
    hub.platform_version,
    hub.subject,
    hub.repository_url,
    hub.deployment_url,
    hub.curriculum_model,
    hub.activity_types,
    hub.features,
    hub.status
  from platform.hubs as hub
  where hub.active
    and hub.status not in ('deprecated', 'archived')
  order by hub.hub_name
$$;

create function api.platform_contract_versions()
returns table (
  contract_key text,
  version text,
  status text,
  compatibility jsonb,
  published_at timestamptz,
  deprecated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    contract.contract_key,
    contract.version,
    contract.status,
    contract.compatibility,
    contract.published_at,
    contract.deprecated_at
  from platform.contract_versions as contract
  where contract.status in ('active', 'deprecated')
  order by contract.contract_key, contract.published_at desc
$$;

create function api.platform_health()
returns table (
  service_key text,
  status text,
  checked_at timestamptz,
  valid_until timestamptz,
  message text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    health.service_key,
    health.status,
    health.checked_at,
    health.valid_until,
    health.public_message
  from platform.operational_health as health
  where health.public_visible
    and (health.valid_until is null or health.valid_until >= clock_timestamp())
  order by health.service_key
$$;

revoke all on function api.registered_hubs() from public, anon, authenticated;
revoke all on function api.platform_contract_versions() from public, anon, authenticated;
revoke all on function api.platform_health() from public, anon, authenticated;
grant execute on function api.registered_hubs() to anon, authenticated;
grant execute on function api.platform_contract_versions() to anon, authenticated;
grant execute on function api.platform_health() to anon, authenticated;

create function platform.record_audit_event(
  p_event_key text,
  p_actor_type text,
  p_entity_type text,
  p_entity_key text,
  p_outcome text,
  p_context jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
begin
  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    p_event_key,
    auth.uid(),
    p_actor_type,
    p_entity_type,
    nullif(btrim(p_entity_key), ''),
    p_outcome,
    coalesce(p_context, '{}'::jsonb)
  )
  returning id into v_event_id;

  return v_event_id;
end
$$;

create function platform.record_operational_health(
  p_service_key text,
  p_status text,
  p_checked_at timestamptz,
  p_valid_until timestamptz,
  p_public_message text,
  p_diagnostics jsonb default '{}'::jsonb,
  p_public_visible boolean default true
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into platform.operational_health (
    service_key,
    status,
    checked_at,
    valid_until,
    public_message,
    diagnostics,
    public_visible
  ) values (
    p_service_key,
    p_status,
    p_checked_at,
    p_valid_until,
    nullif(btrim(p_public_message), ''),
    coalesce(p_diagnostics, '{}'::jsonb),
    p_public_visible
  )
  on conflict (service_key) do update set
    status = excluded.status,
    checked_at = excluded.checked_at,
    valid_until = excluded.valid_until,
    public_message = excluded.public_message,
    diagnostics = excluded.diagnostics,
    public_visible = excluded.public_visible;
end
$$;

revoke all on function platform.record_audit_event(text, text, text, text, text, jsonb)
  from public, anon, authenticated;
revoke all on function platform.record_operational_health(
  text, text, timestamptz, timestamptz, text, jsonb, boolean
) from public, anon, authenticated;
grant execute on function platform.record_audit_event(text, text, text, text, text, jsonb)
  to service_role;
grant execute on function platform.record_operational_health(
  text, text, timestamptz, timestamptz, text, jsonb, boolean
) to service_role;

create view admin_api.hubs
with (security_invoker = true)
as select * from platform.hubs;

create view admin_api.hub_course_links
with (security_invoker = true)
as
select
  link.hub_id,
  hub.hub_code,
  link.course_id,
  course.stable_key as course_key,
  course.title as course_title,
  link.active,
  link.linked_at
from platform.hub_course_links as link
join platform.hubs as hub on hub.id = link.hub_id
join learning.courses as course on course.id = link.course_id;

create view admin_api.platform_contracts
with (security_invoker = true)
as select * from platform.contract_versions;

create view admin_api.staff_roles
with (security_invoker = true)
as
select
  staff_role.id,
  staff_role.teacher_id,
  teacher.staff_reference,
  teacher.display_name,
  staff_role.role,
  staff_role.granted_by,
  staff_role.granted_at,
  staff_role.revoked_at
from platform.staff_roles as staff_role
join learning.teachers as teacher on teacher.id = staff_role.teacher_id;

create view admin_api.audit_events
with (security_invoker = true)
as select * from platform.audit_events;

create view admin_api.operational_health
with (security_invoker = true)
as select * from platform.operational_health;

create view admin_api.learners
with (security_invoker = true)
as
select
  student.id as learner_id,
  student.student_number,
  student.first_name,
  student.surname,
  student.display_name,
  student.contact_email,
  student.active
from learning.students as student
where platform.current_staff_has_role('platform_admin');

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
  academic_year.id as academic_year_id,
  academic_year.code as academic_year,
  course.id as course_id,
  course.stable_key as course_key,
  course.title as course_title
from learning.groups as learner_group
join learning.academic_years as academic_year
  on academic_year.id = learner_group.academic_year_id
join learning.courses as course on course.id = learner_group.course_id
where platform.current_staff_has_role('platform_admin');

create view admin_api.enrolments
with (security_invoker = true)
as
select
  enrolment.id as enrolment_id,
  enrolment.student_id as learner_id,
  student.student_number,
  enrolment.group_id,
  learner_group.code as group_code,
  enrolment.joined_on,
  enrolment.left_on,
  enrolment.status
from learning.enrolments as enrolment
join learning.students as student on student.id = enrolment.student_id
join learning.groups as learner_group on learner_group.id = enrolment.group_id
where platform.current_staff_has_role('platform_admin');

create view admin_api.assignments
with (security_invoker = true)
as
select
  assignment.id as assignment_id,
  assignment.group_id,
  learner_group.code as group_code,
  assignment.activity_version_id,
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  assignment.opens_at,
  assignment.due_at,
  assignment.required,
  assignment.active
from learning.activity_assignments as assignment
join learning.groups as learner_group on learner_group.id = assignment.group_id
join learning.activity_versions as activity_version
  on activity_version.id = assignment.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
where platform.current_staff_has_role('platform_admin');

create view admin_api.attempts
with (security_invoker = true)
as
select
  attempt.id as attempt_id,
  attempt.student_id as learner_id,
  student.student_number,
  attempt.enrolment_id,
  attempt.assignment_id,
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  attempt.attempt_number,
  attempt.status,
  attempt.score,
  attempt.max_score,
  attempt.marking_source,
  attempt.evidence_level,
  attempt.received_at,
  attempt.completed_at
from learning.attempts as attempt
join learning.students as student on student.id = attempt.student_id
join learning.activity_versions as activity_version
  on activity_version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
where platform.current_staff_has_role('platform_admin');

revoke all on all tables in schema admin_api from public, anon, authenticated;
grant select on all tables in schema admin_api to authenticated;

insert into platform.contract_versions (
  contract_key,
  version,
  status,
  compatibility,
  contract_document,
  published_at
) values
  (
    'learner-api',
    '0.1.0',
    'active',
    '{"minimumHubPlatformVersion":"0.1.0"}'::jsonb,
    '{"schema":"api","boundary":"approved views and RPCs only"}'::jsonb,
    '2026-08-11T00:00:00Z'
  ),
  (
    'submission',
    '0.1.0',
    'active',
    '{"idempotent":true}'::jsonb,
    '{"rpc":"api.submit_attempt","identity":"auth.uid()"}'::jsonb,
    '2026-08-11T00:00:00Z'
  ),
  (
    'admin-api',
    '0.1.0',
    'draft',
    '{"readOnly":true}'::jsonb,
    '{"schema":"admin_api","authorization":"platform.staff_roles"}'::jsonb,
    null
  )
on conflict (contract_key, version) do nothing;

comment on schema platform is
  'Protected platform registry, contract, staff authorisation, audit and operations data.';
comment on schema admin_api is
  'Staff-only API boundary for the Central Admin Portal; no learner browser access.';
comment on function api.registered_hubs() is
  'Returns active, non-retired hub registry metadata without internal identifiers.';
comment on function api.platform_contract_versions() is
  'Returns active or deprecated public platform contract versions for client compatibility checks.';
comment on function api.platform_health() is
  'Returns only explicitly public and current operational health summaries.';
