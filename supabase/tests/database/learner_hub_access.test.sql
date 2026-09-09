begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
select hub.id, learner_group.id, true, mapping.join_policy
from (
  values
    ('tlevel-software-development', 'TLEVEL-DSD-Y2', 'open_auto'),
    ('unit-3-cyber-security', 'CYBER-TEST-A', 'open_explicit'),
    ('unit-3-cyber-security', 'CYBER-TEST-QA', 'closed'),
    ('unit-14-software-engineering-for-business', 'UNIT14-TEST-A', 'closed')
) as mapping(hub_code, group_code, join_policy)
join platform.hubs as hub
  on hub.hub_code = mapping.hub_code
join learning.groups as learner_group
  on learner_group.code = mapping.group_code
on conflict (hub_id, group_id) do nothing;

insert into learning.courses (
  id, stable_key, title, qualification_level, active
)
select
  '51000000-0000-4000-8000-0000000000e2',
  'gateway-level-2-digital-it-skills',
  'Gateway Level 2 Digital and IT Skills',
  'Level 2',
  true
where not exists (
  select 1 from learning.courses where stable_key = 'gateway-level-2-digital-it-skills'
);

insert into platform.hubs (
  id, hub_code, hub_name, description, hub_version, platform_version,
  manifest_version, core_version, learner_api_version, submission_contract_version,
  repository_url, deployment_url, activity_types, evidence_capabilities,
  features, compatibility, status, active, manifest, manifest_sha256
)
select
  '34eccf37-3452-50c6-983d-d8e3ef4ca9f6',
  'l2e-exploring-emerging-digital-technologies',
  'Exploring New and Emerging Digital Technologies',
  'Learner hub for Gateway Level 2 Exploring New and Emerging Digital Technologies.',
  '0.1.0',
  '0.2.0',
  '1.0.0',
  '0.2.0',
  '0.1.0',
  '0.1.0',
  'https://github.com/Acerosa/Emerging-Digital-Technologies-Hub',
  'https://acerosa.github.io/Emerging-Digital-Technologies-Hub',
  array['classification', 'reflection', 'retrieval']::text[],
  array['question-level']::text[],
  '{"authentication":true,"onboarding":true,"progress":true}'::jsonb,
  '{"required":{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"},"testedCombinations":[{"coreVersion":"0.2.0","learnerApiContractVersion":"0.1.0","submissionContractVersion":"0.1.0"}]}'::jsonb,
  'testing',
  true,
  '{"capabilities":{"activities":["classification","reflection","retrieval"],"evidence":["question-level"]},"courses":["gateway-level-2-digital-it-skills"],"hubId":"l2e-exploring-emerging-digital-technologies","manifestVersion":"1.0.0","name":"Exploring New and Emerging Digital Technologies","version":"0.1.0"}'::jsonb,
  '97dcbfb7f5bbe0c3928c8d3d9f005e427210504d406c21e3e82a5ec0fb619187'
where not exists (
  select 1 from platform.hubs where hub_code = 'l2e-exploring-emerging-digital-technologies'
);

insert into platform.hub_course_links (hub_id, course_id, active)
select hub.id, course.id, true
from platform.hubs as hub
join learning.courses as course
  on course.stable_key = 'gateway-level-2-digital-it-skills'
where hub.hub_code = 'l2e-exploring-emerging-digital-technologies'
on conflict (hub_id, course_id) do update set active = true;

insert into learning.groups (
  id, academic_year_id, course_id, code, name, active, year_group,
  registration_key, registration_open, is_synthetic
)
select
  '60000000-0000-4000-8000-0000000000a2',
  academic_year.id,
  course.id,
  'L2E-DELIVERY-A',
  'L2E Gateway Delivery Group A',
  true,
  'Year 1',
  'l2e-year-1-delivery',
  true,
  false
from learning.courses as course
join lateral (
  select candidate.id
  from learning.academic_years as candidate
  where candidate.active
  order by candidate.code
  limit 1
) as academic_year on true
where course.stable_key = 'gateway-level-2-digital-it-skills'
on conflict (academic_year_id, course_id, code) do update
set
  active = true,
  registration_open = true,
  registration_key = excluded.registration_key;

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
select hub.id, learner_group.id, true, 'open_auto'
from platform.hubs as hub
join learning.groups as learner_group
  on learner_group.code = 'L2E-DELIVERY-A'
where hub.hub_code = 'l2e-exploring-emerging-digital-technologies'
on conflict (hub_id, group_id) do nothing;

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  fixture.id,
  'authenticated',
  'authenticated',
  fixture.email,
  null,
  clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('synthetic', true, 'fixture', fixture.fixture),
  clock_timestamp(),
  clock_timestamp()
from (
  values
    ('14000000-0000-4000-8000-000000000001'::uuid, 'hub.access.none@local.invalid', 'hub-none'),
    ('14000000-0000-4000-8000-000000000002'::uuid, 'hub.access.profile@local.invalid', 'hub-profile'),
    ('14000000-0000-4000-8000-000000000003'::uuid, 'hub.access.tlevel@local.invalid', 'hub-tlevel'),
    ('14000000-0000-4000-8000-000000000004'::uuid, 'hub.access.cyber@local.invalid', 'hub-cyber'),
    ('14000000-0000-4000-8000-000000000005'::uuid, 'hub.access.l2e@local.invalid', 'hub-l2e'),
    ('14000000-0000-4000-8000-000000000006'::uuid, 'hub.access.dual@local.invalid', 'hub-dual'),
    ('14000000-0000-4000-8000-000000000007'::uuid, 'hub.access.auto@local.invalid', 'hub-auto'),
    ('14000000-0000-4000-8000-000000000008'::uuid, 'hub.access.inactive@local.invalid', 'hub-inactive'),
    ('14000000-0000-4000-8000-000000000009'::uuid, 'hub.access.unit14@local.invalid', 'hub-unit14'),
    ('14000000-0000-4000-8000-00000000000a'::uuid, 'hub.access.closed@local.invalid', 'hub-closed'),
    ('14000000-0000-4000-8000-00000000000b'::uuid, 'hub.access.inactive.cyber@local.invalid', 'hub-inactive-cyber'),
    ('14000000-0000-4000-8000-00000000000c'::uuid, 'hub.access.inactive.closed@local.invalid', 'hub-inactive-closed')
) as fixture(id, email, fixture);

insert into learning.students (
  id, auth_user_id, student_number, first_name, surname, display_name, contact_email, active
) values
  (
    '34000000-0000-4000-8000-000000000002',
    '14000000-0000-4000-8000-000000000002',
    'HUB-PROFILE',
    'Profile',
    'Only',
    'Profile Only',
    'hub.access.profile@local.invalid',
    true
  ),
  (
    '34000000-0000-4000-8000-000000000003',
    '14000000-0000-4000-8000-000000000003',
    'HUB-TLEVEL',
    'TLevel',
    'Learner',
    'TLevel Learner',
    'hub.access.tlevel@local.invalid',
    true
  ),
  (
    '34000000-0000-4000-8000-000000000004',
    '14000000-0000-4000-8000-000000000004',
    'HUB-CYBER',
    'Cyber',
    'Learner',
    'Cyber Learner',
    'hub.access.cyber@local.invalid',
    true
  ),
  (
    '34000000-0000-4000-8000-000000000005',
    '14000000-0000-4000-8000-000000000005',
    'HUB-L2E',
    'L2E',
    'Learner',
    'L2E Learner',
    'hub.access.l2e@local.invalid',
    true
  ),
  (
    '34000000-0000-4000-8000-000000000006',
    '14000000-0000-4000-8000-000000000006',
    'HUB-DUAL',
    'Dual',
    'Learner',
    'Dual Learner',
    'hub.access.dual@local.invalid',
    true
  ),
  (
    '34000000-0000-4000-8000-000000000007',
    '14000000-0000-4000-8000-000000000007',
    'HUB-AUTO',
    'Auto',
    'Enrol',
    'Auto Enrol',
    'hub.access.auto@local.invalid',
    true
  ),
  (
    '34000000-0000-4000-8000-000000000008',
    '14000000-0000-4000-8000-000000000008',
    'HUB-INACTIVE',
    'Inactive',
    'Enrol',
    'Inactive Enrol',
    'hub.access.inactive@local.invalid',
    true
  ),
  (
    '34000000-0000-4000-8000-000000000009',
    '14000000-0000-4000-8000-000000000009',
    'HUB-UNIT14',
    'Unit14',
    'Learner',
    'Unit14 Learner',
    'hub.access.unit14@local.invalid',
    true
  ),
  (
    '34000000-0000-4000-8000-00000000000a',
    '14000000-0000-4000-8000-00000000000a',
    'HUB-CLOSED',
    'Closed',
    'Group',
    'Closed Group',
    'hub.access.closed@local.invalid',
    true
  ),
  (
    '34000000-0000-4000-8000-00000000000b',
    '14000000-0000-4000-8000-00000000000b',
    'HUB-INACTIVE-CYBER',
    'Inactive',
    'Cyber',
    'Inactive Cyber',
    'hub.access.inactive.cyber@local.invalid',
    true
  ),
  (
    '34000000-0000-4000-8000-00000000000c',
    '14000000-0000-4000-8000-00000000000c',
    'HUB-INACTIVE-CLOSED',
    'Inactive',
    'Closed',
    'Inactive Closed',
    'hub.access.inactive.closed@local.invalid',
    true
  );

insert into learning.courses (
  id, stable_key, code, title, qualification_level, active
)
select
  'c5000000-0000-4000-8000-0000000000e2'::uuid,
  'gateway-level-2-digital-it-skills',
  'GW-L2E',
  'Gateway Qualifications Level 2 Certificate in Digital and IT Skills',
  'Level 2',
  true
where not exists (
  select 1 from learning.courses where stable_key = 'gateway-level-2-digital-it-skills'
);

insert into platform.hub_course_links (hub_id, course_id, active)
select hub.id, course.id, true
from platform.hubs as hub
join learning.courses as course
  on course.stable_key = 'gateway-level-2-digital-it-skills'
where hub.hub_code = 'l2e-exploring-emerging-digital-technologies'
on conflict (hub_id, course_id) do update set active = true;

insert into learning.groups (
  id, academic_year_id, course_id, code, name, active, year_group,
  registration_key, registration_open, is_synthetic, synthetic_purpose
)
select
  '60000000-0000-4000-8000-0000000000a2'::uuid,
  academic_year.id,
  course.id,
  'L2E-DELIVERY-A',
  'L2E Gateway Delivery Group A',
  true,
  'Year 1',
  'l2e-year-1-delivery',
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
where course.stable_key = 'gateway-level-2-digital-it-skills'
  and not exists (
    select 1 from learning.groups where code = 'L2E-DELIVERY-A'
  );

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
select hub.id, learner_group.id, true, 'open_auto'
from platform.hubs as hub
join learning.groups as learner_group
  on learner_group.code = 'L2E-DELIVERY-A'
where hub.hub_code = 'l2e-exploring-emerging-digital-technologies'
on conflict (hub_id, group_id) do nothing;

insert into learning.groups (
  id, academic_year_id, course_id, code, name, active, year_group,
  registration_key, registration_open, is_synthetic, synthetic_purpose
)
select
  '60000000-0000-4000-8000-000000000011'::uuid,
  learner_group.academic_year_id,
  learner_group.course_id,
  'CYBER-TEST-QA',
  'Cyber Security Synthetic QA Group',
  true,
  learner_group.year_group,
  'cyber-year-1-qa',
  false,
  true,
  'formative-smoke-test'
from learning.groups as learner_group
where learner_group.code = 'CYBER-TEST-A'
  and not exists (
    select 1 from learning.groups where code = 'CYBER-TEST-QA'
  );

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
select hub.id, learner_group.id, true, 'closed'
from platform.hubs as hub
join learning.groups as learner_group
  on learner_group.code = 'CYBER-TEST-QA'
where hub.hub_code = 'unit-3-cyber-security'
on conflict (hub_id, group_id) do nothing;

-- Seed hubs are created after migrations. Re-assert the Phase 1 bindings here
-- so this test is self-contained on a freshly reset local database.
insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
select hub.id, learner_group.id, true, mapping.join_policy
from (
  values
    ('tlevel-software-development', 'TLEVEL-DSD-Y2', 'open_auto'),
    ('unit-3-cyber-security', 'CYBER-TEST-A', 'open_explicit'),
    ('unit-3-cyber-security', 'CYBER-TEST-QA', 'closed'),
    ('unit-14-software-engineering-for-business', 'UNIT14-TEST-A', 'closed')
) as mapping(hub_code, group_code, join_policy)
join platform.hubs as hub
  on hub.hub_code = mapping.hub_code
join learning.groups as learner_group
  on learner_group.code = mapping.group_code
on conflict (hub_id, group_id) do nothing;

insert into learning.enrolments (student_id, group_id, joined_on, status)
select
  '34000000-0000-4000-8000-000000000003',
  learner_group.id,
  current_date - 3,
  'active'
from learning.groups as learner_group
where learner_group.code = 'TLEVEL-DSD-Y2';

insert into learning.enrolments (student_id, group_id, joined_on, status)
select
  '34000000-0000-4000-8000-000000000004',
  learner_group.id,
  current_date - 3,
  'active'
from learning.groups as learner_group
where learner_group.code = 'CYBER-TEST-A';

insert into learning.enrolments (student_id, group_id, joined_on, status)
select
  '34000000-0000-4000-8000-000000000005',
  learner_group.id,
  current_date - 3,
  'active'
from learning.groups as learner_group
where learner_group.code = 'L2E-DELIVERY-A';

insert into learning.enrolments (student_id, group_id, joined_on, status)
select
  '34000000-0000-4000-8000-000000000006',
  learner_group.id,
  current_date - 3,
  'active'
from learning.groups as learner_group
where learner_group.code in ('TLEVEL-DSD-Y2', 'CYBER-TEST-A');

insert into learning.enrolments (student_id, group_id, joined_on, left_on, status)
select
  '34000000-0000-4000-8000-000000000008',
  learner_group.id,
  current_date - 10,
  current_date - 2,
  'withdrawn'
from learning.groups as learner_group
where learner_group.code = 'TLEVEL-DSD-Y2';

insert into learning.enrolments (student_id, group_id, joined_on, status)
select
  '34000000-0000-4000-8000-000000000009',
  learner_group.id,
  current_date - 3,
  'active'
from learning.groups as learner_group
where learner_group.code = 'UNIT14-TEST-A';

insert into learning.enrolments (student_id, group_id, joined_on, status)
select
  '34000000-0000-4000-8000-00000000000a',
  learner_group.id,
  current_date - 3,
  'active'
from learning.groups as learner_group
where learner_group.code = 'CYBER-TEST-QA';

insert into learning.enrolments (student_id, group_id, joined_on, left_on, status)
select
  '34000000-0000-4000-8000-00000000000b',
  learner_group.id,
  current_date - 10,
  current_date - 2,
  'withdrawn'
from learning.groups as learner_group
where learner_group.code = 'CYBER-TEST-A';

insert into learning.enrolments (student_id, group_id, joined_on, left_on, status)
select
  '34000000-0000-4000-8000-00000000000c',
  learner_group.id,
  current_date - 10,
  current_date - 2,
  'withdrawn'
from learning.groups as learner_group
where learner_group.code = 'UNIT14-TEST-A';

insert into learning.activity_assignments (
  group_id, activity_version_id, required, active
)
select
  learner_group.id,
  assignment.activity_version_id,
  true,
  true
from learning.groups as learner_group
join learning.groups as source
  on source.code = 'TEST-GROUP-A'
join learning.activity_assignments as assignment
  on assignment.group_id = source.id
 and assignment.active
join learning.activity_versions as activity_version
  on activity_version.id = assignment.activity_version_id
join learning.activities as activity
  on activity.id = activity_version.activity_id
where learner_group.code = 'TLEVEL-DSD-Y2'
  and activity.stable_key = 'foundations-requirements-classification'
on conflict (group_id, activity_version_id) do nothing;

select ok(
  exists (
    select 1
    from platform.hub_group_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.groups as learner_group on learner_group.id = link.group_id
    where hub.hub_code = 'tlevel-software-development'
      and learner_group.code = 'TLEVEL-DSD-Y2'
      and link.join_policy = 'open_auto'
      and link.active
  ),
  'T Level hub is bound only to TLEVEL-DSD-Y2'
);

select ok(
  exists (
    select 1
    from platform.hub_group_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.groups as learner_group on learner_group.id = link.group_id
    where hub.hub_code = 'unit-3-cyber-security'
      and learner_group.code = 'CYBER-TEST-A'
      and link.join_policy = 'open_explicit'
  ),
  'Unit 3 hub is bound to CYBER-TEST-A as open_explicit'
);

select ok(
  exists (
    select 1
    from platform.hub_group_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.groups as learner_group on learner_group.id = link.group_id
    where hub.hub_code = 'l2e-exploring-emerging-digital-technologies'
      and learner_group.code = 'L2E-DELIVERY-A'
      and link.join_policy = 'open_auto'
  ),
  'L2E hub is bound to L2E-DELIVERY-A'
);

select is(
  (
    select count(*)
    from platform.hub_group_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    where hub.hub_code = 'level-3-it-year-1-readiness'
  ),
  0::bigint,
  'Readiness has no delivery-group binding'
);

select lives_ok(
  $$
    insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
    select hub.id, learner_group.id, true, 'closed'
    from platform.hubs as hub
    join learning.groups as learner_group
      on learner_group.code = 'UNIT14-TEST-A'
    where hub.hub_code = 'unit-3-cyber-security'
  $$,
  'a course-year cohort may be linked to more than one hub'
);

select is(
  (
    select count(*)
    from pg_indexes
    where schemaname = 'platform'
      and tablename = 'hub_group_links'
      and indexname = 'hub_group_links_one_hub_per_group'
  ),
  0::bigint,
  'hub_group_links has no one-hub-per-group uniqueness constraint'
);

select is(
  (
    select proc.pronargs
    from pg_proc as proc
    join pg_namespace as nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'api'
      and proc.proname = 'resolve_learner_hub_access'
      and pg_get_function_identity_arguments(proc.oid) = 'p_hub_code text, p_course_key text'
  ),
  2::smallint,
  'resolver accepts only hub code and course key; no group UUID'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000009';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000009","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'enrolled',
  'explicit second-hub binding of the same cohort grants that hub access'
);

select is(
  (
    select group_code
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'UNIT14-TEST-A',
  'cross-hub authority comes from the requested hub binding, not one-group-one-hub'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-14-software-engineering-for-business',
      'ocr-level-3-it'
    )
  ),
  'enrolled',
  'the original Unit 14 binding remains after the same cohort is also bound to Cyber'
);
reset role;

delete from platform.hub_group_links as link
using platform.hubs as hub, learning.groups as learner_group
where link.hub_id = hub.id
  and link.group_id = learner_group.id
  and hub.hub_code = 'unit-3-cyber-security'
  and learner_group.code = 'UNIT14-TEST-A';

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000009';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000009","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'no_enrolment',
  'removing the Cyber binding removes Cyber authority from the Unit 14 cohort'
);
reset role;
reset "request.jwt.claim.sub";
reset "request.jwt.claims";

select throws_ok(
  $$
    insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
    select hub.id, learner_group.id, true, 'open_auto'
    from platform.hubs as hub
    join learning.groups as learner_group
      on learner_group.code = 'TEST-GROUP-A'
    where hub.hub_code = 'unit-3-cyber-security'
  $$,
  '23514',
  'HUB_GROUP_COURSE_NOT_LINKED',
  'a wrong-course group cannot be bound to a hub'
);

set local role anon;
select throws_like(
  $$select * from api.resolve_learner_hub_access(
    'tlevel-software-development',
    't-level-digital-software-development'
  )$$,
  '%permission denied%',
  'anonymous callers cannot resolve hub access'
);
select throws_like(
  $$select * from api.my_hub_assignments('tlevel-software-development')$$,
  '%permission denied%',
  'anonymous callers cannot read hub assignments'
);
reset role;

set local role authenticated;
select throws_ok(
  $$select * from api.resolve_learner_hub_access(
    'tlevel-software-development',
    't-level-digital-software-development'
  )$$,
  '28000',
  'AUTH_REQUIRED',
  'hub access requires a current Auth user'
);
reset role;

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'profile_required',
  '1. new Auth user with no learning.students profile is profile_required'
);

select is(
  (
    select registration_option
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'tlevel-dsd-y2',
  'profile_required returns the single T Level registration key, not a picker list'
);

select is(
  (select count(*) from api.my_hub_assignments('tlevel-software-development')),
  0::bigint,
  'no profile yields no hub assignments'
);
reset role;

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled_created',
  '2/7. profile with no enrolments and exactly one open_auto T Level group auto-enrols'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled',
  '12. existing T Level enrolment is idempotent on a second resolve'
);
reset role;

select is(
  (
    select count(*)
    from learning.enrolments
    where student_id = '34000000-0000-4000-8000-000000000002'
      and status = 'active'
  ),
  1::bigint,
  'auto-enrol creates one active T Level enrolment only'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled',
  '3. existing T Level enrolment is success with no write'
);

select is(
  (
    select group_code
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'TLEVEL-DSD-Y2',
  'T Level enrolled status returns the bound group code, not a UUID'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'no_enrolment',
  '6. T Level learner opening Cyber is not Cyber-ready'
);
reset role;

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000004';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000004","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled_created',
  '4. Cyber-enrolled learner with one T Level open_auto group is auto-enrolled into T Level'
);

select is(
  (
    select group_code
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'TLEVEL-DSD-Y2',
  'Cyber enrolment is not used as T Level group authority'
);

select ok(
  exists (
    select 1 from api.my_hub_assignments('tlevel-software-development')
    where activity_key = 'foundations-requirements-classification'
  )
  and not exists (
    select 1 from api.my_hub_assignments('tlevel-software-development')
    where activity_key = 'week2-malware-symptoms'
  ),
  'T Level hub assignments after Cyber auto-enrol exclude Cyber activities'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'enrolled',
  'Cyber-only learner remains enrolled for the Cyber hub after T Level auto-enrol'
);
reset role;

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.groups as learner_group
      on learner_group.id = enrolment.group_id
    where enrolment.student_id = '34000000-0000-4000-8000-000000000004'
      and enrolment.status = 'active'
      and learner_group.code = 'TLEVEL-DSD-Y2'
  ),
  1::bigint,
  'Cyber enrolment does not block a legitimate T Level open_auto enrolment'
);

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.groups as learner_group
      on learner_group.id = enrolment.group_id
    where enrolment.student_id = '34000000-0000-4000-8000-000000000004'
      and enrolment.status = 'active'
      and learner_group.code = 'CYBER-TEST-A'
  ),
  1::bigint,
  'T Level auto-enrol leaves the existing Cyber enrolment in place'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000005';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000005","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled_created',
  '5. L2E-enrolled learner with one T Level open_auto group is auto-enrolled into T Level'
);

select is(
  (
    select group_code
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'TLEVEL-DSD-Y2',
  'L2E enrolment is not used as T Level group authority'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'l2e-exploring-emerging-digital-technologies',
      'gateway-level-2-digital-it-skills'
    )
  ),
  'enrolled',
  'L2E-only learner remains enrolled on the L2E hub after T Level auto-enrol'
);
reset role;

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.groups as learner_group
      on learner_group.id = enrolment.group_id
    where enrolment.student_id = '34000000-0000-4000-8000-000000000005'
      and enrolment.status = 'active'
      and learner_group.code in ('L2E-DELIVERY-A', 'TLEVEL-DSD-Y2')
  ),
  2::bigint,
  'L2E enrolment does not block a legitimate T Level open_auto enrolment'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000009';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000009","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'no_enrolment',
  '14. same-course Unit 14 enrolment cannot satisfy the Cyber hub'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-14-software-engineering-for-business',
      'ocr-level-3-it'
    )
  ),
  'enrolled',
  'Unit 14 enrolment satisfies only the Unit 14 hub'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'level-3-it-year-1-readiness',
      'ocr-level-3-it'
    )
  ),
  'no_open_group',
  '15. Readiness does not inherit Unit 3 or Unit 14 authority from ocr-level-3-it'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled_created',
  '13. Unit 14 enrolment does not block T Level auto-enrol into the bound open_auto group'
);

select is(
  (
    select group_code
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'TLEVEL-DSD-Y2',
  'Unit 14 enrolment is not used as T Level group authority'
);
reset role;

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.groups as learner_group
      on learner_group.id = enrolment.group_id
    where enrolment.student_id = '34000000-0000-4000-8000-000000000009'
      and enrolment.status = 'active'
      and learner_group.code in ('UNIT14-TEST-A', 'TLEVEL-DSD-Y2')
  ),
  2::bigint,
  'Unit 14 enrolment remains after legitimate T Level auto-enrol'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-00000000000a';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-00000000000a","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'enrolled',
  'closed CYBER-TEST-QA still grants Cyber access when already enrolled'
);
reset role;

insert into learning.groups (
  id, academic_year_id, course_id, code, name, active, year_group,
  registration_key, registration_open
)
select
  '61000000-0000-4000-8000-0000000000aa',
  learner_group.academic_year_id,
  learner_group.course_id,
  'TLEVEL-AMBIG-B',
  'T Level ambiguous second group',
  true,
  'Year 2',
  'tlevel-ambig-b',
  true
from learning.groups as learner_group
where learner_group.code = 'TLEVEL-DSD-Y2';

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
select hub.id, '61000000-0000-4000-8000-0000000000aa', true, 'open_auto'
from platform.hubs as hub
where hub.hub_code = 'tlevel-software-development';

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000007';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000007","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'ambiguous',
  '8. multiple mapped open_auto groups are ambiguous and do not auto-enrol'
);

select is(
  (
    select registration_option
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  null,
  'ambiguous hub access does not return a learner-chosen group key'
);
reset role;

delete from platform.hub_group_links
where group_id = '61000000-0000-4000-8000-0000000000aa';

update learning.groups
set registration_open = false
where code = 'TLEVEL-DSD-Y2';

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000007';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000007","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'no_open_group',
  '10. a mapped but closed T Level group is no_open_group for a learner with no enrolment'
);
reset role;

update learning.groups
set registration_open = true
where code = 'TLEVEL-DSD-Y2';

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000007';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000007","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-14-software-engineering-for-business',
      'ocr-level-3-it'
    )
  ),
  'no_open_group',
  '9. Unit 14 closed binding does not auto-enrol through ocr-level-3-it'
);
reset role;

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000008';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000008","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'no_enrolment',
  'D. inactive T Level enrolment does not grant Cyber access'
);
reset role;

select is(
  (
    select enrolment.status
    from learning.enrolments as enrolment
    where enrolment.student_id = '34000000-0000-4000-8000-000000000008'
    order by enrolment.updated_at desc
    limit 1
  ),
  'withdrawn',
  'D. opening Cyber does not reactivate a withdrawn T Level enrolment'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000008';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000008","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled_reactivated',
  '11. inactive matching T Level enrolment is reactivated'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled',
  'reactivated enrolment is idempotent afterwards'
);
reset role;

select is(
  (
    select enrolment.status
    from learning.enrolments as enrolment
    where enrolment.student_id = '34000000-0000-4000-8000-000000000008'
    order by enrolment.updated_at desc
    limit 1
  ),
  'active',
  'A. inactive T Level open_auto enrolment is restored to active'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-00000000000b';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-00000000000b","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'no_enrolment',
  'B. inactive Cyber open_explicit enrolment is not reactivated by opening the hub'
);

select is(
  (
    select registration_option
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'cyber-year-1-test',
  'inactive Cyber learner still receives the JoinClass registration key'
);
reset role;

select is(
  (
    select enrolment.status
    from learning.enrolments as enrolment
    where enrolment.student_id = '34000000-0000-4000-8000-00000000000b'
      and enrolment.group_id = (
        select id from learning.groups where code = 'CYBER-TEST-A'
      )
  ),
  'withdrawn',
  'B. opening Cyber does not bypass JoinClass by restoring a withdrawn enrolment'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-00000000000b';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-00000000000b","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled_created',
  'D. inactive Cyber enrolment is not T Level authority and does not block T Level open_auto'
);
reset role;

select is(
  (
    select enrolment.status
    from learning.enrolments as enrolment
    where enrolment.student_id = '34000000-0000-4000-8000-00000000000b'
      and enrolment.group_id = (
        select id from learning.groups where code = 'CYBER-TEST-A'
      )
  ),
  'withdrawn',
  'D. T Level auto-enrol leaves the withdrawn Cyber enrolment unchanged'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-00000000000c';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-00000000000c","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-14-software-engineering-for-business',
      'ocr-level-3-it'
    )
  ),
  'no_open_group',
  'C. inactive closed Unit 14 enrolment is not reactivated by opening the hub'
);
reset role;

select is(
  (
    select enrolment.status
    from learning.enrolments as enrolment
    where enrolment.student_id = '34000000-0000-4000-8000-00000000000c'
      and enrolment.group_id = (
        select id from learning.groups where code = 'UNIT14-TEST-A'
      )
  ),
  'withdrawn',
  'C. closed bindings stay withdrawn until staff restore them'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled',
  'E. an already-active T Level enrolment remains idempotent'
);
reset role;

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000006';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000006","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*)
    from learning.students
    where auth_user_id = '14000000-0000-4000-8000-000000000006'
  ),
  1::bigint,
  'dual-hub learner has one learning.students identity'
);

select ok(
  (
    select count(*) = 2
    from api.my_enrolments
    where status = 'active'
      and group_code in ('TLEVEL-DSD-Y2', 'CYBER-TEST-A')
  ),
  'dual-hub learner has independent Cyber and T Level enrolments'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'enrolled',
  'dual-hub learner T Level resolver returns T Level enrolled status only'
);

select is(
  (
    select group_code
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'TLEVEL-DSD-Y2',
  'dual-hub learner T Level context is TLEVEL-DSD-Y2'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'enrolled',
  'dual-hub learner Cyber resolver returns Cyber enrolled status only'
);

select is(
  (
    select group_code
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'CYBER-TEST-A',
  'dual-hub learner Cyber context is CYBER-TEST-A'
);

select ok(
  exists (
    select 1 from api.my_hub_assignments('tlevel-software-development')
    where activity_key = 'foundations-requirements-classification'
  )
  and not exists (
    select 1 from api.my_hub_assignments('tlevel-software-development')
    where activity_key = 'week2-malware-symptoms'
  ),
  '16. T Level hub assignments exclude Cyber activities'
);

select ok(
  exists (
    select 1 from api.my_hub_assignments('unit-3-cyber-security')
    where activity_key = 'week2-malware-symptoms'
  )
  and not exists (
    select 1 from api.my_hub_assignments('unit-3-cyber-security')
    where activity_key = 'foundations-requirements-classification'
  ),
  '16. Cyber hub assignments exclude T Level activities'
);

select ok(
  exists (
    select 1 from api.my_assignments
    where activity_key = 'foundations-requirements-classification'
  )
  and exists (
    select 1 from api.my_assignments
    where activity_key = 'week2-malware-symptoms'
  ),
  '17. api.my_assignments remains the unscoped union of active enrolments'
);

select lives_ok(
  $$select * from api.submit_attempt(
    'foundations-requirements-classification',
    '1.0.0',
    'hub-dual-tlevel-1',
    (
      select jsonb_agg(
        jsonb_build_object(
          'question_id', question.stable_key,
          'response_payload', to_jsonb('synthetic-response'::text),
          'awarded_score', 0,
          'is_correct', false
        )
        order by question.ordinal
      )
      from learning.questions as question
      where question.activity_version_id = '91000000-0000-4000-8000-000000000001'
    ),
    '/foundations/requirements-classification/',
    null,
    null,
    null
  )$$,
  '19. dual-enrolled learner can still submit the T Level assignment'
);

select lives_ok(
  $$select * from api.mark_formative_response(
    'week2-malware-symptoms',
    (
      select activity_version.version
      from learning.activities as activity
      join learning.activity_versions as activity_version
        on activity_version.activity_id = activity.id
      where activity.stable_key = 'week2-malware-symptoms'
        and activity_version.published_at is not null
        and activity_version.retired_at is null
      order by activity_version.published_at desc
      limit 1
    ),
    jsonb_build_array(
      jsonb_build_object(
        'question_id', (
          select question.stable_key
          from learning.questions as question
          join learning.activity_versions as activity_version
            on activity_version.id = question.activity_version_id
          join learning.activities as activity
            on activity.id = activity_version.activity_id
          where activity.stable_key = 'week2-malware-symptoms'
          order by question.ordinal
          limit 1
        ),
        'response_payload', jsonb_build_object('optionId', 'wrong')
      )
    ),
    'hub-dual-cyber-formative'
  )$$,
  '18. dual-enrolled learner can still mark a Cyber formative activity'
);

select throws_ok(
  $$select * from api.resolve_learner_hub_access(
    'unit-3-cyber-security',
    't-level-digital-software-development'
  )$$,
  '22023',
  'HUB_COURSE_NOT_LINKED',
  'hub code and course key must match a registered hub course link'
);
reset role;

select is(
  (
    select count(*)
    from learning.attempts
    where client_attempt_id = 'hub-dual-tlevel-1'
  ),
  1::bigint,
  'T Level submit_attempt stored exactly one historical attempt row'
);

select is(
  (
    select learner_group.code
    from learning.attempts as attempt
    join learning.enrolments as enrolment
      on enrolment.id = attempt.enrolment_id
    join learning.groups as learner_group
      on learner_group.id = enrolment.group_id
    where attempt.client_attempt_id = 'hub-dual-tlevel-1'
  ),
  'TLEVEL-DSD-Y2',
  'T Level write is stored against the T Level enrolment, not Cyber'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'api'
      and table_name = 'my_assignments'
      and column_name = 'assignment_id'
  ),
  '20. api.my_assignments remains unchanged as the unscoped compatibility view'
);

select ok(
  exists (
    select 1
    from pg_proc as proc
    join pg_namespace as nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'api'
      and proc.proname = 'complete_learner_onboarding'
  )
  and exists (
    select 1
    from pg_proc as proc
    join pg_namespace as nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'api'
      and proc.proname = 'registration_options'
  ),
  'complete_learner_onboarding and registration_options remain'
);

select is(
  (
    select attempt.score
    from learning.attempts as attempt
    where attempt.client_attempt_id = 'phase-2-demo-attempt'
  ),
  8::numeric,
  '20. historical seed attempt row is unchanged'
);

select is(
  (
    select learner_group.code
    from learning.enrolments as enrolment
    join learning.groups as learner_group
      on learner_group.id = enrolment.group_id
    join platform.hub_group_links as link
      on link.group_id = enrolment.group_id
     and link.active
    join platform.hubs as hub
      on hub.id = link.hub_id
    where enrolment.student_id = '34000000-0000-4000-8000-000000000006'
      and enrolment.status = 'active'
      and hub.hub_code = 'tlevel-software-development'
  ),
  'TLEVEL-DSD-Y2',
  'dual learner T Level access is authorised by TLEVEL-DSD-Y2 hub_group_links'
);

select is(
  (
    select learner_group.code
    from learning.enrolments as enrolment
    join learning.groups as learner_group
      on learner_group.id = enrolment.group_id
    join platform.hub_group_links as link
      on link.group_id = enrolment.group_id
     and link.active
    join platform.hubs as hub
      on hub.id = link.hub_id
    where enrolment.student_id = '34000000-0000-4000-8000-000000000006'
      and enrolment.status = 'active'
      and hub.hub_code = 'unit-3-cyber-security'
  ),
  'CYBER-TEST-A',
  'dual learner Cyber access is authorised by CYBER-TEST-A hub_group_links'
);

select ok(
  (
    select prosecdef
    from pg_proc as proc
    join pg_namespace as nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'api'
      and proc.proname = 'resolve_learner_hub_access'
  ),
  'resolver is SECURITY DEFINER'
);

select ok(
  exists (
    select 1
    from pg_proc as proc
    join pg_namespace as nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'api'
      and proc.proname = 'resolve_learner_hub_access'
      and array_to_string(proc.proconfig, ',') like '%search_path%'
  ),
  'resolver pins search_path'
);

select is(
  has_function_privilege('anon', 'api.resolve_learner_hub_access(text, text)', 'execute'),
  false,
  'anon cannot execute resolve_learner_hub_access'
);

select is(
  has_function_privilege('authenticated', 'api.resolve_learner_hub_access(text, text)', 'execute'),
  true,
  'authenticated can execute resolve_learner_hub_access'
);

set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000006';
set local "request.jwt.claims" = '{"sub":"14000000-0000-4000-8000-000000000006","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from platform.hub_group_links),
  0::bigint,
  'learner RLS cannot read hub_group_links rows'
);
reset role;

select finish();
rollback;
