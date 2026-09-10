begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
select hub.id, learner_group.id, true, mapping.join_policy
from (
  values
    ('tlevel-software-development', 'TLEVEL-DSD-Y2', 'open_explicit'),
    ('l2e-exploring-emerging-digital-technologies', 'L2E-DELIVERY-A', 'open_explicit'),
    ('unit-3-cyber-security', 'CYBER-TEST-A', 'open_explicit'),
    ('unit-3-cyber-security', 'CYBER-TEST-QA', 'closed'),
    ('unit-14-software-engineering-for-business', 'UNIT14-TEST-A', 'closed')
) as mapping(hub_code, group_code, join_policy)
join platform.hubs as hub
  on hub.hub_code = mapping.hub_code
join learning.groups as learner_group
  on learner_group.code = mapping.group_code
on conflict (hub_id, group_id) do update
set join_policy = excluded.join_policy,
    active = excluded.active;

-- Ensure the seeded delivery groups match the explicit-class-keys migration.
update learning.groups set registration_key = 'nhc-cyber-26' where code = 'CYBER-TEST-A';
update learning.groups set registration_key = 'nhc-tlevel-26' where code = 'TLEVEL-DSD-Y2';

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
  'nhc-et-26',
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
select hub.id, learner_group.id, true, 'open_explicit'
from platform.hubs as hub
join learning.groups as learner_group
  on learner_group.code = 'L2E-DELIVERY-A'
where hub.hub_code = 'l2e-exploring-emerging-digital-technologies'
on conflict (hub_id, group_id) do update set join_policy = excluded.join_policy;

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

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
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
    ('15000000-0000-4000-8000-000000000001'::uuid, 'hub.bound.tlevel@local.invalid', 'bound-tlevel'),
    ('15000000-0000-4000-8000-000000000002'::uuid, 'hub.bound.cyber@local.invalid', 'bound-cyber'),
    ('15000000-0000-4000-8000-000000000003'::uuid, 'hub.bound.l2e@local.invalid', 'bound-l2e'),
    ('15000000-0000-4000-8000-000000000004'::uuid, 'hub.bound.dual@local.invalid', 'bound-dual'),
    ('15000000-0000-4000-8000-000000000005'::uuid, 'hub.bound.reload@local.invalid', 'bound-reload')
) as fixture(id, email, fixture);

set local role anon;
select throws_like(
  $$select * from api.join_learner_hub_group('unit-3-cyber-security', 'nhc-cyber-26')$$,
  '%permission denied%',
  'anonymous callers cannot join a class'
);
reset role;

-- 1. New T Level learner: profile only, then JoinClass with the T Level class key.
set local "request.jwt.claim.sub" = '15000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from api.registration_options()),
  0::bigint,
  '1. learners are not given a group/year picker'
);

select is(
  (
    select group_code
    from api.complete_learner_onboarding('New', 'TLevel', 'BOUND-TLEVEL', 'nhc-cyber-26')
  ),
  null,
  '1. complete_learner_onboarding ignores a Cyber class key'
);

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    where student.auth_user_id = '15000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  '1. profile completion does not enrol the learner'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'no_enrolment',
  '1. T Level resolver does not auto-enrol under open_explicit'
);

select is(
  (
    select registration_option
    from api.resolve_learner_hub_access(
      'tlevel-software-development',
      't-level-digital-software-development'
    )
  ),
  'nhc-tlevel-26',
  '1. T Level resolver surfaces the nhc-tlevel-26 JoinClass key'
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
  '1. T Level resolver still identifies TLEVEL-DSD-Y2 as the bound delivery group'
);

select is(
  (
    select group_code
    from api.join_learner_hub_group(
      'tlevel-software-development',
      'nhc-tlevel-26'
    )
  ),
  'TLEVEL-DSD-Y2',
  '1. T Level JoinClass with nhc-tlevel-26 enrols into TLEVEL-DSD-Y2'
);

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    where student.auth_user_id = '15000000-0000-4000-8000-000000000001'
      and enrolment.status = 'active'
  ),
  1::bigint,
  '1. T Level learner has exactly one active enrolment after JoinClass'
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
  '1. T Level assignments exclude Cyber activities'
);

-- 2. Same T Level learner opening Cyber is denied automatic access.
select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'unit-3-cyber-security',
      'ocr-level-3-it'
    )
  ),
  'no_enrolment',
  '2. opening Cyber does not auto-enrol a T Level learner'
);

select is(
  (select count(*) from api.my_hub_assignments('unit-3-cyber-security')),
  0::bigint,
  '2. T Level learner receives no Cyber assignments'
);

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    join learning.groups as learner_group on learner_group.id = enrolment.group_id
    where student.auth_user_id = '15000000-0000-4000-8000-000000000001'
      and learner_group.code = 'CYBER-TEST-A'
  ),
  0::bigint,
  '2. no Cyber enrolment is created'
);

-- 6. Manipulated complete/join requests cannot claim another hub's group.
select throws_ok(
  $$select * from api.join_learner_hub_group(
    'unit-3-cyber-security',
    'nhc-tlevel-26'
  )$$,
  '22023',
  'INVALID_CLASS_KEY',
  '6. Cyber join rejects the T Level registration key'
);

select throws_ok(
  $$select * from api.join_learner_hub_group(
    'tlevel-software-development',
    'nhc-cyber-26'
  )$$,
  '22023',
  'INVALID_CLASS_KEY',
  '6. T Level join rejects the Cyber class key'
);

select throws_ok(
  $$select * from api.join_learner_hub_group(
    'unit-3-cyber-security',
    'unit14-year-1-test'
  )$$,
  '22023',
  'INVALID_CLASS_KEY',
  '6. Cyber join rejects the Unit 14 class key'
);

select is(
  (
    select count(*)
    from learning.students
    where auth_user_id = '15000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  '5/7. T Level learner still has one identity after denied Cyber access'
);
reset role;

-- 3. Cyber controlled join.
set local "request.jwt.claim.sub" = '15000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"15000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$select * from api.complete_learner_onboarding(
    'New', 'Cyber', 'BOUND-CYBER', 'nhc-tlevel-26'
  )$$,
  '3. Cyber profile can complete without a group picker'
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
  '3. opening Cyber does not auto-enrol'
);

select throws_ok(
  $$select * from api.join_learner_hub_group(
    'unit-3-cyber-security',
    'nhc-tlevel-26'
  )$$,
  '22023',
  'INVALID_CLASS_KEY',
  '3. arbitrary T Level key cannot join Cyber'
);

select throws_ok(
  $$select * from api.join_learner_hub_group(
    'unit-3-cyber-security',
    'cyber-test-qa'
  )$$,
  '22023',
  'INVALID_CLASS_KEY',
  '3. closed Cyber QA group cannot be joined with a guessed key'
);

select is(
  (
    select group_code
    from api.join_learner_hub_group(
      'unit-3-cyber-security',
      'nhc-cyber-26'
    )
  ),
  'CYBER-TEST-A',
  '3. authorised Cyber class key joins CYBER-TEST-A'
);

select is(
  (
    select idempotent
    from api.join_learner_hub_group(
      'unit-3-cyber-security',
      'nhc-cyber-26'
    )
  ),
  true,
  '3. repeating the authorised Cyber join is idempotent'
);

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    where student.auth_user_id = '15000000-0000-4000-8000-000000000002'
      and enrolment.status = 'active'
  ),
  1::bigint,
  '3. Cyber join creates one active enrolment only'
);

-- 9. Assigned Cyber learner can still Check answers and submit.
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
    'hub-bound-cyber-formative'
  )$$,
  '9. enrolled Cyber learner can still Check a formative answer'
);

select ok(
  exists (
    select 1
    from api.mark_formative_response(
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
      'hub-bound-cyber-formative-2'
    )
    where is_correct is not null
  ),
  '9. formative Check still returns Correct/Incorrect feedback'
);

select lives_ok(
  $$select * from api.submit_attempt(
    'week2-malware-symptoms',
    '1.0.0',
    'hub-bound-cyber-attempt-1',
    (
      select jsonb_agg(
        jsonb_build_object(
          'question_id', question.stable_key,
          'response_payload', to_jsonb('synthetic-response'::text)
        )
        order by question.ordinal
      )
      from learning.questions as question
      join learning.activity_versions as activity_version
        on activity_version.id = question.activity_version_id
      join learning.activities as activity
        on activity.id = activity_version.activity_id
      where activity.stable_key = 'week2-malware-symptoms'
        and activity_version.version = '1.0.0'
    ),
    '/week-2/malware-symptoms/',
    null,
    null,
    null
  )$$,
  '9. enrolled Cyber learner can still submit an attempt'
);
reset role;

-- 4. L2E open_explicit: resolver surfaces the class key, JoinClass enrols.
set local "request.jwt.claim.sub" = '15000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"15000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$select * from api.complete_learner_onboarding(
    'New', 'L2E', 'BOUND-L2E', null
  )$$,
  '4. L2E profile completion does not require a group choice'
);

select is(
  (
    select status
    from api.resolve_learner_hub_access(
      'l2e-exploring-emerging-digital-technologies',
      'gateway-level-2-digital-it-skills'
    )
  ),
  'no_enrolment',
  '4. L2E resolver does not auto-enrol under open_explicit'
);

select is(
  (
    select registration_option
    from api.resolve_learner_hub_access(
      'l2e-exploring-emerging-digital-technologies',
      'gateway-level-2-digital-it-skills'
    )
  ),
  'nhc-et-26',
  '4. L2E resolver surfaces the nhc-et-26 JoinClass key'
);

select is(
  (
    select group_code
    from api.resolve_learner_hub_access(
      'l2e-exploring-emerging-digital-technologies',
      'gateway-level-2-digital-it-skills'
    )
  ),
  'L2E-DELIVERY-A',
  '4. L2E resolver still identifies L2E-DELIVERY-A as the bound delivery group'
);

select is(
  (
    select group_code
    from api.join_learner_hub_group(
      'l2e-exploring-emerging-digital-technologies',
      'nhc-et-26'
    )
  ),
  'L2E-DELIVERY-A',
  '4. L2E JoinClass with nhc-et-26 enrols into L2E-DELIVERY-A'
);
reset role;

-- 5. Multi-hub learner: one identity, isolated assignments.
set local "request.jwt.claim.sub" = '15000000-0000-4000-8000-000000000004';
set local "request.jwt.claims" = '{"sub":"15000000-0000-4000-8000-000000000004","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$select * from api.complete_learner_onboarding(
    'Dual', 'Learner', 'BOUND-DUAL', 'ignored'
  )$$,
  '5. dual-hub profile is created once'
);

select is(
  (
    select group_code
    from api.join_learner_hub_group(
      'tlevel-software-development',
      'nhc-tlevel-26'
    )
  ),
  'TLEVEL-DSD-Y2',
  '5. dual learner joins T Level with the T Level class key'
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
  '5. dual learner is enrolled on T Level after JoinClass'
);

select is(
  (
    select group_code
    from api.join_learner_hub_group(
      'unit-3-cyber-security',
      'nhc-cyber-26'
    )
  ),
  'CYBER-TEST-A',
  '5. dual learner can later join Cyber with the class key'
);

select is(
  (
    select count(*)
    from learning.students
    where auth_user_id = '15000000-0000-4000-8000-000000000004'
  ),
  1::bigint,
  '5. dual-hub learner has one learning.students identity'
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
  '5. T Level assignments stay T Level-scoped'
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
  '5. Cyber assignments stay Cyber-scoped'
);

select throws_ok(
  $$select * from api.join_learner_hub_group(
    'unit-14-software-engineering-for-business',
    'unit14-year-1-test'
  )$$,
  '22023',
  'INVALID_CLASS_KEY',
  '6. closed Unit 14 cannot be joined with its class key'
);
reset role;

-- 7. Reload does not duplicate learner or enrolment.
set local "request.jwt.claim.sub" = '15000000-0000-4000-8000-000000000005';
set local "request.jwt.claims" = '{"sub":"15000000-0000-4000-8000-000000000005","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$select * from api.complete_learner_onboarding(
    'Reload', 'Learner', 'BOUND-RELOAD', ''
  )$$,
  '7. first profile completion succeeds'
);

select is(
  (
    select idempotent
    from api.complete_learner_onboarding(
      'Reload', 'Learner', 'BOUND-RELOAD', 'nhc-tlevel-26'
    )
  ),
  true,
  '7. reload profile completion is idempotent'
);

select is(
  (
    select status
    from api.join_learner_hub_group(
      'tlevel-software-development',
      'nhc-tlevel-26'
    )
  ),
  'enrolled_created',
  '7. first T Level JoinClass enrols once'
);

select is(
  (
    select status
    from api.join_learner_hub_group(
      'tlevel-software-development',
      'nhc-tlevel-26'
    )
  ),
  'enrolled',
  '7. repeated T Level JoinClass is idempotent'
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
  '7. reload resolve is idempotent for an enrolled learner'
);

select is(
  (
    select count(*)
    from learning.students
    where auth_user_id = '15000000-0000-4000-8000-000000000005'
  ),
  1::bigint,
  '7. reload does not duplicate the learner'
);

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    where student.auth_user_id = '15000000-0000-4000-8000-000000000005'
  ),
  1::bigint,
  '7. reload does not duplicate the enrolment'
);
reset role;

select ok(
  exists (
    select 1
    from pg_proc as proc
    join pg_namespace as nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'api'
      and proc.proname = 'join_learner_hub_group'
      and proc.prosecdef
  ),
  'join_learner_hub_group is SECURITY DEFINER'
);

select finish();
rollback;
