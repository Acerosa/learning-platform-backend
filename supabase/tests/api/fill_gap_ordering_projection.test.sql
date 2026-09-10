begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(16);

create function pg_temp.fill_gap_ordering_package()
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'schema', 'lp.content.package',
    'schemaVersion', '0.1.0',
    'id', 'unit-3-cyber-security-content',
    'version', '0.2.99',
    'hub', jsonb_build_object(
      'metadata', jsonb_build_object('name', 'Unit 3 Cyber Security Hub')
    ),
    'curriculum', jsonb_build_object(
      'metadata', jsonb_build_object('title', 'OCR Level 3 IT')
    ),
    'learningOutcomes', '[]'::jsonb,
    'weeks', jsonb_build_array(
      jsonb_build_object(
        'id', 'week-1',
        'metadata', jsonb_build_object('title', 'Week 1', 'teachingWeek', 1, 'status', 'available'),
        'relationships', jsonb_build_object('sessions', jsonb_build_array('week-1-session-1'))
      )
    ),
    'sessions', jsonb_build_array(
      jsonb_build_object(
        'id', 'week-1-session-1',
        'metadata', jsonb_build_object('title', 'Session 1', 'sortOrder', 1),
        'relationships', jsonb_build_object(
          'activities', jsonb_build_array(
            'u3-w01-definition-gap',
            'u3-w01-cia-incident-challenge',
            'u3-w01-definition-choice',
            'phase1-scored-ordering'
          )
        )
      )
    ),
    'activities', jsonb_build_array(
      jsonb_build_object(
        'id', 'u3-w01-definition-gap',
        'version', '1.0.0',
        'metadata', jsonb_build_object('title', 'Complete the cyber security definition'),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'id', 'u3-w01-definition-gap-g1',
            'type', 'fill-gap',
            'content', jsonb_build_object(
              'questionId', 'u3-w01-definition-gap:g1',
              'prompt', 'Cyber security aims to protect {blank}.',
              'gaps', jsonb_build_array(
                jsonb_build_object('id', 'blank', 'label', 'missing term', 'correctOptionId', 'information')
              ),
              'options', jsonb_build_array(
                jsonb_build_object('id', 'information', 'label', 'information'),
                jsonb_build_object('id', 'furniture', 'label', 'furniture')
              ),
              'feedback', jsonb_build_object(
                'correct', 'Protect information.',
                'incorrect', 'Protect information.'
              )
            )
          ),
          jsonb_build_object(
            'id', 'u3-w01-definition-gap-g2',
            'type', 'fill-gap',
            'content', jsonb_build_object(
              'questionId', 'u3-w01-definition-gap:g2',
              'prompt', 'Unauthorised viewing threatens {blank}.',
              'gaps', jsonb_build_array(
                jsonb_build_object('id', 'blank', 'label', 'CIA aim', 'correctOptionId', 'confidentiality')
              ),
              'options', jsonb_build_array(
                jsonb_build_object('id', 'confidentiality', 'label', 'confidentiality'),
                jsonb_build_object('id', 'integrity', 'label', 'integrity')
              )
            )
          )
        )
      ),
      jsonb_build_object(
        'id', 'u3-w01-cia-incident-challenge',
        'version', '1.0.0',
        'metadata', jsonb_build_object('title', 'CIA incident challenge'),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'id', 'u3-w01-cia-incident-challenge-rank',
            'type', 'ordering',
            'content', jsonb_build_object(
              'questionId', 'u3-w01-cia-incident-challenge:rank',
              'prompt', 'Rank the incident types.',
              'items', jsonb_build_array(
                jsonb_build_object('id', 'Hacking', 'label', 'Hacking'),
                jsonb_build_object('id', 'Denial of service (DoS)', 'label', 'Denial of service (DoS)')
              )
            )
          ),
          jsonb_build_object(
            'id', 'u3-w01-cia-incident-challenge-explain',
            'type', 'short-response',
            'content', jsonb_build_object(
              'questionId', 'u3-w01-cia-incident-challenge:explain',
              'prompt', 'Defend your ranking.'
            )
          )
        )
      ),
      jsonb_build_object(
        'id', 'u3-w01-definition-choice',
        'version', '1.0.0',
        'metadata', jsonb_build_object('title', 'Definition choice'),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'id', 'u3-w01-definition-choice-q1',
            'type', 'single-choice',
            'content', jsonb_build_object(
              'questionId', 'u3-w01-definition-choice:q1',
              'prompt', 'What does cyber security protect?',
              'options', jsonb_build_array(
                jsonb_build_object('id', 'information', 'label', 'Information'),
                jsonb_build_object('id', 'furniture', 'label', 'Furniture')
              ),
              'correctOptionId', 'information'
            )
          )
        )
      ),
      jsonb_build_object(
        'id', 'phase1-scored-ordering',
        'version', '1.0.0',
        'metadata', jsonb_build_object('title', 'Scored ordering fixture'),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'id', 'phase1-scored-ordering-seq',
            'type', 'sequence',
            'content', jsonb_build_object(
              'questionId', 'phase1-scored-ordering:seq',
              'items', jsonb_build_array(
                jsonb_build_object('id', 'a', 'label', 'A'),
                jsonb_build_object('id', 'b', 'label', 'B'),
                jsonb_build_object('id', 'c', 'label', 'C')
              ),
              'correctOrder', jsonb_build_array('a', 'b', 'c')
            )
          )
        )
      )
    )
  )
$$;

create function pg_temp.unsupported_checkable_package()
returns jsonb
language sql
as $$
  select jsonb_set(
    jsonb_set(
      pg_temp.fill_gap_ordering_package(),
      '{sessions}',
      jsonb_build_array(
        jsonb_build_object(
          'id', 'week-1-session-1',
          'metadata', jsonb_build_object('title', 'Session 1', 'sortOrder', 1),
          'relationships', jsonb_build_object(
            'activities', jsonb_build_array('phase1-unsupported-block')
          )
        )
      )
    ),
    '{activities}',
    jsonb_build_array(
      jsonb_build_object(
        'id', 'phase1-unsupported-block',
        'version', '1.0.0',
        'metadata', jsonb_build_object('title', 'Unsupported'),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'id', 'phase1-unsupported-block-q',
            'type', 'multi-select',
            'content', jsonb_build_object(
              'questionId', 'phase1-unsupported-block:q',
              'prompt', 'Pick several'
            )
          )
        )
      )
    )
  )
$$;

insert into learning.modules (id, course_id, stable_key, title, sort_order, active)
select
  platform.curriculum_catalogue_id('module', 'ocr-level-3-it:unit-3-cyber-security'),
  course.id,
  'unit-3-cyber-security',
  'Unit 3 Cyber Security',
  0,
  true
from learning.courses as course
where course.stable_key = 'ocr-level-3-it'
on conflict (course_id, stable_key) do nothing;

insert into learning.groups (
  id, academic_year_id, course_id, code, name, active, year_group, registration_open
)
select
  '60000000-0000-4000-8000-000000000031',
  academic_year.id,
  course.id,
  'CYBER-PHASE1-TEST',
  'Cyber Phase 1 Projection Group',
  true,
  'Year 1',
  false
from learning.academic_years as academic_year
join learning.courses as course
  on course.stable_key = 'ocr-level-3-it'
where academic_year.active
on conflict (academic_year_id, course_id, code) do update
set active = true;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  '10000000-0000-4000-8000-000000000031'::uuid,
  'authenticated',
  'authenticated',
  'cyber.phase1@local.invalid',
  null,
  clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"synthetic":true,"fixture":"cyber-phase1"}'::jsonb,
  clock_timestamp(),
  clock_timestamp()
where not exists (
  select 1 from auth.users where id = '10000000-0000-4000-8000-000000000031'
);

insert into learning.students (
  id, auth_user_id, student_number, first_name, surname, display_name, active
) values (
  '30000000-0000-4000-8000-000000000031',
  '10000000-0000-4000-8000-000000000031',
  'CYBER-PHASE1-0001',
  'Phase',
  'One',
  'Cyber Phase 1 Learner',
  true
)
on conflict (student_number) do update
set
  auth_user_id = excluded.auth_user_id,
  active = true;

insert into learning.enrolments (
  id, student_id, group_id, status, joined_on
)
select
  '31000000-0000-4000-8000-000000000031',
  student.id,
  learner_group.id,
  'active',
  current_date
from learning.students as student
join learning.groups as learner_group
  on learner_group.code = 'CYBER-PHASE1-TEST'
where student.student_number = 'CYBER-PHASE1-0001'
on conflict (student_id, group_id, joined_on) do nothing;

select throws_ok(
  $$select platform.project_curriculum_package(
    pg_temp.unsupported_checkable_package(),
    'unit-3-cyber-security',
    'ocr-level-3-it',
    '0.2.99',
    null
  )$$,
  '22023',
  'CATALOGUE_PROJECTION_FAILED',
  'unsupported checkable block types fail projection instead of silent skip'
);

select lives_ok(
  $$select platform.project_curriculum_package(
    pg_temp.fill_gap_ordering_package(),
    'unit-3-cyber-security',
    'ocr-level-3-it',
    '0.2.99',
    null
  )$$,
  'fill-gap and ordering packages project successfully'
);

select ok(
  exists (
    select 1
    from learning.activities as activity
    where activity.stable_key = 'u3-w01-definition-gap'
  ),
  'fill-gap-only activity enters the catalogue'
);

select is(
  (
    select question.stable_key
    from learning.activities as activity
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.version = '1.0.0'
    join learning.questions as question
      on question.activity_version_id = version.id
    where activity.stable_key = 'u3-w01-definition-gap'
      and question.stable_key = 'u3-w01-definition-gap:g1'
  ),
  'u3-w01-definition-gap:g1',
  'single-gap fill-gap projects bare package questionId'
);

select is(
  (
    select marking.spec ->> 'correctOptionId'
    from learning.activities as activity
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.version = '1.0.0'
    join learning.questions as question
      on question.activity_version_id = version.id
    join learning.question_marking as marking
      on marking.question_id = question.id
    where activity.stable_key = 'u3-w01-definition-gap'
      and question.stable_key = 'u3-w01-definition-gap:g1'
  ),
  'information',
  'fill-gap authoritative marking uses gap correctOptionId'
);

select ok(
  exists (
    select 1
    from learning.activities as activity
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.version = '1.0.0'
    join learning.questions as question
      on question.activity_version_id = version.id
    where activity.stable_key = 'u3-w01-cia-incident-challenge'
      and question.stable_key = 'u3-w01-cia-incident-challenge:rank'
  ),
  'ordering block projects at package questionId'
);

select is(
  (
    select marking.spec ->> 'mode'
    from learning.activities as activity
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.version = '1.0.0'
    join learning.questions as question
      on question.activity_version_id = version.id
    join learning.question_marking as marking
      on marking.question_id = question.id
    where activity.stable_key = 'u3-w01-cia-incident-challenge'
      and question.stable_key = 'u3-w01-cia-incident-challenge:rank'
  ),
  'completion',
  'open ordering without correctOrder projects as completion'
);

select is(
  (
    select marking.spec ->> 'mode'
    from learning.activities as activity
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.version = '1.0.0'
    join learning.questions as question
      on question.activity_version_id = version.id
    join learning.question_marking as marking
      on marking.question_id = question.id
    where activity.stable_key = 'phase1-scored-ordering'
      and question.stable_key = 'phase1-scored-ordering:seq'
  ),
  'ordering-exact',
  'ordering with correctOrder projects ordering-exact mode'
);

select is(
  platform.strip_learner_answer_keys(
    jsonb_build_object(
      'type', 'fill-gap',
      'content', jsonb_build_object(
        'questionId', 'u3-w01-definition-gap:g1',
        'gaps', jsonb_build_array(
          jsonb_build_object('id', 'blank', 'correctOptionId', 'information')
        ),
        'feedback', jsonb_build_object('correct', 'Keep teaching feedback.')
      )
    )
  ) #>> '{content,gaps,0,correctOptionId}',
  null,
  'learner-safe stripping removes fill-gap gap correctOptionId'
);

select is(
  platform.strip_learner_answer_keys(
    jsonb_build_object(
      'type', 'sequence',
      'content', jsonb_build_object(
        'questionId', 'phase1-scored-ordering:seq',
        'correctOrder', jsonb_build_array('a', 'b', 'c'),
        'feedback', jsonb_build_object('correct', 'Keep teaching feedback.')
      )
    )
  ) -> 'content' ? 'correctOrder',
  false,
  'learner-safe stripping removes ordering correctOrder'
);

-- Assign projected versions to the phase-1 group for mark_formative checks.
insert into learning.activity_assignments (
  id, group_id, activity_version_id, active, opens_at
)
select
  platform.curriculum_catalogue_id('assignment', learner_group.code || ':' || activity.stable_key || ':1.0.0'),
  learner_group.id,
  version.id,
  true,
  clock_timestamp() - interval '1 day'
from learning.groups as learner_group
join learning.activities as activity
  on activity.stable_key in (
    'u3-w01-definition-gap',
    'u3-w01-cia-incident-challenge',
    'u3-w01-definition-choice',
    'phase1-scored-ordering'
  )
join learning.activity_versions as version
  on version.activity_id = activity.id
 and version.version = '1.0.0'
where learner_group.code = 'CYBER-PHASE1-TEST'
on conflict (group_id, activity_version_id) do update set active = true;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000031';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000031","role":"authenticated"}';
set local role authenticated;

select results_eq(
  $$
    select question_id, is_correct, requires_review
    from api.mark_formative_response(
      'u3-w01-definition-gap',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'u3-w01-definition-gap:g1',
          'response_type', 'single-choice',
          'response_payload', jsonb_build_object('optionId', 'information')
        )
      ),
      'phase1-fill-gap-g1-correct'
    )
  $$,
  $$
    values
      ('u3-w01-definition-gap:g1'::text, true, false)
  $$,
  'fill-gap Check resolves and marks correct against projected single-choice spec'
);

select results_eq(
  $$
    select question_id, is_correct, requires_review
    from api.mark_formative_response(
      'u3-w01-definition-gap',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'u3-w01-definition-gap:g1',
          'response_type', 'single-choice',
          'response_payload', jsonb_build_object('optionId', 'furniture')
        )
      ),
      'phase1-fill-gap-g1-incorrect'
    )
  $$,
  $$
    values
      ('u3-w01-definition-gap:g1'::text, false, false)
  $$,
  'fill-gap Check marks incorrect answers'
);

select results_eq(
  $$
    select question_id, is_correct, requires_review
    from api.mark_formative_response(
      'u3-w01-cia-incident-challenge',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'u3-w01-cia-incident-challenge:rank',
          'response_type', 'ordering',
          'response_payload', jsonb_build_object(
            'itemIds', jsonb_build_array('Denial of service (DoS)', 'Hacking')
          )
        )
      ),
      'phase1-ordering-open'
    )
  $$,
  $$
    values
      ('u3-w01-cia-incident-challenge:rank'::text, null::boolean, true)
  $$,
  'open ordering Check resolves as completion/review without invented verdict'
);

select results_eq(
  $$
    select question_id, is_correct, requires_review
    from api.mark_formative_response(
      'phase1-scored-ordering',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'phase1-scored-ordering:seq',
          'response_type', 'ordering',
          'response_payload', jsonb_build_object(
            'itemIds', jsonb_build_array('a', 'b', 'c')
          )
        )
      ),
      'phase1-ordering-correct'
    )
  $$,
  $$
    values
      ('phase1-scored-ordering:seq'::text, true, false)
  $$,
  'ordering-exact Check returns correct for matching sequence'
);

select results_eq(
  $$
    select question_id, is_correct, requires_review
    from api.mark_formative_response(
      'phase1-scored-ordering',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'phase1-scored-ordering:seq',
          'response_type', 'ordering',
          'response_payload', jsonb_build_object(
            'itemIds', jsonb_build_array('c', 'b', 'a')
          )
        )
      ),
      'phase1-ordering-incorrect'
    )
  $$,
  $$
    values
      ('phase1-scored-ordering:seq'::text, false, false)
  $$,
  'ordering-exact Check returns incorrect for mismatched sequence'
);

select results_eq(
  $$
    select question_id, is_correct, requires_review
    from api.mark_formative_response(
      'u3-w01-definition-choice',
      '1.0.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'u3-w01-definition-choice:q1',
          'response_type', 'single-choice',
          'response_payload', jsonb_build_object('optionId', 'information')
        )
      ),
      'phase1-single-choice-regression'
    )
  $$,
  $$
    values
      ('u3-w01-definition-choice:q1'::text, true, false)
  $$,
  'existing single-choice still marks after fill-gap/ordering projection'
);

select * from finish();
rollback;
