begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

create function pg_temp.hub_manifest(
  p_hub_id text default 'synthetic-admin-registered-hub',
  p_manifest_version text default '1.0.0',
  p_core_version text default '0.1.0',
  p_learner_api_version text default '0.1.0',
  p_submission_version text default '0.1.0',
  p_repository text default 'https://example.invalid/synthetic-admin-registered-hub',
  p_deployment text default 'https://synthetic-admin-registered-hub.example.invalid',
  p_courses jsonb default '["ocr-level-3-it"]'::jsonb
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'manifestVersion', p_manifest_version,
    'hubId', p_hub_id,
    'name', 'Synthetic Admin Registered Hub',
    'description', 'Synthetic hub used to prove administrative registration.',
    'version', '0.1.0',
    'repositoryUrl', p_repository,
    'deploymentUrl', p_deployment,
    'courses', p_courses,
    'compatibility', jsonb_build_object(
      'required', jsonb_build_object(
        'coreVersion', p_core_version,
        'learnerApiContractVersion', p_learner_api_version,
        'submissionContractVersion', p_submission_version
      ),
      'testedCombinations', jsonb_build_array(
        jsonb_build_object(
          'coreVersion', p_core_version,
          'learnerApiContractVersion', p_learner_api_version,
          'submissionContractVersion', p_submission_version
        )
      )
    ),
    'capabilities', jsonb_build_object(
      'evidence', jsonb_build_array('question-level'),
      'activities', jsonb_build_array('classification', 'diagnostic')
    ),
    'featureFlags', jsonb_build_object(
      'authentication', true,
      'onboarding', true,
      'progress', true
    )
  )
$$;

select has_function(
  'admin_api',
  'register_hub',
  array['jsonb', 'text', 'boolean'],
  'staff API exposes the hub registration RPC'
);

select has_function(
  'platform',
  'register_hub',
  array['jsonb', 'text', 'boolean'],
  'protected hub registration mutation exists'
);

select throws_ok(
  $$select platform.validate_hub_manifest('{"hubId":"incomplete"}'::jsonb)$$,
  '22023',
  'HUB_MANIFEST_INVALID',
  'server-side validation rejects an incomplete manifest'
);

select lives_ok(
  $$select platform.validate_hub_manifest(pg_temp.hub_manifest())$$,
  'a complete LHDS manifest passes server-side validation'
);

set local role anon;
select throws_like(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'planned', false)$sql$,
    pg_temp.hub_manifest()::text
  ),
  '%permission denied%',
  'anonymous clients cannot register hubs'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'planned', false)$sql$,
    pg_temp.hub_manifest()::text
  ),
  '28000',
  'HUB_REGISTRATION_NOT_AUTHORISED',
  'a learner cannot register a hub'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'planned', false)$sql$,
    pg_temp.hub_manifest()::text
  ),
  '28000',
  'HUB_REGISTRATION_NOT_AUTHORISED',
  'an ordinary teacher cannot register a hub'
);
reset role;

insert into platform.staff_roles (
  id,
  teacher_id,
  role,
  granted_at
) values (
  '32000000-0000-4000-8000-000000000101',
  '31000000-0000-4000-8000-000000000001',
  'curriculum_admin',
  clock_timestamp()
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'planned', false)$sql$,
    pg_temp.hub_manifest()::text
  ),
  '28000',
  'HUB_REGISTRATION_NOT_AUTHORISED',
  'curriculum_admin cannot register a hub'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'draft', false)$sql$,
    pg_temp.hub_manifest()::text
  ),
  '22023',
  'HUB_STATUS_INVALID',
  'unsupported lifecycle values are rejected'
);

select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'planned', true)$sql$,
    pg_temp.hub_manifest()::text
  ),
  '22023',
  'HUB_ACTIVE_STATUS_INVALID',
  'planned hubs cannot be registered as active'
);

select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest(
      p_manifest_version := '9.9.9'
    )::text
  ),
  '22023',
  'HUB_MANIFEST_VERSION_UNSUPPORTED',
  'unsupported manifest contract versions are rejected'
);

select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest(
      p_core_version := '9.9.9'
    )::text
  ),
  '22023',
  'HUB_CORE_VERSION_UNSUPPORTED',
  'unsupported core versions are rejected'
);

select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest(
      p_learner_api_version := '9.9.9'
    )::text
  ),
  '22023',
  'HUB_LEARNER_API_VERSION_UNSUPPORTED',
  'unsupported learner API versions are rejected'
);

select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest(
      p_submission_version := '9.9.9'
    )::text
  ),
  '22023',
  'HUB_SUBMISSION_VERSION_UNSUPPORTED',
  'unsupported submission versions are rejected'
);

select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest(
      p_repository := 'http://example.invalid/synthetic-admin-registered-hub'
    )::text
  ),
  '22023',
  'HUB_INVALID_URL',
  'non-HTTPS repository URLs are rejected'
);

select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest(
      p_courses := '["missing-course-key"]'::jsonb
    )::text
  ),
  '22023',
  'HUB_COURSE_NOT_FOUND',
  'unknown course associations are rejected'
);

select is(
  (
    select count(*)
    from platform.hubs
    where hub_code = 'synthetic-admin-registered-hub'
  ),
  0::bigint,
  'a failed registration does not leave a hub row'
);

select is(
  (
    select hub_code
    from admin_api.register_hub(
      pg_temp.hub_manifest(),
      'testing',
      true
    )
  ),
  'synthetic-admin-registered-hub',
  'an authorised platform administrator can register a synthetic hub'
);

select is(
  (
    select status
    from platform.hubs
    where hub_code = 'synthetic-admin-registered-hub'
  ),
  'testing',
  'registration stores the requested lifecycle status'
);

select is(
  (
    select count(*)
    from platform.hub_course_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.courses as course on course.id = link.course_id
    where hub.hub_code = 'synthetic-admin-registered-hub'
      and course.stable_key = 'ocr-level-3-it'
      and link.active
  ),
  1::bigint,
  'registration creates the declared course link in the same transaction'
);

select is(
  (
    select event_key
    from platform.audit_events
    where entity_type = 'hub'
      and entity_key = 'synthetic-admin-registered-hub'
      and event_key = 'hub.registration.registered'
    order by occurred_at desc
    limit 1
  ),
  'hub.registration.registered',
  'successful registration writes a minimised audit event'
);

select ok(
  (
    select context ? 'hubCode'
       and context ? 'registeredBy'
       and not context ? 'email'
    from platform.audit_events
    where entity_key = 'synthetic-admin-registered-hub'
      and event_key = 'hub.registration.registered'
    order by occurred_at desc
    limit 1
  ),
  'audit context stores hub code and staff reference without email'
);

select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest()::text
  ),
  '23505',
  'HUB_DUPLICATE_CODE',
  'duplicate hub codes are rejected without overwrite'
);

select throws_ok(
  format(
    $sql$select * from admin_api.register_hub(%L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest(
      p_hub_id := 'synthetic-admin-duplicate-repo',
      p_deployment := 'https://synthetic-admin-duplicate-repo.example.invalid'
    )::text
  ),
  '23505',
  'HUB_DUPLICATE_REPOSITORY',
  'duplicate repository URLs are rejected'
);

select throws_ok(
  $$select * from admin_api.register_hub(
    '{"hubId":"unit-14-software-engineering-for-business"}'::jsonb,
    'testing',
    true
  )$$,
  '22023',
  'HUB_MANIFEST_INVALID',
  'an incomplete Unit 14 payload cannot overwrite the reviewed registration'
);

select is(
  (
    select count(*)
    from platform.hubs
    where hub_code = 'unit-14-software-engineering-for-business'
  ),
  1::bigint,
  'the reviewed Unit 14 registration remains a single row'
);

select throws_like(
  $$insert into platform.hubs (
    hub_code, hub_name, description, hub_version, platform_version,
    manifest_version, core_version, learner_api_version,
    submission_contract_version, repository_url, activity_types,
    evidence_capabilities, features, compatibility, status, active,
    manifest, manifest_sha256
  ) values (
    'direct-write-hub', 'Direct write hub', 'Denied.',
    '0.1.0', '0.1.0', '1.0.0', '0.1.0', '0.1.0', '0.1.0',
    'https://example.invalid/direct-write-hub', array['quiz'],
    array['question-level'], '{}'::jsonb, '{}'::jsonb, 'planned', false,
    '{}'::jsonb, repeat('a', 64)
  )$$,
  '%violates row-level security policy%',
  'authenticated staff cannot insert into platform.hubs directly'
);

reset role;

select * from finish();
rollback;
