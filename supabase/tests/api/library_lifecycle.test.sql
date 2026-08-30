begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_function(
  'admin_api',
  'publish_library_item',
  array['text', 'uuid'],
  'admin_api.publish_library_item exists'
);
select has_function(
  'admin_api',
  'archive_library_item',
  array['text', 'uuid'],
  'admin_api.archive_library_item exists'
);
select has_function(
  'admin_api',
  'duplicate_library_item',
  array['text', 'uuid', 'text', 'text', 'text'],
  'admin_api.duplicate_library_item exists'
);

insert into library.activities (
  id, stable_key, title, activity_type, status, version, content, author
) values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
  'lifecycle-test-activity',
  'Lifecycle test activity',
  'lesson',
  'draft',
  '1.0.0',
  '{}'::jsonb,
  'Test'
) on conflict (stable_key) do update set
  status = 'draft',
  title = excluded.title;

insert into library.activities (
  id, stable_key, title, activity_type, status, version, content, author
) values (
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid,
  'lifecycle-archived-activity',
  'Archived lifecycle activity',
  'lesson',
  'archived',
  '1.0.0',
  '{}'::jsonb,
  'Test'
) on conflict (stable_key) do update set status = 'archived';

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

-- Draft excluded from published search
select is(
  (select count(*)::integer from admin_api.search_library('', array['activity'], 'published', null, null, '{}'::text[], 50, 0)
   where stable_key = 'lifecycle-test-activity'),
  0,
  'draft activity is excluded from published search'
);

reset role;

set local role anon;
select throws_like(
  $$select * from admin_api.publish_library_item('activity', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid)$$,
  '%permission denied%',
  'anonymous clients cannot publish library items'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from admin_api.publish_library_item('activity', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid)$$,
  'P0001',
  'Content authoring requires platform_admin or curriculum_admin role',
  'learners cannot publish library items'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from admin_api.publish_library_item('activity', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid)$$,
  'P0001',
  'Content authoring requires platform_admin or curriculum_admin role',
  'ordinary teachers cannot publish library items'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (select status from admin_api.publish_library_item('activity', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid)),
  'published',
  'platform_admin can publish a draft activity'
);

select is(
  (select count(*)::integer from admin_api.search_library('', array['activity'], 'published', null, null, '{}'::text[], 50, 0)
   where stable_key = 'lifecycle-test-activity'),
  1,
  'published activity appears in published search'
);

select throws_ok(
  $$select * from admin_api.save_library_activity(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
    'lifecycle-test-activity',
    'Changed title',
    'lesson'
  )$$,
  'P0001',
  'Cannot edit a published activity. Create a new version instead.',
  'published activity cannot be edited in place'
);

select is(
  (select status from admin_api.duplicate_library_item(
    'activity',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
    'lifecycle-test-activity-v2',
    'Lifecycle test activity v2',
    '1.0.1'
  )),
  'draft',
  'duplicate creates a new draft version from published activity'
);

select is(
  (select status from admin_api.archive_library_item('activity', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid)),
  'archived',
  'platform_admin can archive a published activity'
);

select is(
  (select count(*)::integer from admin_api.search_library('', array['activity'], 'published', null, null, '{}'::text[], 50, 0)
   where stable_key = 'lifecycle-test-activity'),
  0,
  'archived activity is excluded from published search'
);

select is(
  (select count(*)::integer from platform.audit_events ae
   where ae.event_key = 'library.item.published'
     and ae.entity_key = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'publish records an audit event'
);

select is(
  (select count(*)::integer from platform.audit_events ae
   where ae.event_key = 'library.item.archived'
     and ae.entity_key = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'archive records an audit event'
);

reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_like(
  $$insert into library.activities (
      stable_key, title, activity_type, status, version, content, author
    ) values (
      'learner-direct-write',
      'Should fail',
      'lesson',
      'draft',
      '1.0.0',
      '{}'::jsonb,
      'Learner'
    )$$,
  '%permission denied%',
  'authenticated learners cannot insert library rows directly'
);
reset role;

select * from finish();
rollback;
