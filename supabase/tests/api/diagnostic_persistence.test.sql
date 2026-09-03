begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

create temporary table pg_temp.diag_session (
  label text primary key,
  session_id uuid not null
);

select has_table('learning', 'diagnostic_sessions', 'diagnostic session table exists');
select has_table('learning', 'diagnostic_responses', 'diagnostic response table exists');
select has_pk('learning', 'diagnostic_sessions', 'diagnostic sessions have a primary key');
select has_pk('learning', 'diagnostic_responses', 'diagnostic responses have a primary key');
select col_is_fk(
  'learning',
  'diagnostic_responses',
  'diagnostic_session_id',
  'responses reference sessions'
);
select index_is_unique(
  'learning',
  'diagnostic_responses',
  'diagnostic_responses_session_question_unique',
  'one response row per session/activity/question'
);

select has_function(
  'api',
  'start_diagnostic',
  array['text', 'text', 'text', 'text'],
  'start diagnostic RPC exists'
);
select has_function(
  'api',
  'submit_diagnostic_response',
  array['uuid', 'text', 'text', 'text', 'jsonb', 'boolean', 'text', 'text'],
  'submit diagnostic response RPC exists'
);
select has_function(
  'api',
  'complete_diagnostic',
  array['uuid'],
  'complete diagnostic RPC exists'
);

select has_view('admin_api', 'diagnostic_sessions', 'staff session list exists');
select has_view('admin_api', 'diagnostic_responses', 'staff response detail exists');
select has_view('admin_api', 'diagnostic_summary', 'staff diagnostic summary exists');

select ok(
  (
    select relrowsecurity
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'learning'
      and relation.relname = 'diagnostic_sessions'
  ),
  'diagnostic_sessions has RLS enabled'
);
select ok(
  (
    select relrowsecurity
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'learning'
      and relation.relname = 'diagnostic_responses'
  ),
  'diagnostic_responses has RLS enabled'
);

select ok(
  has_function_privilege(
    'anon',
    'api.start_diagnostic(text,text,text,text)',
    'EXECUTE'
  ),
  'anonymous clients can execute start_diagnostic'
);
select ok(
  has_function_privilege(
    'anon',
    'api.submit_diagnostic_response(uuid,text,text,text,jsonb,boolean,text,text)',
    'EXECUTE'
  ),
  'anonymous clients can execute submit_diagnostic_response'
);
select ok(
  has_function_privilege(
    'anon',
    'api.complete_diagnostic(uuid)',
    'EXECUTE'
  ),
  'anonymous clients can execute complete_diagnostic'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_sessions', 'INSERT'),
  'anonymous clients cannot insert diagnostic sessions directly'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_sessions', 'SELECT'),
  'anonymous clients cannot select diagnostic sessions directly'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_sessions', 'UPDATE'),
  'anonymous clients cannot update diagnostic sessions directly'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_sessions', 'DELETE'),
  'anonymous clients cannot delete diagnostic sessions directly'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_responses', 'INSERT'),
  'anonymous clients cannot insert diagnostic responses directly'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_responses', 'SELECT'),
  'anonymous clients cannot select diagnostic responses directly'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_responses', 'UPDATE'),
  'anonymous clients cannot update diagnostic responses directly'
);
select ok(
  not has_table_privilege('anon', 'learning.diagnostic_responses', 'DELETE'),
  'anonymous clients cannot delete diagnostic responses directly'
);
select ok(
  not has_table_privilege('anon', 'admin_api.diagnostic_sessions', 'SELECT'),
  'anonymous clients cannot read the staff diagnostic session view'
);

select ok(
  not exists (
    select 1
    from pg_proc as proc
    join pg_namespace as namespace on namespace.oid = proc.pronamespace
    join unnest(proc.proargnames) as argument(name) on true
    where namespace.nspname = 'api'
      and proc.proname in (
        'start_diagnostic',
        'submit_diagnostic_response',
        'complete_diagnostic'
      )
      and argument.name in ('p_is_correct', 'p_score', 'is_correct', 'score')
  ),
  'diagnostic RPCs do not accept client score or is_correct'
);

set local role anon;

select throws_ok(
  $$select api.start_diagnostic('unit-3-cyber-security', '', 'RDY01')$$,
  '22023',
  'INVALID_STUDENT_NAME',
  'blank student name is rejected'
);
select throws_ok(
  $$select api.start_diagnostic('unit-3-cyber-security', 'Ada Lovelace', '')$$,
  '22023',
  'INVALID_STUDENT_ID',
  'blank student ID is rejected'
);
select throws_ok(
  $$select api.start_diagnostic('NOT A HUB', 'Ada Lovelace', 'RDY01')$$,
  '22023',
  'INVALID_HUB_CODE',
  'malformed hub codes are rejected'
);
select throws_ok(
  $$select api.start_diagnostic('unknown-readiness-hub', 'Ada Lovelace', 'RDY01')$$,
  '22023',
  'DIAGNOSTIC_HUB_UNKNOWN',
  'unknown hubs are rejected'
);
select throws_ok(
  $$select api.start_diagnostic(
    'unit-3-cyber-security',
    'Ada Lovelace',
    'RDY01',
    't-level-digital-software-development'
  )$$,
  '22023',
  'DIAGNOSTIC_HUB_COURSE_NOT_LINKED',
  'a hub cannot start against an unlinked course'
);
select throws_ok(
  $$select api.start_diagnostic(
    'unit-3-cyber-security',
    repeat('A', 81),
    'RDY01'
  )$$,
  '22023',
  'INVALID_STUDENT_NAME',
  'oversized student names are rejected'
);

select lives_ok(
  $$select api.start_diagnostic('unit-3-cyber-security', 'Ada Lovelace', 'RDY01')$$,
  'anonymous callers can start a diagnostic without authentication'
);

reset role;

insert into pg_temp.diag_session (label, session_id)
select 'primary', id
from learning.diagnostic_sessions
where student_id = 'RDY01'
order by started_at
limit 1;

select is(
  (
    select count(*)
    from learning.diagnostic_sessions
    where student_id = 'RDY01'
  ),
  1::bigint,
  'started sessions are stored in learning.diagnostic_sessions'
);

select is(
  (
    select course.stable_key
    from learning.diagnostic_sessions as session
    join learning.courses as course on course.id = session.course_id
    where session.id = (select session_id from pg_temp.diag_session where label = 'primary')
  ),
  'ocr-level-3-it',
  'omitted course key resolves through the hub course link'
);

grant select on table pg_temp.diag_session to anon;

set local role anon;

select ok(
  (api.start_diagnostic('unit-3-cyber-security', 'Ada Lovelace', 'RDY02') ? 'id'),
  'start diagnostic returns a generated session id'
);
select ok(
  not (
    api.start_diagnostic('unit-3-cyber-security', 'Ada Lovelace', 'RDY03')
    ? 'score'
  ),
  'start diagnostic does not return a client or server score'
);

select throws_ok(
  $$select api.submit_diagnostic_response(
    '00000000-0000-4000-8000-000000000099',
    'readiness-gist-storage-media',
    'global-information',
    'RDY-GIST-001',
    '{"usb":"local"}'::jsonb,
    false,
    null
  )$$,
  '22023',
  'DIAGNOSTIC_SESSION_NOT_FOUND',
  'responses cannot attach to a nonexistent session'
);

select throws_ok(
  format(
    $sql$select api.submit_diagnostic_response(
      %L::uuid,
      'readiness-gist-storage-media',
      'not-a-unit',
      'RDY-GIST-001',
      '{"usb":"local"}'::jsonb,
      false,
      null
    )$sql$,
    (select session_id from pg_temp.diag_session where label = 'primary')
  ),
  '22023',
  'INVALID_UNIT_KEY',
  'unknown unit keys are rejected'
);

select throws_ok(
  format(
    $sql$select api.submit_diagnostic_response(
      %L::uuid,
      'readiness-gist-storage-media',
      'global-information',
      'RDY-GIST-001',
      null,
      false,
      null
    )$sql$,
    (select session_id from pg_temp.diag_session where label = 'primary')
  ),
  '22023',
  'INVALID_EVIDENCE',
  'null evidence is rejected'
);

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
    (select session_id from pg_temp.diag_session where label = 'primary')
  ),
  'a valid diagnostic response persists'
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
    (select session_id from pg_temp.diag_session where label = 'primary')
  ),
  'repeat submission for the same question upserts rather than duplicating'
);

reset role;

select is(
  (
    select count(*)
    from learning.diagnostic_responses
    where diagnostic_session_id = (
      select session_id from pg_temp.diag_session where label = 'primary'
    )
      and question_key = 'RDY-OPEN-001'
  ),
  1::bigint,
  'one row is stored per session question after a repeated submission'
);

select is(
  (
    select is_not_sure
    from learning.diagnostic_responses
    where diagnostic_session_id = (
      select session_id from pg_temp.diag_session where label = 'primary'
    )
      and question_key = 'RDY-OPEN-001'
  ),
  true,
  'Not sure is derived from evidence even when the client flag is false'
);

select is(
  (
    select is_correct
    from learning.diagnostic_responses
    where diagnostic_session_id = (
      select session_id from pg_temp.diag_session where label = 'primary'
    )
      and question_key = 'RDY-OPEN-001'
  ),
  null,
  'is_correct stays null without an authoritative marking spec'
);

select is(
  (
    select evidence ->> 'optionId'
    from learning.diagnostic_responses
    where diagnostic_session_id = (
      select session_id from pg_temp.diag_session where label = 'primary'
    )
      and question_key = 'RDY-OPEN-001'
  ),
  'not-sure',
  'upsert stores the latest learner evidence'
);

set local role anon;

select lives_ok(
  format(
    $sql$select api.complete_diagnostic(%L::uuid)$sql$,
    (select session_id from pg_temp.diag_session where label = 'primary')
  ),
  'an anonymous caller can complete a diagnostic session'
);

select lives_ok(
  format(
    $sql$select api.complete_diagnostic(%L::uuid)$sql$,
    (select session_id from pg_temp.diag_session where label = 'primary')
  ),
  'completing an already completed session is idempotent'
);

select ok(
  not (
    api.complete_diagnostic(
      (select session_id from pg_temp.diag_session where label = 'primary')
    ) ? 'score'
  ),
  'complete diagnostic does not return or accept a final score'
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
    (select session_id from pg_temp.diag_session where label = 'primary')
  ),
  '22023',
  'DIAGNOSTIC_SESSION_COMPLETED',
  'completed sessions cannot receive further responses'
);

select throws_ok(
  $$select api.complete_diagnostic('00000000-0000-4000-8000-000000000099')$$,
  '22023',
  'DIAGNOSTIC_SESSION_NOT_FOUND',
  'completing a nonexistent session is rejected'
);

select throws_like(
  $$insert into learning.diagnostic_sessions (
    hub_id, course_id, student_name, student_id
  ) values (
    '33000000-0000-4000-8000-000000000001',
    'c3000000-0000-4000-8000-000000000001',
    'Direct Write',
    'DIRECT1'
  )$$,
  '%permission denied%',
  'anonymous clients cannot insert diagnostic sessions directly'
);

reset role;

select isnt(
  (
    select completed_at
    from learning.diagnostic_sessions
    where id = (select session_id from pg_temp.diag_session where label = 'primary')
  ),
  null,
  'completion stores completed_at'
);

select is(
  (
    select status
    from learning.diagnostic_sessions
    where id = (select session_id from pg_temp.diag_session where label = 'primary')
  ),
  'completed',
  'completion sets session status to completed'
);

select is(
  (
    select count(*)
    from learning.diagnostic_sessions
    where student_id in ('RDY01', 'RDY02', 'RDY03')
  ),
  3::bigint,
  'different student IDs create distinct diagnostic sittings'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from learning.diagnostic_sessions),
  0::bigint,
  'authenticated learners cannot read diagnostic sessions through RLS'
);
select is(
  (select count(*) from admin_api.diagnostic_sessions),
  0::bigint,
  'authenticated learners cannot read the staff diagnostic session view'
);
select is(
  (select count(*) from admin_api.diagnostic_summary),
  0::bigint,
  'authenticated learners cannot read diagnostic summary'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from admin_api.diagnostic_sessions),
  0::bigint,
  'ordinary teachers cannot read diagnostic sessions'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select ok(
  exists (
    select 1
    from admin_api.diagnostic_sessions
    where student_id = 'RDY01'
      and status = 'completed'
  ),
  'platform administrators can list diagnostic sessions'
);
select ok(
  exists (
    select 1
    from admin_api.diagnostic_responses
    where student_id = 'RDY01'
      and question_key = 'RDY-OPEN-001'
      and is_correct is null
  ),
  'platform administrators can read diagnostic response detail'
);
select ok(
  exists (
    select 1
    from admin_api.diagnostic_summary
    where hub_code = 'unit-3-cyber-security'
      and course_key = 'ocr-level-3-it'
      and started_count >= 1
      and completed_count >= 1
  ),
  'platform administrators can read diagnostic group summary'
);

reset role;

select finish();
rollback;
