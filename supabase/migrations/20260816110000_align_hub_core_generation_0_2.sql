-- Register supported Core 0.2.0 and align reviewed learner hubs.
-- Does not change api / admin_api contracts. Core 0.1.0 stays active so
-- historical hub-registration migrations continue to apply.

insert into platform.contract_versions (
  contract_key,
  version,
  status,
  compatibility,
  contract_document,
  published_at
) values (
  'learning-platform-core',
  '0.2.0',
  'active',
  '{"registration":"exact-version","generation":"supported"}'::jsonb,
  '{"component":"learning-platform-core"}'::jsonb,
  '2026-08-16T11:00:00Z'
)
on conflict (contract_key, version) do update set
  status = excluded.status,
  compatibility = excluded.compatibility,
  contract_document = excluded.contract_document;

update platform.hubs
set
  platform_version = '0.2.0',
  core_version = '0.2.0',
  compatibility = '{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]}'::jsonb,
  manifest = '{"capabilities":{"activities":["classification","coding-exercise","diagnostic","reflection"],"evidence":["question-level"]},"certification":{"standard":"LHDS","status":"not-certified","version":"1.0.0"},"compatibility":{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]},"courses":["ocr-level-3-it"],"deploymentUrl":"https://acerosa.github.io/unit-14-software-engineering-for-business-hub","description":"Learner hub for OCR Level 3 IT Unit 14 Software Engineering for Business (H/507/5017). Draft foundation; not a certified production hub.","featureFlags":{"authentication":true,"onboarding":true,"progress":true},"hubId":"unit-14-software-engineering-for-business","manifestVersion":"1.0.0","name":"Unit 14 Software Engineering for Business Hub","repositoryUrl":"https://github.com/Acerosa/unit-14-software-engineering-for-business-hub","version":"0.1.0"}'::jsonb,
  manifest_sha256 = '11d8368c5645501a65b5399b7cc87dea2051d1ca02b2ec3d49d7f3aa3e8ad207'
where hub_code = 'unit-14-software-engineering-for-business';

update platform.hubs
set
  hub_version = '0.2.0',
  platform_version = '0.2.0',
  core_version = '0.2.0',
  compatibility = '{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]}'::jsonb,
  manifest = '{"capabilities":{"activities":["classification","matching","reflection","retrieval-quiz"],"evidence":["question-level"]},"compatibility":{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]},"courses":["ocr-level-3-it"],"deploymentUrl":"https://acerosa.github.io/unit-3-Cyber-Security-Hub","description":"Learner hub for OCR Level 3 IT Unit 3 Cyber Security.","featureFlags":{"authentication":true,"onboarding":true,"progress":true},"hubId":"unit-3-cyber-security","manifestVersion":"1.0.0","name":"Unit 3 Cyber Security Hub","repositoryUrl":"https://github.com/Acerosa/unit-3-Cyber-Security-Hub","version":"0.2.0"}'::jsonb,
  manifest_sha256 = 'af84eb1d381807911d1386dd823348a269fce0597b0c6a3f4dc4fbb30c9ae895'
where hub_code = 'unit-3-cyber-security';

update platform.hubs
set
  platform_version = '0.2.0',
  core_version = '0.2.0',
  compatibility = '{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]}'::jsonb,
  manifest = '{"capabilities":{"activities":["classification","coding-exercise","diagnostic"],"evidence":["question-level"]},"compatibility":{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]},"courses":["t-level-digital-software-development"],"deploymentUrl":"https://acerosa.github.io/tlevel-software-development-hub","description":"Learner hub for T Level Digital Software Development.","featureFlags":{"authentication":true,"codingExercises":true,"onboarding":true,"progress":true},"hubId":"tlevel-software-development","manifestVersion":"1.0.0","name":"T Level Digital Software Development Hub","repositoryUrl":"https://github.com/Acerosa/tlevel-software-development-hub","version":"0.1.0"}'::jsonb,
  manifest_sha256 = '3eba98077a14de43e14bb41b24557e437227b90a8f303bc7335aedf38d7585d3'
where hub_code = 'tlevel-software-development';
