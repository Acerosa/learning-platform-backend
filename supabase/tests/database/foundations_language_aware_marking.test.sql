begin;
select plan(12);

select is(
  (
    select count(*)::integer
    from learning.activities as activity
    join learning.activity_versions as activity_version
      on activity_version.activity_id = activity.id
     and activity_version.version = '2.0.0'
    join learning.questions as question
      on question.activity_version_id = activity_version.id
    where activity.stable_key = 'foundations-programming-diagnostic'
      and learning.resolve_marking_question(question.id) is null
  ),
  0,
  'Foundations programming diagnostic has no unresolved marking gaps'
);

select is(
  (
    select count(*)::integer
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'foundations-programming-diagnostic'
      and activity_version.version = '2.0.0'
      and marking.spec->>'mode' = 'language-variants'
  ),
  25,
  '25 language-variants specs registered for Foundations programming'
);

select is(
  platform.learner_package_sanitisation_version(),
  'lp.strip.v2',
  'learner sanitisation version is lp.strip.v2'
);

select ok(
  platform.strip_learner_answer_keys(
    '{"languages":{"python":{"answers":["11"],"rules":{"required":[]},"answer":"2"}},"prompt":"x"}'::jsonb
  ) = '{"languages":{"python":{}},"prompt":"x"}'::jsonb,
  'strip removes nested language answers/rules/answer keys'
);

select lives_ok(
  $$
    select platform.assert_package_marking_coverage(
      jsonb_build_object(
        'activities',
        jsonb_build_array(
          jsonb_build_object(
            'id', 'foundations-programming-diagnostic',
            'version', '2.0.0'
          )
        )
      )
    )
  $$,
  'Foundations package passes publication marking coverage assert'
);

select is(
  (
    select mark.is_correct
    from learning.mark_evidence_response(
      (
        select question.id
        from learning.questions as question
        join learning.activity_versions as activity_version
          on activity_version.id = question.activity_version_id
        join learning.activities as activity
          on activity.id = activity_version.activity_id
        where activity.stable_key = 'foundations-programming-diagnostic'
          and question.stable_key = 'FOUND-PROG-VAR-002'
      ),
      jsonb_build_object('text', '11', 'programmingLanguage', 'python'),
      1
    ) as mark
  ),
  true,
  'predict-output marks correct for selected language'
);

select is(
  (
    select mark.is_correct
    from learning.mark_evidence_response(
      (
        select question.id
        from learning.questions as question
        join learning.activity_versions as activity_version
          on activity_version.id = question.activity_version_id
        join learning.activities as activity
          on activity.id = activity_version.activity_id
        where activity.stable_key = 'foundations-programming-diagnostic'
          and question.stable_key = 'FOUND-PROG-VAR-002'
      ),
      jsonb_build_object('text', '99', 'programmingLanguage', 'python'),
      1
    ) as mark
  ),
  false,
  'predict-output marks incorrect for wrong output'
);

select is(
  (
    select mark.is_correct
    from learning.mark_evidence_response(
      (
        select question.id
        from learning.questions as question
        join learning.activity_versions as activity_version
          on activity_version.id = question.activity_version_id
        join learning.activities as activity
          on activity.id = activity_version.activity_id
        where activity.stable_key = 'foundations-programming-diagnostic'
          and question.stable_key = 'FOUND-PROG-ITER-003'
      ),
      jsonb_build_object('text', 'number <= 5', 'programmingLanguage', 'python'),
      1
    ) as mark
  ),
  false,
  'javascript code-gap answer is not accepted for python'
);

select is(
  (
    select mark.is_correct
    from learning.mark_evidence_response(
      (
        select question.id
        from learning.questions as question
        join learning.activity_versions as activity_version
          on activity_version.id = question.activity_version_id
        join learning.activities as activity
          on activity.id = activity_version.activity_id
        where activity.stable_key = 'foundations-programming-diagnostic'
          and question.stable_key = 'FOUND-PROG-ITER-003'
      ),
      jsonb_build_object('text', 'number <= 5', 'programmingLanguage', 'javascript'),
      1
    ) as mark
  ),
  true,
  'javascript code-gap answer is accepted for javascript'
);

select is(
  (
    select mark.requires_review
    from learning.mark_evidence_response(
      (
        select question.id
        from learning.questions as question
        join learning.activity_versions as activity_version
          on activity_version.id = question.activity_version_id
        join learning.activities as activity
          on activity.id = activity_version.activity_id
        where activity.stable_key = 'foundations-programming-diagnostic'
          and question.stable_key = 'FOUND-PROG-VAR-002'
      ),
      jsonb_build_object('text', '11'),
      1
    ) as mark
  ),
  true,
  'missing programming language fails closed for language-only variants'
);

select ok(
  learning.language_variant_matches(
    jsonb_build_object(
      'kind', 'code',
      'accepted', '[]'::jsonb,
      'required', jsonb_build_array(jsonb_build_object('pattern', 'score\s*=\s*10', 'flags', '')),
      'prohibited', '[]'::jsonb
    ),
    'score = 10'
  ),
  'code variant matches required regex without execution'
);

select ok(
  not learning.language_variant_matches(
    jsonb_build_object(
      'kind', 'exact',
      'accepted', jsonb_build_array('11'),
      'caseInsensitive', false
    ),
    '12'
  ),
  'exact variant rejects non-accepted output'
);

select * from finish();
rollback;
