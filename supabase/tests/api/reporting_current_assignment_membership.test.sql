begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_function(
  'learning',
  'current_activity_assignment_id',
  array['uuid', 'uuid'],
  'current assignment helper exists'
);

-- Isolated hub / group fixtures for current-membership reporting tests.
insert into platform.hubs (
  id, hub_code, hub_name, description, hub_version, platform_version,
  manifest_version, core_version, learner_api_version, submission_contract_version,
  repository_url, deployment_url, activity_types, evidence_capabilities,
  features, compatibility, status, active, manifest, manifest_sha256
) values
  (
    '36a10000-0000-4000-8000-000000000001',
    'reporting-current-alpha',
    'Reporting Current Alpha',
    'Synthetic hub for Phase 1A.1 current assignment tests.',
    '0.1.0',
    '0.2.0',
    '1.0.0',
    '0.2.0',
    '0.1.0',
    '0.1.0',
    'https://example.invalid/reporting-current-alpha',
    'https://example.invalid/reporting-current-alpha/',
    array['retrieval-quiz'],
    array['question-level'],
    '{}'::jsonb,
    '{}'::jsonb,
    'testing',
    true,
    '{}'::jsonb,
    repeat('a', 64)
  ),
  (
    '36a10000-0000-4000-8000-000000000002',
    'reporting-current-beta',
    'Reporting Current Beta',
    'Synthetic second hub for Phase 1A.1 isolation.',
    '0.1.0',
    '0.2.0',
    '1.0.0',
    '0.2.0',
    '0.1.0',
    '0.1.0',
    'https://example.invalid/reporting-current-beta',
    'https://example.invalid/reporting-current-beta/',
    array['retrieval-quiz'],
    array['question-level'],
    '{}'::jsonb,
    '{}'::jsonb,
    'testing',
    true,
    '{}'::jsonb,
    repeat('b', 64)
  );

insert into learning.modules (
  id, course_id, stable_key, title, active
)
select
  '36b10000-0000-4000-8000-000000000001',
  course.id,
  'reporting-current-module',
  'Reporting Current Module',
  true
from learning.courses as course
where course.stable_key = 't-level-digital-software-development'
limit 1;

insert into learning.curriculum_weeks (
  id, module_id, stable_key, title, week_number, ordinal, active
) values (
  '36b10000-0000-4000-8000-000000000011',
  '36b10000-0000-4000-8000-000000000001',
  'reporting-current-week-1',
  'Reporting Current Week 1',
  1,
  1,
  true
);

insert into learning.groups (
  id,
  academic_year_id,
  course_id,
  code,
  name,
  active,
  year_group,
  registration_key,
  registration_open
)
select
  mapping.id,
  template.academic_year_id,
  template.course_id,
  mapping.code,
  mapping.name,
  true,
  'Year 1',
  mapping.registration_key,
  false
from learning.groups as template
cross join (
  values
    (
      '36c10000-0000-4000-8000-000000000001'::uuid,
      'REPORT-CUR-A',
      'Reporting Current Group A',
      'report-cur-a'
    ),
    (
      '36c10000-0000-4000-8000-000000000002'::uuid,
      'REPORT-CUR-B',
      'Reporting Current Group B',
      'report-cur-b'
    )
) as mapping(id, code, name, registration_key)
where template.id = '60000000-0000-4000-8000-000000000001';

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
values
  (
    '36a10000-0000-4000-8000-000000000001',
    '36c10000-0000-4000-8000-000000000001',
    true,
    'closed'
  ),
  (
    '36a10000-0000-4000-8000-000000000002',
    '36c10000-0000-4000-8000-000000000002',
    true,
    'closed'
  );

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
) values
  (
    '36d10000-0000-4000-8000-000000000001',
    '36b10000-0000-4000-8000-000000000001',
    'reporting-current-shared',
    'Reporting Current Shared',
    'retrieval-quiz',
    'tests/reporting-current-shared.html',
    true
  ),
  (
    '36d10000-0000-4000-8000-000000000002',
    '36b10000-0000-4000-8000-000000000001',
    'reporting-current-other',
    'Reporting Current Other',
    'retrieval-quiz',
    'tests/reporting-current-other.html',
    true
  );

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count, published_at
) values
  (
    '36e10000-0000-4000-8000-000000000001',
    '36d10000-0000-4000-8000-000000000001',
    '1.0.0',
    repeat('1', 64),
    10,
    1,
    timestamptz '2026-09-01 10:00:00+00'
  ),
  (
    '36e10000-0000-4000-8000-000000000002',
    '36d10000-0000-4000-8000-000000000001',
    '1.1.0',
    repeat('2', 64),
    10,
    1,
    timestamptz '2026-09-02 10:00:00+00'
  ),
  (
    '36e10000-0000-4000-8000-000000000003',
    '36d10000-0000-4000-8000-000000000002',
    '1.0.0',
    repeat('3', 64),
    5,
    1,
    timestamptz '2026-09-01 11:00:00+00'
  );

insert into learning.activity_delivery (
  id, activity_version_id, academic_year_id, group_id, curriculum_week_id,
  week_number, session_number, sort_order, active
)
select
  '36f10000-0000-4000-8000-000000000001',
  '36e10000-0000-4000-8000-000000000002',
  academic_year.id,
  null,
  '36b10000-0000-4000-8000-000000000011',
  1,
  1,
  1,
  true
from learning.academic_years as academic_year
where academic_year.active
order by academic_year.code
limit 1;

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score
) values
  (
    '36110000-0000-4000-8000-000000000001',
    '36e10000-0000-4000-8000-000000000001',
    'RC-Q1',
    'main',
    'Main',
    'single',
    'Current Q1',
    1,
    10
  ),
  (
    '36110000-0000-4000-8000-000000000002',
    '36e10000-0000-4000-8000-000000000002',
    'RC-Q1',
    'main',
    'Main',
    'single',
    'Current Q1 v1.1',
    1,
    10
  );

-- Both versions remain active: required for version-pinned learner APIs.
insert into learning.activity_assignments (
  id, group_id, activity_version_id, required, active
) values
  (
    '36g10000-0000-4000-8000-000000000001',
    '36c10000-0000-4000-8000-000000000001',
    '36e10000-0000-4000-8000-000000000001',
    true,
    true
  ),
  (
    '36g10000-0000-4000-8000-000000000002',
    '36c10000-0000-4000-8000-000000000001',
    '36e10000-0000-4000-8000-000000000002',
    true,
    true
  ),
  (
    '36g10000-0000-4000-8000-000000000003',
    '36c10000-0000-4000-8000-000000000001',
    '36e10000-0000-4000-8000-000000000003',
    true,
    true
  ),
  (
    '36g10000-0000-4000-8000-000000000004',
    '36c10000-0000-4000-8000-000000000002',
    '36e10000-0000-4000-8000-000000000002',
    true,
    true
  );

insert into learning.enrolments (
  id, student_id, group_id, joined_on, status
) values
  (
    '36j10000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '36c10000-0000-4000-8000-000000000001',
    '2026-09-01',
    'active'
  ),
  (
    '36j10000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000002',
    '36c10000-0000-4000-8000-000000000002',
    '2026-09-01',
    'active'
  );

-- Historical completion against older 1.0.0 assignment.
insert into learning.attempts (
  id, client_attempt_id, student_id, enrolment_id, assignment_id,
  activity_version_id, attempt_number, status, score, max_score,
  marking_source, evidence_level, submission_hash, received_at, completed_at
) values (
  '36k10000-0000-4000-8000-000000000001',
  'rc-hist-1',
  '30000000-0000-4000-8000-000000000001',
  '36j10000-0000-4000-8000-000000000001',
  '36g10000-0000-4000-8000-000000000001',
  '36e10000-0000-4000-8000-000000000001',
  1,
  'completed',
  8,
  10,
  'server',
  'question_level',
  repeat('5', 64),
  timestamptz '2026-09-01 12:00:00+00',
  timestamptz '2026-09-01 12:05:00+00'
);

insert into learning.responses (
  id, attempt_id, question_id, response_payload, awarded_score, max_score,
  is_correct, requires_review, marking_source
) values (
  '36l10000-0000-4000-8000-000000000001',
  '36k10000-0000-4000-8000-000000000001',
  '36110000-0000-4000-8000-000000000001',
  '{"selected":"A"}'::jsonb,
  8,
  10,
  true,
  false,
  'server'
);

select is(
  learning.current_activity_assignment_id(
    '36c10000-0000-4000-8000-000000000001',
    '36d10000-0000-4000-8000-000000000001'
  ),
  '36g10000-0000-4000-8000-000000000002'::uuid,
  'helper selects later-published 1.1.0 as current among active versions'
);

select is(
  (
    select count(*)::int
    from learning.activity_assignments
    where id in (
      '36g10000-0000-4000-8000-000000000001',
      '36g10000-0000-4000-8000-000000000002'
    )
      and active
  ),
  2,
  'both historical and current assignments remain active for version-pinned APIs'
);

select is(
  (
    select count(*)::int
    from learning.attempts
    where id = '36k10000-0000-4000-8000-000000000001'
  ),
  1,
  'historical attempt against 1.0.0 remains stored'
);

select is(
  (
    select count(*)::int
    from learning.responses
    where id = '36l10000-0000-4000-8000-000000000001'
  ),
  1,
  'historical responses against 1.0.0 remain stored'
);

set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*)::int
    from api.my_hub_activity_progress('reporting-current-alpha')
    where activity_key = 'reporting-current-shared'
  ),
  1,
  'reporting returns one current row for multi-version activity key'
);

select is(
  (
    select activity_version
    from api.my_hub_activity_progress('reporting-current-alpha')
    where activity_key = 'reporting-current-shared'
  ),
  '1.1.0',
  'reporting membership uses authoritative current version 1.1.0'
);

select is(
  (
    select completed
    from api.my_hub_activity_progress('reporting-current-alpha')
    where activity_key = 'reporting-current-shared'
  ),
  false,
  'historical 1.0.0 completion does not mark current 1.1.0 completed'
);

select is(
  (
    select count(*)::int
    from api.my_hub_activity_progress('reporting-current-alpha')
  ),
  2,
  'session required count is not inflated by historical versions'
);

reset role;

insert into learning.attempts (
  id, client_attempt_id, student_id, enrolment_id, assignment_id,
  activity_version_id, attempt_number, status, score, max_score,
  marking_source, evidence_level, submission_hash, received_at, completed_at
) values
  (
    '36k10000-0000-4000-8000-000000000002',
    'rc-cur-1',
    '30000000-0000-4000-8000-000000000001',
    '36j10000-0000-4000-8000-000000000001',
    '36g10000-0000-4000-8000-000000000002',
    '36e10000-0000-4000-8000-000000000002',
    1,
    'completed',
    4,
    10,
    'server',
    'question_level',
    repeat('6', 64),
    timestamptz '2026-09-03 09:00:00+00',
    timestamptz '2026-09-03 09:05:00+00'
  ),
  (
    '36k10000-0000-4000-8000-000000000003',
    'rc-cur-2',
    '30000000-0000-4000-8000-000000000001',
    '36j10000-0000-4000-8000-000000000001',
    '36g10000-0000-4000-8000-000000000002',
    '36e10000-0000-4000-8000-000000000002',
    2,
    'completed',
    9,
    10,
    'server',
    'question_level',
    repeat('7', 64),
    timestamptz '2026-09-03 10:00:00+00',
    timestamptz '2026-09-03 10:05:00+00'
  );

set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select results_eq(
  $$
    select
      attempt_count,
      first_score,
      latest_score,
      best_score,
      improvement,
      completed
    from api.my_hub_activity_progress('reporting-current-alpha')
    where activity_key = 'reporting-current-shared'
  $$,
  $$
    values (2::bigint, 4::numeric, 9::numeric, 9::numeric, 5::numeric, true)
  $$,
  'current assignment report scores remain correct'
);

set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*)::int
    from api.my_hub_activity_progress('reporting-current-beta')
  ),
  1,
  'beta learner reporting stays hub-scoped'
);

select is(
  (
    select count(*)::int
    from api.my_hub_activity_progress('reporting-current-alpha')
  ),
  0,
  'beta learner cannot read alpha hub progress'
);

set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*)::int
    from api.my_hub_activity_progress('reporting-current-alpha')
    where activity_key = 'reporting-current-shared'
      and completed
  ),
  1,
  'learner A reporting remains bound to auth.uid()'
);

reset role;

-- Newer published version becomes current for reporting without deleting old.
insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count, published_at
) values (
  '36e10000-0000-4000-8000-000000000005',
  '36d10000-0000-4000-8000-000000000001',
  '1.2.0',
  repeat('8', 64),
  10,
  1,
  timestamptz '2026-09-04 10:00:00+00'
);

insert into learning.activity_assignments (
  id, group_id, activity_version_id, required, active
) values (
  '36g10000-0000-4000-8000-000000000005',
  '36c10000-0000-4000-8000-000000000001',
  '36e10000-0000-4000-8000-000000000005',
  true,
  true
);

select is(
  learning.current_activity_assignment_id(
    '36c10000-0000-4000-8000-000000000001',
    '36d10000-0000-4000-8000-000000000001'
  ),
  '36g10000-0000-4000-8000-000000000005'::uuid,
  'assigning a later-published version replaces current membership selection'
);

select is(
  (
    select count(*)::int
    from learning.activity_assignments
    where group_id = '36c10000-0000-4000-8000-000000000001'
      and activity_version_id in (
        '36e10000-0000-4000-8000-000000000001',
        '36e10000-0000-4000-8000-000000000002',
        '36e10000-0000-4000-8000-000000000005'
      )
      and active
  ),
  3,
  'replacement retains all historical active assignment rows'
);

set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select activity_version
    from api.my_hub_activity_progress('reporting-current-alpha')
    where activity_key = 'reporting-current-shared'
  ),
  '1.2.0',
  'reporting follows current membership selection to 1.2.0'
);

select * from finish();
rollback;
