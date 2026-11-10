begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select lives_ok(
  $$
    select platform.project_curriculum_package(
      jsonb_build_object(
        'activities', jsonb_build_array(
          jsonb_build_object(
            'id', 'u3-lo12-timed-mini-mock',
            'version', '0.1.0',
            'metadata', jsonb_build_object(
              'title', 'LO1 and LO2 Timed Mini-Mock',
              'knowledgeReport', jsonb_build_object(
                'placement', 'knowledge-report',
                'assessmentType', 'timed-written-paper',
                'durationMinutes', 20
              )
            ),
            'blocks', jsonb_build_array(
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-timed-mini-mock:mm-1', 'maxMarks', 3)),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-timed-mini-mock:mm-2', 'maxMarks', 4)),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-timed-mini-mock:mm-3', 'maxMarks', 3)),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-timed-mini-mock:mm-4', 'maxMarks', 4)),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-timed-mini-mock:mm-5', 'maxMarks', 6))
            )
          ),
          jsonb_build_object(
            'id', 'u3-paper-regression-report',
            'version', '1.1.0',
            'metadata', jsonb_build_object(
              'title', 'Regression report',
              'knowledgeReport', jsonb_build_object(
                'placement', 'knowledge-report',
                'durationMinutes', 30,
                'minWords', 500,
                'additionalTimeMinutes', 15,
                'additionalTimeThresholdWords', 400
              )
            ),
            'blocks', jsonb_build_array(
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-paper-regression-report-response'))
            )
          )
        ),
        'sessions', '[]'::jsonb,
        'weeks', '[]'::jsonb
      ),
      'unit-3-cyber-security',
      'ocr-level-3-it',
      '9.9.9-paper',
      null
    )
  $$,
  'the five-question paper and the knowledge report both project'
);

select is(
  (
    select version.max_score = 20 and version.question_count = 5
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-lo12-timed-mini-mock'
      and version.version = '0.1.0'
  ),
  true,
  'the paper is one activity scored out of 20'
);

select is(
  (
    select count(*)::integer
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-lo12-timed-mini-mock'
      and marking.spec ->> 'assessmentType' = 'timed-written-paper'
  ),
  5,
  'every paper question carries the timed-written-paper type'
);

select is(
  (
    select marking.spec ->> 'durationSeconds'
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-lo12-timed-mini-mock'
      and marking.spec ->> 'mode' = 'timed-knowledge-report'
  ),
  '1200',
  'one question carries the 20-minute duration'
);

select is(
  (
    select coalesce(marking.spec ->> 'assessmentType', '') = ''
      and (marking.spec ->> 'minWords')::integer = 500
      and (marking.spec ->> 'durationSeconds')::integer = 1800
      and (marking.spec ->> 'additionalTimeSeconds')::integer = 900
      and (marking.spec ->> 'additionalTimeThresholdWords')::integer = 400
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-paper-regression-report'
      and question.stable_key = 'u3-paper-regression-report-response'
  ),
  true,
  'the knowledge report keeps 30 minutes, 500 words and the 15-minute extension'
);

select ok(
  not has_table_privilege('authenticated', 'learning.question_marking', 'select'),
  'a learner cannot select indicative marking'
);

insert into learning.activity_assignments (group_id, activity_version_id, required, active)
select '60000000-0000-4000-8000-000000000001', version.id, true, true
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where activity.stable_key = 'u3-lo12-timed-mini-mock'
  and version.version = '0.1.0'
on conflict (group_id, activity_version_id) do update set active = true;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$
    select api.save_activity_state(
      'u3-lo12-timed-mini-mock',
      '0.1.0',
      jsonb_build_object(
        'startedAt', '2099-01-01T00:00:00Z',
        'responses', jsonb_build_object(
          'u3-lo12-timed-mini-mock:mm-1', 'one',
          'u3-lo12-timed-mini-mock:mm-2', 'two',
          'u3-lo12-timed-mini-mock:mm-3', 'three',
          'u3-lo12-timed-mini-mock:mm-4', 'four',
          'u3-lo12-timed-mini-mock:mm-5', 'five'
        )
      ),
      null,
      null,
      0
    )
  $$,
  'the first save starts one sitting for all five answers'
);

select is(
  (
    select state ->> 'startedAt' is null
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-1' = 'one'
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-5' = 'five'
      and (state -> 'knowledgeReportPhase' ->> 'authoritativeStartedAt') is not null
    from api.save_activity_state(
      'u3-lo12-timed-mini-mock',
      '0.1.0',
      jsonb_build_object(
        'startedAt', '2099-01-01T00:00:00Z',
        'responses', jsonb_build_object(
          'u3-lo12-timed-mini-mock:mm-1', 'one',
          'u3-lo12-timed-mini-mock:mm-2', 'two',
          'u3-lo12-timed-mini-mock:mm-3', 'three',
          'u3-lo12-timed-mini-mock:mm-4', 'four',
          'u3-lo12-timed-mini-mock:mm-5', 'five'
        )
      ),
      null,
      null,
      1
    )
  ),
  true,
  'a client start time is ignored and a refresh returns all five answers'
);

reset role;

update learning.activity_states as draft
set started_at = pg_catalog.clock_timestamp() - interval '21 minutes'
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where draft.activity_version_id = version.id
  and activity.stable_key = 'u3-lo12-timed-mini-mock'
  and draft.student_id = '30000000-0000-4000-8000-000000000001';

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select save_outcome = 'locked'
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-1' = 'one'
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-2' = 'two'
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-3' = 'three'
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-4' = 'four'
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-5' = 'five'
    from api.save_activity_state(
      'u3-lo12-timed-mini-mock',
      '0.1.0',
      jsonb_build_object(
        'responses', jsonb_build_object(
          'u3-lo12-timed-mini-mock:mm-1', 'changed-1',
          'u3-lo12-timed-mini-mock:mm-2', 'changed-2',
          'u3-lo12-timed-mini-mock:mm-3', 'changed-3',
          'u3-lo12-timed-mini-mock:mm-4', 'changed-4',
          'u3-lo12-timed-mini-mock:mm-5', 'changed-5'
        )
      )
    )
  ),
  true,
  'expiry locks every question, not only the timed question'
);

select lives_ok(
  $$
    select * from api.submit_attempt(
      'u3-lo12-timed-mini-mock',
      '0.1.0',
      'paper-sitting-1',
      jsonb_build_array(
        jsonb_build_object('question_id', 'u3-lo12-timed-mini-mock:mm-1', 'response_payload', jsonb_build_object('text', 'late-1')),
        jsonb_build_object('question_id', 'u3-lo12-timed-mini-mock:mm-2', 'response_payload', jsonb_build_object('text', 'late-2')),
        jsonb_build_object('question_id', 'u3-lo12-timed-mini-mock:mm-3', 'response_payload', jsonb_build_object('text', 'late-3')),
        jsonb_build_object('question_id', 'u3-lo12-timed-mini-mock:mm-4', 'response_payload', jsonb_build_object('text', 'late-4')),
        jsonb_build_object('question_id', 'u3-lo12-timed-mini-mock:mm-5', 'response_payload', jsonb_build_object('text', 'late-5'))
      ),
      '/exam-practice/mini-mock/'
    )
  $$,
  'all five questions submit together'
);

select is(
  (
    select attempt.max_score = 20
      and count(response.id) = 5
      and bool_and(response.response_payload ->> 'text' in ('one', 'two', 'three', 'four', 'five'))
    from learning.attempts as attempt
    join learning.responses as response on response.attempt_id = attempt.id
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-lo12-timed-mini-mock'
      and attempt.student_id = '30000000-0000-4000-8000-000000000001'
    group by attempt.max_score
  ),
  true,
  'the submitted script keeps the saved answers and totals 20'
);

select throws_ok(
  $$
    select * from api.submit_attempt(
      'u3-lo12-timed-mini-mock',
      '0.1.0',
      'paper-sitting-2',
      jsonb_build_array(
        jsonb_build_object('question_id', 'u3-lo12-timed-mini-mock:mm-1', 'response_payload', jsonb_build_object('text', 'again'))
      ),
      '/exam-practice/mini-mock/'
    )
  $$,
  '23514',
  'TIMED_REPORT_ALREADY_SUBMITTED',
  'a second sitting cannot be created'
);

select is(
  (select awarded_score is null and feedback_summary is null from api.my_responses limit 1),
  true,
  'marks and feedback stay hidden before release'
);

reset role;

select throws_ok(
  $$select admin_api.set_timed_paper_allowance(
      'u3-paper-regression-report', '1.1.0',
      '30000000-0000-4000-8000-000000000001', 900
    )$$,
  '28000',
  'REVIEW_NOT_AUTHORISED',
  'a learner session cannot grant extra time'
);

reset role;

create temp table paper_mark (response_id uuid, attempt_id uuid);
grant all on table paper_mark to authenticated;
insert into paper_mark (response_id, attempt_id)
select response.id, response.attempt_id
from learning.responses as response
join learning.questions as question on question.id = response.question_id
where question.stable_key = 'u3-lo12-timed-mini-mock:mm-1';

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select admin_api.set_timed_paper_allowance(
      'u3-paper-regression-report', '1.1.0',
      '30000000-0000-4000-8000-000000000001', 900
    )$$,
  '22023',
  'TIMED_PAPER_ALLOWANCE_NOT_SUPPORTED',
  'teacher extra time cannot be applied to the knowledge report'
);

select lives_ok(
  $$select admin_api.review_response(
      response_id, 2, null, 'Develop the consequence.', 'Name the aim and the effect.'
    ) from paper_mark$$,
  'the teacher marks one question with the existing review'
);

reset role;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select awarded_score is null and feedback_summary is null
    from api.my_responses
    where question_key = 'u3-lo12-timed-mini-mock:mm-1'
  ),
  true,
  'a marked script stays hidden until it is released'
);

reset role;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select admin_api.finalise_timed_paper_marking(attempt_id) from paper_mark$$,
  '22023',
  'MARKING_INCOMPLETE',
  'incomplete marking cannot be finalised'
);

select throws_ok(
  $$select admin_api.release_timed_paper_results(attempt_id) from paper_mark$$,
  '22023',
  'MARKING_NOT_FINALISED',
  'results cannot be released before marking is finalised'
);

reset role;

create temp table paper_rest (response_id uuid);
grant all on table paper_rest to authenticated;
insert into paper_rest (response_id)
select response.id
from learning.responses as response
join learning.questions as question on question.id = response.question_id
where question.stable_key like 'u3-lo12-timed-mini-mock:mm-%'
  and question.stable_key <> 'u3-lo12-timed-mini-mock:mm-1';

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$select admin_api.review_response(response_id, 1, null, 'Marked for the paper.', null) from paper_rest$$,
  'the remaining questions are marked with the existing review'
);

select is(
  (
    select marking_status = 'finalised'
    from admin_api.finalise_timed_paper_marking((select attempt_id from paper_mark))
  ),
  true,
  'finalising the completed script is stored'
);

select is(
  (
    select marking_status = 'finalised'
    from admin_api.timed_paper_marking_status((select attempt_id from paper_mark))
  ),
  true,
  'finalisation is still there for a later read'
);

select lives_ok(
  $$select admin_api.release_timed_paper_results(attempt_id) from paper_mark$$,
  'the teacher releases the result after finalisation'
);

select is(
  (
    select marking_status = 'released'
    from admin_api.timed_paper_marking_status((select attempt_id from paper_mark))
  ),
  true,
  'release stays separate from finalisation'
);

reset role;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select awarded_score = 2 and feedback_summary = 'Develop the consequence.'
    from api.my_responses
    where question_key = 'u3-lo12-timed-mini-mock:mm-1'
  ),
  true,
  'the learner sees the released mark and feedback'
);

select is(
  (
    select save_outcome = 'locked'
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-1' = 'one'
    from api.save_activity_state(
      'u3-lo12-timed-mini-mock',
      '0.1.0',
      jsonb_build_object('responses', jsonb_build_object('u3-lo12-timed-mini-mock:mm-1', 'rewritten'))
    )
  ),
  true,
  'a released result cannot be rewritten by the learner'
);

reset role;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from api.my_responses where question_key like 'u3-lo12-timed-mini-mock:%'),
  0::bigint,
  'another student cannot read the submitted answers'
);

reset role;

insert into learning.activity_assignments (group_id, activity_version_id, required, active)
select '60000000-0000-4000-8000-000000000002', version.id, true, true
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where activity.stable_key = 'u3-lo12-timed-mini-mock'
  and version.version = '0.1.0'
on conflict (group_id, activity_version_id) do update set active = true;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select api.save_activity_state(
      'u3-lo12-timed-mini-mock', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-timed-mini-mock:mm-1', 'bypass'
      ))
    )$$,
  '22023',
  'REVISION_REQUIRED',
  'a timed paper cannot be created without a revision'
);

select lives_ok(
  $$select api.save_activity_state(
      'u3-lo12-timed-mini-mock', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-timed-mini-mock:mm-1', 'b1',
        'u3-lo12-timed-mini-mock:mm-2', 'b2',
        'u3-lo12-timed-mini-mock:mm-3', 'b3',
        'u3-lo12-timed-mini-mock:mm-4', 'b4',
        'u3-lo12-timed-mini-mock:mm-5', 'b5'
      )),
      null, null, 0
    )$$,
  'a second student can start a separate sitting'
);

reset role;

create temp table revision_guard (
  started_at timestamptz,
  revision bigint,
  attempts integer
);
grant all on table revision_guard to authenticated;
insert into revision_guard (started_at, revision, attempts)
select draft.started_at, draft.revision, (
  select count(*)::integer
  from learning.attempts as attempt
  where attempt.student_id = draft.student_id
    and attempt.activity_version_id = draft.activity_version_id
)
from learning.activity_states as draft
join learning.activity_versions as version on version.id = draft.activity_version_id
join learning.activities as activity on activity.id = version.activity_id
where activity.stable_key = 'u3-lo12-timed-mini-mock'
  and draft.student_id = '30000000-0000-4000-8000-000000000002';

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select save_outcome = 'saved'
      and revision = 2
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-5' = 'newer'
    from api.save_activity_state(
      'u3-lo12-timed-mini-mock', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-timed-mini-mock:mm-1', 'b1',
        'u3-lo12-timed-mini-mock:mm-5', 'newer'
      )),
      null, null, 1
    )
  ),
  true,
  'a matching revision saves the timed paper and returns the new revision'
);

select is(
  (
    select save_outcome = 'conflict'
      and revision = 2
      and started_at = (select started_at from revision_guard)
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-5' = 'newer'
    from api.save_activity_state(
      'u3-lo12-timed-mini-mock', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-timed-mini-mock:mm-5', 'stale overwrite'
      )),
      null, null, 1
    )
  ),
  true,
  'a stale revision cannot overwrite a newer answer or the deadline'
);

select is(
  (
    select save_outcome = 'saved'
      and revision = 3
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-5' = 'first winner'
    from api.save_activity_state(
      'u3-lo12-timed-mini-mock', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-timed-mini-mock:mm-5', 'first winner'
      )),
      null, null, 2
    )
  ),
  true,
  'the first of two saves against one revision succeeds'
);

select is(
  (
    select save_outcome = 'conflict'
      and revision = 3
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-5' = 'first winner'
    from api.save_activity_state(
      'u3-lo12-timed-mini-mock', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-timed-mini-mock:mm-5', 'second writer'
      )),
      null, null, 2
    )
  ),
  true,
  'two saves cannot both succeed against the same revision'
);

select throws_ok(
  $$select api.save_activity_state(
      'u3-lo12-timed-mini-mock', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-timed-mini-mock:mm-5', 'omitted revision'
      ))
    )$$,
  '22023',
  'REVISION_REQUIRED',
  'omitting the revision cannot bypass a timed paper'
);

reset role;

select is(
  (
    select draft.state_payload -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-5' = 'first winner'
      and draft.revision = 3
      and draft.started_at = (select started_at from revision_guard)
      and (
        select count(*)::integer
        from learning.attempts as attempt
        where attempt.student_id = draft.student_id
          and attempt.activity_version_id = draft.activity_version_id
      ) = (select attempts from revision_guard)
    from learning.activity_states as draft
    join learning.activity_versions as version on version.id = draft.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-lo12-timed-mini-mock'
      and draft.student_id = '30000000-0000-4000-8000-000000000002'
  ),
  true,
  'a rejected save does not change the payload, deadline, or attempt count'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select save_outcome = 'saved'
      and revision = 4
      and state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-5' = 'b5'
    from api.save_activity_state(
      'u3-lo12-timed-mini-mock', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-timed-mini-mock:mm-1', 'b1',
        'u3-lo12-timed-mini-mock:mm-2', 'b2',
        'u3-lo12-timed-mini-mock:mm-3', 'b3',
        'u3-lo12-timed-mini-mock:mm-4', 'b4',
        'u3-lo12-timed-mini-mock:mm-5', 'b5'
      )),
      null, null, 3
    )
  ),
  true,
  'the sitting can continue from the revision returned after the conflict'
);

reset role;

update learning.activity_states as draft
set started_at = pg_catalog.clock_timestamp() - interval '21 minutes'
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where draft.activity_version_id = version.id
  and activity.stable_key = 'u3-lo12-timed-mini-mock'
  and draft.student_id = '30000000-0000-4000-8000-000000000002';

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$select admin_api.set_timed_paper_allowance(
      'u3-lo12-timed-mini-mock', '0.1.0',
      '30000000-0000-4000-8000-000000000002', 600
    )$$,
  'the teacher adds ten minutes for one student'
);

reset role;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-5'
    from api.save_activity_state(
      'u3-lo12-timed-mini-mock', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-timed-mini-mock:mm-1', 'b1',
        'u3-lo12-timed-mini-mock:mm-2', 'b2',
        'u3-lo12-timed-mini-mock:mm-3', 'b3',
        'u3-lo12-timed-mini-mock:mm-4', 'b4',
        'u3-lo12-timed-mini-mock:mm-5', 'b5-extra'
      )),
      null, null, 4
    )
  ),
  'b5-extra',
  'additional time keeps the sitting open for every question'
);

reset role;

update learning.activity_states as draft
set started_at = pg_catalog.clock_timestamp() - interval '31 minutes'
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where draft.activity_version_id = version.id
  and activity.stable_key = 'u3-lo12-timed-mini-mock'
  and draft.student_id = '30000000-0000-4000-8000-000000000002';

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select state -> 'responses' ->> 'u3-lo12-timed-mini-mock:mm-5'
    from api.save_activity_state(
      'u3-lo12-timed-mini-mock', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-timed-mini-mock:mm-5', 'after-allowance'
      ))
    )
  ),
  'b5-extra',
  'the sitting locks again when the extra time has also ended'
);

reset role;

select lives_ok(
  $$select platform.project_curriculum_package(
      jsonb_build_object(
        'activities', jsonb_build_array(
          jsonb_build_object(
            'id', 'u3-lo12-answer-writing', 'version', '0.1.0',
            'metadata', jsonb_build_object('title', 'Answer writing', 'cataloguePlacement', 'unscheduled'),
            'blocks', jsonb_build_array(
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-answer-writing:aw-1')),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-answer-writing:aw-2')),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-answer-writing:aw-3')),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-answer-writing:aw-4')),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-answer-writing:aw-5')),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-answer-writing:aw-6'))
            )
          ),
          jsonb_build_object(
            'id', 'u3-lo12-reflection', 'version', '0.1.0',
            'metadata', jsonb_build_object('title', 'Reflection', 'cataloguePlacement', 'unscheduled'),
            'blocks', jsonb_build_array(
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-reflection:topic')),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-reflection:command')),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-reflection:time')),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-reflection:improve')),
              jsonb_build_object('type', 'short-response', 'content', jsonb_build_object('questionId', 'u3-lo12-reflection:revise'))
            )
          )
        ),
        'sessions', '[]'::jsonb,
        'weeks', '[]'::jsonb
      ),
      'unit-3-cyber-security', 'ocr-level-3-it', '9.9.9-practice', null
    )$$,
  'answer writing and reflection project without a timer'
);

select is(
  (
    select count(*)::integer
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-lo12-reflection'
  ),
  5,
  'reflection keeps the five questions'
);

select is(
  (
    select count(*) = 0
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key in ('u3-lo12-answer-writing', 'u3-lo12-reflection')
      and (marking.spec ? 'durationSeconds' or marking.spec ? 'assessmentType' or marking.spec::text ilike '%indicative%')
  ),
  true,
  'practice and reflection have no timer and no marking guidance'
);

insert into learning.activity_assignments (group_id, activity_version_id, required, active)
select '60000000-0000-4000-8000-000000000001', version.id, false, true
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where activity.stable_key in ('u3-lo12-answer-writing', 'u3-lo12-reflection')
on conflict (group_id, activity_version_id) do update set active = true;

create temp table reflection_link (attempt_id text);
grant all on table reflection_link to authenticated;
insert into reflection_link (attempt_id)
select attempt.id::text
from learning.attempts as attempt
join learning.activity_versions as version on version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = version.activity_id
where activity.stable_key = 'u3-lo12-timed-mini-mock'
  and attempt.student_id = '30000000-0000-4000-8000-000000000001';

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select state -> 'responses' -> 'u3-lo12-answer-writing:aw-1' ->> 'original' = 'Confidentiality.'
      and (state -> 'responses' -> 'u3-lo12-answer-writing:aw-1' ->> 'guidanceViewed')::boolean
    from api.save_activity_state(
      'u3-lo12-answer-writing', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-answer-writing:aw-1', jsonb_build_object(
          'original', 'Confidentiality.',
          'revised', 'Confidentiality, because the shared login exposes files.',
          'guidanceViewed', true
        )
      ), 'completed', false)
    )
  ),
  true,
  'answer writing keeps the original, the comparison and the improved answer'
);

select is(
  (
    select state -> 'responses' -> 'u3-lo12-answer-writing:aw-1' ->> 'original'
    from api.save_activity_state(
      'u3-lo12-answer-writing', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-answer-writing:aw-1', jsonb_build_object(
          'original', 'LATE LOCAL RECONNECTED',
          'revised', 'Confidentiality, because the shared login exposes files.',
          'guidanceViewed', true
        )
      ), 'completed', false),
      clock_timestamp()
    )
  ),
  'LATE LOCAL RECONNECTED',
  'the later answer is stored before an older request returns'
);

select is(
  (
    select state -> 'responses' -> 'u3-lo12-answer-writing:aw-1' ->> 'original'
    from api.save_activity_state(
      'u3-lo12-answer-writing', '0.1.0',
      jsonb_build_object('responses', jsonb_build_object(
        'u3-lo12-answer-writing:aw-1', jsonb_build_object(
          'original', 'STALE OVERWRITE',
          'revised', 'This older request must not replace the later answer.',
          'guidanceViewed', true
        )
      ), 'completed', false),
      clock_timestamp() - interval '2 minutes'
    )
  ),
  'LATE LOCAL RECONNECTED',
  'an older save response does not replace a newer answer'
);

select is(
  (
    select state ->> 'relatedActivityKey' = 'u3-lo12-timed-mini-mock'
      and state -> 'responses' ->> 'u3-lo12-reflection:topic' = 'Threats and vulnerabilities.'
      and state -> 'responses' ->> 'u3-lo12-reflection:revise' = 'Impacts and legal issues.'
    from api.save_activity_state(
      'u3-lo12-reflection', '0.1.0',
      jsonb_build_object(
        'relatedActivityKey', 'u3-lo12-timed-mini-mock',
        'relatedAttemptId', (select attempt_id from reflection_link),
        'responses', jsonb_build_object(
          'u3-lo12-reflection:topic', 'Threats and vulnerabilities.',
          'u3-lo12-reflection:command', 'Explain',
          'u3-lo12-reflection:time', 'Yes, I finished with time remaining.',
          'u3-lo12-reflection:improve', 'Use the scenario.',
          'u3-lo12-reflection:revise', 'Impacts and legal issues.'
        )
      )
    )
  ),
  true,
  'reflection is stored with the mini-mock attempt and does not contain a mark'
);

reset role;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select extra_seconds = 300 and standard_duration_seconds = 1200 and total_seconds = 1500
    from admin_api.set_timed_paper_allowance_for_learner(
      'u3-lo12-timed-mini-mock', '0.1.0', 'SYNTH-0001', 300
    )
  ),
  true,
  'a teacher sets extra time from the student number and sees the total duration'
);

select throws_ok(
  $$select * from admin_api.timed_paper_allowance(
      'u3-paper-regression-report', '1.1.0', 'SYNTH-0001'
    )$$,
  '22023',
  'TIMED_PAPER_ALLOWANCE_NOT_SUPPORTED',
  'the class allowance cannot be read for the knowledge report'
);

select is(
  (
    select count(*)
    from admin_api.class_learners() as learner
    where learner.student_number = 'SYNTH-0001'
  ),
  1::bigint,
  'a teacher can search a learner in an authorised class'
);

select is(
  (
    select count(*)
    from admin_api.class_learners() as learner
    where learner.student_number = 'SYNTH-0002'
  ),
  0::bigint,
  'a teacher cannot search a learner from another class'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*) = 2
    from admin_api.class_learners() as learner
    where learner.student_number in ('SYNTH-0001', 'SYNTH-0002')
  ),
  true,
  'a platform administrator without a class keeps the wider learner list'
);

select * from finish();
rollback;
