begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(12);

select ok(
  learning.resolve_marking_question((
    select question.id
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'week6-legislation-learning'
      and activity_version.version = '1.0.0'
      and question.stable_key = 'LK1'
  )) is not null,
  'Week 6 legislation learning 1.0.0 still resolves a marking spec'
);

select ok(
  learning.resolve_marking_question((
    select question.id
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'week6-legislation-retrieval'
      and activity_version.version = '1.0.0'
      and question.stable_key = 'LR1'
  )) is not null,
  'Week 6 legislation retrieval 1.0.0 resolves the unbound 1.1.0 spec'
);

select ok(
  learning.resolve_marking_question((
    select question.id
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'week7-session1-retrieval'
      and activity_version.version = '1.0.0'
      and question.stable_key = 'S1R1'
  )) is not null,
  'Week 7 session 1 retrieval 1.0.0 resolves the 1.1.0 marking spec'
);

select ok(
  learning.resolve_marking_question((
    select question.id
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'week7-session2-retrieval'
      and activity_version.version = '1.0.0'
      and question.stable_key = 'S2R1'
  )) is not null,
  'Week 7 session 2 retrieval 1.0.0 resolves despite sourceQuestionId alias mismatch'
);

select ok(
  learning.resolve_marking_question((
    select question.id
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'week7-testing-methods'
      and activity_version.version = '1.0.0'
      and question.stable_key = 'TM1'
  )) is not null,
  'Week 7 testing methods 1.0.0 resolves a marking spec'
);

select ok(
  learning.resolve_marking_question((
    select question.id
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'week7-testing-matching'
      and activity_version.version = '1.0.0'
      and question.stable_key = 'M1'
  )) is not null,
  'Week 7 testing matching 1.0.0 resolves a classification marking spec'
);

select is(
  (
    select is_correct
    from learning.mark_evidence_response(
      (
        select question.id
        from learning.questions as question
        join learning.activity_versions as activity_version
          on activity_version.id = question.activity_version_id
        join learning.activities as activity
          on activity.id = activity_version.activity_id
        where activity.stable_key = 'week7-session1-retrieval'
          and activity_version.version = '1.0.0'
          and question.stable_key = 'S1R1'
      ),
      '{"optionId":"a"}'::jsonb,
      1
    )
  ),
  true,
  'Week 7 session 1 S1R1 marks option a as correct on package version 1.0.0'
);

select is(
  (
    select is_correct
    from learning.mark_evidence_response(
      (
        select question.id
        from learning.questions as question
        join learning.activity_versions as activity_version
          on activity_version.id = question.activity_version_id
        join learning.activities as activity
          on activity.id = activity_version.activity_id
        where activity.stable_key = 'week7-session1-retrieval'
          and activity_version.version = '1.0.0'
          and question.stable_key = 'S1R1'
      ),
      '{"optionId":"b"}'::jsonb,
      1
    )
  ),
  false,
  'Week 7 session 1 S1R1 marks option b as incorrect on package version 1.0.0'
);

select is(
  (
    select requires_review
    from learning.mark_evidence_response(
      (
        select question.id
        from learning.questions as question
        join learning.activity_versions as activity_version
          on activity_version.id = question.activity_version_id
        join learning.activities as activity
          on activity.id = activity_version.activity_id
        where activity.stable_key = 'week7-session1-retrieval'
          and activity_version.version = '1.0.0'
          and question.stable_key = 'S1R5'
      ),
      '{"text":"Northbank should fund the highest residual risk first."}'::jsonb,
      1
    )
  ),
  true,
  'Week 7 written retrieval items stay on requires_review'
);

select is(
  learning.resolve_marking_question((
    select question.id
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'week7-session1-retrieval'
      and activity_version.version = '1.1.0'
      and question.stable_key = 'S1R1'
  )),
  (
    select question.id
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity
      on activity.id = activity_version.activity_id
    where activity.stable_key = 'week7-session1-retrieval'
      and activity_version.version = '1.1.0'
      and question.stable_key = 'S1R1'
  ),
  'Week 7 1.1.0 keeps using its own marking row'
);

select is(
  (
    select marking.spec->>'correctOptionId'
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where activity.stable_key = 'week7-session1-retrieval'
      and activity_version.version = '1.1.0'
      and question.stable_key = 'S1R1'
  ),
  'a',
  'the existing Week 7 S1R1 answer key is unchanged'
);

select is(
  (
    select count(*)
    from learning.activities
    where stable_key like 'week8-%'
  ),
  0::bigint,
  'Unit 3 has no Week 8 activities'
);

select * from finish();
rollback;
