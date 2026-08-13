begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

create function pg_temp.publication_package(p_title text default 'Platform curriculum')
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'hub', jsonb_build_object(
      'schema', 'lp.content.hub',
      'schemaVersion', '0.1.0',
      'id', 'unit-3-cyber-security',
      'version', '0.1.0',
      'metadata', jsonb_build_object('name', 'Unit 3 Cyber Security Hub'),
      'relationships', jsonb_build_object('curriculum', 'unit-3-cyber-security-curriculum')
    ),
    'curriculum', jsonb_build_object(
      'schema', 'lp.content.curriculum',
      'schemaVersion', '0.1.0',
      'id', 'unit-3-cyber-security-curriculum',
      'version', '0.1.0',
      'metadata', jsonb_build_object('title', p_title, 'course', 'ocr-level-3-it'),
      'relationships', jsonb_build_object(
        'learningOutcomes', '[]'::jsonb,
        'assignments', '[]'::jsonb,
        'weeks', jsonb_build_array('week-20')
      )
    ),
    'learningOutcomes', '[]'::jsonb,
    'assignments', '[]'::jsonb,
    'weeks', jsonb_build_array(
      jsonb_build_object(
        'schema', 'lp.content.week',
        'schemaVersion', '0.1.0',
        'id', 'week-20',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Synthetic week', 'teachingWeek', 20),
        'relationships', jsonb_build_object('sessions', jsonb_build_array('week-20-workshop'))
      )
    ),
    'sessions', jsonb_build_array(
      jsonb_build_object(
        'schema', 'lp.content.session',
        'schemaVersion', '0.1.0',
        'id', 'week-20-workshop',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Workshop', 'kind', 'session'),
        'relationships', jsonb_build_object(
          'week', 'week-20',
          'activities', jsonb_build_array('pub-activity')
        )
      )
    ),
    'activities', jsonb_build_array(
      jsonb_build_object(
        'schema', 'lp.content.activity',
        'schemaVersion', '0.1.0',
        'id', 'pub-activity',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Publication activity'),
        'relationships', jsonb_build_object(),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'schema', 'lp.content.block',
            'schemaVersion', '0.1.0',
            'id', 'pub-activity-block-1',
            'version', '0.1.0',
            'type', 'paragraph',
            'metadata', jsonb_build_object(),
            'relationships', jsonb_build_object(),
            'content', jsonb_build_object('text', 'Published locally then to the platform.')
          )
        )
      )
    ),
    'questions', '[]'::jsonb,
    'assets', '[]'::jsonb
  )
$$;

select has_table('platform', 'curriculum_publications', 'publication catalogue table exists');
select has_function(
  'admin_api',
  'publish_curriculum',
  array['text', 'text', 'text', 'text', 'text', 'text', 'jsonb', 'text', 'text', 'text'],
  'staff API exposes the curriculum publication RPC'
);
select has_function(
  'api',
  'published_curriculum',
  array[]::text[],
  'learner-safe published curriculum metadata RPC exists'
);
select has_view('admin_api', 'curriculum_publications', 'staff publication history view exists');

select throws_ok(
  $$select platform.validate_curriculum_package('{"hub":{}}'::jsonb)$$,
  '22023',
  'PUBLICATION_VALIDATION_FAILED',
  'server-side validation rejects an incomplete package'
);

select lives_ok(
  $$select platform.validate_curriculum_package(pg_temp.publication_package())$$,
  'a canonical package passes server-side validation'
);

set local role anon;
select throws_like(
  $$select * from admin_api.publish_curriculum(
    'published', 'unit-3-cyber-security', 'ocr-level-3-it', '0.1.0', '0.1.0', '0.1.0',
    '{}'::jsonb, 'Author', 'Reviewer', 'Notes'
  )$$,
  '%permission denied%',
  'anonymous clients cannot publish curriculum'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  format(
    $sql$select * from admin_api.publish_curriculum(
      'published', 'unit-3-cyber-security', 'ocr-level-3-it', '0.1.0', '0.1.0', '0.1.0',
      %L::jsonb, 'Author', 'Reviewer', 'Notes'
    )$sql$,
    pg_temp.publication_package()::text
  ),
  '28000',
  'PUBLICATION_NOT_AUTHORISED',
  'a learner cannot publish curriculum'
);
select is(
  (select count(*) from admin_api.curriculum_publications),
  0::bigint,
  'a learner cannot read staff publication history'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  format(
    $sql$select * from admin_api.publish_curriculum(
      'published', 'unit-3-cyber-security', 'ocr-level-3-it', '0.1.0', '0.1.0', '0.1.0',
      %L::jsonb, 'Author', 'Reviewer', 'Notes'
    )$sql$,
    pg_temp.publication_package()::text
  ),
  '28000',
  'PUBLICATION_NOT_AUTHORISED',
  'an ordinary teacher cannot publish curriculum'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  format(
    $sql$select * from admin_api.publish_curriculum(
      'draft', 'unit-3-cyber-security', 'ocr-level-3-it', '0.1.0', '0.1.0', '0.1.0',
      %L::jsonb, 'Ada Author', 'Riley Reviewer', 'Notes'
    )$sql$,
    pg_temp.publication_package()::text
  ),
  '22023',
  'PUBLICATION_STATUS_INVALID',
  'draft snapshots are rejected'
);

select throws_ok(
  format(
    $sql$select * from admin_api.publish_curriculum(
      'ready-for-review', 'unit-3-cyber-security', 'ocr-level-3-it', '0.1.0', '0.1.0', '0.1.0',
      %L::jsonb, 'Ada Author', 'Riley Reviewer', 'Notes'
    )$sql$,
    pg_temp.publication_package()::text
  ),
  '22023',
  'PUBLICATION_STATUS_INVALID',
  'ready-for-review snapshots are rejected'
);

select throws_ok(
  format(
    $sql$select * from admin_api.publish_curriculum(
      'in-review', 'unit-3-cyber-security', 'ocr-level-3-it', '0.1.0', '0.1.0', '0.1.0',
      %L::jsonb, 'Ada Author', 'Riley Reviewer', 'Notes'
    )$sql$,
    pg_temp.publication_package()::text
  ),
  '22023',
  'PUBLICATION_STATUS_INVALID',
  'in-review snapshots are rejected'
);

select throws_ok(
  format(
    $sql$select * from admin_api.publish_curriculum(
      'published', 'unit-3-cyber-security', 'ocr-level-3-it', '0.1.0', '9.9.9', '0.1.0',
      %L::jsonb, 'Ada Author', 'Riley Reviewer', 'Notes'
    )$sql$,
    pg_temp.publication_package()::text
  ),
  '22023',
  'UNSUPPORTED_SCHEMA_VERSION',
  'unsupported schema versions are rejected'
);

select throws_ok(
  format(
    $sql$select * from admin_api.publish_curriculum(
      'published', 'unit-3-cyber-security', 'ocr-level-3-it', '0.1.0', '0.1.0', '9.9.9',
      %L::jsonb, 'Ada Author', 'Riley Reviewer', 'Notes'
    )$sql$,
    pg_temp.publication_package()::text
  ),
  '22023',
  'UNSUPPORTED_PACKAGE_VERSION',
  'unsupported content package versions are rejected'
);

select throws_ok(
  $sql$select * from admin_api.publish_curriculum(
    'published', 'unit-3-cyber-security', 'ocr-level-3-it', '0.1.0', '0.1.0', '0.1.0',
    '{"hub":{"schema":"lp.content.hub","schemaVersion":"0.1.0","id":"unit-3-cyber-security","version":"0.1.0","metadata":{},"relationships":{}},"curriculum":{"schema":"lp.content.curriculum","schemaVersion":"0.1.0","id":"unit-3-cyber-security-curriculum","version":"0.1.0","metadata":{"course":"ocr-level-3-it"},"relationships":{}},"learningOutcomes":[],"assignments":[],"weeks":[],"sessions":[{"schema":"lp.content.session","schemaVersion":"0.1.0","id":"missing-week-session","version":"0.1.0","metadata":{"title":"Broken"},"relationships":{"week":"missing-week","activities":[]}}],"activities":[],"questions":[],"assets":[]}'::jsonb,
    'Ada Author', 'Riley Reviewer', 'Notes'
  )$sql$,
  '22023',
  'PUBLICATION_VALIDATION_FAILED',
  'broken references are rejected'
);

select is(
  (
    select package_version
    from admin_api.publish_curriculum(
      'published',
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '0.1.0',
      '0.1.0',
      '0.1.0',
      pg_temp.publication_package(),
      'Ada Author',
      'Riley Reviewer',
      'First platform snapshot.'
    )
  ),
  '0.1.0',
  'an authorised administrator can publish a valid snapshot'
);

select is(
  (
    select idempotent
    from admin_api.publish_curriculum(
      'published',
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '0.1.0',
      '0.1.0',
      '0.1.0',
      pg_temp.publication_package(),
      'Ada Author',
      'Riley Reviewer',
      'First platform snapshot.'
    )
  ),
  true,
  'retrying the same published snapshot is idempotent'
);

select throws_ok(
  format(
    $sql$select * from admin_api.publish_curriculum(
      'published', 'unit-3-cyber-security', 'ocr-level-3-it', '0.1.0', '0.1.0', '0.1.0',
      %L::jsonb, 'Ada Author', 'Riley Reviewer', 'Changed body'
    )$sql$,
    pg_temp.publication_package('Changed title')::text
  ),
  '22023',
  'DUPLICATE_VERSION',
  'a different package cannot reuse an existing version'
);

select is(
  (
    select package_version
    from admin_api.publish_curriculum(
      'approved',
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '0.1.1',
      '0.1.0',
      '0.1.0',
      pg_temp.publication_package('Second snapshot'),
      'Ada Author',
      'Riley Reviewer',
      'Superseding snapshot.'
    )
  ),
  '0.1.1',
  'publishing a newer version succeeds'
);

select is(
  (
    select status
    from platform.curriculum_publications
    where package_version = '0.1.0'
      and hub_code = 'unit-3-cyber-security'
  ),
  'superseded',
  'the previous published version is superseded'
);

select is(
  (
    select count(*)
    from platform.curriculum_publications
    where hub_code = 'unit-3-cyber-security'
      and status = 'published'
  ),
  1::bigint,
  'exactly one current published version remains'
);

select is(
  (
    select count(*)
    from platform.audit_events
    where event_key = 'curriculum.publication.published'
      and actor_auth_user_id = '20000000-0000-4000-8000-000000000003'
      and outcome = 'succeeded'
  ),
  2::bigint,
  'successful publications are audited and history is retained'
);

select is(
  (select count(*) from admin_api.curriculum_publications),
  2::bigint,
  'staff can read publication history including superseded versions'
);

select is(
  (select package_version from api.published_curriculum()),
  '0.1.1',
  'learner-safe metadata exposes only the current published version'
);

select throws_like(
  $$update platform.curriculum_publications
    set author = 'mutated'
    where package_version = '0.1.1'$$,
  '%permission denied%',
  'authenticated administrators cannot update publication rows directly'
);

select throws_like(
  $$delete from platform.curriculum_publications where package_version = '0.1.1'$$,
  '%permission denied%',
  'authenticated administrators cannot delete publication rows directly'
);

select throws_like(
  $$insert into platform.curriculum_publications (
      hub_code, course_key, package_version, schema_version, source_package_version,
      status, package, content_hash, author, published_by_auth_user_id, published_by_staff_reference
    ) values (
      'unit-3-cyber-security', 'ocr-level-3-it', '9.9.9', '0.1.0', '0.1.0',
      'published', '{}'::jsonb, repeat('a', 64), 'Browser',
      '20000000-0000-4000-8000-000000000003', 'SYNTH-PLATFORM-ADMIN'
    )$$,
  '%permission denied%',
  'authenticated administrators cannot insert publication rows directly'
);

reset role;

select throws_ok(
  $$update platform.curriculum_publications
    set author = 'mutated'
    where package_version = '0.1.1'$$,
  '22023',
  'PUBLISHED_CURRICULUM_IMMUTABLE',
  'published catalogue rows cannot be edited even by the table owner'
);

select throws_ok(
  $$delete from platform.curriculum_publications where package_version = '0.1.1'$$,
  '22023',
  'PUBLISHED_CURRICULUM_IMMUTABLE',
  'published catalogue rows cannot be deleted even by the table owner'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select is(
  (select package_version from api.published_curriculum()),
  '0.1.1',
  'authenticated learners can read published curriculum metadata'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'api'
      and table_name = 'published_curriculum'
  ),
  'learner consumption is an RPC, not a package-body table'
);
reset role;

select * from finish();
rollback;
