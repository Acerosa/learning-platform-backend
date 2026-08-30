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
          ),
          jsonb_build_object(
            'schema', 'lp.content.block',
            'schemaVersion', '0.1.0',
            'id', 'pub-activity-teacher-note',
            'version', '0.1.0',
            'type', 'teacher-note',
            'metadata', jsonb_build_object(),
            'relationships', jsonb_build_object(),
            'content', jsonb_build_object('text', 'Staff only marking guidance.')
          ),
          jsonb_build_object(
            'schema', 'lp.content.block',
            'schemaVersion', '0.1.0',
            'id', 'pub-activity-choice',
            'version', '0.1.0',
            'type', 'single-choice',
            'metadata', jsonb_build_object(),
            'relationships', jsonb_build_object(),
            'content', jsonb_build_object(
              'questionId', 'pub-activity-q1',
              'prompt', 'Which snapshot is live?',
              'options', jsonb_build_array(
                jsonb_build_object('id', 'a', 'label', 'Published'),
                jsonb_build_object('id', 'b', 'label', 'Draft')
              ),
              'correctOptionId', 'a'
            )
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
select has_function(
  'api',
  'published_curriculum_package',
  array['text', 'text'],
  'learner-safe published curriculum package RPC exists'
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
      '0.3.0',
      '0.1.0',
      '0.1.0',
      pg_temp.publication_package(),
      'Ada Author',
      'Riley Reviewer',
      'First platform snapshot.'
    )
  ),
  '0.3.0',
  'an authorised administrator can publish a valid snapshot'
);

select is(
  (
    select idempotent
    from admin_api.publish_curriculum(
      'published',
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '0.3.0',
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
      'published', 'unit-3-cyber-security', 'ocr-level-3-it', '0.3.0', '0.1.0', '0.1.0',
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
      '0.3.1',
      '0.1.0',
      '0.1.0',
      pg_temp.publication_package('Second snapshot'),
      'Ada Author',
      'Riley Reviewer',
      'Superseding snapshot.'
    )
  ),
  '0.3.1',
  'publishing a newer version succeeds'
);

select is(
  (
    select status
    from platform.curriculum_publications
    where package_version = '0.3.0'
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
  (
    select count(*)
    from admin_api.curriculum_publications
    where hub_code = 'unit-3-cyber-security'
  ),
  3::bigint,
  'staff can read publication history including superseded versions'
);

select is(
  (
    select package_version
    from api.published_curriculum()
    where hub_code = 'unit-3-cyber-security'
  ),
  '0.3.1',
  'learner-safe metadata exposes only the current published version'
);

select is(
  (
    select package->'curriculum'->'metadata'->>'title'
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it')
  ),
  'Second snapshot',
  'a newer published package becomes the learner runtime source without a git commit'
);

select throws_like(
  $$update platform.curriculum_publications
    set author = 'mutated'
    where package_version = '0.3.1'$$,
  '%permission denied%',
  'authenticated administrators cannot update publication rows directly'
);

select throws_like(
  $$delete from platform.curriculum_publications where package_version = '0.3.1'$$,
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
    where package_version = '0.3.1'$$,
  '22023',
  'PUBLISHED_CURRICULUM_IMMUTABLE',
  'published catalogue rows cannot be edited even by the table owner'
);

select throws_ok(
  $$delete from platform.curriculum_publications where package_version = '0.3.1'$$,
  '22023',
  'PUBLISHED_CURRICULUM_IMMUTABLE',
  'published catalogue rows cannot be deleted even by the table owner'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select is(
  (
    select package_version
    from api.published_curriculum()
    where hub_code = 'unit-3-cyber-security'
  ),
  '0.3.1',
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
select is(
  (
    select package_version
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it')
  ),
  '0.3.1',
  'authenticated learners can read the current published package body'
);
select is(
  (
    select package_version
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it', '0.3.0')
  ),
  '0.3.0',
  'authenticated learners can read an explicit historical package version'
);
select is(
  (
    select package_version
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it', '0.2.0')
  ),
  '0.2.0',
  'the migrated publication remains readable after a later staff publish'
);
select is(
  (
    select package_version
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it', null)
  ),
  '0.3.1',
  'a null package version still returns the current published package'
);
select ok(
  exists (
    select 1
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it') as published,
      jsonb_array_elements(published.package->'activities') as activity,
      jsonb_array_elements(activity->'blocks') as block
    where block->>'type' = 'single-choice'
      and block->'content'->>'questionId' = 'pub-activity-q1'
  ),
  'the learner package keeps published teaching activities'
);
select ok(
  (
    select not coalesce(package::text, '') like '%teacher-note%'
      and not coalesce(package::text, '') like '%Staff only marking guidance%'
      and not coalesce(package::text, '') like '%Ada Author%'
      and not coalesce(package::text, '') like '%Riley Reviewer%'
      and not coalesce(package::text, '') like '%correctOptionId%'
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it')
  ),
  'the learner package omits teacher-notes, staff publication metadata and answer keys'
);
select throws_like(
  $$select spec from learning.question_marking limit 1$$,
  '%permission denied%',
  'authenticated learners cannot read protected marking specs'
);
reset role;

set local role anon;
select is(
  (
    select package_version
    from api.published_curriculum()
    where hub_code = 'unit-3-cyber-security'
  ),
  '0.3.1',
  'anonymous clients can read published curriculum metadata'
);
select is(
  (
    select package->>'version'
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it')
  ),
  '0.3.1',
  'anonymous clients can read the current published teaching package'
);
select throws_ok(
  $$select * from api.published_curriculum_package('missing-hub', 'ocr-level-3-it')$$,
  '22023',
  'HUB_NOT_FOUND',
  'an unknown hub is rejected'
);
select throws_ok(
  $$select * from api.published_curriculum_package('unit-3-cyber-security', 'missing-course')$$,
  '22023',
  'COURSE_NOT_FOUND',
  'an unknown course is rejected'
);
reset role;

select ok(
  exists (
    select 1
    from learning.activities as activity
    join learning.activity_versions as version on version.activity_id = activity.id
    where activity.stable_key = 'pub-activity'
      and version.version = '0.1.0'
      and version.published_at is not null
  ),
  'publication projects interactive activities into the delivery catalogue'
);
select is(
  (
    select count(*)::int
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'pub-activity'
      and version.version = '0.1.0'
  ),
  1,
  'catalogue projection is idempotent for an unchanged activity version'
);
select ok(
  exists (
    select 1
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week-1-baseline-diagnostic'
      and version.version = '0.1.0'
      and version.published_at is not null
  ),
  'historical Unit 14 Week 1 activity versions remain published'
);
select ok(
  not exists (
    select 1
    from platform.curriculum_publications
    where status not in ('published', 'superseded')
  ),
  'draft and in-review snapshots are never stored in the publication catalogue'
);

select * from finish();
rollback;
