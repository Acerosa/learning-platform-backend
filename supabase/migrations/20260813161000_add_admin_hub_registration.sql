-- Controlled administrative hub registration. Reviewed hub manifests become
-- platform.hubs rows through a narrow staff RPC. This is not curriculum
-- publication and does not fetch GitHub.

update platform.contract_versions
set
  compatibility = jsonb_build_object(
    'previousVersion', '0.1.0',
    'mode', 'read-models-with-hub-registration-and-curriculum-publication'
  ),
  contract_document = jsonb_build_object(
    'schema', 'admin_api',
    'boundary', 'authenticated staff read models, one-time administrator bootstrap, hub registration and curriculum publication'
  )
where contract_key = 'admin-api'
  and version = '0.2.0'
  and status = 'draft';

create function platform.hub_manifest_text_array(p_value jsonb)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(item order by item), '{}'::text[])
  from jsonb_array_elements_text(coalesce(p_value, '[]'::jsonb)) as item
$$;

create function platform.hub_https_url_canonical(p_url text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_url text;
  v_host text;
  v_path text;
begin
  v_url := nullif(btrim(p_url), '');
  if v_url is null
     or v_url !~ '^https://'
     or v_url ~ '[[:space:]]'
     or v_url ~ '@'
     or v_url ~ '[?#]'
     or v_url ~ ':$'
     or v_url ~ '://:' then
    return null;
  end if;

  v_host := substring(v_url from '^https://([^/]+)');
  v_path := substring(v_url from '^https://[^/]+(/.*)$');

  if v_host is null
     or v_host = ''
     or v_host ~ ':[0-9]+$' and v_host !~ ':443$'
     or coalesce(v_path, '') ~ '/$' then
    return null;
  end if;

  v_host := lower(regexp_replace(v_host, ':443$', ''));
  return 'https://' || v_host || coalesce(v_path, '');
end;
$$;

create function platform.validate_hub_manifest(p_manifest jsonb)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_key text;
  v_required jsonb;
  v_tested jsonb;
  v_combo jsonb;
  v_seen boolean := false;
  v_items text[];
  v_item text;
  v_url text;
  v_semver constant text := '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*))(\.((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*)))*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$';
  v_stable constant text := '^[a-z0-9]+(-[a-z0-9]+)*$';
begin
  if jsonb_typeof(p_manifest) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
  end if;

  for v_key in
    select jsonb_object_keys(p_manifest)
  loop
    if v_key not in (
      'manifestVersion',
      'hubId',
      'name',
      'description',
      'version',
      'repositoryUrl',
      'deploymentUrl',
      'courses',
      'compatibility',
      'capabilities',
      'featureFlags',
      'certification'
    ) then
      raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
    end if;
  end loop;

  if not (
    p_manifest ? 'manifestVersion'
    and p_manifest ? 'hubId'
    and p_manifest ? 'name'
    and p_manifest ? 'description'
    and p_manifest ? 'version'
    and p_manifest ? 'repositoryUrl'
    and p_manifest ? 'deploymentUrl'
    and p_manifest ? 'courses'
    and p_manifest ? 'compatibility'
    and p_manifest ? 'capabilities'
    and p_manifest ? 'featureFlags'
  ) then
    raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
  end if;

  if jsonb_typeof(p_manifest->'manifestVersion') is distinct from 'string'
     or jsonb_typeof(p_manifest->'hubId') is distinct from 'string'
     or jsonb_typeof(p_manifest->'name') is distinct from 'string'
     or jsonb_typeof(p_manifest->'description') is distinct from 'string'
     or jsonb_typeof(p_manifest->'version') is distinct from 'string'
     or jsonb_typeof(p_manifest->'repositoryUrl') is distinct from 'string'
     or jsonb_typeof(p_manifest->'deploymentUrl') is distinct from 'string'
     or jsonb_typeof(p_manifest->'courses') is distinct from 'array'
     or jsonb_typeof(p_manifest->'compatibility') is distinct from 'object'
     or jsonb_typeof(p_manifest->'capabilities') is distinct from 'object'
     or jsonb_typeof(p_manifest->'featureFlags') is distinct from 'object' then
    raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
  end if;

  if p_manifest->>'hubId' !~ v_stable
     or btrim(p_manifest->>'name') = ''
     or length(p_manifest->>'name') > 160
     or p_manifest->>'name' is distinct from btrim(p_manifest->>'name')
     or btrim(p_manifest->>'description') = ''
     or length(p_manifest->>'description') > 1000
     or p_manifest->>'description' is distinct from btrim(p_manifest->>'description')
     or p_manifest->>'version' !~ v_semver
     or p_manifest->>'manifestVersion' !~ v_semver then
    raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
  end if;

  v_url := platform.hub_https_url_canonical(p_manifest->>'repositoryUrl');
  if v_url is null then
    raise exception using errcode = '22023', message = 'HUB_INVALID_URL';
  end if;

  v_url := platform.hub_https_url_canonical(p_manifest->>'deploymentUrl');
  if v_url is null then
    raise exception using errcode = '22023', message = 'HUB_INVALID_URL';
  end if;

  v_items := platform.hub_manifest_text_array(p_manifest->'courses');
  if cardinality(v_items) = 0
     or exists (
       select 1 from unnest(v_items) as item
       where item !~ v_stable
     )
     or (
       select count(*) from unnest(v_items) as item
     ) <> (
       select count(distinct item) from unnest(v_items) as item
     ) then
    raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
  end if;

  v_required := p_manifest->'compatibility'->'required';
  v_tested := p_manifest->'compatibility'->'testedCombinations';
  if jsonb_typeof(v_required) is distinct from 'object'
     or jsonb_typeof(v_tested) is distinct from 'array'
     or jsonb_array_length(v_tested) < 1
     or exists (
       select 1
       from jsonb_object_keys(p_manifest->'compatibility') as keys(compatibility_key)
       where compatibility_key not in ('required', 'testedCombinations')
     )
     or exists (
       select 1
       from jsonb_object_keys(v_required) as keys(required_key)
       where required_key not in (
         'coreVersion',
         'learnerApiContractVersion',
         'submissionContractVersion'
       )
     )
     or not (
       v_required ? 'coreVersion'
       and v_required ? 'learnerApiContractVersion'
       and v_required ? 'submissionContractVersion'
     )
     or v_required->>'coreVersion' !~ v_semver
     or v_required->>'learnerApiContractVersion' !~ v_semver
     or v_required->>'submissionContractVersion' !~ v_semver then
    raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
  end if;

  for v_combo in select value from jsonb_array_elements(v_tested) as value
  loop
    if jsonb_typeof(v_combo) is distinct from 'object'
       or v_combo->>'coreVersion' !~ v_semver
       or v_combo->>'learnerApiContractVersion' !~ v_semver
       or v_combo->>'submissionContractVersion' !~ v_semver then
      raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
    end if;
    if v_combo = v_required then
      v_seen := true;
    end if;
  end loop;

  if not v_seen then
    raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
  end if;

  if jsonb_typeof(p_manifest->'capabilities'->'evidence') is distinct from 'array'
     or jsonb_typeof(p_manifest->'capabilities'->'activities') is distinct from 'array'
     or exists (
       select 1
       from jsonb_object_keys(p_manifest->'capabilities') as keys(capability_key)
       where capability_key not in ('evidence', 'activities')
     ) then
    raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
  end if;

  foreach v_item in array array['evidence', 'activities']
  loop
    v_items := platform.hub_manifest_text_array(p_manifest->'capabilities'->v_item);
    if cardinality(v_items) = 0
       or exists (
         select 1 from unnest(v_items) as item
         where item !~ v_stable
       )
       or (
         select count(*) from unnest(v_items) as item
       ) <> (
         select count(distinct item) from unnest(v_items) as item
       ) then
      raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
    end if;
  end loop;

  if exists (
    select 1
    from jsonb_each(p_manifest->'featureFlags') as flag
    where flag.key !~ '^[a-z][A-Za-z0-9]*$'
       or jsonb_typeof(flag.value) is distinct from 'boolean'
  ) then
    raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
  end if;

  if p_manifest ? 'certification' then
    if jsonb_typeof(p_manifest->'certification') is distinct from 'object'
       or p_manifest->'certification'->>'standard' is distinct from 'LHDS'
       or p_manifest->'certification'->>'version' !~ v_semver
       or p_manifest->'certification'->>'status' not in (
         'not-certified', 'in-review', 'certified', 'expired', 'revoked'
       ) then
      raise exception using errcode = '22023', message = 'HUB_MANIFEST_INVALID';
    end if;
  end if;
end;
$$;

create function platform.register_hub(
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

  v_hub_code := p_manifest->>'hubId';
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

  if exists (
    select 1 from platform.hubs as hub
    where hub.hub_code = v_hub_code
  ) then
    raise exception using errcode = '23505', message = 'HUB_DUPLICATE_CODE';
  end if;

  if exists (
    select 1 from platform.hubs as hub
    where lower(rtrim(hub.repository_url, '/')) = lower(rtrim(v_repository_url, '/'))
  ) then
    raise exception using errcode = '23505', message = 'HUB_DUPLICATE_REPOSITORY';
  end if;

  if exists (
    select 1 from platform.hubs as hub
    where hub.deployment_url is not null
      and lower(rtrim(hub.deployment_url, '/')) = lower(rtrim(v_deployment_url, '/'))
  ) then
    raise exception using errcode = '23505', message = 'HUB_DUPLICATE_DEPLOYMENT';
  end if;

  insert into platform.hubs (
    hub_code,
    hub_name,
    description,
    hub_version,
    platform_version,
    manifest_version,
    core_version,
    learner_api_version,
    submission_contract_version,
    repository_url,
    deployment_url,
    activity_types,
    evidence_capabilities,
    features,
    compatibility,
    status,
    active,
    manifest,
    manifest_sha256
  ) values (
    v_hub_code,
    v_name,
    v_description,
    v_hub_version,
    v_core_version,
    v_manifest_version,
    v_core_version,
    v_learner_api_version,
    v_submission_version,
    v_repository_url,
    v_deployment_url,
    v_activities,
    v_evidence,
    v_features,
    v_compatibility,
    v_status,
    v_active,
    p_manifest,
    v_hash
  )
  returning * into v_hub;

  foreach v_course in array v_courses
  loop
    insert into platform.hub_course_links (hub_id, course_id, active)
    select v_hub.id, course.id, true
    from learning.courses as course
    where course.stable_key = v_course
      and course.active;
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
    'hub.registration.registered',
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
      'registeredBy', v_teacher.staff_reference
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

create function admin_api.register_hub(
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
  from platform.register_hub(p_manifest, p_status, p_active)
$$;

revoke all on function platform.hub_manifest_text_array(jsonb)
  from public, anon, authenticated;
revoke all on function platform.hub_https_url_canonical(text)
  from public, anon, authenticated;
revoke all on function platform.validate_hub_manifest(jsonb)
  from public, anon, authenticated;
revoke all on function platform.register_hub(jsonb, text, boolean)
  from public, anon, authenticated;
revoke all on function admin_api.register_hub(jsonb, text, boolean)
  from public, anon, authenticated;

grant execute on function platform.register_hub(jsonb, text, boolean)
  to authenticated;
grant execute on function admin_api.register_hub(jsonb, text, boolean)
  to authenticated;

comment on function platform.validate_hub_manifest(jsonb) is
  'Validates a learning-platform-hub.json object against the LHDS 1.0.0 contract.';
comment on function platform.register_hub(jsonb, text, boolean) is
  'Registers a reviewed hub manifest into platform.hubs after staff-role checks. Identity comes from auth.uid(). Duplicate hub codes are rejected.';
comment on function admin_api.register_hub(jsonb, text, boolean) is
  'Browser-safe wrapper for controlled hub registration. This is not curriculum publication.';
