begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'response_payload_size_valid'
      and conrelid = 'learning.responses'::regclass
      and pg_get_constraintdef(oid) like '%131072%'
  ),
  'finished response payloads may be up to 128 KiB'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'formative_check_payload_size_valid'
      and conrelid = 'learning.formative_checks'::regclass
      and pg_get_constraintdef(oid) like '%4096%'
  ),
  'formative check payloads stay at 4 KiB'
);

select ok(
  pg_get_functiondef('api.submit_attempt(text,text,text,jsonb,text,timestamptz,timestamptz,text)'::regprocedure)
    like '%131072%',
  'submit_attempt accepts a 128 KiB response item'
);

select is(learning.count_words(''), 0, 'empty text has no words');
select is(learning.count_words('   one   two' || E'\n' || 'three  '), 3, 'word count ignores empty whitespace');

select lives_ok(
  $$
    select platform.project_curriculum_package(
      jsonb_build_object(
        'activities', jsonb_build_array(
          jsonb_build_object(
            'id', 'u3-cyber-security-knowledge-report',
            'version', '1.0.0',
            'metadata', jsonb_build_object(
              'title', 'Cyber Security Knowledge Report',
              'knowledgeReport', jsonb_build_object(
                'placement', 'knowledge-report',
                'durationMinutes', 30,
                'minWords', 500
              )
            ),
            'blocks', jsonb_build_array(
              jsonb_build_object(
                'type', 'short-response',
                'content', jsonb_build_object(
                  'questionId', 'u3-cyber-security-knowledge-report-response'
                )
              )
            )
          )
        ),
        'sessions', '[]'::jsonb,
        'weeks', '[]'::jsonb
      ),
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '9.9.9-test',
      null
    )
  $$,
  'a knowledge report projects without a week or session'
);

select is(
  (
    select delivery.week_number is null
      and delivery.session_number is null
      and delivery.curriculum_week_id is null
    from learning.activity_delivery as delivery
    join learning.activity_versions as version
      on version.id = delivery.activity_version_id
    join learning.activities as activity
      on activity.id = version.activity_id
    where activity.stable_key = 'u3-cyber-security-knowledge-report'
      and version.version = '1.0.0'
      and delivery.group_id is null
  ),
  true,
  'knowledge report delivery has no week or session'
);

select is(
  (
    select marking.spec ->> 'mode'
    from learning.question_marking as marking
    join learning.questions as question
      on question.id = marking.question_id
    join learning.activity_versions as version
      on version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = version.activity_id
    where activity.stable_key = 'u3-cyber-security-knowledge-report'
      and question.stable_key = 'u3-cyber-security-knowledge-report-response'
  ),
  'timed-knowledge-report',
  'the report question uses the timed knowledge report marking mode'
);

select throws_ok(
  $$
    select platform.project_knowledge_report_activities(
      jsonb_build_object(
        'activities', jsonb_build_array(
          jsonb_build_object(
            'id', 'u3-cyber-security-knowledge-report',
            'version', '1.0.0',
            'metadata', jsonb_build_object(
              'knowledgeReport', jsonb_build_object(
                'placement', 'knowledge-report',
                'durationMinutes', 30,
                'minWords', 500
              )
            ),
            'blocks', jsonb_build_array(
              jsonb_build_object(
                'type', 'short-response',
                'content', jsonb_build_object(
                  'questionId', 'u3-cyber-security-knowledge-report-response'
                )
              )
            )
          )
        ),
        'sessions', jsonb_build_array(
          jsonb_build_object(
            'relationships', jsonb_build_object(
              'activities', jsonb_build_array('u3-cyber-security-knowledge-report')
            )
          )
        )
      ),
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '9.9.9-test'
    )
  $$,
  '22023',
  'CATALOGUE_PROJECTION_FAILED',
  'a knowledge report listed on a session is rejected'
);

insert into learning.activity_assignments (
  group_id, activity_version_id, required, active
)
select
  '60000000-0000-4000-8000-000000000001',
  version.id,
  true,
  true
from learning.activity_versions as version
join learning.activities as activity
  on activity.id = version.activity_id
where activity.stable_key = 'u3-cyber-security-knowledge-report'
  and version.version = '1.0.0'
on conflict (group_id, activity_version_id) do update
set active = true;

create temp table timed_report_clock (
  started_at timestamptz
);
grant all on table timed_report_clock to authenticated;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

insert into timed_report_clock (started_at)
select started_at
from api.save_activity_state(
  'u3-cyber-security-knowledge-report',
  '1.0.0',
  jsonb_build_object(
    'responses', jsonb_build_object(
      'u3-cyber-security-knowledge-report-response', 'hello world'
    )
  )
);

select is(
  (select started_at is not null from timed_report_clock),
  true,
  'the first save records a server started_at'
);

select is(
  (
    select started_at
    from api.save_activity_state(
      'u3-cyber-security-knowledge-report',
      '1.0.0',
      jsonb_build_object(
        'responses', jsonb_build_object(
          'u3-cyber-security-knowledge-report-response', repeat('a', 5000)
        )
      )
    )
  ),
  (select started_at from timed_report_clock),
  'a later save keeps the first started_at'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'u3-cyber-security-knowledge-report',
      '1.0.0',
      'timed-report-manual-short',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-cyber-security-knowledge-report-response',
        'response_payload', jsonb_build_object('text', 'too short')
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  '22023',
  'MINIMUM_WORDS_NOT_MET',
  'manual submit below the minimum is rejected'
);

reset role;

update learning.activity_states as draft
set started_at = pg_catalog.clock_timestamp() - interval '31 minutes'
from learning.activity_versions as version
join learning.activities as activity
  on activity.id = version.activity_id
where draft.activity_version_id = version.id
  and activity.stable_key = 'u3-cyber-security-knowledge-report'
  and draft.student_id = '30000000-0000-4000-8000-000000000001';

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select state -> 'responses' ->> 'u3-cyber-security-knowledge-report-response'
    from api.save_activity_state(
      'u3-cyber-security-knowledge-report',
      '1.0.0',
      jsonb_build_object(
        'responses', jsonb_build_object(
          'u3-cyber-security-knowledge-report-response', 'should not stick'
        )
      )
    )
  ),
  repeat('a', 5000),
  'a save after the sitting ends does not replace the accepted draft'
);

select lives_ok(
  $$
    select * from api.submit_attempt(
      'u3-cyber-security-knowledge-report',
      '1.0.0',
      'timed-report-expired-1',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-cyber-security-knowledge-report-response',
        'response_payload', jsonb_build_object('text', 'ignored after expiry')
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  'timer expiry submits the accepted draft even below 500 words'
);

select lives_ok(
  $$
    select * from api.submit_attempt(
      'u3-cyber-security-knowledge-report',
      '1.0.0',
      'timed-report-expired-1',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-cyber-security-knowledge-report-response',
        'response_payload', jsonb_build_object('text', 'ignored after expiry')
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  'retrying the same client attempt is idempotent'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'u3-cyber-security-knowledge-report',
      '1.0.0',
      'timed-report-second-sitting',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-cyber-security-knowledge-report-response',
        'response_payload', jsonb_build_object('text', 'another sitting')
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  '23514',
  'TIMED_REPORT_ALREADY_SUBMITTED',
  'a second sitting is rejected'
);

reset role;

select is(
  (
    select response.response_payload ->> 'text'
    from learning.responses as response
    join learning.attempts as attempt
      on attempt.id = response.attempt_id
    where attempt.client_attempt_id = 'timed-report-expired-1'
  ),
  repeat('a', 5000),
  'timer expiry stores the latest accepted draft'
);

select is(
  (
    select response.response_payload ->> 'submissionMethod'
    from learning.responses as response
    join learning.attempts as attempt
      on attempt.id = response.attempt_id
    where attempt.client_attempt_id = 'timed-report-expired-1'
  ),
  'timer_expired',
  'timer expiry records the submission method'
);

select is(
  (
    select (response.response_payload ->> 'wordCount')::integer
    from learning.responses as response
    join learning.attempts as attempt
      on attempt.id = response.attempt_id
    where attempt.client_attempt_id = 'timed-report-expired-1'
  ),
  1,
  'the stored word count is computed on the server'
);

select is(
  (
    select (response.response_payload ->> 'minimumMet')::boolean
    from learning.responses as response
    join learning.attempts as attempt
      on attempt.id = response.attempt_id
    where attempt.client_attempt_id = 'timed-report-expired-1'
  ),
  false,
  'expiry below the minimum records that the minimum was not met'
);

select is(
  (
    select (response.response_payload ->> 'durationSeconds')::integer
    from learning.responses as response
    join learning.attempts as attempt
      on attempt.id = response.attempt_id
    where attempt.client_attempt_id = 'timed-report-expired-1'
  ),
  1800,
  'the stored duration is the configured 30 minutes'
);

select is(
  (
    select (response.response_payload ->> 'elapsedSeconds')::integer
        = (response.response_payload ->> 'durationSeconds')::integer
    from learning.responses as response
    join learning.attempts as attempt
      on attempt.id = response.attempt_id
    where attempt.client_attempt_id = 'timed-report-expired-1'
  ),
  true,
  'elapsed time is capped at the configured duration'
);

select is(
  (
    select response.requires_review and response.is_correct is null
    from learning.responses as response
    join learning.attempts as attempt
      on attempt.id = response.attempt_id
    where attempt.client_attempt_id = 'timed-report-expired-1'
  ),
  true,
  'the report stays pending review without a pass or fail mark'
);

select ok(
  (
    select octet_length(response.response_payload::text) > 4096
    from learning.responses as response
    join learning.attempts as attempt
      on attempt.id = response.attempt_id
    where attempt.client_attempt_id = 'timed-report-expired-1'
  ),
  'a response longer than 4 KiB is stored'
);

select * from finish();
rollback;
