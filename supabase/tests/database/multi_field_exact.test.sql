begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
) values (
  'a1000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'test-multi-field-exact',
  'Synthetic multi-field-exact',
  'test-only',
  'supabase/tests/database/multi_field_exact.test.sql',
  true
);

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count
) values (
  'a1000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000001',
  '1.0.0',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  4,
  4
);

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score
) values
  (
    'a1000000-0000-4000-8000-000000000011',
    'a1000000-0000-4000-8000-000000000002',
    'MF-Q1',
    'multi-field',
    'Multi-field',
    'matching',
    'Two-field exact',
    1,
    2
  ),
  (
    'a1000000-0000-4000-8000-000000000012',
    'a1000000-0000-4000-8000-000000000002',
    'MF-Q2',
    'multi-field',
    'Multi-field',
    'matching',
    'Malformed spec',
    2,
    1
  ),
  (
    'a1000000-0000-4000-8000-000000000013',
    'a1000000-0000-4000-8000-000000000002',
    'MF-Q3',
    'multi-field',
    'Multi-field',
    'matching',
    'Case-insensitive pair',
    3,
    1
  ),
  (
    'a1000000-0000-4000-8000-000000000014',
    'a1000000-0000-4000-8000-000000000002',
    'MF-Q4',
    'multi-field',
    'Multi-field',
    'matching',
    'Keys-only spec',
    4,
    1
  );

insert into learning.question_marking (question_id, spec) values
  (
    'a1000000-0000-4000-8000-000000000011',
    jsonb_build_object(
      'mode', 'multi-field-exact',
      'requiredFields', jsonb_build_array('incidentType', 'ciaAim'),
      'correctValues', jsonb_build_object(
        'incidentType', 'malware',
        'ciaAim', 'confidentiality'
      )
    )
  ),
  (
    'a1000000-0000-4000-8000-000000000012',
    jsonb_build_object('mode', 'multi-field-exact', 'correctValues', '{}'::jsonb)
  ),
  (
    'a1000000-0000-4000-8000-000000000013',
    jsonb_build_object(
      'mode', 'multi-field-exact',
      'caseInsensitive', true,
      'requiredFields', jsonb_build_array('incidentType', 'ciaAim'),
      'correctValues', jsonb_build_object(
        'incidentType', 'Phishing',
        'ciaAim', 'Confidentiality'
      )
    )
  ),
  (
    'a1000000-0000-4000-8000-000000000014',
    jsonb_build_object(
      'mode', 'multi-field-exact',
      'correctValues', jsonb_build_object(
        'legislation', 'Computer Misuse Act 1990',
        'duty', 'Unauthorised access to computer material'
      )
    )
  );

select plan(40);

select ok(
  (
    select mark.is_correct
       and mark.awarded_score = 2
       and not mark.requires_review
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000011',
      jsonb_build_object('incidentType', 'malware', 'ciaAim', 'confidentiality'),
      2
    ) as mark
  ),
  'exact two-field match is correct for full max_score'
);

select ok(
  (
    select not mark.is_correct
       and mark.awarded_score = 0
       and not mark.requires_review
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000011',
      jsonb_build_object('incidentType', 'phishing', 'ciaAim', 'confidentiality'),
      2
    ) as mark
  ),
  'wrong first required field is incorrect with no partial credit'
);

select ok(
  (
    select not mark.is_correct
       and mark.awarded_score = 0
       and not mark.requires_review
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000011',
      jsonb_build_object('incidentType', 'malware', 'ciaAim', 'integrity'),
      2
    ) as mark
  ),
  'wrong second required field is incorrect with no partial credit'
);

select ok(
  (
    select not mark.is_correct
       and mark.awarded_score = 0
       and not mark.requires_review
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000011',
      jsonb_build_object('incidentType', 'malware'),
      2
    ) as mark
  ),
  'a missing required field is incorrect'
);

select ok(
  (
    select mark.is_correct
       and mark.awarded_score = 2
       and not mark.requires_review
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000011',
      jsonb_build_object(
        'incidentType', 'malware',
        'ciaAim', 'confidentiality',
        'evidence', 'Free-text learner justification'
      ),
      2
    ) as mark
  ),
  'additional evidence fields do not affect exact matching'
);

select ok(
  (
    select not mark.is_correct
       and mark.awarded_score = 0
       and not mark.requires_review
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000011',
      to_jsonb('not-an-object'::text),
      2
    ) as mark
  ),
  'a malformed non-object response fails closed as incorrect'
);

select ok(
  (
    select mark.is_correct
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000011',
      jsonb_build_object('incidentType', ' malware ', 'ciaAim', 'confidentiality'),
      2
    ) as mark
  ),
  'configured strings are compared after trim'
);

select ok(
  (
    select mark.is_correct
       and mark.awarded_score = 2
       and mark.marking_source = 'server'
    from learning.score_submitted_item(
      'a1000000-0000-4000-8000-000000000011',
      2,
      jsonb_build_object('incidentType', 'malware', 'ciaAim', 'confidentiality'),
      true,
      99,
      true
    ) as mark
  ),
  'forged awarded_score / is_correct cannot inflate a correct multi-field item'
);

select ok(
  (
    select not mark.is_correct
       and mark.awarded_score = 0
       and mark.marking_source = 'server'
    from learning.score_submitted_item(
      'a1000000-0000-4000-8000-000000000011',
      2,
      jsonb_build_object('incidentType', 'phishing', 'ciaAim', 'confidentiality'),
      true,
      99,
      true
    ) as mark
  ),
  'forged awarded_score / is_correct cannot award an incorrect multi-field item'
);

select is(
  platform.strip_learner_answer_keys(
    '{
      "mode": "multi-field-exact",
      "requiredFields": ["legislation", "duty"],
      "correctValues": {
        "legislation": "secret-act",
        "duty": "secret-duty"
      }
    }'::jsonb
  ),
  '{
    "mode": "multi-field-exact",
    "requiredFields": ["legislation", "duty"]
  }'::jsonb,
  'learner packages strip structured correctValues'
);

select is(
  platform.strip_learner_answer_keys(
    '{
      "prompt": "Complete the register",
      "requiredFields": ["asset", "likelihood"]
    }'::jsonb
  ),
  '{
    "prompt": "Complete the register",
    "requiredFields": ["asset", "likelihood"]
  }'::jsonb,
  'teaching requiredFields lists are not stripped as answer keys'
);

select ok(
  (
    select mark.requires_review
       and mark.is_correct is null
       and mark.awarded_score = 0
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000012',
      jsonb_build_object('incidentType', 'malware', 'ciaAim', 'confidentiality'),
      1
    ) as mark
  ),
  'a malformed multi-field-exact spec stays pending evidence'
);

select ok(
  (
    select mark.is_correct
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000013',
      jsonb_build_object('incidentType', 'phishing', 'ciaAim', 'CONFIDENTIALITY'),
      1
    ) as mark
  ),
  'caseInsensitive true compares configured fields without regard to case'
);

select ok(
  (
    select not mark.is_correct
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000011',
      jsonb_build_object('incidentType', 'Malware', 'ciaAim', 'confidentiality'),
      2
    ) as mark
  ),
  'default multi-field-exact comparison remains case-sensitive'
);

select ok(
  (
    select mark.is_correct
    from learning.mark_evidence_response(
      'a1000000-0000-4000-8000-000000000014',
      jsonb_build_object(
        'legislation', 'Computer Misuse Act 1990',
        'duty', 'Unauthorised access to computer material'
      ),
      1
    ) as mark
  ),
  'omitted requiredFields uses the keys of correctValues'
);

select is(
  (
    select (learning.mark_evidence_response(
      question.id,
      jsonb_build_object('optionId', 'B'),
      question.max_score
    )).is_correct
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week2-malware-symptoms'
      and version.version = '1.1.0'
      and question.stable_key = 'MW-Q1'
  ),
  true,
  'single-choice marking is unchanged'
);

select is(
  (
    select (learning.mark_evidence_response(
      question.id,
      jsonb_build_object('categoryId', 'Penetration testing'),
      question.max_score
    )).is_correct
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week7-testing-matching'
      and version.version = '1.1.0'
      and question.stable_key = 'M1'
  ),
  true,
  'classification marking is unchanged'
);

select ok(
  (
    select mark.requires_review
       and mark.is_correct is null
       and mark.awarded_score = 0
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object('text', 'forged', 'is_correct', true, 'awarded_score', 6),
      question.max_score
    ) as mark
    where activity.stable_key = 'week2-ocr-question-practice'
      and version.version = '1.2.0'
      and question.stable_key = 'W2OCR-Q08'
  ),
  'requires_review marking is unchanged'
);

select ok(
  (
    select mark.requires_review
       and mark.is_correct is null
       and mark.awarded_score = 0
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object('text', 'peer reflection'),
      question.max_score
    ) as mark
    where activity.stable_key = 'u3-w01-peer-improvement'
      and version.version = '1.2.0'
      and question.stable_key = 'PM-Q02'
  ),
  'completion marking is unchanged'
);

select ok(
  (
    select mark.is_correct
       and mark.awarded_score = question.max_score
       and not mark.requires_review
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object(
        'legislation', 'Computer Misuse Act 1990',
        'duty', 'Unauthorised access to computer material'
      ),
      question.max_score
    ) as mark
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
      and question.stable_key = 'M1'
  ),
  'legislation 1.2.0 M1 is correct for the hub source pair'
);

select ok(
  (
    select mark.is_correct
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object(
        'legislation', 'Computer Misuse Act 1990',
        'duty', 'Unauthorised access to computer material',
        'evidence', 'Learner notes'
      ),
      question.max_score
    ) as mark
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
      and question.stable_key = 'M1'
  ),
  'legislation 1.2.0 extra evidence does not change a correct pair'
);

select ok(
  (
    select not mark.is_correct
       and mark.awarded_score = 0
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object(
        'legislation', 'Current United Kingdom data protection legislation',
        'duty', 'Unauthorised access to computer material'
      ),
      question.max_score
    ) as mark
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
      and question.stable_key = 'M1'
  ),
  'legislation 1.2.0 M1 rejects the wrong legislation'
);

select ok(
  (
    select not mark.is_correct
       and mark.awarded_score = 0
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object(
        'legislation', 'Computer Misuse Act 1990',
        'duty', 'Unauthorised modification of computer material'
      ),
      question.max_score
    ) as mark
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
      and question.stable_key = 'M1'
  ),
  'legislation 1.2.0 M1 rejects the wrong duty'
);

select ok(
  (
    select mark.requires_review
       and mark.is_correct is null
       and mark.awarded_score = 0
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object(
        'legislation', 'Computer Misuse Act 1990',
        'duty', 'Unauthorised access to computer material'
      ),
      question.max_score
    ) as mark
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.1.0'
      and question.stable_key = 'M1'
  ),
  'legislation 1.1.0 remains requires_review and is not backfilled'
);

select ok(
  not exists (
    select 1
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    where question.id = '22a36c27-1b37-5b80-b9e7-5a9a5c892847'
  ),
  'historical legislation 1.0.0 M1 stays unmarked'
);

select is(
  (
    select question.id::text
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.1.0'
      and question.stable_key = 'M1'
  ),
  '465212d3-8d7e-5157-93b8-437e6af22474',
  'historical legislation 1.1.0 M1 question id is unchanged'
);

select is(
  (
    select question.id::text
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.0.0'
      and question.stable_key = 'M1'
  ),
  '22a36c27-1b37-5b80-b9e7-5a9a5c892847',
  'historical legislation 1.0.0 M1 question id is unchanged'
);

select is(
  (
    select version.id::text
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
  ),
  '19bc924f-db02-55e7-be0b-c5f70f2abece',
  'legislation 1.2.0 uses the deterministic version id'
);

select is(
  (
    select version.question_count
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
  ),
  6,
  'legislation 1.2.0 question_count is 6'
);

select is(
  (
    select count(*)::int
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
  ),
  6,
  'legislation 1.2.0 question rows match question_count'
);

select is(
  (
    select version.max_score
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
  ),
  6::numeric,
  'legislation 1.2.0 max_score remains 6'
);

select is(
  (
    select array_agg(question.stable_key order by question.ordinal)
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
  ),
  array['M1', 'M2', 'M3', 'M4', 'M5', 'M6']::text[],
  'legislation 1.2.0 preserves stable question keys'
);

select is(
  (
    select count(*)::int
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
      and marking.spec->>'mode' = 'multi-field-exact'
      and marking.spec->'correctValues' ? 'legislation'
      and marking.spec->'correctValues' ? 'duty'
  ),
  6,
  'legislation 1.2.0 attaches multi-field-exact specs to every question'
);

select ok(
  (
    select version.published_at is not null
      and version.retired_at is null
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
  ),
  'legislation 1.2.0 is published'
);

select ok(
  not exists (
    select 1
    from learning.attempts as attempt
    join learning.activity_versions as version on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.2.0'
  ),
  'no learner attempts are moved onto legislation 1.2.0'
);

select ok(
  (
    select mark.requires_review
       and mark.is_correct is null
       and mark.awarded_score = 0
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object(
        'incidentType', 'phishing',
        'ciaAim', 'Confidentiality',
        'evidence', 'Fake invoice email.'
      ),
      question.max_score
    ) as mark
    where activity.stable_key = 'u3-w01-incidents'
      and version.version = '1.2.0'
      and question.stable_key = 'INC-Q01'
  ),
  'incidents remain requires_review even for a representative structured response'
);

select ok(
  (
    select mark.requires_review
       and mark.is_correct is null
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object(
        'incidentType', 'malware',
        'ciaAim', 'Confidentiality'
      ),
      question.max_score
    ) as mark
    where activity.stable_key = 'u3-w01-incidents'
      and version.version = '1.2.0'
      and question.stable_key = 'INC-Q01'
  ),
  'incidents do not auto-mark a different incidentType'
);

select ok(
  (
    select mark.requires_review
       and mark.is_correct is null
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    cross join lateral learning.mark_evidence_response(
      question.id,
      jsonb_build_object(
        'incidentType', 'phishing',
        'ciaAim', 'Integrity'
      ),
      question.max_score
    ) as mark
    where activity.stable_key = 'u3-w01-incidents'
      and version.version = '1.2.0'
      and question.stable_key = 'INC-Q01'
  ),
  'incidents do not auto-mark a different ciaAim'
);

select ok(
  not exists (
    select 1
    from learning.activity_versions as version
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'u3-w01-incidents'
      and version.version = '1.3.0'
  ),
  'incidents are not given an invented multi-field version'
);

select is(
  (
    select marking.spec->>'mode'
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week6-legislation-matching'
      and version.version = '1.1.0'
      and question.stable_key = 'M1'
  ),
  'requires_review',
  'published legislation 1.1.0 marking mode is unchanged'
);

select * from finish();
rollback;
