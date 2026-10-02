begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

create function pg_temp.words(p_count integer)
returns text
language sql
as $$
  select coalesce(string_agg('a', ' '), '')
  from generate_series(1, greatest(p_count, 0));
$$;

create function pg_temp.prepare_report(p_id text)
returns void
language plpgsql
as $$
begin
  perform platform.project_knowledge_report_activities(
    jsonb_build_object(
      'activities', jsonb_build_array(
        jsonb_build_object(
          'id', p_id,
          'version', '1.1.0',
          'metadata', jsonb_build_object(
            'title', 'Boundary report',
            'knowledgeReport', jsonb_build_object(
              'placement', 'knowledge-report',
              'durationMinutes', 30,
              'minWords', 500,
              'additionalTimeMinutes', 15,
              'additionalTimeThresholdWords', 400
            )
          ),
          'blocks', jsonb_build_array(
            jsonb_build_object(
              'type', 'short-response',
              'content', jsonb_build_object('questionId', p_id || '-response')
            )
          )
        )
      )
    ),
    'unit-3-cyber-security',
    'ocr-level-3-it',
    p_id
  );

  insert into learning.activity_assignments (
    group_id, activity_version_id, required, active
  )
  select '60000000-0000-4000-8000-000000000001', version.id, true, true
  from learning.activity_versions as version
  join learning.activities as activity on activity.id = version.activity_id
  where activity.stable_key = p_id
    and version.version = '1.1.0'
  on conflict (group_id, activity_version_id) do update set active = true;
end;
$$;

create function pg_temp.expire_standard(p_id text)
returns void
language plpgsql
as $$
begin
  update learning.activity_states as draft
  set started_at = pg_catalog.clock_timestamp() - interval '31 minutes'
  from learning.activity_versions as version
  join learning.activities as activity on activity.id = version.activity_id
  where draft.activity_version_id = version.id
    and activity.stable_key = p_id
    and version.version = '1.1.0'
    and draft.student_id = '30000000-0000-4000-8000-000000000001';
end;
$$;

select is(
  (select count(*) from learning.knowledge_report_test_clock),
  0::bigint,
  'production timing has no frozen clock'
);

select ok(
  abs(extract(epoch from learning.knowledge_report_now() - pg_catalog.clock_timestamp())) < 2,
  'an empty clock uses the real server time'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$ insert into learning.knowledge_report_test_clock (frozen_at) values (pg_catalog.clock_timestamp()) $$,
  '42501',
  null,
  'a learner cannot move the knowledge report clock'
);

reset role;

select pg_temp.prepare_report('u3-kr-boundary-399');
select pg_temp.prepare_report('u3-kr-boundary-400');
select pg_temp.prepare_report('u3-kr-boundary-450');
select pg_temp.prepare_report('u3-kr-boundary-499');
select pg_temp.prepare_report('u3-kr-boundary-500');
select pg_temp.prepare_report('u3-kr-expiry');

set local role authenticated;

select lives_ok(
  $$
    select * from api.save_activity_state(
      'u3-kr-boundary-399',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-boundary-399-response', pg_temp.words(399)
      ))
    )
  $$,
  '399 words are saved during standard time'
);

reset role;
select pg_temp.expire_standard('u3-kr-boundary-399');
set local role authenticated;

select is(
  (
    select state -> 'responses' ->> 'u3-kr-boundary-399-response'
    from api.save_activity_state(
      'u3-kr-boundary-399',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-boundary-399-response', 'this late text must not replace the snapshot'
      ))
    )
  ),
  pg_temp.words(399),
  '399 words stay frozen when standard time expires'
);

select is(
  (
    select state -> 'knowledgeReportPhase' ->> 'phase'
    from api.get_activity_state('u3-kr-boundary-399', '1.1.0')
  ),
  'additional_available',
  '399 words offers additional time'
);

select is(
  (
    select state -> 'knowledgeReportPhase' ->> 'additionalTimeStartedAt'
    from api.get_activity_state('u3-kr-boundary-399', '1.1.0')
  ),
  null,
  'additional time does not start automatically at 399 words'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'u3-kr-boundary-399',
      '1.1.0',
      'kr-399-early',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-kr-boundary-399-response',
        'response_payload', jsonb_build_object('text', pg_temp.words(399))
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  '22023',
  'ADDITIONAL_TIME_NOT_STARTED',
  '399 words is not finally submitted at standard-time expiry'
);

reset role;

select is(
  (
    select evidence.standard_word_count
    from learning.knowledge_report_standard_evidence as evidence
    join learning.activity_versions as version on version.id = evidence.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-399'
      and evidence.student_id = '30000000-0000-4000-8000-000000000001'
  ),
  399,
  'the 399-word snapshot records standardTimeWordCount 399'
);

select is(
  (
    select evidence.additional_time_eligible
    from learning.knowledge_report_standard_evidence as evidence
    join learning.activity_versions as version on version.id = evidence.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-399'
  ),
  true,
  '399 words is eligible for additional time'
);

select is(
  (
    select count(*)
    from learning.attempts as attempt
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-399'
      and attempt.student_id = '30000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'the 399-word report has no final attempt'
);

set local role authenticated;

select lives_ok(
  $$ select * from api.start_knowledge_report_additional_time('u3-kr-boundary-399', '1.1.0') $$,
  'the editor resumes only after the explicit additional-time start'
);

select is(
  (
    select state -> 'responses' ->> 'u3-kr-boundary-399-response'
    from api.save_activity_state(
      'u3-kr-boundary-399',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-boundary-399-response', pg_temp.words(410)
      ))
    )
  ),
  pg_temp.words(410),
  'writing is accepted after additional time has been started'
);

reset role;

select is(
  (
    select evidence.standard_word_count
    from learning.knowledge_report_standard_evidence as evidence
    join learning.activity_versions as version on version.id = evidence.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-399'
  ),
  399,
  'later writing does not change the 399-word snapshot'
);

set local role authenticated;

select lives_ok(
  $$
    select * from api.save_activity_state(
      'u3-kr-boundary-400',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-boundary-400-response', pg_temp.words(400)
      ))
    )
  $$,
  '400 words are saved during standard time'
);

reset role;
select pg_temp.expire_standard('u3-kr-boundary-400');
set local role authenticated;

select is(
  (
    select state -> 'responses' ->> 'u3-kr-boundary-400-response'
    from api.save_activity_state(
      'u3-kr-boundary-400',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-boundary-400-response', 'tampered after the threshold'
      ))
    )
  ),
  pg_temp.words(400),
  'the 400-word standard-time snapshot is frozen'
);

select lives_ok(
  $$
    select * from api.submit_attempt(
      'u3-kr-boundary-400',
      '1.1.0',
      'kr-400-final',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-kr-boundary-400-response',
        'response_payload', jsonb_build_object('text', 'tampered after the threshold')
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  'exactly 400 words finalises from the standard-time snapshot'
);

reset role;

select is(
  (
    select response.response_payload ->> 'text'
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-400'
      and attempt.student_id = '30000000-0000-4000-8000-000000000001'
  ),
  pg_temp.words(400),
  'the final 400-word report is the frozen evidence'
);

select is(
  (
    select (response.response_payload ->> 'wordCount')::integer
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-400'
  ),
  400,
  'the final word count is 400'
);

select is(
  (
    select response.response_payload ->> 'submissionMethod'
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-400'
  ),
  'standard_time_complete',
  '400 words finalises because standard time is complete'
);

select is(
  (
    select (response.response_payload ->> 'additionalTimeStarted')::boolean
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-400'
  ),
  false,
  'additional time is recorded as not used at 400 words'
);

select is(
  (
    select evidence.additional_time_eligible
    from learning.knowledge_report_standard_evidence as evidence
    join learning.activity_versions as version on version.id = evidence.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-400'
  ),
  false,
  'additional time is not offered at exactly 400 words'
);

set local role authenticated;

select throws_ok(
  $$ select * from api.start_knowledge_report_additional_time('u3-kr-boundary-400', '1.1.0') $$,
  '22023',
  'ADDITIONAL_TIME_NOT_AVAILABLE',
  'the learner cannot start additional time after a 400-word finalisation'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'u3-kr-boundary-400',
      '1.1.0',
      'kr-400-second',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-kr-boundary-400-response',
        'response_payload', jsonb_build_object('text', pg_temp.words(400))
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  '23514',
  'TIMED_REPORT_ALREADY_SUBMITTED',
  'a 400-word report cannot be submitted again'
);

select lives_ok(
  $$
    select * from api.save_activity_state(
      'u3-kr-boundary-450',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-boundary-450-response', pg_temp.words(450)
      ))
    )
  $$,
  '450 words are saved during standard time'
);

reset role;
select pg_temp.expire_standard('u3-kr-boundary-450');
set local role authenticated;

select lives_ok(
  $$
    select * from api.submit_attempt(
      'u3-kr-boundary-450',
      '1.1.0',
      'kr-450-final',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-kr-boundary-450-response',
        'response_payload', jsonb_build_object('text', 'later text')
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  '450 words also finalises without additional time'
);

reset role;

select is(
  (
    select (response.response_payload ->> 'wordCount')::integer
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-450'
  ),
  450,
  'a count above the threshold finalises at that frozen count'
);

select is(
  (
    select evidence.additional_time_eligible
    from learning.knowledge_report_standard_evidence as evidence
    join learning.activity_versions as version on version.id = evidence.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-450'
  ),
  false,
  '450 words does not offer additional time'
);

set local role authenticated;

select throws_ok(
  $$
    select * from api.submit_attempt(
      'u3-kr-boundary-499',
      '1.1.0',
      'kr-499-early',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-kr-boundary-499-response',
        'response_payload', jsonb_build_object('text', pg_temp.words(499))
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  '22023',
  'TIMED_REPORT_NOT_STARTED',
  '499 words cannot be submitted before the sitting starts'
);

select lives_ok(
  $$
    select * from api.save_activity_state(
      'u3-kr-boundary-499',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-boundary-499-response', pg_temp.words(499)
      ))
    )
  $$,
  '499 words are saved during standard time'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'u3-kr-boundary-499',
      '1.1.0',
      'kr-499-manual',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-kr-boundary-499-response',
        'response_payload', jsonb_build_object('text', pg_temp.words(499))
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  '22023',
  'MINIMUM_WORDS_NOT_MET',
  'the server rejects a manual submit at 499 words'
);

select lives_ok(
  $$
    select * from api.save_activity_state(
      'u3-kr-boundary-500',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-boundary-500-response', pg_temp.words(500)
      ))
    )
  $$,
  '500 words are saved during standard time'
);

select lives_ok(
  $$
    select * from api.submit_attempt(
      'u3-kr-boundary-500',
      '1.1.0',
      'kr-500-manual',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-kr-boundary-500-response',
        'response_payload', jsonb_build_object('text', pg_temp.words(500))
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  'exactly 500 words can be submitted during standard time'
);

reset role;

select is(
  (
    select (response.response_payload ->> 'wordCount')::integer
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-500'
  ),
  500,
  'a manual 500-word submit records a final word count of 500'
);

select is(
  (
    select response.response_payload ->> 'submissionMethod'
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-500'
  ),
  'manual',
  'a 500-word submit finalises immediately'
);

select is(
  (
    select evidence.additional_time_eligible
    from learning.knowledge_report_standard_evidence as evidence
    join learning.activity_versions as version on version.id = evidence.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-boundary-500'
  ),
  false,
  'a manual 500-word submit does not offer additional time'
);

set local role authenticated;

select throws_ok(
  $$ select * from api.start_knowledge_report_additional_time('u3-kr-boundary-500', '1.1.0') $$,
  '22023',
  'ADDITIONAL_TIME_NOT_AVAILABLE',
  'additional time cannot be started after a manual 500-word submit'
);

select lives_ok(
  $$
    select * from api.save_activity_state(
      'u3-kr-expiry',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-expiry-response', pg_temp.words(348)
      ))
    )
  $$,
  'the expiry sitting starts with 348 words'
);

reset role;
select pg_temp.expire_standard('u3-kr-expiry');
set local role authenticated;

select is(
  (
    select state -> 'knowledgeReportPhase' ->> 'phase'
    from api.get_activity_state('u3-kr-expiry', '1.1.0')
  ),
  'additional_available',
  '348 words offers additional time after standard time'
);

select lives_ok(
  $$ select * from api.start_knowledge_report_additional_time('u3-kr-expiry', '1.1.0') $$,
  'the learner explicitly starts additional time'
);

select lives_ok(
  $$
    select * from api.save_activity_state(
      'u3-kr-expiry',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-expiry-response', pg_temp.words(420)
      ))
    )
  $$,
  'the learner continues writing during additional time'
);

reset role;

insert into learning.knowledge_report_test_clock (frozen_at)
select evidence.additional_time_started_at + interval '16 minutes'
from learning.knowledge_report_standard_evidence as evidence
join learning.activity_versions as version on version.id = evidence.activity_version_id
join learning.activities as activity on activity.id = version.activity_id
where activity.stable_key = 'u3-kr-expiry'
  and evidence.student_id = '30000000-0000-4000-8000-000000000001';

set local role authenticated;

select is(
  (
    select state -> 'responses' ->> 'u3-kr-expiry-response'
    from api.save_activity_state(
      'u3-kr-expiry',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-expiry-response', pg_temp.words(480)
      ))
    )
  ),
  pg_temp.words(420),
  'the editor no longer accepts changes after additional time expires'
);

select lives_ok(
  $$
    select * from api.submit_attempt(
      'u3-kr-expiry',
      '1.1.0',
      'kr-expiry-final',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-kr-expiry-response',
        'response_payload', jsonb_build_object('text', 'this late payload must not become the report')
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  'additional-time expiry submits the latest accepted text'
);

reset role;

select is(
  (
    select response.response_payload ->> 'text'
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-expiry'
  ),
  pg_temp.words(420),
  'the final report is the last accepted additional-time text'
);

select is(
  (
    select (response.response_payload ->> 'wordCount')::integer
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-expiry'
  ),
  420,
  'the final word count is the accepted additional-time count'
);

select is(
  (
    select (response.response_payload ->> 'standardTimeWordCount')::integer
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-expiry'
  ),
  348,
  'the submitted evidence still records 348 standard-time words'
);

select is(
  (
    select (response.response_payload ->> 'additionalTimeUsedSeconds')::integer
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-expiry'
  ),
  900,
  'additional time used is capped at the 15-minute allowance'
);

select is(
  (
    select (response.response_payload ->> 'wordsAddedDuringAdditionalTime')::integer
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-expiry'
  ),
  72,
  'words added during additional time are the net change from 348 to 420'
);

select is(
  (
    select response.response_payload ->> 'submissionMethod'
    from learning.responses as response
    join learning.attempts as attempt on attempt.id = response.attempt_id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-expiry'
  ),
  'additional_time_expired',
  'finalisation identifies additional-time expiry'
);

select is(
  (
    select evidence.standard_word_count
    from learning.knowledge_report_standard_evidence as evidence
    join learning.activity_versions as version on version.id = evidence.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-expiry'
  ),
  348,
  'the standard-time snapshot remains 348 words'
);

select is(
  (
    select evidence.standard_text
    from learning.knowledge_report_standard_evidence as evidence
    join learning.activity_versions as version on version.id = evidence.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-kr-expiry'
  ),
  pg_temp.words(348),
  'the standard-time snapshot text is unchanged'
);

select throws_ok(
  $$
    update learning.knowledge_report_standard_evidence as evidence
    set standard_text = 'changed'
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where evidence.activity_version_id = version.id
      and activity.stable_key = 'u3-kr-expiry'
  $$,
  '55000',
  'STANDARD_TIME_EVIDENCE_IMMUTABLE',
  'expiry does not make the standard-time snapshot writable'
);

set local role authenticated;

select throws_ok(
  $$ select * from api.start_knowledge_report_additional_time('u3-kr-expiry', '1.1.0') $$,
  '22023',
  'ADDITIONAL_TIME_NOT_AVAILABLE',
  'a second additional-time period is impossible'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'u3-kr-expiry',
      '1.1.0',
      'kr-expiry-second',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-kr-expiry-response',
        'response_payload', jsonb_build_object('text', pg_temp.words(420))
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  '23514',
  'TIMED_REPORT_ALREADY_SUBMITTED',
  'a second sitting is impossible after additional-time expiry'
);

select is(
  (
    select status
    from api.save_activity_state(
      'u3-kr-expiry',
      '1.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-kr-expiry-response', 'a new sitting must not start'
      ))
    )
  ),
  'completed',
  'saving after expiry does not open another sitting'
);

select * from finish();
rollback;
