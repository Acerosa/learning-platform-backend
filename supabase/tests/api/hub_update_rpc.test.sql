begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

create function pg_temp.hub_manifest(
  p_hub_id text default 'synthetic-admin-updated-hub',
  p_name text default 'Synthetic Admin Updated Hub',
  p_manifest_version text default '1.0.0',
  p_core_version text default '0.1.0',
  p_learner_api_version text default '0.1.0',
  p_submission_version text default '0.1.0',
  p_repository text default 'https://example.invalid/synthetic-admin-updated-hub',
  p_deployment text default 'https://synthetic-admin-updated-hub.example.invalid',
  p_courses jsonb default '["ocr-level-3-it"]'::jsonb
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'manifestVersion', p_manifest_version,
    'hubId', p_hub_id,
    'name', p_name,
    'description', 'Synthetic hub used to prove administrative updates.',
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
  'update_hub',
  array['text', 'jsonb', 'text', 'boolean'],
  'staff API exposes the hub update RPC'
);

select has_view(
  'admin_api',
  'courses',
  'staff API exposes the course catalogue for hub validation'
);

insert into learning.courses (
  id,
  stable_key,
  code,
  title,
  qualification_level,
  active
) values (
  '42000000-0000-4000-8000-000000000201',
  'inactive-admin-course',
  'INACTIVE',
  'Inactive Admin Course',
  '3',
  false
);

set local role anon;
select throws_like(
  format(
    $sql$select * from admin_api.update_hub('synthetic-admin-updated-hub', %L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest()::text
  ),
  '%permission denied%',
  'anonymous clients cannot update hubs'
);
select throws_like(
  $$select count(*) from admin_api.courses$$,
  '%permission denied%',
  'anonymous clients cannot read the staff course catalogue'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  format(
    $sql$select * from admin_api.update_hub('synthetic-admin-updated-hub', %L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest()::text
  ),
  '28000',
  'HUB_REGISTRATION_NOT_AUTHORISED',
  'a learner cannot update a hub'
);
select is(
  (select count(*) from admin_api.courses),
  0::bigint,
  'a learner cannot read the staff course catalogue'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  format(
    $sql$select * from admin_api.update_hub('synthetic-admin-updated-hub', %L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest()::text
  ),
  '28000',
  'HUB_REGISTRATION_NOT_AUTHORISED',
  'an ordinary teacher cannot update a hub'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  format(
    $sql$select * from admin_api.update_hub('missing-admin-hub', %L::jsonb, 'testing', true)$sql$,
    pg_temp.hub_manifest(p_hub_id := 'missing-admin-hub')::text
  ),
  'P0002',
  'HUB_NOT_FOUND',
  'updates require an existing hub registration'
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
  'synthetic-admin-updated-hub',
  'an authorised platform administrator can register a hub before updating it'
);

select ok(
  exists (
    select 1 from admin_api.courses
    where course_key = 'ocr-level-3-it'
      and active
  ),
  'a platform administrator can read active courses for hub validation'
);

select is(
  (
    select count(*) from admin_api.courses
    where course_key = 'inactive-admin-course'
      and not active
  ),
  1::bigint,
  'the course catalogue includes inactive courses without exposing learning.courses'
);

select throws_ok(
  format(
    $sql$select * from admin_api.update_hub(
      'synthetic-admin-updated-hub',
      %L::jsonb,
      'testing',
      true
    )$sql$,
    pg_temp.hub_manifest(p_hub_id := 'other-hub-code')::text
  ),
  '22023',
  'HUB_CODE_MISMATCH',
  'the manifest hub code must match the registered hub code'
);

select throws_ok(
  format(
    $sql$select * from admin_api.update_hub(
      'synthetic-admin-updated-hub',
      %L::jsonb,
      'testing',
      true
    )$sql$,
    pg_temp.hub_manifest(p_courses := '["missing-course-key"]'::jsonb)::text
  ),
  '22023',
  'HUB_COURSE_NOT_FOUND',
  'unknown course associations are rejected on update'
);

select throws_ok(
  format(
    $sql$select * from admin_api.update_hub(
      'synthetic-admin-updated-hub',
      %L::jsonb,
      'testing',
      true
    )$sql$,
    pg_temp.hub_manifest(p_courses := '["inactive-admin-course"]'::jsonb)::text
  ),
  '22023',
  'HUB_COURSE_INACTIVE',
  'inactive course associations are rejected on update'
);

select throws_ok(
  format(
    $sql$select * from admin_api.update_hub(
      'synthetic-admin-updated-hub',
      %L::jsonb,
      'testing',
      true
    )$sql$,
    pg_temp.hub_manifest(
      p_repository := (
        select hub.repository_url
        from platform.hubs as hub
        where hub.hub_code = 'unit-14-software-engineering-for-business'
      )
    )::text
  ),
  '23505',
  'HUB_DUPLICATE_REPOSITORY',
  'updates cannot reuse another hub repository URL'
);

select is(
  (
    select hub_name
    from admin_api.update_hub(
      'synthetic-admin-updated-hub',
      pg_temp.hub_manifest(
        p_name := 'Synthetic Admin Updated Hub Revised',
        p_repository := 'https://example.invalid/synthetic-admin-updated-hub'
      ),
      'maintenance',
      false
    )
  ),
  'Synthetic Admin Updated Hub Revised',
  'an authorised platform administrator can update hub metadata and disable the hub'
);

select is(
  (
    select status
    from platform.hubs
    where hub_code = 'synthetic-admin-updated-hub'
  ),
  'maintenance',
  'update stores the requested lifecycle status'
);

select is(
  (
    select active
    from platform.hubs
    where hub_code = 'synthetic-admin-updated-hub'
  ),
  false,
  'update can disable a registered hub without deleting it'
);

select is(
  (
    select count(*)
    from platform.hubs
    where hub_code = 'synthetic-admin-updated-hub'
  ),
  1::bigint,
  'update does not create a duplicate hub row'
);

select is(
  (
    select event_key
    from platform.audit_events
    where entity_type = 'hub'
      and entity_key = 'synthetic-admin-updated-hub'
      and event_key = 'hub.registration.updated'
    order by occurred_at desc
    limit 1
  ),
  'hub.registration.updated',
  'successful update writes a minimised audit event'
);

select ok(
  (
    select context ? 'hubCode'
       and context ? 'updatedBy'
       and not context ? 'email'
    from platform.audit_events
    where entity_key = 'synthetic-admin-updated-hub'
      and event_key = 'hub.registration.updated'
    order by occurred_at desc
    limit 1
  ),
  'update audit context stores hub code and staff reference without email'
);

select throws_like(
  $$update platform.hubs
    set hub_name = 'Direct update denied'
    where hub_code = 'synthetic-admin-updated-hub'$$,
  '%permission denied%',
  'authenticated staff cannot update platform.hubs directly'
);

reset role;

select * from finish();
rollback;
