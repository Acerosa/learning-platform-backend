begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

create function pg_temp.draft_package(p_activity_version text, p_title text)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'hub', jsonb_build_object(
      'schema', 'lp.content.hub',
      'schemaVersion', '0.1.0',
      'id', 'unit-3-cyber-security',
      'version', '0.1.0',
      'metadata', jsonb_build_object('name', 'Unit 3 Cyber Security Hub'),
      'relationships', jsonb_build_object('curriculum', 'unit-3-cyber-security-curriculum')
    ),
    'curriculum', jsonb_build_object(
      'schema', 'lp.content.curriculum',
      'schemaVersion', '0.1.0',
      'id', 'unit-3-cyber-security-curriculum',
      'version', '0.1.0',
      'metadata', jsonb_build_object('title', p_title, 'course', 'ocr-level-3-it'),
      'relationships', jsonb_build_object(
        'learningOutcomes', '[]'::jsonb,
        'assignments', '[]'::jsonb,
        'weeks', jsonb_build_array('week-21')
      )
    ),
    'learningOutcomes', '[]'::jsonb,
    'assignments', '[]'::jsonb,
    'weeks', jsonb_build_array(
      jsonb_build_object(
        'schema', 'lp.content.week',
        'schemaVersion', '0.1.0',
        'id', 'week-21',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Draft week', 'teachingWeek', 21),
        'relationships', jsonb_build_object('sessions', jsonb_build_array('week-21-workshop'))
      )
    ),
    'sessions', jsonb_build_array(
      jsonb_build_object(
        'schema', 'lp.content.session',
        'schemaVersion', '0.1.0',
        'id', 'week-21-workshop',
        'version', '0.1.0',
        'metadata', jsonb_build_object('title', 'Workshop', 'kind', 'session'),
        'relationships', jsonb_build_object(
          'week', 'week-21',
          'activities', jsonb_build_array('loops-practice')
        )
      )
    ),
    'activities', jsonb_build_array(
      jsonb_build_object(
        'schema', 'lp.content.activity',
        'schemaVersion', '0.1.0',
        'id', 'loops-practice',
        'version', p_activity_version,
        'metadata', jsonb_build_object(
          'title', p_title,
          'difficulty', 'standard',
          'familyId', 'loops-practice'
        ),
        'relationships', jsonb_build_object(),
                'blocks', jsonb_build_array(
          jsonb_build_object(
            'schema', 'lp.content.block',
            'schemaVersion', '0.1.0',
            'id', 'loops-practice-block-1',
            'version', '0.1.0',
            'type', 'paragraph',
            'metadata', jsonb_build_object(),
            'relationships', jsonb_build_object(),
            'content', jsonb_build_object('text', p_title)
          ),
          jsonb_build_object(
            'schema', 'lp.content.block',
            'schemaVersion', '0.1.0',
            'id', 'loops-practice-choice',
            'version', '0.1.0',
            'type', 'single-choice',
            'metadata', jsonb_build_object(),
            'relationships', jsonb_build_object(),
            'content', jsonb_build_object(
              'questionId', 'loops-practice-q1',
              'prompt', p_title,
              'options', jsonb_build_array(
                jsonb_build_object('id', 'a', 'label', 'Published'),
                jsonb_build_object('id', 'b', 'label', 'Draft')
              ),
              'correctOptionId', 'a'
            )
          )
        )
      )
    ),
    'questions', '[]'::jsonb,
    'assets', '[]'::jsonb
  )
$$;

select has_table('platform', 'curriculum_drafts', 'staff curriculum drafts table exists');
select has_function(
  'admin_api',
  'save_curriculum_draft',
  array['uuid', 'text', 'text', 'text', 'text', 'integer', 'jsonb', 'text'],
  'staff API exposes draft save'
);
select has_function(
  'admin_api',
  'current_curriculum_package',
  array['text', 'text'],
  'staff API can read the live published package body'
);

set local role anon;
select throws_like(
  $$select * from admin_api.save_curriculum_draft(
    null, 'unit-3-cyber-security', 'ocr-level-3-it', 'Draft', 'draft', 0, '{}'::jsonb, null
  )$$,
  '%permission denied%',
  'anonymous clients cannot save curriculum drafts'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from admin_api.save_curriculum_draft(
    null, 'unit-3-cyber-security', 'ocr-level-3-it', 'Draft', 'draft', 0, '{}'::jsonb, null
  )$$,
  '28000',
  'CURRICULUM_AUTHORING_NOT_AUTHORISED',
  'a learner cannot save curriculum drafts'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from admin_api.save_curriculum_draft(
    null, 'unit-3-cyber-security', 'ocr-level-3-it', 'Draft', 'draft', 0, '{}'::jsonb, null
  )$$,
  '28000',
  'CURRICULUM_AUTHORING_NOT_AUTHORISED',
  'an ordinary teacher cannot save curriculum drafts'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  format(
    $sql$select * from admin_api.save_curriculum_draft(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
      'unit-3-cyber-security',
      'ocr-level-3-it',
      'Loops draft',
      'draft',
      0,
      %L::jsonb,
      null
    )$sql$,
    pg_temp.draft_package('1.0.0', 'Loops v1')::text
  ),
  'platform_admin can create a curriculum draft'
);

select is(
  (select revision from admin_api.get_curriculum_draft('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid::uuid)),
  1,
  'a new draft starts at revision 1'
);

select throws_ok(
  format(
    $sql$select * from admin_api.save_curriculum_draft(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
      'unit-3-cyber-security',
      'ocr-level-3-it',
      'Loops draft',
      'draft',
      0,
      %L::jsonb,
      null
    )$sql$,
    pg_temp.draft_package('1.0.0', 'Loops stale')::text
  ),
  '22023',
  'DRAFT_REVISION_CONFLICT',
  'a stale draft revision cannot overwrite a newer save'
);

select lives_ok(
  format(
    $sql$select * from admin_api.publish_curriculum(
      'published', 'unit-3-cyber-security', 'ocr-level-3-it', '2.0.0', '0.1.0', '0.1.0',
      %L::jsonb, 'Ada Author', 'Riley Reviewer', 'v1'
    )$sql$,
    pg_temp.draft_package('1.0.0', 'Loops v1')::text
  ),
  'first immutable publication succeeds'
);

select lives_ok(
  $$select * from admin_api.current_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it')$$,
  'staff can load the currently published package for editing'
);

reset role;

select is(
  (
    select version.version
    from learning.activity_versions as version
    join learning.activities as activity
      on activity.id = version.activity_id
    where activity.stable_key = 'loops-practice'
      and version.version = '1.0.0'
  ),
  '1.0.0',
  'v1 activity version is projected before the historic attempt'
);

insert into learning.activity_assignments (
  group_id, activity_version_id, required, active
)
select
  enrolment.group_id,
  version.id,
  true,
  true
from learning.activity_versions as version
join learning.activities as activity
  on activity.id = version.activity_id
join learning.enrolments as enrolment
  on enrolment.status = 'active'
where activity.stable_key = 'loops-practice'
  and version.version = '1.0.0'
limit 1
on conflict (group_id, activity_version_id) do nothing;

insert into learning.attempts (
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
  source_system,
  submission_hash
)
select
  'historic-loops-v1',
  enrolment.student_id,
  enrolment.id,
  assignment.id,
  assignment.activity_version_id,
  1,
  'completed',
  1,
  1,
  'imported',
  'summary_only',
  'supabase',
  repeat('a', 64)
from learning.activity_assignments as assignment
join learning.activity_versions as version
  on version.id = assignment.activity_version_id
join learning.activities as activity
  on activity.id = version.activity_id
join learning.enrolments as enrolment
  on enrolment.group_id = assignment.group_id
  and enrolment.status = 'active'
where activity.stable_key = 'loops-practice'
  and version.version = '1.0.0'
limit 1;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  format(
    $sql$select * from admin_api.publish_curriculum(
      'published', 'unit-3-cyber-security', 'ocr-level-3-it', '2.1.0', '0.1.0', '0.1.0',
      %L::jsonb, 'Ada Author', 'Riley Reviewer', 'v2'
    )$sql$,
    pg_temp.draft_package('1.1.0', 'Loops v2')::text
  ),
  'second immutable publication succeeds'
);

select is(
  (
    select package->'activities'->0->>'version'
    from api.published_curriculum_package('unit-3-cyber-security', 'ocr-level-3-it')
  ),
  '1.1.0',
  'learners receive the newly published activity version without a git commit'
);

reset role;

select is(
  (
    select version.version
    from learning.attempts as attempt
    join learning.activity_versions as version
      on version.id = attempt.activity_version_id
    where attempt.client_attempt_id = 'historic-loops-v1'
  ),
  '1.0.0',
  'historic learner attempts remain bound to the activity version actually completed'
);

select is(
  (
    select count(*)
    from learning.activity_versions as version
    join learning.activities as activity
      on activity.id = version.activity_id
    where activity.stable_key = 'loops-practice'
      and version.version in ('1.0.0', '1.1.0')
  ),
  2::bigint,
  'publishing v1.1.0 preserves the immutable v1.0.0 activity version'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;
select throws_like(
  $$insert into platform.curriculum_drafts (
    hub_code, course_key, title, package
  ) values (
    'unit-3-cyber-security', 'ocr-level-3-it', 'browser', '{}'::jsonb
  )$$,
  '%permission denied%',
  'authenticated staff cannot insert curriculum drafts directly into the protected table'
);
reset role;

select * from finish();
rollback;
