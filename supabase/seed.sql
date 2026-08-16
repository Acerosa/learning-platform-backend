-- Local development fixtures only. All identities and records are synthetic.
-- This file is applied only by explicit local Supabase reset/seed commands.

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  confirmation_token,
  recovery_token,
  email_change_token_new,
  email_change,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'student.a@local.invalid',
    null,
    now(),
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"synthetic":true,"fixture":"student-a"}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'student.b@local.invalid',
    null,
    now(),
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"synthetic":true,"fixture":"student-b"}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-4000-8000-000000000003',
    'authenticated',
    'authenticated',
    'demo.learner@local.invalid',
    null,
    now(),
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"synthetic":true,"fixture":"phase-2-demo-learner"}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '20000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'teacher.a@local.invalid',
    null,
    now(),
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"synthetic":true,"fixture":"teacher-a"}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '20000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'teacher.b@local.invalid',
    null,
    now(),
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"synthetic":true,"fixture":"teacher-b"}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '20000000-0000-4000-8000-000000000003',
    'authenticated',
    'authenticated',
    'platform.admin@local.invalid',
    null,
    now(),
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"synthetic":true,"fixture":"platform-admin"}'::jsonb,
    now(),
    now()
  )
on conflict (id) do nothing;

insert into auth.identities (
  id,
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
) values
  (
    '10000000-0000-4000-8000-000000000001',
    'student.a@local.invalid',
    '10000000-0000-4000-8000-000000000001',
    '{"sub":"10000000-0000-4000-8000-000000000001","email":"student.a@local.invalid","synthetic":true}'::jsonb,
    'email',
    now(),
    now(),
    now()
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    'student.b@local.invalid',
    '10000000-0000-4000-8000-000000000002',
    '{"sub":"10000000-0000-4000-8000-000000000002","email":"student.b@local.invalid","synthetic":true}'::jsonb,
    'email',
    now(),
    now(),
    now()
  ),
  (
    '10000000-0000-4000-8000-000000000003',
    'demo.learner@local.invalid',
    '10000000-0000-4000-8000-000000000003',
    '{"sub":"10000000-0000-4000-8000-000000000003","email":"demo.learner@local.invalid","synthetic":true}'::jsonb,
    'email',
    now(),
    now(),
    now()
  ),
  (
    '20000000-0000-4000-8000-000000000001',
    'teacher.a@local.invalid',
    '20000000-0000-4000-8000-000000000001',
    '{"sub":"20000000-0000-4000-8000-000000000001","email":"teacher.a@local.invalid","synthetic":true}'::jsonb,
    'email',
    now(),
    now(),
    now()
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    'teacher.b@local.invalid',
    '20000000-0000-4000-8000-000000000002',
    '{"sub":"20000000-0000-4000-8000-000000000002","email":"teacher.b@local.invalid","synthetic":true}'::jsonb,
    'email',
    now(),
    now(),
    now()
  ),
  (
    '20000000-0000-4000-8000-000000000003',
    'platform.admin@local.invalid',
    '20000000-0000-4000-8000-000000000003',
    '{"sub":"20000000-0000-4000-8000-000000000003","email":"platform.admin@local.invalid","synthetic":true}'::jsonb,
    'email',
    now(),
    now(),
    now()
  )
on conflict (provider_id, provider) do nothing;

insert into learning.academic_years (
  id, code, starts_on, ends_on, active
) values (
  '40000000-0000-4000-8000-000000000001',
  '2026-27',
  '2026-09-01',
  '2027-08-31',
  true
)
on conflict (code) do nothing;

insert into learning.groups (
  id,
  academic_year_id,
  course_id,
  code,
  name,
  active,
  year_group,
  registration_key,
  registration_open
) values
  (
    '60000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001',
    '50000000-0000-4000-8000-000000000001',
    'TEST-GROUP-A',
    'Synthetic Test Group A',
    true,
    'Year 1',
    'synthetic-year-1-a',
    true
  ),
  (
    '60000000-0000-4000-8000-000000000002',
    '40000000-0000-4000-8000-000000000001',
    '50000000-0000-4000-8000-000000000001',
    'TEST-GROUP-B',
    'Synthetic Test Group B',
    true,
    'Year 2',
    'synthetic-year-2-b',
    false
  ),
  (
    '60000000-0000-4000-8000-000000000003',
    '40000000-0000-4000-8000-000000000001',
    '50000000-0000-4000-8000-000000000001',
    'DEMO-GROUP',
    'Phase 2 Demonstration Group',
    true,
    'Year 1',
    'phase-2-demonstration',
    false
  );

insert into learning.students (
  id, auth_user_id, student_number, first_name, surname, display_name, active
) values
  (
    '30000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'SYNTH-0001',
    'Synthetic',
    'Student A',
    'Synthetic Student A',
    true
  ),
  (
    '30000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000002',
    'SYNTH-0002',
    'Synthetic',
    'Student B',
    'Synthetic Student B',
    true
  ),
  (
    '30000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000003',
    'SYNTH-DEMO',
    'Phase 2',
    'Learner',
    'Phase 2 Demonstration Learner',
    true
  );

insert into learning.teachers (
  id, auth_user_id, staff_reference, display_name, active
) values
  (
    '31000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'SYNTH-TEACHER-A',
    'Synthetic Teacher A',
    true
  ),
  (
    '31000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'SYNTH-TEACHER-B',
    'Synthetic Teacher B',
    true
  ),
  (
    '31000000-0000-4000-8000-000000000003',
    '20000000-0000-4000-8000-000000000003',
    'SYNTH-PLATFORM-ADMIN',
    'Synthetic Platform Administrator',
    true
  );

insert into learning.enrolments (
  id, student_id, group_id, joined_on, status
) values
  (
    '70000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-000000000001',
    '2026-09-01',
    'active'
  ),
  (
    '70000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000002',
    '60000000-0000-4000-8000-000000000002',
    '2026-09-01',
    'active'
  ),
  (
    '70000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000003',
    '60000000-0000-4000-8000-000000000003',
    '2026-09-01',
    'active'
  );

insert into learning.teacher_group_access (
  teacher_id, group_id, role, granted_at
) values
  (
    '31000000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-000000000001',
    'teacher',
    '2026-09-01T00:00:00Z'
  ),
  (
    '31000000-0000-4000-8000-000000000002',
    '60000000-0000-4000-8000-000000000002',
    'teacher',
    '2026-09-01T00:00:00Z'
  );

-- Separate synthetic local-only platform administrator used to demonstrate the
-- authenticated Central Admin Portal vertical slice. Authentication still
-- happens through Supabase Auth; this row is the backend authority.
insert into platform.staff_roles (
  id,
  teacher_id,
  role,
  granted_at
) values (
  '32000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000003',
  'platform_admin',
  '2026-08-11T14:58:37Z'
)
on conflict (teacher_id, role) where revoked_at is null do nothing;

insert into learning.activity_assignments (
  id, group_id, activity_version_id, required, active
)
select
  case
    when learner_group.id = '60000000-0000-4000-8000-000000000001'
      and activity_version.id = '91000000-0000-4000-8000-000000000001'
      then '92000000-0000-4000-8000-000000000001'::uuid
    when learner_group.id = '60000000-0000-4000-8000-000000000002'
      and activity_version.id = '91000000-0000-4000-8000-000000000001'
      then '92000000-0000-4000-8000-000000000002'::uuid
    else md5(learner_group.id::text || activity_version.id::text)::uuid
  end,
  learner_group.id,
  activity_version.id,
  true,
  true
from learning.groups as learner_group
join learning.activity_versions as activity_version
  on true
join learning.activities as activity
  on activity.id = activity_version.activity_id
join learning.modules as module
  on module.id = activity.module_id
where learner_group.code in ('TEST-GROUP-A', 'TEST-GROUP-B')
  and module.course_id = learner_group.course_id
  and activity_version.published_at is not null
  and activity_version.retired_at is null;

-- A single isolated local-only attempt gives the Phase 2 portal repeatable
-- Attempts and Analytics data without changing the established A/B RLS cases.
insert into learning.activity_assignments (
  id, group_id, activity_version_id, required, active
) values (
  '92000000-0000-4000-8000-000000000003',
  '60000000-0000-4000-8000-000000000003',
  '91000000-0000-4000-8000-000000000001',
  true,
  true
);

insert into learning.attempts (
  id,
  client_attempt_id,
  student_id,
  enrolment_id,
  assignment_id,
  activity_version_id,
  attempt_number,
  status,
  score,
  max_score,
  marking_source,
  evidence_level,
  submission_hash,
  received_at,
  completed_at
) values (
  '93000000-0000-4000-8000-000000000003',
  'phase-2-demo-attempt',
  '30000000-0000-4000-8000-000000000003',
  '70000000-0000-4000-8000-000000000003',
  '92000000-0000-4000-8000-000000000003',
  '91000000-0000-4000-8000-000000000001',
  1,
  'completed',
  8,
  10,
  'server',
  'summary_only',
  repeat('d', 64),
  clock_timestamp() - interval '1 hour',
  clock_timestamp() - interval '55 minutes'
);

-- Local catalogue delivery rows for the imported Unit 3 activity metadata.
insert into learning.activity_delivery (
  activity_version_id,
  academic_year_id,
  curriculum_week_id,
  week_number,
  session_number,
  sort_order,
  active
)
select
  version.id,
  year.id,
  week.id,
  week.week_number,
  case
    when activity.stable_key like 'u3-w01-%' then 1
    else null
  end,
  row_number() over (partition by week.id order by activity.stable_key),
  true
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
join learning.modules as module on module.id = activity.module_id
join learning.courses as course on course.id = module.course_id
join learning.curriculum_weeks as week
  on week.module_id = module.id
  and (
    activity.stable_key like 'week' || week.week_number || '-%'
    or (week.week_number = 1 and activity.stable_key like 'u3-w01-%')
  )
join learning.academic_years as year on year.code = '2026-27' and year.active
where course.stable_key = 'ocr-level-3-it'
  and not exists (
    select 1 from learning.activity_delivery as existing
    where existing.activity_version_id = version.id
      and existing.academic_year_id = year.id
      and existing.group_id is null
  );

-- Platform repository fixtures. These records are synthetic/local registry
-- data and are not a hosted deployment instruction.
insert into platform.hubs (
  id,
  hub_code,
  hub_name,
  description,
  hub_version,
  platform_version,
  manifest_version,
  core_version,
  learner_api_version,
  submission_contract_version,
  subject,
  repository_url,
  deployment_url,
  curriculum_model,
  activity_types,
  evidence_capabilities,
  features,
  compatibility,
  status,
  active,
  manifest,
  manifest_sha256
) values
  (
    '33000000-0000-4000-8000-000000000001',
    'unit-3-cyber-security',
    'Unit 3 Cyber Security Hub',
    'Learner hub for OCR Level 3 IT Unit 3 Cyber Security.',
    '0.2.0',
    '0.2.0',
    '1.0.0',
    '0.2.0',
    '0.1.0',
    '0.1.0',
    'OCR Level 3 IT Unit 3 Cyber Security',
    'https://github.com/Acerosa/unit-3-Cyber-Security-Hub',
    'https://acerosa.github.io/unit-3-Cyber-Security-Hub/',
    'course/unit/week/session/activity/learning-outcome',
    array['retrieval-quiz', 'classification', 'matching', 'reflection'],
    array['question-level'],
    '{"authentication":true,"onboarding":true,"progress":true}'::jsonb,
    '{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]}'::jsonb,
    'testing',
    true,
    '{"capabilities":{"activities":["classification","matching","reflection","retrieval-quiz"],"evidence":["question-level"]},"compatibility":{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]},"courses":["ocr-level-3-it"],"deploymentUrl":"https://acerosa.github.io/unit-3-Cyber-Security-Hub","description":"Learner hub for OCR Level 3 IT Unit 3 Cyber Security.","featureFlags":{"authentication":true,"onboarding":true,"progress":true},"hubId":"unit-3-cyber-security","manifestVersion":"1.0.0","name":"Unit 3 Cyber Security Hub","repositoryUrl":"https://github.com/Acerosa/unit-3-Cyber-Security-Hub","version":"0.2.0"}'::jsonb,
    'af84eb1d381807911d1386dd823348a269fce0597b0c6a3f4dc4fbb30c9ae895'
  ),
  (
    '33000000-0000-4000-8000-000000000002',
    'tlevel-software-development',
    'T Level Digital Software Development Hub',
    'Learner hub for T Level Digital Software Development.',
    '0.1.0',
    '0.2.0',
    '1.0.0',
    '0.2.0',
    '0.1.0',
    '0.1.0',
    'T Level Digital Software Development',
    'https://github.com/Acerosa/tlevel-software-development-hub',
    'https://acerosa.github.io/tlevel-software-development-hub/',
    'course/unit/week/session/activity/learning-outcome',
    array['diagnostic', 'classification', 'coding-exercise'],
    array['question-level'],
    '{"authentication":true,"onboarding":true,"progress":true,"codingExercises":true}'::jsonb,
    '{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]}'::jsonb,
    'testing',
    true,
    '{"capabilities":{"activities":["classification","coding-exercise","diagnostic"],"evidence":["question-level"]},"compatibility":{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]},"courses":["t-level-digital-software-development"],"deploymentUrl":"https://acerosa.github.io/tlevel-software-development-hub","description":"Learner hub for T Level Digital Software Development.","featureFlags":{"authentication":true,"codingExercises":true,"onboarding":true,"progress":true},"hubId":"tlevel-software-development","manifestVersion":"1.0.0","name":"T Level Digital Software Development Hub","repositoryUrl":"https://github.com/Acerosa/tlevel-software-development-hub","version":"0.1.0"}'::jsonb,
    '3eba98077a14de43e14bb41b24557e437227b90a8f303bc7335aedf38d7585d3'
  )
on conflict (hub_code) do nothing;

insert into platform.hub_course_links (hub_id, course_id, active)
select hub.id, course.id, true
from platform.hubs as hub
join learning.courses as course
  on course.stable_key = case hub.hub_code
    when 'unit-3-cyber-security' then 'ocr-level-3-it'
    when 'tlevel-software-development' then 't-level-digital-software-development'
  end
where hub.hub_code in (
  'unit-3-cyber-security',
  'tlevel-software-development'
)
on conflict (hub_id, course_id) do nothing;

insert into platform.operational_health (
  service_key,
  status,
  checked_at,
  valid_until,
  public_message,
  diagnostics,
  public_visible
) values (
  'local-database',
  'healthy',
  clock_timestamp(),
  clock_timestamp() + interval '1 day',
  'Local database fixtures loaded.',
  '{"environment":"local","fixture":true}'::jsonb,
  true
)
on conflict (service_key) do update set
  status = excluded.status,
  checked_at = excluded.checked_at,
  valid_until = excluded.valid_until,
  public_message = excluded.public_message,
  diagnostics = excluded.diagnostics,
  public_visible = excluded.public_visible;
