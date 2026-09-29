begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(20);

select is(
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'MW-Q1', 'single-choice', 'Which type?',
    '[{"id":"a","label":"Virus"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'mw-q1', 'single-choice', '  Which   type?  ',
    '[{"id":"a","label":"Virus"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  'identical structures share a fingerprint, including whitespace and key case'
);

select isnt(
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'MW-Q1', 'single-choice', 'Which type?',
    '[{"id":"a","label":"Virus"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'MW-Q1', 'single-choice', 'Which category?',
    '[{"id":"a","label":"Virus"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  'a changed prompt rejects the old fingerprint'
);

select isnt(
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'MW-Q1', 'single-choice', 'Which type?',
    '[{"id":"a","label":"Virus"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'MW-Q1', 'single-choice', 'Which type?',
    '[{"id":"a","label":"Malware"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  'a changed option label rejects the old fingerprint'
);

select isnt(
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'MW-Q1', 'single-choice', 'Which type?',
    '[{"id":"a","label":"Virus"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'MW-Q1', 'single-choice', 'Which type?',
    '[{"id":"a","label":"Virus"},{"id":"c","label":"Worm"}]'::jsonb
  ),
  'a changed option id rejects the old fingerprint'
);

select isnt(
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'MW-Q1', 'single-choice', 'Which type?',
    '[{"id":"a","label":"Virus"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  learning.question_structure_fingerprint(
    'other-activity', 'MW-Q1', 'single-choice', 'Which type?',
    '[{"id":"a","label":"Virus"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  'the same question key in another activity does not collide'
);

select isnt(
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'MW-Q1', 'single-choice', 'Which type?',
    '[{"id":"a","label":"Virus"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  learning.question_structure_fingerprint(
    'week2-malware-symptoms', 'MW-Q2', 'single-choice', 'Which type?',
    '[{"id":"a","label":"Virus"},{"id":"b","label":"Worm"}]'::jsonb
  ),
  'adding another question key does not reuse the first fingerprint'
);

select is(
  learning.block_question_fingerprint(
    'week4-motivations-learning',
    'MOTKC1',
    '{"type":"single-choice","content":{"sourceQuestionId":"mot-kc1","prompt":"Which statement?","options":[{"id":"a","label":"Phishing"},{"id":"b","label":"Publicity"}]}}'::jsonb
  ),
  learning.question_structure_fingerprint(
    'week4-motivations-learning',
    'MOTKC1',
    'single-choice',
    'Which statement?',
    '[{"id":"a","label":"Phishing"},{"id":"b","label":"Publicity"}]'::jsonb
  ),
  'a hyphenated learner question id matches the catalogue key'
);

select ok(
  learning.block_question_fingerprint(
    'week2-ocr-question-practice',
    'W2OCR-Q01',
    '{"type":"single-choice","content":{"sourceQuestionId":"ocr-q1","prompt":"Which?","options":[{"id":"a","label":"One"}]}}'::jsonb
  ) is null,
  'a different local question id does not inherit another catalogue key'
);

select is(
  learning.block_question_fingerprint(
    'week4-ocr-question-practice',
    'OCR1',
    '{"type":"single-choice","content":{"sourceQuestionId":"ocr-1","prompt":"Identify the motivation.","options":[{"id":"a","label":"Phishing"},{"id":"b","label":"Publicity"}]}}'::jsonb
  ),
  learning.question_structure_fingerprint(
    'week4-ocr-question-practice',
    'OCR1',
    'single-choice',
    'Identify the motivation.',
    '[{"id":"a","label":"Phishing"},{"id":"b","label":"Publicity"}]'::jsonb
  ),
  'ocr-1 matches the catalogue key OCR1'
);

select ok(
  learning.question_keys_compatible('OCR10', 'OCR1') = false
  and learning.question_keys_compatible('ocr-q1', 'W2OCR-Q01') = false,
  'extra characters or a different key still do not match'
);

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
) values (
  'b3000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'fingerprint-mark-activity',
  'Fingerprint mark activity',
  'test-only',
  'supabase/tests/database/question_structure_fingerprint.test.sql',
  true
);

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count
) values
  ('b3000000-0000-4000-8000-000000000010', 'b3000000-0000-4000-8000-000000000001', '1.0.0', repeat('a', 64), 1, 1),
  ('b3000000-0000-4000-8000-000000000011', 'b3000000-0000-4000-8000-000000000001', '1.1.0', repeat('b', 64), 1, 1);

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score
) values
  ('b3000000-0000-4000-8000-000000000020', 'b3000000-0000-4000-8000-000000000010', 'MW-Q1', 'test', 'Test', 'single', 'MW-Q1', 1, 1),
  ('b3000000-0000-4000-8000-000000000021', 'b3000000-0000-4000-8000-000000000011', 'MW-Q1', 'test', 'Test', 'single', 'MW-Q1', 1, 1),
  ('b3000000-0000-4000-8000-000000000022', 'b3000000-0000-4000-8000-000000000010', 'MW-Q2', 'test', 'Test', 'single', 'MW-Q2', 2, 1);

insert into platform.curriculum_publications (
  hub_code, course_key, package_version, schema_version, source_package_version,
  status, package, content_hash, author, published_by_auth_user_id, published_by_staff_reference
) values (
  'unit-3-cyber-security',
  'ocr-level-3-it',
  '9.8.8',
  '0.1.0',
  '0.1.0',
  'published',
  jsonb_build_object('activities', jsonb_build_array(jsonb_build_object(
    'id', 'fingerprint-mark-activity',
    'version', '1.0.0',
    'blocks', jsonb_build_array(
      jsonb_build_object('type', 'paragraph', 'content', jsonb_build_object('text', 'Week 2 introduction that must not affect marking')),
      jsonb_build_object('type', 'single-choice', 'content', jsonb_build_object(
        'sourceQuestionId', 'mw-q1',
        'prompt', 'Which type?',
        'options', jsonb_build_array(
          jsonb_build_object('id', 'a', 'label', 'Virus'),
          jsonb_build_object('id', 'b', 'label', 'Worm')
        ),
        'correctOptionId', 'b'
      ))
    )
  ))),
  repeat('c', 64),
  'Fingerprint test',
  '20000000-0000-4000-8000-000000000003',
  'TEST'
);

insert into learning.question_marking (question_id, spec)
values (
  'b3000000-0000-4000-8000-000000000021',
  jsonb_build_object('mode', 'single-choice', 'correctOptionId', 'b')
);

update learning.question_marking
set structure_fingerprint = learning.published_question_fingerprint(
  'fingerprint-mark-activity', '1.0.0', 'MW-Q1'
)
where question_id = 'b3000000-0000-4000-8000-000000000021';

select is(
  learning.resolve_marking_question('b3000000-0000-4000-8000-000000000020'),
  'b3000000-0000-4000-8000-000000000021'::uuid,
  'an unchanged published question uses the compatible server rule without a new activity version'
);

select is(
  (select is_correct from learning.mark_evidence_response(
    'b3000000-0000-4000-8000-000000000020',
    '{"optionId":"a"}'::jsonb,
    1
  )),
  false,
  'an incorrect option returns correct false'
);

select is(
  (select is_correct from learning.mark_evidence_response(
    'b3000000-0000-4000-8000-000000000020',
    '{"optionId":"b"}'::jsonb,
    1
  )),
  true,
  'the correct option returns correct true'
);

select is(
  learning.resolve_marking_question('b3000000-0000-4000-8000-000000000022'),
  null,
  'a question with no compatible fingerprint is not marked'
);

select is(
  (select requires_review from learning.mark_evidence_response(
    'b3000000-0000-4000-8000-000000000022',
    '{"optionId":"a"}'::jsonb,
    1
  )),
  true,
  'an unmatched question is stored as requiring review'
);

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
) values (
  'b3000000-0000-4000-8000-000000000002',
  '80000000-0000-4000-8000-000000000001',
  'fingerprint-other-activity',
  'Other activity',
  'test-only',
  'supabase/tests/database/question_structure_fingerprint.test.sql',
  true
);

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count
) values (
  'b3000000-0000-4000-8000-000000000012',
  'b3000000-0000-4000-8000-000000000002',
  '1.0.0', repeat('d', 64), 1, 1
);

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score
) values (
  'b3000000-0000-4000-8000-000000000023',
  'b3000000-0000-4000-8000-000000000012',
  'MW-Q1', 'test', 'Test', 'single', 'MW-Q1', 1, 1
);

select is(
  learning.resolve_marking_question('b3000000-0000-4000-8000-000000000023'),
  null,
  'the same question key in a different activity does not inherit the rule'
);

select throws_ok(
  $$insert into learning.question_marking (question_id, spec, structure_fingerprint, bound_activity_id, bound_question_key)
    values (
      'b3000000-0000-4000-8000-000000000020',
      '{"mode":"single-choice","correctOptionId":"a"}'::jsonb,
      (select structure_fingerprint from learning.question_marking where question_id = 'b3000000-0000-4000-8000-000000000021'),
      'b3000000-0000-4000-8000-000000000001',
      'MW-Q1'
    )$$,
  '23505',
  'duplicate key value violates unique constraint "question_marking_structure_fingerprint_unique"',
  'a conflicting answer for the same question structure is rejected'
);

select ok(
  (select structure_fingerprint is not null
   from learning.question_marking
   where question_id = 'b3000000-0000-4000-8000-000000000021'),
  'the compatible rule stores a structure fingerprint'
);

select is(
  (select spec->>'correctOptionId' from learning.question_marking
   where question_id = 'b3000000-0000-4000-8000-000000000021'),
  'b',
  'changing the correct answer is blocked, so the original rule remains'
);

select ok(
  not exists (
    select 1
    from learning.question_marking
    where question_id = 'b3000000-0000-4000-8000-000000000020'
  ),
  'the published version does not need its own copied activity to be marked'
);

select * from finish();
rollback;
