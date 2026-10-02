begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select lives_ok(
  $$
    select platform.project_knowledge_report_activities(
      jsonb_build_object(
        'activities', jsonb_build_array(
          jsonb_build_object(
            'id', 'u3-cyber-security-knowledge-report',
            'version', '1.1.0',
            'metadata', jsonb_build_object(
              'title', 'Cyber Security Knowledge Report',
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
                'content', jsonb_build_object(
                  'questionId', 'u3-cyber-security-knowledge-report-response'
                )
              )
            )
          )
        )
      ),
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '9.9.9-additional-time'
    )
  $$,
  'version 1.1.0 projects the additional-time configuration'
);

select is(
  (
    select marking.spec
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-cyber-security-knowledge-report'
      and version.version = '1.1.0'
  ),
  jsonb_build_object(
    'mode', 'timed-knowledge-report',
    'durationSeconds', 1800,
    'minWords', 500,
    'additionalTimeSeconds', 900,
    'additionalTimeThresholdWords', 400
  ),
  'the new version stores standard time, the 500-word target and the internal threshold'
);

insert into learning.activity_assignments (
  group_id, activity_version_id, required, active
)
select '60000000-0000-4000-8000-000000000001', version.id, true, true
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where activity.stable_key = 'u3-cyber-security-knowledge-report'
  and version.version = '1.1.0'
on conflict (group_id, activity_version_id) do update set active = true;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select started_at is not null
    from api.save_activity_state(
      'u3-cyber-security-knowledge-report',
      '1.1.0',
      jsonb_build_object(
        'responses', jsonb_build_object(
          'u3-cyber-security-knowledge-report-response',
          (select string_agg('word', ' ') from generate_series(1, 348))
        )
      )
    )
  ),
  true,
  'the timer starts on the first save'
);

select is(
  (
    select state -> 'knowledgeReportPhase' ->> 'phase'
    from api.get_activity_state('u3-cyber-security-knowledge-report', '1.1.0')
  ),
  'standard',
  'standard time stays open until the server clock expires'
);

reset role;

update learning.activity_states as draft
set started_at = pg_catalog.clock_timestamp() - interval '31 minutes'
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where draft.activity_version_id = version.id
  and activity.stable_key = 'u3-cyber-security-knowledge-report'
  and version.version = '1.1.0'
  and draft.student_id = '30000000-0000-4000-8000-000000000001';

set local role authenticated;

select is(
  (
    select state -> 'responses' ->> 'u3-cyber-security-knowledge-report-response'
    from api.save_activity_state(
      'u3-cyber-security-knowledge-report',
      '1.1.0',
      jsonb_build_object(
        'responses', jsonb_build_object(
          'u3-cyber-security-knowledge-report-response', 'late text should not replace the snapshot'
        )
      )
    )
  ),
  (select string_agg('word', ' ') from generate_series(1, 348)),
  'a late save does not change the accepted standard-time text'
);

reset role;

select is(
  (
    select standard_word_count
    from learning.knowledge_report_standard_evidence as evidence
    join learning.activity_versions as version on version.id = evidence.activity_version_id
    where evidence.student_id = '30000000-0000-4000-8000-000000000001'
      and version.version = '1.1.0'
  ),
  348,
  'the standard-time snapshot records 348 words'
);

set local role authenticated;

select is(
  (
    select state -> 'knowledgeReportPhase' ->> 'phase'
    from api.get_activity_state('u3-cyber-security-knowledge-report', '1.1.0')
  ),
  'additional_available',
  'additional time is offered but not started'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'u3-cyber-security-knowledge-report',
      '1.1.0',
      'kr-additional-skip',
      jsonb_build_array(jsonb_build_object(
        'question_id', 'u3-cyber-security-knowledge-report-response',
        'response_payload', jsonb_build_object('text', 'trying to skip additional time')
      )),
      '/knowledge-reports/cyber-security/'
    )
  $$,
  '22023',
  'ADDITIONAL_TIME_NOT_STARTED',
  'the learner cannot finalise before starting additional time'
);

select lives_ok(
  $$
    select * from api.start_knowledge_report_additional_time(
      'u3-cyber-security-knowledge-report',
      '1.1.0'
    )
  $$,
  'the learner can start the one additional-time period'
);

select throws_ok(
  $$
    select * from api.start_knowledge_report_additional_time(
      'u3-cyber-security-knowledge-report',
      '1.1.0'
    )
  $$,
  '22023',
  'ADDITIONAL_TIME_NOT_AVAILABLE',
  'a second additional-time period is rejected'
);

select is(
  (
    select state -> 'knowledgeReportPhase' ->> 'phase'
    from api.get_activity_state('u3-cyber-security-knowledge-report', '1.1.0')
  ),
  'additional',
  'the editor phase is additional time after the explicit start'
);

select lives_ok(
  $$
    select * from api.save_activity_state(
      'u3-cyber-security-knowledge-report',
      '1.1.0',
      jsonb_build_object(
        'responses', jsonb_build_object(
          'u3-cyber-security-knowledge-report-response',
          (select string_agg('word', ' ') from generate_series(1, 510))
        )
      )
    )
  $$,
  'editing continues during additional time'
);

reset role;

select is(
  (
    select prepared -> 0 -> 'response_payload' ->> 'submissionMethod'
    from (
      select learning.prepare_timed_knowledge_report_submission(
        '30000000-0000-4000-8000-000000000001',
        version.id,
        jsonb_build_array(jsonb_build_object(
          'question_id', 'u3-cyber-security-knowledge-report-response',
          'response_payload', jsonb_build_object(
            'text', (select string_agg('word', ' ') from generate_series(1, 510))
          )
        ))
      ) as prepared
      from learning.activity_versions as version
      join learning.activities as activity on activity.id = version.activity_id
      where activity.stable_key = 'u3-cyber-security-knowledge-report'
        and version.version = '1.1.0'
    ) as submission
  ),
  'manual',
  'manual additional-time submission is recorded'
);

select is(
  (
    select (prepared -> 0 -> 'response_payload' ->> 'standardTimeWordCount')::integer
    from (
      select learning.prepare_timed_knowledge_report_submission(
        '30000000-0000-4000-8000-000000000001',
        version.id,
        jsonb_build_array(jsonb_build_object(
          'question_id', 'u3-cyber-security-knowledge-report-response',
          'response_payload', jsonb_build_object(
            'text', (select string_agg('word', ' ') from generate_series(1, 510))
          )
        ))
      ) as prepared
      from learning.activity_versions as version
      join learning.activities as activity on activity.id = version.activity_id
      where activity.stable_key = 'u3-cyber-security-knowledge-report'
        and version.version = '1.1.0'
    ) as submission
  ),
  348,
  'the prepared response keeps the standard-time word count'
);

select is(
  (
    select (prepared -> 0 -> 'response_payload' ->> 'wordsAddedDuringAdditionalTime')::integer
    from (
      select learning.prepare_timed_knowledge_report_submission(
        '30000000-0000-4000-8000-000000000001',
        version.id,
        jsonb_build_array(jsonb_build_object(
          'question_id', 'u3-cyber-security-knowledge-report-response',
          'response_payload', jsonb_build_object(
            'text', (select string_agg('word', ' ') from generate_series(1, 510))
          )
        ))
      ) as prepared
      from learning.activity_versions as version
      join learning.activities as activity on activity.id = version.activity_id
      where activity.stable_key = 'u3-cyber-security-knowledge-report'
        and version.version = '1.1.0'
    ) as submission
  ),
  162,
  'net words added is the change from the standard-time count'
);

select is(
  (
    select evidence.standard_word_count
    from learning.knowledge_report_standard_evidence as evidence
    where evidence.student_id = '30000000-0000-4000-8000-000000000001'
  ),
  348,
  'submitting does not overwrite the standard-time snapshot'
);

select throws_ok(
  $$
    update learning.knowledge_report_standard_evidence
    set standard_text = 'changed'
    where student_id = '30000000-0000-4000-8000-000000000001'
  $$,
  '55000',
  'STANDARD_TIME_EVIDENCE_IMMUTABLE',
  'the standard-time snapshot cannot be overwritten'
);

select * from finish();
rollback;
