begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_function(
  'admin_api',
  'review_response',
  array['uuid', 'numeric', 'boolean', 'text', 'text'],
  'staff API exposes the teacher review RPC'
);

select has_column(
  'learning',
  'responses',
  'feedback_summary',
  'responses store teacher feedback summaries'
);

select has_column(
  'learning',
  'responses',
  'feedback_next_step',
  'responses store optional next-step guidance'
);

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
) values (
  '93000000-0000-4000-8000-000000000001',
  'phase-8-teacher-review',
  '30000000-0000-4000-8000-000000000001',
  '70000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000001',
  1,
  'completed',
  0,
  1,
  'server',
  'question_level',
  repeat('e', 64),
  clock_timestamp(),
  clock_timestamp()
);

insert into learning.responses (
  id,
  attempt_id,
  question_id,
  response_payload,
  awarded_score,
  max_score,
  is_correct,
  requires_review,
  marking_source,
  marked_at
)
select
  '94000000-0000-4000-8000-000000000101',
  '93000000-0000-4000-8000-000000000001',
  question.id,
  '{"text":"Synthetic written evidence for teacher review."}'::jsonb,
  0,
  question.max_score,
  null,
  true,
  'server',
  clock_timestamp()
from learning.questions as question
where question.activity_version_id = '91000000-0000-4000-8000-000000000001'
order by question.ordinal
limit 1;

select throws_ok(
  $$select * from admin_api.review_response(
    '94000000-0000-4000-8000-000000000101',
    1,
    true,
    'Unauthorised learner review',
    null
  )$$,
  '28000',
  'AUTHENTICATION_REQUIRED',
  'anonymous callers cannot review responses'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select * from admin_api.review_response(
    '94000000-0000-4000-8000-000000000101',
    1,
    true,
    'Learner attempted review',
    null
  )$$,
  '28000',
  'REVIEW_NOT_AUTHORISED',
  'learners cannot review responses'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select * from admin_api.review_response(
    '94000000-0000-4000-8000-000000000101',
    1,
    true,
    'Teacher without group access',
    null
  )$$,
  '28000',
  'REVIEW_NOT_AUTHORISED',
  'teachers without group access are denied'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select * from admin_api.review_response(
    '94000000-0000-4000-8000-000000000101',
    999,
    true,
    'Invalid score',
    null
  )$$,
  '22023',
  'REVIEW_SCORE_INVALID',
  'scores above the question maximum are rejected'
);

select throws_ok(
  $$select * from admin_api.review_response(
    '94000000-0000-4000-8000-000000000101',
    1,
    true,
    '   ',
    null
  )$$,
  '22023',
  'REVIEW_FEEDBACK_REQUIRED',
  'blank feedback is rejected'
);

select is(
  (
    select awarded_score
    from admin_api.review_response(
      '94000000-0000-4000-8000-000000000101',
      1,
      true,
      'Clear explanation of the concept.',
      'Add one workplace example'
    )
  ),
  1::numeric,
  'platform administrators can complete an authorised review'
);

select is(
  (
    select requires_review
    from learning.responses
    where id = '94000000-0000-4000-8000-000000000101'
  ),
  false,
  'successful review clears requires_review'
);

select is(
  (
    select marking_source
    from learning.responses
    where id = '94000000-0000-4000-8000-000000000101'
  ),
  'teacher',
  'successful review records teacher marking source'
);

select is(
  (
    select feedback_summary
    from learning.responses
    where id = '94000000-0000-4000-8000-000000000101'
  ),
  'Clear explanation of the concept.',
  'successful review persists teacher feedback'
);

select is(
  (
    select feedback_next_step
    from learning.responses
    where id = '94000000-0000-4000-8000-000000000101'
  ),
  'Add one workplace example',
  'successful review persists next-step guidance'
);

select is(
  (
    select response_payload ->> 'text'
    from learning.responses
    where id = '94000000-0000-4000-8000-000000000101'
  ),
  'Synthetic written evidence for teacher review.',
  'review never overwrites submitted evidence'
);

select is(
  (
    select idempotent
    from admin_api.review_response(
      '94000000-0000-4000-8000-000000000101',
      1,
      true,
      'Clear explanation of the concept.',
      'Add one workplace example'
    )
  ),
  true,
  'identical retry is idempotent'
);

select ok(
  exists (
    select 1
    from platform.audit_events
    where event_key = 'learning.response.reviewed'
      and entity_key = '94000000-0000-4000-8000-000000000101'
      and outcome = 'succeeded'
      and context ? 'before'
      and context ? 'after'
      and context ? 'staffReference'
  ),
  'successful review writes a before/after audit event without learner PII keys'
);

select is(
  (
    select marking_source
    from learning.attempts
    where id = '93000000-0000-4000-8000-000000000001'
  ),
  'teacher',
  'attempt marking source becomes teacher after review'
);

select is(
  (
    select feedback_summary
    from admin_api.responses
    where response_id = '94000000-0000-4000-8000-000000000101'
  ),
  'Clear explanation of the concept.',
  'admin responses read model exposes teacher feedback'
);

reset role;

insert into learning.responses (
  id,
  attempt_id,
  question_id,
  response_payload,
  awarded_score,
  max_score,
  is_correct,
  requires_review,
  marking_source,
  marked_at
)
select
  '94000000-0000-4000-8000-000000000102',
  '93000000-0000-4000-8000-000000000001',
  question.id,
  '{"text":"Group-scoped teacher review evidence."}'::jsonb,
  0,
  question.max_score,
  null,
  true,
  'server',
  clock_timestamp()
from learning.questions as question
where question.activity_version_id = '91000000-0000-4000-8000-000000000001'
  and question.id <> (
    select question_id
    from learning.responses
    where id = '94000000-0000-4000-8000-000000000101'
  )
order by question.ordinal
limit 1;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select marking_source
    from admin_api.review_response(
      '94000000-0000-4000-8000-000000000102',
      1,
      false,
      'Needs more precision.',
      null
    )
  ),
  'teacher',
  'group-scoped teachers can review responses in their groups'
);

reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*)
    from admin_api.responses
    where response_id = '94000000-0000-4000-8000-000000000101'
  ),
  0::bigint,
  'learners still cannot read staff response evidence after review'
);

reset role;

select * from finish();
rollback;
