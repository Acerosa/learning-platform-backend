-- Align Core 0.2.5 with the reviewed platform-contracts catalogue, then
-- register the Level 3 IT Year 1 Readiness Diagnostic Hub against
-- ocr-level-3-it. Local testing/active only. Does not create a Year 1 course.
-- Generated registration body from scripts/import/generate-hub-registration-migration.py.
-- Canonical manifest SHA-256: 1d929082ae5e849f9166c87f59ce754dca88ca87e5482d32a583629b7bd9f07f

begin;

insert into platform.contract_versions (
  contract_key,
  version,
  status,
  compatibility,
  contract_document,
  published_at
) values (
  'learning-platform-core',
  '0.2.5',
  'active',
  '{"registration":"exact-version","generation":"supported","notes":"Auth email confirmation redirect and hubRootPath generation"}'::jsonb,
  '{"component":"learning-platform-core"}'::jsonb,
  '2026-09-03T12:00:00Z'
)
on conflict (contract_key, version) do update set
  status = excluded.status,
  compatibility = excluded.compatibility,
  contract_document = excluded.contract_document;

select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended('hub-registration:level-3-it-year-1-readiness', 0)
);

do $$
begin
  if not exists (
    select 1
    from platform.contract_versions as contract
    where contract.contract_key = 'hub-manifest'
      and contract.version = '1.0.0'
      and contract.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'HUB_MANIFEST_VERSION_UNSUPPORTED';
  end if;
  if not exists (
    select 1
    from platform.contract_versions as contract
    where contract.contract_key = 'learning-platform-core'
      and contract.version = '0.2.5'
      and contract.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'HUB_CORE_VERSION_UNSUPPORTED';
  end if;
  if not exists (
    select 1
    from platform.contract_versions as contract
    where contract.contract_key = 'learner-api'
      and contract.version = '0.1.0'
      and contract.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'HUB_LEARNER_API_VERSION_UNSUPPORTED';
  end if;
  if not exists (
    select 1
    from platform.contract_versions as contract
    where contract.contract_key = 'submission'
      and contract.version = '0.1.0'
      and contract.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'HUB_SUBMISSION_VERSION_UNSUPPORTED';
  end if;
  if not exists (
    select 1 from learning.courses as course
    where course.stable_key = 'ocr-level-3-it' and course.active
  ) then
    raise exception using errcode = '23514', message = 'HUB_COURSE_NOT_FOUND:ocr-level-3-it';
  end if;
end
$$;

insert into platform.hubs (
  id, hub_code, hub_name, description, hub_version, platform_version,
  manifest_version, core_version, learner_api_version, submission_contract_version,
  repository_url, deployment_url, activity_types, evidence_capabilities,
  features, compatibility, status, active, manifest, manifest_sha256
) values (
  '5a7a4d40-70a1-51d0-b93b-8fa970f2a0b0',
  'level-3-it-year-1-readiness',
  'Level 3 IT Year 1 Readiness Diagnostic Hub',
  'Short, low-pressure readiness check for new OCR Level 3 IT Year 1 learners covering first-term units. Diagnostic only; not a formal assessment.',
  '0.1.0',
  '0.2.5',
  '1.0.0',
  '0.2.5',
  '0.1.0',
  '0.1.0',
  'https://github.com/Acerosa/level-3-it-year-1-readiness-hub',
  'https://acerosa.github.io/level-3-it-year-1-readiness-hub',
  array['classification', 'diagnostic', 'matching', 'reflection', 'retrieval-quiz']::text[],
  array['question-level']::text[],
  '{"authentication":false,"diagnostic":true,"onboarding":false,"progress":false}'::jsonb,
  '{"required":{"coreVersion":"0.2.5","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.5","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]}'::jsonb,
  'testing',
  true,
  '{"capabilities":{"activities":["classification","diagnostic","matching","reflection","retrieval-quiz"],"evidence":["question-level"]},"compatibility":{"required":{"coreVersion":"0.2.5","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.5","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]},"courses":["ocr-level-3-it"],"deploymentUrl":"https://acerosa.github.io/level-3-it-year-1-readiness-hub","description":"Short, low-pressure readiness check for new OCR Level 3 IT Year 1 learners covering first-term units. Diagnostic only; not a formal assessment.","featureFlags":{"authentication":false,"diagnostic":true,"onboarding":false,"progress":false},"hubId":"level-3-it-year-1-readiness","manifestVersion":"1.0.0","name":"Level 3 IT Year 1 Readiness Diagnostic Hub","repositoryUrl":"https://github.com/Acerosa/level-3-it-year-1-readiness-hub","version":"0.1.0"}'::jsonb,
  '1d929082ae5e849f9166c87f59ce754dca88ca87e5482d32a583629b7bd9f07f'
)
on conflict (hub_code) do update set
  hub_name = excluded.hub_name,
  description = excluded.description,
  hub_version = excluded.hub_version,
  platform_version = excluded.platform_version,
  manifest_version = excluded.manifest_version,
  core_version = excluded.core_version,
  learner_api_version = excluded.learner_api_version,
  submission_contract_version = excluded.submission_contract_version,
  repository_url = excluded.repository_url,
  deployment_url = excluded.deployment_url,
  activity_types = excluded.activity_types,
  evidence_capabilities = excluded.evidence_capabilities,
  features = excluded.features,
  compatibility = excluded.compatibility,
  status = excluded.status,
  active = excluded.active,
  manifest = excluded.manifest,
  manifest_sha256 = excluded.manifest_sha256,
  updated_at = clock_timestamp();

update platform.hub_course_links as link
set active = false
where link.hub_id = (select id from platform.hubs where hub_code = 'level-3-it-year-1-readiness')
  and link.course_id not in (
    select course.id from learning.courses as course
    where course.stable_key = any (array['ocr-level-3-it']::text[])
  );

insert into platform.hub_course_links (hub_id, course_id, active)
select hub.id, course.id, true
from platform.hubs as hub
join learning.courses as course
  on course.stable_key = 'ocr-level-3-it'
where hub.hub_code = 'level-3-it-year-1-readiness'
on conflict (hub_id, course_id) do update set active = true;

commit;
