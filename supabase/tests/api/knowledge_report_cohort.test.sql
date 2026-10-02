begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select ok(
  pg_get_functiondef(
    'admin_api.list_knowledge_report_cohort(text,text,text,text,text,text,text,text,text,integer,integer)'::regprocedure
  ) not like '%state_payload%',
  'the cohort function does not read activity state payloads'
);

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
      '9.9.9-cohort-test',
      null
    )
  $$,
  'the knowledge report is available for the cohort test'
);

update learning.groups as learner_group
set course_id = course.id
from learning.courses as course
where course.stable_key = 'ocr-level-3-it'
  and learner_group.code in ('TEST-GROUP-A', 'TEST-GROUP-B', 'DEMO-GROUP');

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
select hub.id, learner_group.id, true, 'closed'
from platform.hubs as hub
join learning.groups as learner_group
  on learner_group.code in ('TEST-GROUP-A', 'TEST-GROUP-B', 'DEMO-GROUP')
where hub.hub_code = 'unit-3-cyber-security'
on conflict (hub_id, group_id) do update
set active = true;

insert into learning.activity_assignments (group_id, activity_version_id, required, active)
select learner_group.id, version.id, true, true
from learning.groups as learner_group
join learning.activity_versions as version
  on true
join learning.activities as activity
  on activity.id = version.activity_id
where learner_group.code = 'TEST-GROUP-A'
  and activity.stable_key = 'u3-cyber-security-knowledge-report'
  and version.version = '1.0.0'
on conflict (group_id, activity_version_id) do update
set active = true;

insert into learning.students (
  id, student_number, first_name, display_name, active
) values (
  '30000000-0000-4000-8000-000000000091',
  'SYNTH-KR-IDLE',
  'Idle',
  'Idle Learner',
  true
);

insert into learning.enrolments (
  id, student_id, group_id, joined_on, status
) values (
  '70000000-0000-4000-8000-000000000091',
  '30000000-0000-4000-8000-000000000091',
  '60000000-0000-4000-8000-000000000001',
  '2026-09-01',
  'active'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select ok(
  exists (
    select 1
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security') as row
    where row.student_number = 'SYNTH-0001'
      and row.completion_status = 'not_started'
      and row.activity_key = 'u3-cyber-security-knowledge-report'
  ),
  'an assigned learner with no sitting is not started'
);

select ok(
  exists (
    select 1
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security') as row
    where row.student_number = 'SYNTH-KR-IDLE'
      and row.completion_status = 'not_started'
  ),
  'the complete assigned cohort includes a learner who has not started'
);

select ok(
  not exists (
    select 1
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security') as row
    where row.student_number in ('SYNTH-0002', 'SYNTH-DEMO')
  ),
  'learners without this assignment do not appear'
);

reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$
    select api.save_activity_state(
      'u3-cyber-security-knowledge-report',
      '1.0.0',
      jsonb_build_object(
        'responses', jsonb_build_object(
          'u3-cyber-security-knowledge-report-response',
          'SECRET_DRAFT_SHOULD_NOT_LEAK'
        )
      )
    )
  $$,
  'the learner can start a private sitting'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select completion_status
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security')
    where student_number = 'SYNTH-0001'
  ),
  'in_progress',
  'a sitting inside its duration is in progress'
);

select ok(
  (
    select started_at is not null
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security')
    where student_number = 'SYNTH-0001'
  ),
  'an open sitting exposes its server started_at'
);

select ok(
  position(
    'SECRET_DRAFT_SHOULD_NOT_LEAK' in (
      select row::text
      from admin_api.list_knowledge_report_cohort('unit-3-cyber-security') as row
      where row.student_number = 'SYNTH-0001'
    )
  ) = 0,
  'an in-progress cohort row does not contain the draft'
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

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select completion_status
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security')
    where student_number = 'SYNTH-0001'
  ),
  'time_elapsed',
  'a sitting past its server duration is awaiting finalisation'
);

select ok(
  position(
    'SECRET_DRAFT_SHOULD_NOT_LEAK' in (
      select row::text
      from admin_api.list_knowledge_report_cohort('unit-3-cyber-security') as row
      where row.student_number = 'SYNTH-0001'
    )
  ) = 0,
  'an elapsed sitting still does not expose the draft'
);

reset role;

insert into learning.activity_assignments (group_id, activity_version_id, required, active)
select '60000000-0000-4000-8000-000000000002', version.id, true, true
from learning.activity_versions as version
join learning.activities as activity
  on activity.id = version.activity_id
where activity.stable_key = 'u3-cyber-security-knowledge-report'
  and version.version = '1.0.0'
on conflict (group_id, activity_version_id) do update
set active = true;

insert into learning.attempts (
  id,
  client_attempt_id,
  student_id,
  enrolment_id,
  assignment_id,
  activity_version_id,
  attempt_number,
  status,
  score,
  max_score,
  marking_source,
  evidence_level,
  submission_hash,
  received_at,
  completed_at
)
select
  '93000000-0000-4000-8000-000000000091',
  'knowledge-report-cohort-submitted',
  '30000000-0000-4000-8000-000000000002',
  '70000000-0000-4000-8000-000000000002',
  assignment.id,
  version.id,
  1,
  'completed',
  0,
  1,
  'server',
  'question_level',
  repeat('a', 64),
  clock_timestamp(),
  clock_timestamp()
from learning.activity_assignments as assignment
join learning.activity_versions as version
  on version.id = assignment.activity_version_id
join learning.activities as activity
  on activity.id = version.activity_id
where assignment.group_id = '60000000-0000-4000-8000-000000000002'
  and activity.stable_key = 'u3-cyber-security-knowledge-report';

insert into learning.responses (
  id,
  attempt_id,
  question_id,
  response_payload,
  awarded_score,
  max_score,
  is_correct,
  requires_review,
  marking_source
)
select
  '94000000-0000-4000-8000-000000000091',
  '93000000-0000-4000-8000-000000000091',
  question.id,
  jsonb_build_object(
    'text', 'submitted essay body that staff review later',
    'wordCount', 341,
    'minimumMet', false,
    'elapsedSeconds', 1800,
    'durationSeconds', 1800,
    'submissionMethod', 'timer_expired'
  ),
  0,
  question.max_score,
  null,
  true,
  'server'
from learning.questions as question
join learning.activity_versions as version
  on version.id = question.activity_version_id
join learning.activities as activity
  on activity.id = version.activity_id
where activity.stable_key = 'u3-cyber-security-knowledge-report'
  and question.stable_key = 'u3-cyber-security-knowledge-report-response';

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select ok(
  not exists (
    select 1
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security') as row
    where row.student_number = 'SYNTH-0002'
  ),
  'a teacher does not see another group''s assigned report'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select completion_status
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security')
    where student_number = 'SYNTH-0002'
  ),
  'submitted',
  'a completed report that still needs review is submitted'
);

select is(
  (
    select word_count = 341
      and minimum_met is false
      and elapsed_seconds = 1800
      and submission_method = 'timer_expired'
      and requires_review is true
      and response_id = '94000000-0000-4000-8000-000000000091'
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security')
    where student_number = 'SYNTH-0002'
  ),
  true,
  'submitted metadata is returned without the essay'
);

select ok(
  position(
    'submitted essay body' in (
      select row::text
      from admin_api.list_knowledge_report_cohort('unit-3-cyber-security') as row
      where row.student_number = 'SYNTH-0002'
    )
  ) = 0,
  'the cohort row does not include the submitted essay text'
);

reset role;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{}';

select throws_ok(
  $$
    select * from admin_api.review_knowledge_report(
      '94000000-0000-4000-8000-000000000091',
      'Anonymous feedback'
    )
  $$,
  '28000',
  'AUTHENTICATION_REQUIRED',
  'anonymous callers cannot review a knowledge report'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$
    select * from admin_api.review_knowledge_report(
      '94000000-0000-4000-8000-000000000091',
      'Teacher without this group'
    )
  $$,
  '28000',
  'REVIEW_NOT_AUTHORISED',
  'a teacher outside the group cannot review the report'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select is_correct is null
      and requires_review is false
      and feedback_summary = 'Evidence note only.'
      and response_payload = jsonb_build_object(
        'text', 'submitted essay body that staff review later',
        'wordCount', 341,
        'minimumMet', false,
        'elapsedSeconds', 1800,
        'durationSeconds', 1800,
        'submissionMethod', 'timer_expired'
      )
    from admin_api.review_knowledge_report(
      '94000000-0000-4000-8000-000000000091',
      'Evidence note only.'
    )
  ),
  true,
  'feedback-only review keeps the payload and leaves is_correct null'
);

select is(
  (
    select awarded_score = 0
      and response_payload ->> 'text' = 'submitted essay body that staff review later'
      and requires_review is false
      and marked_at is not null
      and marking_source = 'teacher'
    from learning.responses
    where id = '94000000-0000-4000-8000-000000000091'
  ),
  true,
  'review stores feedback without changing the score or the frozen text'
);

reset role;

select ok(
  exists (
    select 1
    from platform.audit_events
    where event_key = 'learning.response.reviewed'
      and entity_key = '94000000-0000-4000-8000-000000000091'
      and context ->> 'staffReference' = 'SYNTH-TEACHER-B'
      and context ->> 'reviewMode' = 'knowledge-report-feedback'
  ),
  'review records the existing staff identity'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select completion_status = 'reviewed'
      and reviewed_at is not null
      and requires_review is false
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security')
    where student_number = 'SYNTH-0002'
  ),
  true,
  'a reviewed report is returned as reviewed'
);

reset role;

select is(
  learning.assess_knowledge_report_content(
    'The CIA Triad has three parts and helps keep computer systems safe.'
  ) ->> 'overallRelevance',
  'low',
  'a relevant but shallow sentence is not treated as off-topic'
);

select is(
  learning.assess_knowledge_report_content(
    'My favourite football team plays every Saturday and the crowd sings for the whole match.'
  ) ->> 'overallRelevance',
  'very_low',
  'an unrelated response is very low relevance'
);

select is(
  (
    select topic ->> 'coverage'
    from jsonb_array_elements(
      learning.assess_knowledge_report_content('CIA CIA CIA CIA confidentiality confidentiality') -> 'topics'
    ) as topic
    where topic ->> 'key' = 'cia'
  ),
  'not_demonstrated',
  'repeating topic words is not treated as explanation'
);

select is(
  (
    learning.assess_knowledge_report_content('CIA CIA CIA CIA confidentiality confidentiality') ->> 'repetitionFlag'
  )::boolean,
  true,
  'obvious token repetition is flagged for the teacher'
);

select is(
  learning.assess_knowledge_report_content(
    'Confidentiality means only authorised people can read stored information. Integrity means the information stays accurate when it is changed. A threat can harm an organisation when a weakness is left open.'
  ) ->> 'overallRelevance',
  'moderate',
  'a response that explains some areas and not others is partially relevant'
);

select is(
  learning.assess_knowledge_report_content(
    'Cyber security protects information for people and organisations. Confidentiality means only authorised people can read data, and integrity means the data stays accurate. Availability means systems can be used when needed, so the CIA triad explains those three protections. A threat is something that can cause harm, while a vulnerability is a weakness that can be exploited. Malware is a cyber attack that can spread through a network and disrupt services. Phishing is another attack that tricks people into revealing information. The impact on an organisation can include lost data and downtime. A consequence of a successful attack is that services stop and trust is damaged. A firewall protects the network by filtering unwanted traffic, and strong passwords protect accounts from misuse. Encryption protects stored information if a device is stolen. In conclusion, organisations should prioritise monitoring and staff awareness. Overall, cyber security matters because people and services depend on trustworthy systems.'
  ) ->> 'overallRelevance',
  'high',
  'a response that explains several expected areas is high relevance'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select * from admin_api.ensure_knowledge_report_content_review('94000000-0000-4000-8000-000000000091')$$,
  '28000',
  'REVIEW_NOT_AUTHORISED',
  'a teacher outside the group cannot generate the content review'
);

reset role;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$select * from admin_api.ensure_knowledge_report_content_review('94000000-0000-4000-8000-000000000091')$$,
  'authorised staff can store an advisory content review'
);

select is(
  (
    select response_payload ->> 'text' = 'submitted essay body that staff review later'
      and is_correct is null
      and awarded_score = 0
    from learning.responses
    where id = '94000000-0000-4000-8000-000000000091'
  ),
  true,
  'content review does not change the frozen response'
);

select is(
  (
    select overall_relevance
    from admin_api.list_knowledge_report_cohort('unit-3-cyber-security')
    where student_number = 'SYNTH-0002'
  ),
  'very_low',
  'the cohort row exposes stored relevance without the essay'
);

select * from finish();
rollback;
