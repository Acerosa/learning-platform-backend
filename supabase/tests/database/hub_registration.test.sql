begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_column(
  'platform',
  'hubs',
  'manifest_version',
  'hub registry records the reviewed manifest contract version'
);

select has_column(
  'platform',
  'hubs',
  'learner_api_version',
  'hub registry records the required learner API contract'
);

select has_column(
  'platform',
  'hubs',
  'submission_contract_version',
  'hub registry records the required submission contract'
);

select has_function(
  'platform',
  'enforce_hub_compatibility',
  array[]::text[],
  'database compatibility enforcement exists'
);

select is(
  (
    select count(*)
    from platform.contract_versions
    where contract_key in ('hub-manifest', 'learning-platform-core')
      and status = 'active'
  ),
  2::bigint,
  'manifest and core compatibility versions are active'
);

select is(
  (
    select count(*)
    from platform.hubs
    where manifest_version = '1.0.0'
      and core_version = '0.1.0'
      and learner_api_version = '0.1.0'
      and submission_contract_version = '0.1.0'
      and manifest_sha256 ~ '^[0-9a-f]{64}$'
  ),
  2::bigint,
  'local hub fixtures carry complete manifest provenance and compatibility metadata'
);

select lives_ok(
  $$insert into platform.hubs (
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
      'test-prerelease-hub',
      'Test prerelease hub',
      'Synthetic validation row.',
      '1.0.0-rc.1',
      '0.1.0',
      '1.0.0',
      '0.1.0',
      '0.1.0',
      '0.1.0',
      'https://example.invalid/test-prerelease-hub',
      'https://test-prerelease-hub.example.invalid',
      array['quiz'],
      array['question-level'],
      '{}'::jsonb,
      '{}'::jsonb,
      'planned',
      false,
      '{}'::jsonb,
      repeat('0', 64)
    )$$,
  'Semantic Versioning prerelease hub versions are accepted'
);

select throws_like(
  $$update platform.hubs
    set hub_version = '1.0.0-01'
    where hub_code = 'test-prerelease-hub'$$,
  '%hub_version_semver_valid%',
  'numeric prerelease identifiers with leading zeroes are rejected'
);

select throws_like(
  $$insert into platform.hubs (
      hub_code, hub_name, description, hub_version, platform_version,
      manifest_version, core_version, learner_api_version,
      submission_contract_version, repository_url, deployment_url,
      activity_types, evidence_capabilities, features, compatibility,
      status, active, manifest, manifest_sha256
    ) values (
      'duplicate-repository-hub', 'Duplicate repository hub', 'Synthetic.',
      '1.0.0', '0.1.0', '1.0.0', '0.1.0', '0.1.0', '0.1.0',
      'https://github.com/acerosa/unit-3-cyber-security-hub/',
      'https://duplicate-repository.example.invalid', array['quiz'],
      array['question-level'], '{}'::jsonb, '{}'::jsonb, 'planned', false,
      '{}'::jsonb, repeat('1', 64)
    )$$,
  '%hubs_repository_url_unique%',
  'repository conflicts are rejected case-insensitively and without trailing-slash ambiguity'
);

select throws_like(
  $$insert into platform.hubs (
      hub_code, hub_name, description, hub_version, platform_version,
      manifest_version, core_version, learner_api_version,
      submission_contract_version, repository_url, deployment_url,
      activity_types, evidence_capabilities, features, compatibility,
      status, active, manifest, manifest_sha256
    ) values (
      'duplicate-deployment-hub', 'Duplicate deployment hub', 'Synthetic.',
      '1.0.0', '0.1.0', '1.0.0', '0.1.0', '0.1.0', '0.1.0',
      'https://example.invalid/duplicate-deployment-hub',
      'https://ACEROSA.github.io/unit-3-Cyber-Security-Hub/', array['quiz'],
      array['question-level'], '{}'::jsonb, '{}'::jsonb, 'planned', false,
      '{}'::jsonb, repeat('2', 64)
    )$$,
  '%hubs_deployment_url_unique%',
  'deployment conflicts are rejected case-insensitively and without trailing-slash ambiguity'
);

select throws_ok(
  $$insert into platform.hubs (
      hub_code, hub_name, description, hub_version, platform_version,
      manifest_version, core_version, learner_api_version,
      submission_contract_version, repository_url, deployment_url,
      activity_types, evidence_capabilities, features, compatibility,
      status, active, manifest, manifest_sha256
    ) values (
      'unsupported-core-hub', 'Unsupported core hub', 'Synthetic.',
      '1.0.0', '9.0.0', '1.0.0', '9.0.0', '0.1.0', '0.1.0',
      'https://example.invalid/unsupported-core-hub',
      'https://unsupported-core.example.invalid', array['quiz'],
      array['question-level'], '{}'::jsonb, '{}'::jsonb, 'planned', false,
      '{}'::jsonb, repeat('3', 64)
    )$$,
  '23514',
  'HUB_CORE_VERSION_UNSUPPORTED',
  'database registration refuses an unsupported core version'
);

select * from finish();
rollback;
