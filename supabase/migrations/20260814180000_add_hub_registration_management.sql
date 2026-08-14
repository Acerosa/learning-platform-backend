-- Hub registration management: update an existing registry row and expose the
-- course catalogue for administrative validation. This is not curriculum
-- publication and does not store curriculum packages.

create view admin_api.courses
with (security_invoker = true)
as
select
  course.stable_key as course_key,
  course.title as course_title,
  course.code,
  course.qualification_level,
  course.active
from learning.courses as course
where platform.current_staff_has_role('platform_admin');

grant select on table admin_api.courses to authenticated;

comment on view admin_api.courses is
  'Staff-only course catalogue for hub registration validation. Does not expose privileged learning tables.';

create function platform.update_hub(
  p_hub_code text,
  p_manifest jsonb,
  p_status text default 'planned',
  p_active boolean default false
)
returns table (
  hub_code text,
  hub_name text,
  description text,
  hub_version text,
  manifest_version text,
  core_version text,
  learner_api_version text,
  submission_contract_version text,
  platform_version text,
  repository_url text,
  deployment_url text,
  activity_types text[],
  evidence_capabilities text[],
  features jsonb,
  compatibility jsonb,
  status text,
  active boolean,
  course_keys text[]
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_teacher learning.teachers%rowtype;
  v_status text;
  v_active boolean;
  v_hub_code text;
  v_name text;
  v_description text;
  v_hub_version text;
  v_manifest_version text;
  v_core_version text;
  v_learner_api_version text;
  v_submission_version text;
  v_repository_url text;
  v_deployment_url text;
  v_courses text[];
  v_course text;
  v_activities text[];
  v_evidence text[];
  v_features jsonb;
  v_compatibility jsonb;
  v_hash text;
  v_existing platform.hubs%rowtype;
  v_hub platform.hubs%rowtype;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  select teacher.*
  into v_teacher
  from learning.teachers as teacher
  where teacher.auth_user_id = v_auth_user_id
    and teacher.active;

  if not found
     or not platform.current_staff_has_role('platform_admin') then
    raise exception using errcode = '28000', message = 'HUB_REGISTRATION_NOT_AUTHORISED';
  end if;

  perform platform.validate_hub_manifest(p_manifest);

  v_status := lower(nullif(btrim(p_status), ''));
  v_active := coalesce(p_active, false);
  if v_status is null
     or v_status not in (
       'planned',
       'development',
       'testing',
       'production',
       'maintenance',
       'deprecated',
       'archived'
     ) then
    raise exception using errcode = '22023', message = 'HUB_STATUS_INVALID';
  end if;

  if v_active and v_status not in ('testing', 'production', 'maintenance') then
    raise exception using errcode = '22023', message = 'HUB_ACTIVE_STATUS_INVALID';
  end if;

  v_hub_code := nullif(btrim(p_hub_code), '');
  if v_hub_code is null
     or v_hub_code is distinct from (p_manifest->>'hubId') then
    raise exception using errcode = '22023', message = 'HUB_CODE_MISMATCH';
  end if;

  v_name := btrim(p_manifest->>'name');
  v_description := btrim(p_manifest->>'description');
  v_hub_version := p_manifest->>'version';
  v_manifest_version := p_manifest->>'manifestVersion';
  v_core_version := p_manifest->'compatibility'->'required'->>'coreVersion';
  v_learner_api_version := p_manifest->'compatibility'->'required'->>'learnerApiContractVersion';
  v_submission_version := p_manifest->'compatibility'->'required'->>'submissionContractVersion';
  v_repository_url := platform.hub_https_url_canonical(p_manifest->>'repositoryUrl');
  v_deployment_url := platform.hub_https_url_canonical(p_manifest->>'deploymentUrl');
  v_courses := platform.hub_manifest_text_array(p_manifest->'courses');
  v_activities := platform.hub_manifest_text_array(p_manifest->'capabilities'->'activities');
  v_evidence := platform.hub_manifest_text_array(p_manifest->'capabilities'->'evidence');
  v_features := p_manifest->'featureFlags';
  v_compatibility := p_manifest->'compatibility';
  v_hash := encode(
    extensions.digest(pg_catalog.convert_to(p_manifest::text, 'UTF8'), 'sha256'),
    'hex'
  );

  if not exists (
    select 1 from platform.contract_versions as contract
    where contract.contract_key = 'hub-manifest'
      and contract.version = v_manifest_version
      and contract.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'HUB_MANIFEST_VERSION_UNSUPPORTED';
  end if;

  if not exists (
    select 1 from platform.contract_versions as contract
    where contract.contract_key = 'learning-platform-core'
      and contract.version = v_core_version
      and contract.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'HUB_CORE_VERSION_UNSUPPORTED';
  end if;

  if not exists (
    select 1 from platform.contract_versions as contract
    where contract.contract_key = 'learner-api'
      and contract.version = v_learner_api_version
      and contract.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'HUB_LEARNER_API_VERSION_UNSUPPORTED';
  end if;

  if not exists (
    select 1 from platform.contract_versions as contract
    where contract.contract_key = 'submission'
      and contract.version = v_submission_version
      and contract.status = 'active'
  ) then
    raise exception using errcode = '22023', message = 'HUB_SUBMISSION_VERSION_UNSUPPORTED';
  end if;

  foreach v_course in array v_courses
  loop
    if exists (
      select 1 from learning.courses as course
      where course.stable_key = v_course
        and not course.active
    ) then
      raise exception using errcode = '22023', message = 'HUB_COURSE_INACTIVE';
    end if;

    if not exists (
      select 1 from learning.courses as course
      where course.stable_key = v_course
        and course.active
    ) then
      raise exception using errcode = '22023', message = 'HUB_COURSE_NOT_FOUND';
    end if;
  end loop;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('hub-registration:' || v_hub_code, 0)
  );

  select hub.*
  into v_existing
  from platform.hubs as hub
  where hub.hub_code = v_hub_code;

  if not found then
    raise exception using errcode = 'P0002', message = 'HUB_NOT_FOUND';
  end if;

  if exists (
    select 1 from platform.hubs as hub
    where hub.hub_code is distinct from v_hub_code
      and lower(rtrim(hub.repository_url, '/')) = lower(rtrim(v_repository_url, '/'))
  ) then
    raise exception using errcode = '23505', message = 'HUB_DUPLICATE_REPOSITORY';
  end if;

  if exists (
    select 1 from platform.hubs as hub
    where hub.hub_code is distinct from v_hub_code
      and hub.deployment_url is not null
      and lower(rtrim(hub.deployment_url, '/')) = lower(rtrim(v_deployment_url, '/'))
  ) then
    raise exception using errcode = '23505', message = 'HUB_DUPLICATE_DEPLOYMENT';
  end if;

  update platform.hubs as hub
  set
    hub_name = v_name,
    description = v_description,
    hub_version = v_hub_version,
    platform_version = v_core_version,
    manifest_version = v_manifest_version,
    core_version = v_core_version,
    learner_api_version = v_learner_api_version,
    submission_contract_version = v_submission_version,
    repository_url = v_repository_url,
    deployment_url = v_deployment_url,
    activity_types = v_activities,
    evidence_capabilities = v_evidence,
    features = v_features,
    compatibility = v_compatibility,
    status = v_status,
    active = v_active,
    manifest = p_manifest,
    manifest_sha256 = v_hash,
    updated_at = clock_timestamp()
  where hub.id = v_existing.id
  returning * into v_hub;

  update platform.hub_course_links as link
  set active = false
  where link.hub_id = v_hub.id
    and not exists (
      select 1 from learning.courses as course
      where course.id = link.course_id
        and course.stable_key = any (v_courses)
    );

  foreach v_course in array v_courses
  loop
    insert into platform.hub_course_links (hub_id, course_id, active)
    select v_hub.id, course.id, true
    from learning.courses as course
    where course.stable_key = v_course
      and course.active
    on conflict (hub_id, course_id) do update
      set active = true;
  end loop;

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'hub.registration.updated',
    v_auth_user_id,
    'staff',
    'hub',
    v_hub.hub_code,
    'succeeded',
    jsonb_build_object(
      'hubCode', v_hub.hub_code,
      'hubVersion', v_hub.hub_version,
      'status', v_hub.status,
      'active', v_hub.active,
      'courseKeys', to_jsonb(v_courses),
      'updatedBy', v_teacher.staff_reference
    )
  );

  return query
  select
    v_hub.hub_code,
    v_hub.hub_name,
    v_hub.description,
    v_hub.hub_version,
    v_hub.manifest_version,
    v_hub.core_version,
    v_hub.learner_api_version,
    v_hub.submission_contract_version,
    v_hub.platform_version,
    v_hub.repository_url,
    v_hub.deployment_url,
    v_hub.activity_types,
    v_hub.evidence_capabilities,
    v_hub.features,
    v_hub.compatibility,
    v_hub.status,
    v_hub.active,
    v_courses;
end;
$$;

create function admin_api.update_hub(
  p_hub_code text,
  p_manifest jsonb,
  p_status text default 'planned',
  p_active boolean default false
)
returns table (
  hub_code text,
  hub_name text,
  description text,
  hub_version text,
  manifest_version text,
  core_version text,
  learner_api_version text,
  submission_contract_version text,
  platform_version text,
  repository_url text,
  deployment_url text,
  activity_types text[],
  evidence_capabilities text[],
  features jsonb,
  compatibility jsonb,
  status text,
  active boolean,
  course_keys text[]
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from platform.update_hub(p_hub_code, p_manifest, p_status, p_active)
$$;

revoke all on function platform.update_hub(text, jsonb, text, boolean)
  from public, anon, authenticated;
revoke all on function admin_api.update_hub(text, jsonb, text, boolean)
  from public, anon, authenticated;

grant execute on function platform.update_hub(text, jsonb, text, boolean)
  to authenticated;
grant execute on function admin_api.update_hub(text, jsonb, text, boolean)
  to authenticated;

comment on function platform.update_hub(text, jsonb, text, boolean) is
  'Updates an existing hub registry row after staff-role checks. Identity comes from auth.uid(). Hub codes cannot be changed.';
comment on function admin_api.update_hub(text, jsonb, text, boolean) is
  'Browser-safe wrapper for hub metadata, lifecycle and enablement updates. This is not curriculum publication.';
