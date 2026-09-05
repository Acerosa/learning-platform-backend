begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

create temporary table pg_temp.diag_mark (
  label text primary key,
  session_id uuid not null
);

select has_table(
  'learning',
  'diagnostic_question_marking',
  'diagnostic marking specs live in their own table'
);
select has_column(
  'learning',
  'diagnostic_responses',
  'awarded_score',
  'diagnostic responses store server awarded marks'
);
select has_column(
  'learning',
  'diagnostic_responses',
  'max_score',
  'diagnostic responses store server maximum marks'
);
select index_is_unique(
  'learning',
  'diagnostic_sessions',
  'diagnostic_sessions_one_sitting_idx',
  'duplicate sitting protection remains intact'
);

select ok(
  (
    select relrowsecurity
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'learning'
      and relation.relname = 'diagnostic_question_marking'
  ),
  'diagnostic_question_marking has RLS enabled'
);

select ok(
  not has_table_privilege('anon', 'learning.diagnostic_question_marking', 'SELECT'),
  'anonymous clients cannot read diagnostic answer specs'
);
select ok(
  not has_table_privilege('authenticated', 'learning.diagnostic_question_marking', 'SELECT'),
  'authenticated clients cannot read diagnostic answer specs'
);
select ok(
  not has_function_privilege(
    'anon',
    'learning.mark_diagnostic_evidence(jsonb,jsonb,numeric)',
    'EXECUTE'
  ),
  'anonymous clients cannot execute the diagnostic marker'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'learning.mark_diagnostic_evidence(jsonb,jsonb,numeric)',
    'EXECUTE'
  ),
  'authenticated clients cannot execute the diagnostic marker'
);
select ok(
  not has_function_privilege(
    'anon',
    'learning.diagnostic_version_max_score(text,text)',
    'EXECUTE'
  ),
  'anonymous clients cannot execute the diagnostic denominator helper'
);

select is(
  (
    select hub.features ->> 'diagnosticVersion'
    from platform.hubs as hub
    where hub.hub_code = 'level-3-it-year-1-readiness'
  ),
  '1.1.0',
  'readiness hub is version-locked to the 25-question marking contract'
);

select is(
  (
    select count(*)
    from learning.diagnostic_question_marking
    where diagnostic_key = 'level-3-it-year-1-readiness'
      and diagnostic_version = '1.1.0'
  ),
  25::bigint,
  '1.1.0 registers one spec per current diagnostic question'
);

select is(
  (
    select count(*) filter (where scorable)
    from learning.diagnostic_question_marking
    where diagnostic_key = 'level-3-it-year-1-readiness'
      and diagnostic_version = '1.1.0'
  ),
  24::bigint,
  '24 of 25 current questions are scorable'
);

select is(
  (
    select sum(max_score)
    from learning.diagnostic_question_marking
    where diagnostic_key = 'level-3-it-year-1-readiness'
      and diagnostic_version = '1.1.0'
      and scorable
  ),
  24::numeric,
  'current diagnostic maximum is 24, not 25'
);

select is(
  (
    select count(*)
    from learning.diagnostic_question_marking
    where diagnostic_key = 'level-3-it-year-1-readiness'
      and diagnostic_version = '1.0.0'
  ),
  0::bigint,
  'historical 1.0.0 is not seeded with the current 25-question spec'
);

select is(
  (select awarded_score from learning.mark_diagnostic_evidence(
    '{"mode":"single-choice","correctOptionId":"ram"}'::jsonb,
    '"ram"'::jsonb,
    1
  )),
  1::numeric,
  'single-choice string evidence awards a full mark'
);
select is(
  (select is_correct from learning.mark_diagnostic_evidence(
    '{"mode":"single-choice","correctOptionId":"ram"}'::jsonb,
    jsonb_build_object('optionId', 'ram'),
    1
  )),
  true,
  'single-choice object evidence is correct'
);
select is(
  (select awarded_score from learning.mark_diagnostic_evidence(
    '{"mode":"single-choice","correctOptionId":"ram"}'::jsonb,
    jsonb_build_object('optionId', 'ssd', 'is_correct', true, 'awarded_score', 9),
    1
  )),
  0::numeric,
  'learner-supplied correctness cannot inflate a single-choice mark'
);
select is(
  (select awarded_score from learning.mark_diagnostic_evidence(
    '{"mode":"single-choice","correctOptionId":"ram"}'::jsonb,
    '"not-sure"'::jsonb,
    1
  )),
  0::numeric,
  'Not sure is not awarded for single-choice'
);

select is(
  (select is_correct from learning.mark_diagnostic_evidence(
    '{"mode":"multi-select-exact","correctOptions":["file-size","network-busy","connection-speed"]}'::jsonb,
    '["connection-speed","file-size","network-busy"]'::jsonb,
    1
  )),
  true,
  'multi-select exact set is order-independent'
);
select is(
  (select awarded_score from learning.mark_diagnostic_evidence(
    '{"mode":"multi-select-exact","correctOptions":["file-size","network-busy","connection-speed"]}'::jsonb,
    '["file-size","network-busy"]'::jsonb,
    1
  )),
  0::numeric,
  'multi-select partial credit is not awarded'
);

select is(
  (select is_correct from learning.mark_diagnostic_evidence(
    '{"mode":"classification-map","correctAssignments":{"keyboard":"hardware","windows":"software"}}'::jsonb,
    '{"keyboard":"hardware","windows":"software"}'::jsonb,
    1
  )),
  true,
  'classification awards a mark only when every item matches'
);
select is(
  (select awarded_score from learning.mark_diagnostic_evidence(
    '{"mode":"classification-map","correctAssignments":{"keyboard":"hardware","windows":"software"}}'::jsonb,
    '{"keyboard":"hardware","windows":"hardware"}'::jsonb,
    1
  )),
  0::numeric,
  'one wrong classification item scores zero'
);

select is(
  (select is_correct from learning.mark_diagnostic_evidence(
    '{"mode":"unscored"}'::jsonb,
    '"somewhat"'::jsonb,
    0
  )),
  null,
  'intentionally unscored questions stay unmarked'
);

grant select, insert, update, delete on table pg_temp.diag_mark to anon;
grant select on table pg_temp.diag_mark to authenticated;

set local role anon;

select lives_ok(
  $$insert into pg_temp.diag_mark (label, session_id)
    select
      'current',
      (api.start_diagnostic(
        'level-3-it-year-1-readiness',
        'Maya Chen',
        'MARK01'
      ) ->> 'id')::uuid$$,
  'a 1.1.0 readiness sitting can start'
);

select ok(
  not (
    api.submit_diagnostic_response(
      (select session_id from pg_temp.diag_mark where label = 'current'),
      'readiness-fit-running-applications',
      'fundamentals-of-it',
      'RDY-FIT-003',
      '"ram"'::jsonb,
      false,
      null,
      'memory'
    ) ? 'is_correct'
  ),
  'submit does not return is_correct to the learner'
);
select ok(
  not (
    api.submit_diagnostic_response(
      (select session_id from pg_temp.diag_mark where label = 'current'),
      'readiness-fit-running-applications',
      'fundamentals-of-it',
      'RDY-FIT-003',
      jsonb_build_object('optionId', 'ssd', 'is_correct', true, 'awarded_score', 1),
      false,
      null,
      'memory'
    ) ? 'score'
  ),
  'submit does not return a score to the learner'
);

reset role;

select is(
  (
    select is_correct
    from learning.diagnostic_responses
    where diagnostic_session_id = (select session_id from pg_temp.diag_mark where label = 'current')
      and question_key = 'RDY-FIT-003'
  ),
  false,
  'forged client correctness is ignored and the wrong option scores zero'
);
select is(
  (
    select awarded_score
    from learning.diagnostic_responses
    where diagnostic_session_id = (select session_id from pg_temp.diag_mark where label = 'current')
      and question_key = 'RDY-FIT-003'
  ),
  0::numeric,
  'incorrect single-choice stores awarded_score 0'
);

set local role anon;

select lives_ok(
  format(
    $sql$select api.submit_diagnostic_response(
      %L::uuid,
      'readiness-fit-running-applications',
      'fundamentals-of-it',
      'RDY-FIT-003',
      '"ram"'::jsonb,
      false,
      null,
      'memory'
    )$sql$,
    (select session_id from pg_temp.diag_mark where label = 'current')
  ),
  'upsert re-marks the latest evidence'
);
select lives_ok(
  format(
    $sql$select api.submit_diagnostic_response(
      %L::uuid,
      'readiness-opening-confidence',
      'general',
      'RDY-GEN-001',
      '"somewhat"'::jsonb,
      false,
      'somewhat',
      'confidence'
    )$sql$,
    (select session_id from pg_temp.diag_mark where label = 'current')
  ),
  'confidence remains persistable'
);
select lives_ok(
  format(
    $sql$select api.submit_diagnostic_response(
      %L::uuid,
      'readiness-gist-download-time',
      'global-information',
      'RDY-GIST-005',
      '["file-size","network-busy","connection-speed"]'::jsonb,
      false,
      null,
      'transmission'
    )$sql$,
    (select session_id from pg_temp.diag_mark where label = 'current')
  ),
  'correct multi-select persists'
);
select lives_ok(
  format(
    $sql$select api.submit_diagnostic_response(
      %L::uuid,
      'readiness-fit-hardware-software',
      'fundamentals-of-it',
      'RDY-FIT-001',
      '{"keyboard":"hardware","windows":"software","monitor":"hardware","browser":"software","mouse":"hardware","word-processor":"software"}'::jsonb,
      false,
      null,
      'hardware-software'
    )$sql$,
    (select session_id from pg_temp.diag_mark where label = 'current')
  ),
  'correct classification persists'
);

reset role;

select is(
  (
    select is_correct and awarded_score = 1
    from learning.diagnostic_responses
    where diagnostic_session_id = (select session_id from pg_temp.diag_mark where label = 'current')
      and question_key = 'RDY-FIT-003'
  ),
  true,
  'correct single-choice receives the authoritative mark'
);
select is(
  (
    select is_correct
    from learning.diagnostic_responses
    where diagnostic_session_id = (select session_id from pg_temp.diag_mark where label = 'current')
      and question_key = 'RDY-GEN-001'
  ),
  null,
  'confidence stays intentionally unmarked'
);
select is(
  (
    select is_correct and awarded_score = 1
    from learning.diagnostic_responses
    where diagnostic_session_id = (select session_id from pg_temp.diag_mark where label = 'current')
      and question_key = 'RDY-GIST-005'
  ),
  true,
  'exact multi-select receives one mark'
);
select is(
  (
    select is_correct and awarded_score = 1
    from learning.diagnostic_responses
    where diagnostic_session_id = (select session_id from pg_temp.diag_mark where label = 'current')
      and question_key = 'RDY-FIT-001'
  ),
  true,
  'exact classification map receives one mark'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select awarded_score
    from admin_api.diagnostic_sessions
    where session_id = (select session_id from pg_temp.diag_mark where label = 'current')
  ),
  3::numeric,
  'in-progress Admin sessions expose awarded marks so far'
);
select is(
  (
    select max_score
    from admin_api.diagnostic_sessions
    where session_id = (select session_id from pg_temp.diag_mark where label = 'current')
  ),
  24::numeric,
  'Admin session maximum is the version denominator'
);
select is(
  (
    select score_percentage
    from admin_api.diagnostic_sessions
    where session_id = (select session_id from pg_temp.diag_mark where label = 'current')
  ),
  null,
  'in-progress sittings do not expose a completion percentage'
);

set local role anon;

select lives_ok(
  format(
    $sql$select api.complete_diagnostic(%L::uuid)$sql$,
    (select session_id from pg_temp.diag_mark where label = 'current')
  ),
  'completion remains available after marking'
);
select ok(
  not (
    api.complete_diagnostic(
      (select session_id from pg_temp.diag_mark where label = 'current')
    ) ? 'score'
  ),
  'complete_diagnostic still does not return a score'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select awarded_score = 3
      and max_score = 24
      and score_percentage = 12.5
    from admin_api.diagnostic_sessions
    where session_id = (select session_id from pg_temp.diag_mark where label = 'current')
  ),
  true,
  'completed Admin score uses awarded marks against the 24-mark denominator'
);

reset role;

insert into learning.diagnostic_sessions (
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
  'Historical Learner',
  'HIST14',
  hub.hub_code,
  '1.0.0'
from platform.hubs as hub
join platform.hub_course_links as link on link.hub_id = hub.id
join learning.courses as course on course.id = link.course_id
where hub.hub_code = 'level-3-it-year-1-readiness'
  and link.active
limit 1;

insert into pg_temp.diag_mark (label, session_id)
select 'historical', id
from learning.diagnostic_sessions
where student_id = 'HIST14'
  and diagnostic_version = '1.0.0';

set local role anon;

select lives_ok(
  format(
    $sql$select api.submit_diagnostic_response(
      %L::uuid,
      'readiness-fit-running-applications',
      'fundamentals-of-it',
      'RDY-FIT-003',
      '"ram"'::jsonb,
      false,
      null,
      'memory'
    )$sql$,
    (select session_id from pg_temp.diag_mark where label = 'historical')
  ),
  'a 1.0.0 sitting can still store evidence'
);

reset role;

select is(
  (
    select is_correct
    from learning.diagnostic_responses
    where diagnostic_session_id = (select session_id from pg_temp.diag_mark where label = 'historical')
      and question_key = 'RDY-FIT-003'
  ),
  null,
  '1.0.0 sittings cannot use the 1.1.0 answer spec'
);
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select awarded_score
    from admin_api.diagnostic_sessions
    where session_id = (select session_id from pg_temp.diag_mark where label = 'historical')
  ),
  null,
  'Admin score stays unavailable without a versioned spec'
);

reset role;
set local role anon;

select throws_ok(
  $$select api.start_diagnostic(
    'level-3-it-year-1-readiness',
    'Maya Chen',
    'MARK01'
  )$$,
  '22023',
  'DIAGNOSTIC_ALREADY_COMPLETED',
  'completed 1.1.0 sittings still cannot start again'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from admin_api.diagnostic_sessions),
  0::bigint,
  'authenticated learners cannot read Admin diagnostic scores'
);

reset role;

select finish();

rollback;
