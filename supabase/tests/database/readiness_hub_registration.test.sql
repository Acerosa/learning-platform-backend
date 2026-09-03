begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select is(
  (
    select hub.active
      and hub.status = 'testing'
      and hub.hub_code = 'level-3-it-year-1-readiness'
      and hub.core_version = '0.2.5'
      and hub.features ->> 'authentication' = 'false'
      and hub.features ->> 'diagnosticVersion' = '1.0.0'
    from platform.hubs as hub
    where hub.hub_code = 'level-3-it-year-1-readiness'
  ),
  true,
  'readiness hub is locally registered, active, and does not require authentication'
);

select is(
  (
    select course.stable_key
    from platform.hub_course_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.courses as course on course.id = link.course_id
    where hub.hub_code = 'level-3-it-year-1-readiness'
      and link.active
      and course.active
  ),
  'ocr-level-3-it',
  'readiness hub is linked only to the existing OCR Level 3 IT course'
);

select is(
  (
    select count(*)
    from learning.courses
    where stable_key like 'ocr-level-3-it-year-1%'
  ),
  0::bigint,
  'no Year 1-only course was created'
);

set local role anon;

select ok(
  exists (
    select 1
    from api.registered_hubs()
    where hub_code = 'level-3-it-year-1-readiness'
  ),
  'anonymous clients can discover the readiness hub'
);

select lives_ok(
  $$select api.start_diagnostic(
    'level-3-it-year-1-readiness',
    'Diagnostic Test Learner',
    'TEST-READINESS-001'
  )$$,
  'start_diagnostic accepts the locally registered readiness hub'
);

reset role;

select is(
  (
    select course.stable_key
    from learning.diagnostic_sessions as session
    join learning.courses as course on course.id = session.course_id
    join platform.hubs as hub on hub.id = session.hub_id
    where session.student_id = 'TEST-READINESS-001'
      and hub.hub_code = 'level-3-it-year-1-readiness'
    order by session.started_at desc
    limit 1
  ),
  'ocr-level-3-it',
  'omitted course key resolves to ocr-level-3-it'
);

select finish();
rollback;
