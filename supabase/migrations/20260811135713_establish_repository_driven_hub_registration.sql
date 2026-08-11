-- Establish the database half of repository-driven hub registration. Repository
-- manifests are reviewed inputs; runtime reads only these authoritative tables.

insert into platform.contract_versions (
  contract_key,
  version,
  status,
  compatibility,
  contract_document,
  published_at
) values
  (
    'hub-manifest',
    '1.0.0',
    'active',
    '{"validator":"scripts/import/validate-hub-manifest.py"}'::jsonb,
    '{"schema":"learning-platform-hub.schema.json","standard":"LHDS"}'::jsonb,
    '2026-08-11T13:57:13Z'
  ),
  (
    'learning-platform-core',
    '0.1.0',
    'active',
    '{"registration":"exact-version"}'::jsonb,
    '{"component":"learning-platform-core"}'::jsonb,
    '2026-08-11T13:57:13Z'
  )
on conflict (contract_key, version) do nothing;

alter table platform.hubs
  add column description text,
  add column manifest_version text,
  add column core_version text,
  add column learner_api_version text,
  add column submission_contract_version text,
  add column evidence_capabilities text[],
  add column compatibility jsonb,
  add column manifest_sha256 text;

update platform.hubs as hub
set
  description = coalesce(nullif(btrim(hub.subject), ''), hub.hub_name),
  manifest_version = '1.0.0',
  core_version = hub.platform_version,
  learner_api_version = '0.1.0',
  submission_contract_version = '0.1.0',
  evidence_capabilities = array['question-level'],
  compatibility = jsonb_build_object(
    'required',
    jsonb_build_object(
      'coreVersion', hub.platform_version,
      'learnerApiContractVersion', '0.1.0',
      'submissionContractVersion', '0.1.0'
    ),
    'testedCombinations',
    jsonb_build_array(
      jsonb_build_object(
        'coreVersion', hub.platform_version,
        'learnerApiContractVersion', '0.1.0',
        'submissionContractVersion', '0.1.0'
      )
    )
  ),
  manifest_sha256 = encode(
    extensions.digest(
      pg_catalog.convert_to(hub.manifest::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

alter table platform.hubs
  alter column subject drop not null,
  alter column curriculum_model drop not null,
  alter column description set not null,
  alter column manifest_version set not null,
  alter column core_version set not null,
  alter column learner_api_version set not null,
  alter column submission_contract_version set not null,
  alter column evidence_capabilities set not null,
  alter column compatibility set not null,
  alter column manifest_sha256 set not null,
  drop constraint hub_version_semver_valid,
  drop constraint hub_platform_version_semver_valid,
  add constraint hub_description_not_blank
    check (btrim(description) <> ''),
  add constraint hub_manifest_version_semver_valid check (
    manifest_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*))(\.((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*)))*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
  ),
  add constraint hub_version_semver_valid check (
    hub_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*))(\.((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*)))*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
  ),
  add constraint hub_platform_version_semver_valid check (
    platform_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*))(\.((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*)))*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
  ),
  add constraint hub_core_version_semver_valid check (
    core_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*))(\.((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*)))*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
  ),
  add constraint hub_learner_api_version_semver_valid check (
    learner_api_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*))(\.((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*)))*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
  ),
  add constraint hub_submission_version_semver_valid check (
    submission_contract_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*))(\.((0|[1-9][0-9]*)|([0-9]*[A-Za-z-][0-9A-Za-z-]*)))*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
  ),
  add constraint hub_evidence_capabilities_not_empty
    check (cardinality(evidence_capabilities) > 0),
  add constraint hub_compatibility_object
    check (jsonb_typeof(compatibility) = 'object'),
  add constraint hub_manifest_sha256_valid
    check (manifest_sha256 ~ '^[0-9a-f]{64}$');

create unique index hubs_repository_url_unique
  on platform.hubs (lower(rtrim(repository_url, '/')));

create unique index hubs_deployment_url_unique
  on platform.hubs (lower(rtrim(deployment_url, '/')))
  where deployment_url is not null;

create function platform.enforce_hub_compatibility()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from platform.contract_versions as contract
    where contract.contract_key = 'hub-manifest'
      and contract.version = new.manifest_version
      and contract.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'HUB_MANIFEST_VERSION_UNSUPPORTED';
  end if;

  if not exists (
    select 1 from platform.contract_versions as contract
    where contract.contract_key = 'learning-platform-core'
      and contract.version = new.core_version
      and contract.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'HUB_CORE_VERSION_UNSUPPORTED';
  end if;

  if not exists (
    select 1 from platform.contract_versions as contract
    where contract.contract_key = 'learner-api'
      and contract.version = new.learner_api_version
      and contract.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'HUB_LEARNER_API_VERSION_UNSUPPORTED';
  end if;

  if not exists (
    select 1 from platform.contract_versions as contract
    where contract.contract_key = 'submission'
      and contract.version = new.submission_contract_version
      and contract.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      message = 'HUB_SUBMISSION_VERSION_UNSUPPORTED';
  end if;

  if new.platform_version <> new.core_version then
    raise exception using
      errcode = '23514',
      message = 'HUB_LEGACY_PLATFORM_VERSION_MISMATCH';
  end if;

  return new;
end
$$;

create trigger hubs_enforce_compatibility
before insert or update of
  manifest_version,
  platform_version,
  core_version,
  learner_api_version,
  submission_contract_version
on platform.hubs
for each row execute function platform.enforce_hub_compatibility();

create or replace view admin_api.hubs
with (security_invoker = true)
as
select
  hub.id,
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
  hub.status,
  hub.active,
  hub.manifest,
  hub.created_at,
  hub.updated_at,
  hub.description,
  hub.manifest_version,
  hub.core_version,
  hub.learner_api_version,
  hub.submission_contract_version,
  hub.evidence_capabilities,
  hub.compatibility,
  hub.manifest_sha256
from platform.hubs as hub;

comment on column platform.hubs.manifest_version is
  'Version of the LHDS learning-platform-hub.json contract used for registration.';
comment on column platform.hubs.manifest_sha256 is
  'SHA-256 of the canonical reviewed source manifest used to generate registration SQL.';
comment on function platform.enforce_hub_compatibility() is
  'Rejects hub rows that reference inactive platform, API, submission or manifest contract versions.';
