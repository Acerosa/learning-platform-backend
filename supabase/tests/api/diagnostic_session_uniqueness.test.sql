begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

create temporary table pg_temp.diag_unique (
  label text primary key,
  session_id uuid not null,
  payload jsonb not null
);

select has_column(
  'learning',
  'diagnostic_sessions',
  'diagnostic_key',
  'diagnostic sessions store a server-derived diagnostic key'
);
select has_column(
  'learning',
  'diagnostic_sessions',
  'diagnostic_version',
  'diagnostic sessions store a server-derived diagnostic version'
);
select index_is_unique(
  'learning',
  'diagnostic_sessions',
  'diagnostic_sessions_one_sitting_idx',
  'one sitting per hub, course, diagnostic version, and student ID'
);
select index_is_unique(
  'learning',
  'diagnostic_responses',
  'diagnostic_responses_session_question_unique',
  'response uniqueness remains one row per session/activity/question'
);

select ok(
  position(
    'auth.uid' in lower(
      pg_get_functiondef('api.start_diagnostic(text,text,text,text)'::regprocedure)
    )
  ) = 0,
  'start_diagnostic does not use auth.uid'
);

select ok(
  has_function_privilege(
    'anon',
    'api.start_diagnostic(text,text,text,text)',
    'EXECUTE'
  ),
  'anonymous clients can still execute start_diagnostic'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_sessions', 'SELECT'),
  'anonymous clients still cannot select diagnostic sessions'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_sessions', 'INSERT'),
  'anonymous clients still cannot insert diagnostic sessions directly'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_sessions', 'UPDATE'),
  'anonymous clients still cannot update diagnostic sessions'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_responses', 'SELECT'),
  'anonymous clients still cannot select diagnostic responses'
);

grant select, insert, update, delete on table pg_temp.diag_unique to anon;

set local role anon;

select lives_ok(
  $$insert into pg_temp.diag_unique (label, session_id, payload)
    select
      'first',
      (payload->>'id')::uuid,
      payload
    from (
      select api.start_diagnostic(
        'unit-3-cyber-security',
        'John Smith',
        '123456'
      ) as payload
    ) as started$$,
  'first Start for a student ID creates a session'
);

select is(
  (select payload->>'status' from pg_temp.diag_unique where label = 'first'),
  'started',
  'new sittings start with status started'
);
select is(
  (select payload->>'resumed' from pg_temp.diag_unique where label = 'first'),
  'false',
  'a new sitting is not marked resumed'
);
select is(
  (select payload->>'hub_code' from pg_temp.diag_unique where label = 'first'),
  'unit-3-cyber-security',
  'start diagnostic still returns hub_code'
);
select is(
  (select payload->>'course_key' from pg_temp.diag_unique where label = 'first'),
  'ocr-level-3-it',
  'start diagnostic still returns course_key'
);
select ok(
  not ((select payload from pg_temp.diag_unique where label = 'first') ? 'score'),
  'start diagnostic does not return a score'
);

select lives_ok(
  $$insert into pg_temp.diag_unique (label, session_id, payload)
    select
      'repeat',
      (payload->>'id')::uuid,
      payload
    from (
      select api.start_diagnostic(
        'unit-3-cyber-security',
        'John Smith',
        '123456'
      ) as payload
    ) as started$$,
  'repeat Start while started reuses the sitting'
);

select is(
  (select session_id from pg_temp.diag_unique where label = 'repeat'),
  (select session_id from pg_temp.diag_unique where label = 'first'),
  'repeat Start returns the original session id'
);
select is(
  (select payload->>'resumed' from pg_temp.diag_unique where label = 'repeat'),
  'true',
  'repeat Start marks the sitting as resumed'
);
select is(
  (select payload->>'started_at' from pg_temp.diag_unique where label = 'repeat'),
  (select payload->>'started_at' from pg_temp.diag_unique where label = 'first'),
  'resumed sittings keep the original started_at'
);

select lives_ok(
  $$insert into pg_temp.diag_unique (label, session_id, payload)
    select
      'name-mismatch',
      (payload->>'id')::uuid,
      payload
    from (
      select api.start_diagnostic(
        'unit-3-cyber-security',
        'Jon Smith',
        '123456'
      ) as payload
    ) as started$$,
  'a later name variation does not create another sitting'
);

select is(
  (select session_id from pg_temp.diag_unique where label = 'name-mismatch'),
  (select session_id from pg_temp.diag_unique where label = 'first'),
  'name variation reuses the student-ID sitting'
);

select lives_ok(
  $$insert into pg_temp.diag_unique (label, session_id, payload)
    select
      'whitespace',
      (payload->>'id')::uuid,
      payload
    from (
      select api.start_diagnostic(
        'unit-3-cyber-security',
        'John Smith',
        ' 123456 '
      ) as payload
    ) as started$$,
  'leading and trailing student ID whitespace collapse to the same sitting'
);

select is(
  (select session_id from pg_temp.diag_unique where label = 'whitespace'),
  (select session_id from pg_temp.diag_unique where label = 'first'),
  'trimmed student IDs share one diagnostic identity'
);

select lives_ok(
  $$insert into pg_temp.diag_unique (label, session_id, payload)
    select
      'other-student',
      (payload->>'id')::uuid,
      payload
    from (
      select api.start_diagnostic(
        'unit-3-cyber-security',
        'John Smith',
        '123457'
      ) as payload
    ) as started$$,
  'a different student ID creates a new sitting'
);

select isnt(
  (select session_id from pg_temp.diag_unique where label = 'other-student'),
  (select session_id from pg_temp.diag_unique where label = 'first'),
  'different student IDs do not share a sitting'
);

reset role;

select is(
  (
    select count(*)
    from learning.diagnostic_sessions
    where student_id = '123456'
      and diagnostic_key = 'unit-3-cyber-security'
      and diagnostic_version = '1.0.0'
  ),
  1::bigint,
  'repeat Starts keep a single sitting for the same student and version'
);

select is(
  (
    select student_name
    from learning.diagnostic_sessions
    where id = (select session_id from pg_temp.diag_unique where label = 'first')
  ),
  'John Smith',
  'repeat Starts preserve the original stored name'
);

select lives_ok(
  $$insert into learning.diagnostic_sessions (
      hub_id,
      course_id,
      student_name,
      student_id,
      diagnostic_key,
      diagnostic_version
    )
    select
      hub.id,
      course.id,
      'John Smith',
      '123456',
      hub.hub_code,
      '2.0.0'
    from platform.hubs as hub
    join learning.courses as course on course.stable_key = 'ocr-level-3-it'
    where hub.hub_code = 'unit-3-cyber-security'$$,
  'a genuinely different diagnostic version may create a new sitting'
);

select is(
  (
    select count(*)
    from learning.diagnostic_sessions
    where student_id = '123456'
      and diagnostic_key = 'unit-3-cyber-security'
  ),
  2::bigint,
  'the same student ID can sit a later diagnostic version'
);

select throws_ok(
  $$insert into learning.diagnostic_sessions (
      hub_id,
      course_id,
      student_name,
      student_id,
      diagnostic_key,
      diagnostic_version
    )
    select
      hub.id,
      course.id,
      'Duplicate Start',
      '123456',
      hub.hub_code,
      '1.0.0'
    from platform.hubs as hub
    join learning.courses as course on course.stable_key = 'ocr-level-3-it'
    where hub.hub_code = 'unit-3-cyber-security'$$,
  '23505',
  NULL,
  'the unique sitting index rejects a concurrent equivalent insert'
);

set local role anon;

select lives_ok(
  format(
    $sql$select api.submit_diagnostic_response(
      %L::uuid,
      'readiness-opening-confidence',
      'general',
      'RDY-OPEN-001',
      jsonb_build_object('optionId', 'somewhat'),
      false,
      'somewhat'
    )$sql$,
    (select session_id from pg_temp.diag_unique where label = 'first')
  ),
  'the first response for a question persists'
);

select lives_ok(
  format(
    $sql$select api.submit_diagnostic_response(
      %L::uuid,
      'readiness-opening-confidence',
      'general',
      'RDY-OPEN-001',
      jsonb_build_object('optionId', 'not-sure'),
      false,
      'not-sure'
    )$sql$,
    (select session_id from pg_temp.diag_unique where label = 'first')
  ),
  'repeat response delivery upserts rather than inserting a second row'
);

select lives_ok(
  format(
    $sql$select api.complete_diagnostic(%L::uuid)$sql$,
    (select session_id from pg_temp.diag_unique where label = 'first')
  ),
  'the sitting can be completed'
);

select lives_ok(
  format(
    $sql$select api.complete_diagnostic(%L::uuid)$sql$,
    (select session_id from pg_temp.diag_unique where label = 'first')
  ),
  'complete_diagnostic remains idempotent'
);

select throws_ok(
  $$select api.start_diagnostic(
    'unit-3-cyber-security',
    'John Smith',
    '123456'
  )$$,
  '22023',
  'DIAGNOSTIC_ALREADY_COMPLETED',
  'a completed sitting cannot be started again for the same version'
);

select throws_ok(
  format(
    $sql$select api.submit_diagnostic_response(
      %L::uuid,
      'readiness-gist-email',
      'global-information',
      'RDY-GIST-002',
      jsonb_build_object('optionId', 'copy-sent'),
      false,
      null
    )$sql$,
    (select session_id from pg_temp.diag_unique where label = 'first')
  ),
  '22023',
  'DIAGNOSTIC_SESSION_COMPLETED',
  'completed sittings still reject further responses'
);

reset role;

select is(
  (
    select count(*)
    from learning.diagnostic_sessions
    where student_id = '123456'
      and diagnostic_key = 'unit-3-cyber-security'
      and diagnostic_version = '1.0.0'
  ),
  1::bigint,
  'completed Start attempts do not create another version-1 sitting'
);

select is(
  (
    select count(*)
    from learning.diagnostic_responses
    where diagnostic_session_id = (
      select session_id from pg_temp.diag_unique where label = 'first'
    )
      and question_key = 'RDY-OPEN-001'
  ),
  1::bigint,
  'response-level uniqueness still stores one row per question'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select ok(
  exists (
    select 1
    from admin_api.diagnostic_sessions
    where student_id = '123456'
      and diagnostic_version = '1.0.0'
      and status = 'completed'
  ),
  'platform administrators can still list diagnostic sessions including version'
);

reset role;

select finish();
rollback;
