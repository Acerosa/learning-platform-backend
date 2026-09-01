begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
) values (
  'a2000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'test-formative-mark',
  'Synthetic formative mark',
  'test-only',
  'supabase/tests/database/formative_mark_response.test.sql',
  true
), (
  'a2000000-0000-4000-8000-000000000011',
  '80000000-0000-4000-8000-000000000001',
  'test-formative-other',
  'Synthetic formative other activity',
  'test-only',
  'supabase/tests/database/formative_mark_response.test.sql',
  true
);

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count
) values (
  'a2000000-0000-4000-8000-000000000002',
  'a2000000-0000-4000-8000-000000000001',
  '1.0.0',
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  5,
  5
), (
  'a2000000-0000-4000-8000-000000000012',
  'a2000000-0000-4000-8000-000000000011',
  '1.0.0',
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  1,
  1
);

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score,
  formative_retry, formative_max_attempts
) values
  (
    'a2000000-0000-4000-8000-000000000021',
    'a2000000-0000-4000-8000-000000000002',
    'FM-Q1',
    'formative',
    'Formative',
    'single',
    'Single choice',
    1,
    1,
    true,
    null
  ),
  (
    'a2000000-0000-4000-8000-000000000022',
    'a2000000-0000-4000-8000-000000000002',
    'FM-Q2:customer-name',
    'formative',
    'Formative',
    'matching',
    'Classification item',
    2,
    1,
    true,
    null
  ),
  (
    'a2000000-0000-4000-8000-000000000023',
    'a2000000-0000-4000-8000-000000000002',
    'FM-Q3',
    'formative',
    'Formative',
    'text',
    'Review required',
    3,
    1,
    true,
    null
  ),
  (
    'a2000000-0000-4000-8000-000000000024',
    'a2000000-0000-4000-8000-000000000002',
    'FM-Q4',
    'formative',
    'Formative',
    'single',
    'No retry',
    4,
    1,
    false,
    null
  ),
  (
    'a2000000-0000-4000-8000-000000000025',
    'a2000000-0000-4000-8000-000000000002',
    'FM-Q5',
    'formative',
    'Formative',
    'single',
    'Two checks',
    5,
    1,
    true,
    2
  ),
  (
    'a2000000-0000-4000-8000-000000000031',
    'a2000000-0000-4000-8000-000000000012',
    'FM-OTHER',
    'other',
    'Other',
    'single',
    'Other activity question',
    1,
    1,
    true,
    null
  );

insert into learning.question_marking (question_id, spec) values
  (
    'a2000000-0000-4000-8000-000000000021',
    jsonb_build_object('mode', 'single-choice', 'correctOptionId', 'iaas')
  ),
  (
    'a2000000-0000-4000-8000-000000000022',
    jsonb_build_object('mode', 'classification', 'correctCategoryId', 'string')
  ),
  (
    'a2000000-0000-4000-8000-000000000023',
    jsonb_build_object('mode', 'requires_review')
  ),
  (
    'a2000000-0000-4000-8000-000000000024',
    jsonb_build_object('mode', 'single-choice', 'correctOptionId', 'iaas')
  ),
  (
    'a2000000-0000-4000-8000-000000000025',
    jsonb_build_object('mode', 'single-choice', 'correctOptionId', 'iaas')
  ),
  (
    'a2000000-0000-4000-8000-000000000031',
    jsonb_build_object('mode', 'single-choice', 'correctOptionId', 'a')
  );

update learning.activity_versions
set published_at = clock_timestamp()
where id in (
  'a2000000-0000-4000-8000-000000000002',
  'a2000000-0000-4000-8000-000000000012'
);

insert into learning.activity_assignments (
  id, group_id, activity_version_id, required, active
) values (
  'a2000000-0000-4000-8000-000000000041',
  '60000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000002',
  true,
  true
);

select no_plan();

set local role anon;
select throws_like(
  $$select * from api.mark_formative_response(
    'test-formative-mark',
    '1.0.0',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'FM-Q1',
        'response_payload', jsonb_build_object('optionId', 'iaas')
      )
    ),
    'anon-check-1'
  )$$,
  '%permission denied%',
  'unauthenticated callers cannot mark formative responses'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select jsonb_build_object(
      'question_id', question_id,
      'check_number', check_number,
      'awarded_score', awarded_score,
      'max_score', max_score,
      'is_correct', is_correct,
      'requires_review', requires_review,
      'marking_source', marking_source,
      'can_retry', can_retry
    )
    from api.mark_formative_response(
      'test-formative-mark',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'FM-Q1',
          'response_payload', jsonb_build_object('optionId', 'iaas')
        )
      ),
      'student-a-fm-q1-1'
    )
  ),
  jsonb_build_object(
    'question_id', 'FM-Q1',
    'check_number', 1,
    'awarded_score', 1,
    'max_score', 1,
    'is_correct', true,
    'requires_review', false,
    'marking_source', 'server',
    'can_retry', true
  ),
  'valid single-choice check is recorded as check number 1 with a server score'
);

reset role;

select is(
  (
    select student_id
    from learning.formative_checks
    where client_check_id = 'student-a-fm-q1-1'
  ),
  '30000000-0000-4000-8000-000000000001'::uuid,
  'formative check identity is resolved from auth.uid()'
);

select is(
  (
    select jsonb_build_object(
      'awarded_score', awarded_score,
      'is_correct', is_correct,
      'check_number', check_number
    )
    from learning.formative_checks
    where client_check_id = 'student-a-fm-q1-1'
  ),
  jsonb_build_object(
    'awarded_score', 1,
    'is_correct', true,
    'check_number', 1
  ),
  'server score is stored on the formative check'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select count(*) from learning.formative_checks),
  0::bigint,
  'learners cannot select formative_checks through the table'
);

reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select check_number
    from api.mark_formative_response(
      'test-formative-mark',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'FM-Q1',
          'response_payload', jsonb_build_object('optionId', 'saas')
        )
      ),
      'student-a-fm-q1-2'
    )
  ),
  2,
  'the next check number increments'
);

select is(
  (
    select is_correct
    from api.mark_formative_response(
      'test-formative-mark',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'FM-Q1',
          'response_payload', jsonb_build_object('optionId', 'saas')
        )
      ),
      'student-a-fm-q1-2'
    )
  ),
  false,
  'identical replay returns the existing incorrect mark without duplicating'
);

reset role;

select is(
  (
    select count(*)
    from learning.formative_checks
    where student_id = '30000000-0000-4000-8000-000000000001'
      and question_id = 'a2000000-0000-4000-8000-000000000021'
  ),
  2::bigint,
  'idempotent replay does not duplicate formative checks'
);

set local role authenticated;

select throws_ok(
  $$select * from api.mark_formative_response(
    'test-formative-mark',
    '1.0.0',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'FM-Q1',
        'response_payload', jsonb_build_object('optionId', 'iaas')
      )
    ),
    'student-a-fm-q1-2'
  )$$,
  '23505',
  'CLIENT_CHECK_ID_CONFLICT',
  'conflicting replay of a client_check_id is rejected'
);

select is(
  (
    select jsonb_build_object(
      'is_correct', is_correct,
      'awarded_score', awarded_score,
      'requires_review', requires_review
    )
    from api.mark_formative_response(
      'test-formative-mark',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'FM-Q2:customer-name',
          'response_payload', jsonb_build_object('categoryId', 'string', 'itemId', 'customer-name')
        )
      ),
      'student-a-fm-q2-1'
    )
  ),
  jsonb_build_object(
    'is_correct', true,
    'awarded_score', 1,
    'requires_review', false
  ),
  'classification items are marked from the hosted item key'
);

select is(
  (
    select jsonb_build_object(
      'is_correct', is_correct,
      'requires_review', requires_review,
      'awarded_score', awarded_score
    )
    from api.mark_formative_response(
      'test-formative-mark',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'FM-Q3',
          'response_payload', jsonb_build_object('text', 'A valid reflection for review.')
        )
      ),
      'student-a-fm-q3-1'
    )
  ),
  jsonb_build_object(
    'is_correct', null,
    'requires_review', true,
    'awarded_score', 0
  ),
  'requires-review questions return review state without a fake score'
);

reset role;

select is(
  (
    select requires_review
    from learning.formative_checks
    where client_check_id = 'student-a-fm-q3-1'
  ),
  true,
  'requires_review is stored on the formative check'
);

set local role authenticated;

select is(
  (
    select jsonb_build_object(
      'check_number', check_number,
      'can_retry', can_retry,
      'remaining_attempts', remaining_attempts
    )
    from api.mark_formative_response(
      'test-formative-mark',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'FM-Q4',
          'response_payload', jsonb_build_object('optionId', 'saas')
        )
      ),
      'student-a-fm-q4-1'
    )
  ),
  jsonb_build_object(
    'check_number', 1,
    'can_retry', false,
    'remaining_attempts', 0
  ),
  'retry=false allows one formative check only'
);

select throws_ok(
  $$select * from api.mark_formative_response(
    'test-formative-mark',
    '1.0.0',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'FM-Q4',
        'response_payload', jsonb_build_object('optionId', 'iaas')
      )
    ),
    'student-a-fm-q4-2'
  )$$,
  '23514',
  'FORMATIVE_RETRY_LIMIT',
  'retry=false is enforced on the second check'
);

select is(
  (
    select remaining_attempts
    from api.mark_formative_response(
      'test-formative-mark',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'FM-Q5',
          'response_payload', jsonb_build_object('optionId', 'saas')
        )
      ),
      'student-a-fm-q5-1'
    )
  ),
  1,
  'maxAttempts=2 leaves one remaining check after the first'
);

select is(
  (
    select can_retry
    from api.mark_formative_response(
      'test-formative-mark',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'FM-Q5',
          'response_payload', jsonb_build_object('optionId', 'iaas')
        )
      ),
      'student-a-fm-q5-2'
    )
  ),
  false,
  'the second of two allowed checks exhausts retry'
);

select throws_ok(
  $$select * from api.mark_formative_response(
    'test-formative-mark',
    '1.0.0',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'FM-Q5',
        'response_payload', jsonb_build_object('optionId', 'iaas')
      )
    ),
    'student-a-fm-q5-3'
  )$$,
  '23514',
  'FORMATIVE_RETRY_LIMIT',
  'maxAttempts is enforced'
);

select is(
  (
    select can_retry
    from api.mark_formative_response(
      'test-formative-mark',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'FM-Q1',
          'response_payload', jsonb_build_object('optionId', 'iaas')
        )
      ),
      'student-a-fm-q1-3'
    )
  ),
  true,
  'unlimited retry policy remains auditable and allows further checks'
);

select is(
  (
    select count(*)
    from api.mark_formative_response(
      'test-formative-mark',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'FM-Q1',
          'response_payload', jsonb_build_object('optionId', 'iaas')
        )
      ),
      'student-a-fm-q1-3'
    ) as marked
    where to_jsonb(marked) ? 'correctOptionId'
       or to_jsonb(marked) ? 'correctCategoryId'
       or to_jsonb(marked) ? 'spec'
       or to_jsonb(marked) ? 'answerKey'
       or to_jsonb(marked) ? 'markScheme'
       or to_jsonb(marked) ? 'modelAnswer'
  ),
  0::bigint,
  'formative mark rows do not include expected answers or marking specs'
);

reset role;

select is(
  (select count(*) from learning.attempts where student_id = '30000000-0000-4000-8000-000000000001'),
  0::bigint,
  'formative marking does not write an official attempt'
);

set local role authenticated;

select throws_ok(
  $$select * from api.mark_formative_response(
    'test-formative-mark',
    '1.0.0',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'FM-Q1',
        'response_payload', jsonb_build_object('optionId', 'saas'),
        'awarded_score', 1,
        'is_correct', true
      )
    ),
    'student-a-forged-score'
  )$$,
  '22023',
  'FORBIDDEN_SUBMISSION_FIELD',
  'forged awarded_score and is_correct are rejected'
);

select throws_ok(
  $$select * from api.mark_formative_response(
    'test-formative-mark',
    '1.0.0',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'FM-Q1',
        'response_payload', jsonb_build_object('optionId', 'iaas'),
        'learner_id', '30000000-0000-4000-8000-000000000002'
      )
    ),
    'student-a-forged-identity'
  )$$,
  '22023',
  'FORBIDDEN_SUBMISSION_FIELD',
  'forged learner identity on the request is rejected'
);

select throws_ok(
  $$select * from api.mark_formative_response(
    'test-formative-mark',
    '1.0.0',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'UNKNOWN-Q',
        'response_payload', jsonb_build_object('optionId', 'iaas')
      )
    ),
    'student-a-unknown'
  )$$,
  '22023',
  'UNKNOWN_QUESTION',
  'unknown questions fail closed'
);

select throws_ok(
  $$select * from api.mark_formative_response(
    'test-formative-mark',
    '1.0.0',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'FM-OTHER',
        'response_payload', jsonb_build_object('optionId', 'a')
      )
    ),
    'student-a-wrong-activity'
  )$$,
  '23514',
  'QUESTION_WRONG_ACTIVITY_VERSION',
  'questions from another activity version fail closed'
);

select throws_ok(
  $$select * from api.mark_formative_response(
    'test-formative-mark',
    '9.9.9',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'FM-Q1',
        'response_payload', jsonb_build_object('optionId', 'iaas')
      )
    ),
    'student-a-bad-version'
  )$$,
  '22023',
  'INVALID_ACTIVITY_VERSION',
  'unpublished or unknown activity versions fail closed'
);

select throws_ok(
  $$insert into learning.formative_checks (
    client_check_id,
    student_id,
    assignment_id,
    activity_version_id,
    question_id,
    check_number,
    response_payload,
    awarded_score,
    max_score,
    is_correct,
    requires_review,
    marking_source,
    request_hash
  ) values (
    'direct-insert',
    '30000000-0000-4000-8000-000000000001',
    'a2000000-0000-4000-8000-000000000041',
    'a2000000-0000-4000-8000-000000000002',
    'a2000000-0000-4000-8000-000000000021',
    99,
    '{"optionId":"iaas"}'::jsonb,
    1,
    1,
    true,
    false,
    'server',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  )$$,
  '42501',
  'permission denied for table formative_checks',
  'learner cannot direct-insert formative_checks'
);

reset role;

select throws_ok(
  $$update learning.formative_checks
    set is_correct = true
    where client_check_id = 'student-a-fm-q1-2'$$,
  '55000',
  'FORMATIVE_CHECK_IMMUTABLE',
  'prior formative checks cannot be updated'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select * from api.mark_formative_response(
    'test-formative-mark',
    '1.0.0',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'FM-Q1',
        'response_payload', jsonb_build_object('optionId', 'iaas')
      )
    ),
    'student-b-unassigned'
  )$$,
  '42501',
  'ACTIVITY_NOT_ASSIGNED',
  'unassigned enrolled learners cannot mark the activity'
);

reset role;

select finish();
rollback;
