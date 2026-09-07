begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select plan(30);

create function pg_temp.week1_marking_package()
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'schema', 'lp.content.package',
    'schemaVersion', '0.1.0',
    'id', 'tlevel-software-development-content',
    'version', '0.4.3',
    'hub', jsonb_build_object(
      'metadata', jsonb_build_object('name', 'T Level Digital Software Development Hub')
    ),
    'curriculum', jsonb_build_object(
      'metadata', jsonb_build_object('title', 'T Level Digital Software Development')
    ),
    'learningOutcomes', '[]'::jsonb,
    'weeks', jsonb_build_array(
      jsonb_build_object(
        'id', 'week-1',
        'metadata', jsonb_build_object('title', 'Week 1', 'teachingWeek', 1, 'status', 'available'),
        'relationships', jsonb_build_object('sessions', jsonb_build_array('week-1-lesson-1'))
      )
    ),
    'sessions', jsonb_build_array(
      jsonb_build_object(
        'id', 'week-1-lesson-1',
        'metadata', jsonb_build_object('title', 'Lesson 1', 'sortOrder', 1),
        'relationships', jsonb_build_object(
          'activities', jsonb_build_array(
            'week-1-lesson-1-ex-01',
            'week-1-lesson-1-ex-07',
            'week-1-lesson-1-ex-13',
            'week-1-lesson-1-ex-20'
          )
        )
      )
    ),
    'activities', jsonb_build_array(
      jsonb_build_object(
        'id', 'week-1-lesson-1-ex-01',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Who is the client?'),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'id', 'week-1-lesson-1-ex-01-client',
            'type', 'single-choice',
            'content', jsonb_build_object(
              'questionId', 'week-1-lesson-1-ex-01:client',
              'prompt', 'Who is the client in the Oakfield scenario?',
              'options', jsonb_build_array(
                jsonb_build_object('id', 'a', 'label', 'Option A'),
                jsonb_build_object('id', 'b', 'label', 'Option B')
              ),
              'correctOptionId', 'a'
            )
          )
        )
      ),
      jsonb_build_object(
        'id', 'week-1-lesson-1-ex-07',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Users'),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'id', 'week-1-lesson-1-ex-07-users',
            'type', 'classification',
            'content', jsonb_build_object(
              'questionId', 'week-1-lesson-1-ex-07:users',
              'items', jsonb_build_array(
                jsonb_build_object('id', 'item-1', 'label', 'Item 1', 'correctCategoryId', 'cat-a'),
                jsonb_build_object('id', 'item-2', 'label', 'Item 2', 'correctCategoryId', 'cat-b')
              ),
              'categories', jsonb_build_array(
                jsonb_build_object('id', 'cat-a', 'label', 'A'),
                jsonb_build_object('id', 'cat-b', 'label', 'B')
              )
            )
          )
        )
      ),
      jsonb_build_object(
        'id', 'week-1-lesson-1-ex-13',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Needs'),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'id', 'week-1-lesson-1-ex-13-needs',
            'type', 'drag-drop',
            'content', jsonb_build_object(
              'questionId', 'week-1-lesson-1-ex-13:needs',
              'items', jsonb_build_array(
                jsonb_build_object('id', 'need-1', 'label', 'Need 1'),
                jsonb_build_object('id', 'need-2', 'label', 'Need 2')
              ),
              'targets', jsonb_build_array(
                jsonb_build_object('id', 'target-a', 'label', 'Target A'),
                jsonb_build_object('id', 'target-b', 'label', 'Target B')
              ),
              'correct', jsonb_build_object(
                'need-1', 'target-a',
                'need-2', 'target-b'
              )
            )
          )
        )
      ),
      jsonb_build_object(
        'id', 'week-1-lesson-1-ex-20',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Client user'),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'id', 'week-1-lesson-1-ex-20-client-user',
            'type', 'short-response',
            'content', jsonb_build_object(
              'questionId', 'week-1-lesson-1-ex-20:client-user',
              'prompt', 'Describe the client user.'
            )
          )
        )
      )
    )
  )
$$;

create function pg_temp.malformed_drag_drop_package()
returns jsonb
language sql
as $$
  select jsonb_set(
    pg_temp.week1_marking_package(),
    '{activities}',
    jsonb_build_array(
      jsonb_build_object(
        'id', 'week-1-lesson-1-ex-13',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Needs'),
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'id', 'week-1-lesson-1-ex-13-needs',
            'type', 'drag-drop',
            'content', jsonb_build_object(
              'questionId', 'week-1-lesson-1-ex-13:needs',
              'items', jsonb_build_array(
                jsonb_build_object('id', 'need-1', 'label', 'Need 1')
              ),
              'targets', jsonb_build_array(
                jsonb_build_object('id', 'target-a', 'label', 'Target A')
              ),
              'correct', jsonb_build_object('need-1', 'missing-target')
            )
          )
        )
      )
    )
  )
$$;

insert into learning.modules (id, course_id, stable_key, title, sort_order, active)
select
  platform.curriculum_catalogue_id(
    'module', 't-level-digital-software-development:tlevel-software-development'
  ),
  course.id,
  'tlevel-software-development',
  'T Level Digital Software Development',
  0,
  true
from learning.courses as course
where course.stable_key = 't-level-digital-software-development'
on conflict (course_id, stable_key) do nothing;

insert into learning.groups (
  id, academic_year_id, course_id, code, name, active, year_group, registration_open
)
select
  '60000000-0000-4000-8000-000000000021',
  academic_year.id,
  course.id,
  'TLEVEL-DSD-Y2',
  'T Level Digital Software Development - Year 2',
  true,
  'Year 2',
  false
from learning.academic_years as academic_year
join learning.courses as course
  on course.stable_key = 't-level-digital-software-development'
where academic_year.active
on conflict (academic_year_id, course_id, code) do update
set active = true;

insert into learning.groups (
  id, academic_year_id, course_id, code, name, active, year_group, registration_open
)
select
  '60000000-0000-4000-8000-000000000022',
  academic_year.id,
  course.id,
  'TLEVEL-INACTIVE-Y2',
  'Inactive T Level group',
  false,
  'Year 2',
  false
from learning.academic_years as academic_year
join learning.courses as course
  on course.stable_key = 't-level-digital-software-development'
where academic_year.active
on conflict (academic_year_id, course_id, code) do update
set active = false;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  '10000000-0000-4000-8000-000000000004'::uuid,
  'authenticated',
  'authenticated',
  'tlevel.y2@local.invalid',
  null,
  clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"synthetic":true,"fixture":"tlevel-y2"}'::jsonb,
  clock_timestamp(),
  clock_timestamp()
where not exists (
  select 1 from auth.users where id = '10000000-0000-4000-8000-000000000004'
);

insert into learning.students (
  id, auth_user_id, student_number, first_name, surname, display_name, active
) values (
  '30000000-0000-4000-8000-000000000021',
  '10000000-0000-4000-8000-000000000004',
  'TLEVEL-Y2-0001',
  'Year',
  'Two',
  'T Level Year 2 Learner',
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
  '31000000-0000-4000-8000-000000000021',
  student.id,
  learner_group.id,
  'active',
  current_date
from learning.students as student
join learning.groups as learner_group
  on learner_group.code = 'TLEVEL-DSD-Y2'
where student.student_number = 'TLEVEL-Y2-0001'
on conflict (student_id, group_id, joined_on) do nothing;

select is(
  platform.strip_learner_answer_keys(
    jsonb_build_object(
      'type', 'drag-drop',
      'content', jsonb_build_object(
        'questionId', 'week-1-lesson-1-ex-13:needs',
        'correct', jsonb_build_object('need-1', 'target-a'),
        'feedback', jsonb_build_object('correct', 'Keep this teaching string.')
      )
    )
  ) -> 'content' ? 'correct',
  false,
  'learner-safe stripping removes drag-drop object correct maps'
);

select is(
  platform.strip_learner_answer_keys(
    jsonb_build_object(
      'feedback', jsonb_build_object('correct', 'Keep this teaching string.')
    )
  ) #>> '{feedback,correct}',
  'Keep this teaching string.',
  'learner-safe stripping keeps teaching feedback.correct strings'
);

select throws_ok(
  $$select platform.project_curriculum_package(
    pg_temp.malformed_drag_drop_package(),
    'tlevel-software-development',
    't-level-digital-software-development',
    '0.4.3',
    null
  )$$,
  '22023',
  'CATALOGUE_PROJECTION_FAILED',
  'malformed drag-drop target mappings fail projection'
);

select lives_ok(
  $$select platform.project_curriculum_package(
    pg_temp.week1_marking_package(),
    'tlevel-software-development',
    't-level-digital-software-development',
    '0.4.3',
    null
  )$$,
  'authoritative projection accepts current Week 1 split activities including drag-drop'
);

select ok(
  exists (
    select 1
    from learning.activities as activity
    join learning.activity_versions as version on version.activity_id = activity.id
    where activity.stable_key = 'week-1-lesson-1-ex-13'
      and version.version = '0.1.0'
      and version.published_at is not null
  ),
  'drag-drop activity week-1-lesson-1-ex-13 is projected as a published 0.1.0 version'
);

select is(
  (
    select count(*)::int
    from learning.questions as question
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week-1-lesson-1-ex-13'
  ),
  2,
  'drag-drop projection creates one authoritative question per item'
);

select ok(
  exists (
    select 1
    from learning.question_marking as marking
    join learning.questions as question on question.id = marking.question_id
    join learning.activity_versions as version on version.id = question.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where activity.stable_key = 'week-1-lesson-1-ex-13'
      and question.stable_key = 'week-1-lesson-1-ex-13:needs:need-1'
      and marking.spec ->> 'mode' = 'classification'
      and coalesce(marking.spec ->> 'correctCategoryId', '') <> ''
  ),
  'drag-drop item specs reuse classification mode with a hosted answer key'
);

select ok(
  exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'TLEVEL-DSD-Y2'
      and assignment.active
      and activity.stable_key = 'week-1-lesson-1-ex-01'
  ),
  'TLEVEL-DSD-Y2 receives current T Level activities despite having no prior module assignment'
);

select ok(
  exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'TLEVEL-DSD-Y2'
      and assignment.active
      and activity.stable_key = 'week-1-lesson-1-ex-13'
  ),
  'TLEVEL-DSD-Y2 also receives the projected drag-drop activity'
);

select ok(
  not exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code in ('TEST-GROUP-A', 'TEST-GROUP-B')
      and assignment.active
      and activity.stable_key like 'week-1-lesson-1-ex-%'
  ),
  'groups already taking a different module of the same course do not receive the new module activities'
);

select ok(
  not exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'TLEVEL-TEST-A'
      and assignment.active
      and activity.stable_key in (
        'week-1-lesson-1-ex-07',
        'week-1-lesson-1-ex-13',
        'week-1-lesson-1-ex-20'
      )
  ),
  'exclusive QA group does not receive extra Week 1 activities from projection'
);

select lives_ok(
  $$select platform.project_curriculum_package(
    pg_temp.week1_marking_package(),
    'tlevel-software-development',
    't-level-digital-software-development',
    '0.4.3',
    null
  )$$,
  're-running projection is idempotent'
);

select is(
  (
    select count(*)::int
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'TLEVEL-DSD-Y2'
      and assignment.active
      and activity.stable_key in (
        'week-1-lesson-1-ex-01',
        'week-1-lesson-1-ex-07',
        'week-1-lesson-1-ex-13',
        'week-1-lesson-1-ex-20'
      )
  ),
  4,
  'idempotent replay does not duplicate TLEVEL-DSD-Y2 assignments'
);

select ok(
  not exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    where learner_group.code = 'TLEVEL-INACTIVE-Y2'
      and assignment.active
  ),
  'inactive groups do not receive projected assignments'
);

select is(
  learning.expand_formative_matching_responses(
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'week-1-lesson-1-ex-13:needs',
        'response_type', 'matching',
        'response_payload', jsonb_build_object(
          'pairs', jsonb_build_array(
            jsonb_build_object('left', 'need-1', 'right', 'target-a'),
            jsonb_build_object('left', 'need-2', 'right', 'target-b')
          )
        )
      )
    )
  ) -> 0 ->> 'question_id',
  'week-1-lesson-1-ex-13:needs:need-1',
  'matching evidence expands onto the hosted per-item question key'
);

select lives_ok(
  $$select * from learning.ensure_synthetic_qa_groups()$$,
  'QA ensure remains valid after the T Level smoke key update'
);

select is(
  (
    select smoke_activity_key
    from learning.synthetic_qa_fixtures
    where persona = 'TLEVEL_TEST_LEARNER'
  ),
  'week-1-lesson-1-ex-01',
  'T Level smoke fixture points at the current Lesson 1 activity'
);

select is(
  (
    select count(*)::int
    from learning.synthetic_qa_smoke_activities
    where persona = 'TLEVEL_TEST_LEARNER'
  ),
  1,
  'T Level exclusive smoke allowlist remains a single activity'
);

select is(
  (
    select activity_key
    from learning.synthetic_qa_smoke_activities
    where persona = 'TLEVEL_TEST_LEARNER'
  ),
  'week-1-lesson-1-ex-01',
  'T Level exclusive allowlist catalogues week-1-lesson-1-ex-01'
);

select is(
  (
    select count(*)::int
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'TLEVEL-TEST-A'
      and assignment.active
      and activity.stable_key = 'week-1-lesson-1-ex-01'
  ),
  1,
  'exclusive QA assignment is switched to the current smoke activity when it exists'
);

select ok(
  not exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version
      on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'TLEVEL-TEST-A'
      and assignment.active
      and activity.stable_key <> 'week-1-lesson-1-ex-01'
  ),
  'exclusive QA group keeps only the catalogued smoke assignment active'
);

select is(
  (
    select is_synthetic
    from learning.groups
    where code = 'TLEVEL-DSD-Y2'
  ),
  false,
  'ensure does not convert teaching group TLEVEL-DSD-Y2 to synthetic'
);

select is(
  (
    select year_group
    from learning.groups
    where code = 'TLEVEL-DSD-Y2'
  ),
  'Year 2',
  'ensure leaves TLEVEL-DSD-Y2 year_group unchanged'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000004';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select jsonb_build_object('is_correct', is_correct, 'requires_review', requires_review)
    from api.mark_formative_response(
      'week-1-lesson-1-ex-01',
      '0.1.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'week-1-lesson-1-ex-01:client',
          'response_type', 'single-choice',
          'response_payload', jsonb_build_object('optionId', 'a')
        )
      ),
      'tlevel-y2-ex01-correct'
    )
  ),
  jsonb_build_object('is_correct', true, 'requires_review', false),
  'assigned learner receives correct single-choice feedback for ex-01'
);

select is(
  (
    select jsonb_build_object('is_correct', is_correct, 'requires_review', requires_review)
    from api.mark_formative_response(
      'week-1-lesson-1-ex-01',
      '0.1.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'week-1-lesson-1-ex-01:client',
          'response_type', 'single-choice',
          'response_payload', jsonb_build_object('optionId', 'b')
        )
      ),
      'tlevel-y2-ex01-incorrect'
    )
  ),
  jsonb_build_object('is_correct', false, 'requires_review', false),
  'assigned learner receives incorrect single-choice feedback for ex-01'
);

select ok(
  (
    select bool_and(is_correct) and bool_and(not requires_review)
    from api.mark_formative_response(
      'week-1-lesson-1-ex-07',
      '0.1.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'week-1-lesson-1-ex-07:users:item-1',
          'response_type', 'classification',
          'response_payload', jsonb_build_object('categoryId', 'cat-a', 'itemId', 'item-1')
        ),
        jsonb_build_object(
          'question_id', 'week-1-lesson-1-ex-07:users:item-2',
          'response_type', 'classification',
          'response_payload', jsonb_build_object('categoryId', 'cat-b', 'itemId', 'item-2')
        )
      ),
      'tlevel-y2-ex07-correct'
    )
  ),
  'classification marks through the existing per-item path for ex-07'
);

select ok(
  (
    select bool_and(is_correct) and bool_and(not requires_review)
    from api.mark_formative_response(
      'week-1-lesson-1-ex-13',
      '0.1.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'week-1-lesson-1-ex-13:needs',
          'response_type', 'matching',
          'response_payload', jsonb_build_object(
            'pairs', jsonb_build_array(
              jsonb_build_object('left', 'need-1', 'right', 'target-a'),
              jsonb_build_object('left', 'need-2', 'right', 'target-b')
            )
          )
        )
      ),
      'tlevel-y2-ex13-correct'
    )
  ),
  'drag-drop matching evidence is marked from hosted per-item specs'
);

select is(
  (
    select jsonb_build_object(
      'is_correct', is_correct,
      'requires_review', requires_review,
      'awarded_score', awarded_score
    )
    from api.mark_formative_response(
      'week-1-lesson-1-ex-20',
      '0.1.0',
      jsonb_build_array(
        jsonb_build_object(
          'question_id', 'week-1-lesson-1-ex-20:client-user',
          'response_type', 'written',
          'response_payload', jsonb_build_object('text', 'A client user description for review.')
        )
      ),
      'tlevel-y2-ex20-review'
    )
  ),
  jsonb_build_object(
    'is_correct', null,
    'requires_review', true,
    'awarded_score', 0
  ),
  'short-response returns review/recorded semantics for ex-20'
);

select throws_ok(
  $$select * from api.mark_formative_response(
    'week-1-lesson-1-ex-01',
    '9.9.9',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'week-1-lesson-1-ex-01:client',
        'response_payload', jsonb_build_object('optionId', 'a')
      )
    ),
    'tlevel-y2-invalid-version'
  )$$,
  '22023',
  'INVALID_ACTIVITY_VERSION',
  'unknown activity versions still fail closed'
);

reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select throws_ok(
  $$select * from api.mark_formative_response(
    'week-1-lesson-1-ex-01',
    '0.1.0',
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'week-1-lesson-1-ex-01:client',
        'response_payload', jsonb_build_object('optionId', 'a')
      )
    ),
    'student-b-unassigned-ex01'
  )$$,
  '42501',
  'ACTIVITY_NOT_ASSIGNED',
  'unassigned learners still receive ACTIVITY_NOT_ASSIGNED'
);

reset role;

select * from finish();
rollback;
