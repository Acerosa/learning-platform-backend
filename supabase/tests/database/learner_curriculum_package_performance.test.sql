-- Phase A regression: set-based strip_learner_answer_keys and
-- learner_curriculum_package preserve behaviour and stay private.

begin;
select plan(24);

select is(
  platform.strip_learner_answer_keys(null::jsonb),
  null,
  'null input remains null'
);

select is(
  platform.strip_learner_answer_keys('[]'::jsonb),
  '[]'::jsonb,
  'empty arrays remain empty arrays'
);

select is(
  platform.strip_learner_answer_keys('{}'::jsonb),
  '{}'::jsonb,
  'empty objects remain empty objects'
);

select is(
  platform.strip_learner_answer_keys('["a", null, {"k": 1}]'::jsonb),
  '["a", null, {"k": 1}]'::jsonb,
  'array null members and nested objects are preserved'
);

select is(
  platform.strip_learner_answer_keys(
    '{
      "items": [
        {
          "id": "q1",
          "correctOptionId": "A",
          "options": [{"id": "A"}, {"id": "B"}],
          "nested": {
            "correctOrder": ["x", "y"],
            "prompt": "keep"
          }
        },
        {
          "id": "q2",
          "accepted": ["yes"],
          "checks": [{"pattern": "secret"}],
          "modelAnswer": "secret",
          "markScheme": "secret",
          "answerKey": "secret",
          "correctAnswers": ["secret"],
          "correctOption": "A",
          "correctOptions": ["A"],
          "correctCategoryId": "c1",
          "correctValues": {"field": "secret"},
          "correct": true,
          "feedback": {"correct": "Well done", "incorrect": "Try again"}
        }
      ]
    }'::jsonb
  ),
  '{
    "items": [
      {
        "id": "q1",
        "options": [{"id": "A"}, {"id": "B"}],
        "nested": {"prompt": "keep"}
      },
      {
        "id": "q2",
        "feedback": {"correct": "Well done", "incorrect": "Try again"}
      }
    ]
  }'::jsonb,
  'protected keys are stripped at multiple nesting levels and feedback.correct strings remain'
);

select is(
  platform.strip_learner_answer_keys(
    '{
      "type": "drag-drop",
      "correct": {"find": "learner", "register": "tutor"},
      "label": "keep"
    }'::jsonb
  ),
  '{"type": "drag-drop", "label": "keep"}'::jsonb,
  'object-valued correct maps are stripped'
);

select is(
  platform.strip_learner_answer_keys(
    '{"correct": false, "label": "keep"}'::jsonb
  ),
  '{"label": "keep"}'::jsonb,
  'boolean correct keys are stripped'
);

select is(
  platform.strip_learner_answer_keys(
    '[{"id": "a"}, {"id": "b"}, {"id": "c"}]'::jsonb
  ),
  '[{"id": "a"}, {"id": "b"}, {"id": "c"}]'::jsonb,
  'array ordering is preserved'
);

select is(
  platform.learner_curriculum_package(null, '1.0.0', '0.1.0'),
  jsonb_build_object(
    'schema', 'lp.content.package',
    'schemaVersion', '0.1.0',
    'id', null,
    'version', '1.0.0',
    'activities', '[]'::jsonb
  ),
  'null package becomes an empty stamped learner package'
);

select is(
  platform.learner_curriculum_package('{}'::jsonb, '9.9.9', '0.1.0'),
  jsonb_build_object(
    'schema', 'lp.content.package',
    'schemaVersion', '0.1.0',
    'id', null,
    'version', '9.9.9',
    'activities', '[]'::jsonb
  ),
  'empty package stamps identity fields and empty activities'
);

create temporary table phase_a_sample (
  learner jsonb
) on commit drop;

insert into phase_a_sample (learner)
select platform.learner_curriculum_package(
  '{
    "id": "demo-hub",
    "hub": {"id": "demo-hub"},
    "schemaVersion": "0.1.0",
    "activities": [
      {
        "id": "act-1",
        "version": "1.0.0",
        "blocks": [
          {"type": "heading", "content": {"text": "Title"}},
          {"type": "teacher-note", "content": {"text": "staff only"}},
          {
            "type": "single-choice",
            "content": {
              "prompt": "Q1",
              "correctOptionId": "A",
              "options": [{"id": "A"}, {"id": "B"}]
            }
          },
          {"type": "teacher-note", "content": {"text": "another note"}},
          {
            "type": "short-response",
            "content": {
              "prompt": "Q2",
              "accepted": ["secret"],
              "modelAnswer": "secret"
            }
          }
        ]
      },
      {
        "id": "act-2",
        "version": "2.0.0",
        "blocks": []
      }
    ]
  }'::jsonb,
  '1.2.3',
  '0.1.0'
);

select is(
  (select learner->'version' from phase_a_sample),
  '"1.2.3"'::jsonb,
  'learner package uses the published package version'
);

select is(
  (select learner->>'id' from phase_a_sample),
  'demo-hub',
  'learner package preserves hub identity'
);

select is(
  (select jsonb_array_length(learner->'activities') from phase_a_sample),
  2,
  'activity count is preserved'
);

select is(
  (select learner#>'{activities,0,id}' from phase_a_sample),
  '"act-1"'::jsonb,
  'first activity id is preserved'
);

select is(
  (select learner#>'{activities,0,version}' from phase_a_sample),
  '"1.0.0"'::jsonb,
  'first activity version is preserved'
);

select is(
  (select learner#>'{activities,1,id}' from phase_a_sample),
  '"act-2"'::jsonb,
  'second activity id and order are preserved'
);

select is(
  (select jsonb_array_length(learner#>'{activities,0,blocks}') from phase_a_sample),
  3,
  'teacher-note blocks are removed and interactive blocks remain'
);

select ok(
  not exists (
    select 1
    from phase_a_sample,
    jsonb_array_elements(learner#>'{activities,0,blocks}') as block
    where coalesce(block->>'type', '') = 'teacher-note'
  ),
  'no teacher-note blocks remain in the learner package'
);

select ok(
  (select learner::text from phase_a_sample)
    !~ 'correctOptionId|modelAnswer|"accepted"|markScheme|answerKey',
  'protected answer material is absent from the learner package text'
);

select ok(
  not has_function_privilege('anon', 'platform.strip_learner_answer_keys(jsonb)', 'execute'),
  'anon cannot execute strip_learner_answer_keys'
);

select ok(
  not has_function_privilege('authenticated', 'platform.strip_learner_answer_keys(jsonb)', 'execute'),
  'authenticated cannot execute strip_learner_answer_keys'
);

select ok(
  not has_function_privilege('anon', 'platform.learner_curriculum_package(jsonb, text, text)', 'execute'),
  'anon cannot execute learner_curriculum_package'
);

select ok(
  not has_function_privilege('authenticated', 'platform.learner_curriculum_package(jsonb, text, text)', 'execute'),
  'authenticated cannot execute learner_curriculum_package'
);

select ok(
  has_function_privilege('anon', 'api.published_curriculum_package(text, text)', 'execute')
  and has_function_privilege('authenticated', 'api.published_curriculum_package(text, text)', 'execute'),
  'public curriculum API remains executable for anon and authenticated'
);

select * from finish();
rollback;
