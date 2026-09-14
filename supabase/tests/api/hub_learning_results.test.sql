begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_function(
  'admin_api',
  'list_hub_learning_result_filters',
  array['text'],
  'hub result filter RPC exists'
);
select has_function(
  'admin_api',
  'list_hub_learning_results',
  array['text', 'text', 'text', 'text', 'integer', 'integer', 'text', 'text', 'integer'],
  'hub result list RPC exists'
);
select has_function(
  'admin_api',
  'summarise_hub_learning_results',
  array['text', 'text', 'text', 'text', 'integer', 'integer', 'text', 'text'],
  'hub result summary RPC exists'
);
select has_function(
  'admin_api',
  'list_hub_learning_result_evidence',
  array['text', 'text', 'uuid'],
  'hub result evidence RPC exists'
);

select ok(
  (
    select bool_and(coalesce(pg_catalog.array_to_string(proc.proconfig, ','), '') like '%search_path=%')
    from pg_catalog.pg_proc as proc
    join pg_catalog.pg_namespace as nsp on nsp.oid = proc.pronamespace
    where nsp.nspname in ('admin_api', 'learning')
      and proc.proname in (
        'staff_can_read_hub_results',
        'staff_visible_hub_group_ids',
        'staff_hub_learning_result_rows',
        'list_hub_learning_result_filters',
        'list_hub_learning_results',
        'summarise_hub_learning_results',
        'list_hub_learning_result_evidence'
      )
  ),
  'hub result functions set an explicit search_path'
);

select ok(
  not has_function_privilege(
    'anon',
    'admin_api.list_hub_learning_results(text,text,text,text,integer,integer,text,text,integer)',
    'EXECUTE'
  ),
  'anonymous clients cannot list hub learning results'
);
select ok(
  not has_function_privilege(
    'anon',
    'admin_api.list_hub_learning_result_filters(text)',
    'EXECUTE'
  ),
  'anonymous clients cannot list hub result filters'
);
select ok(
  not has_function_privilege(
    'anon',
    'admin_api.summarise_hub_learning_results(text,text,text,text,integer,integer,text,text)',
    'EXECUTE'
  ),
  'anonymous clients cannot summarise hub learning results'
);
select ok(
  not has_function_privilege(
    'anon',
    'admin_api.list_hub_learning_result_evidence(text,text,uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot read hub result evidence'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'learning.staff_can_read_hub_results(text)',
    'EXECUTE'
  ),
  'learners cannot execute the internal hub-results authorisation helper'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'learning.staff_hub_learning_result_rows(text,text,text,text,integer,integer,text,text)',
    'EXECUTE'
  ),
  'learners cannot execute the unbounded hub-results helper'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'learning.current_activity_assignment_id(uuid,uuid)',
    'EXECUTE'
  ),
  'current assignment helper stays revoked from authenticated'
);

insert into platform.hubs (
  id, hub_code, hub_name, description, hub_version, platform_version,
  manifest_version, core_version, learner_api_version, submission_contract_version,
  repository_url, deployment_url, activity_types, evidence_capabilities,
  features, compatibility, status, active, manifest, manifest_sha256
) values
  (
    '38a10000-0000-4000-8000-000000000001',
    'hub-results-alpha',
    'Hub Results Alpha',
    'Synthetic hub for staff hub-learning Results tests.',
    '0.1.0', '0.2.0', '1.0.0', '0.2.0', '0.1.0', '0.1.0',
    'https://example.invalid/hub-results-alpha',
    'https://example.invalid/hub-results-alpha/',
    array['retrieval-quiz'],
    array['question-level'],
    '{}'::jsonb, '{}'::jsonb, 'testing', true, '{}'::jsonb, repeat('a', 64)
  ),
  (
    '38a10000-0000-4000-8000-000000000002',
    'hub-results-beta',
    'Hub Results Beta',
    'Synthetic second hub for Results isolation.',
    '0.1.0', '0.2.0', '1.0.0', '0.2.0', '0.1.0', '0.1.0',
    'https://example.invalid/hub-results-beta',
    'https://example.invalid/hub-results-beta/',
    array['retrieval-quiz'],
    array['question-level'],
    '{}'::jsonb, '{}'::jsonb, 'testing', true, '{}'::jsonb, repeat('b', 64)
  );

insert into learning.modules (
  id, course_id, stable_key, title, active
)
select
  '38b10000-0000-4000-8000-000000000001',
  template.course_id,
  'hub-results-module',
  'Hub Results Module',
  true
from learning.groups as template
where template.id = '60000000-0000-4000-8000-000000000001';

insert into learning.curriculum_weeks (
  id, module_id, stable_key, title, week_number, sort_order, active
) values (
  '38b10000-0000-4000-8000-000000000011',
  '38b10000-0000-4000-8000-000000000001',
  'hub-results-week-1',
  'Hub Results Week 1',
  4,
  4,
  true
);

insert into platform.hub_course_links (hub_id, course_id, active)
select hub.id, template.course_id, true
from platform.hubs as hub
cross join learning.groups as template
where hub.hub_code in ('hub-results-alpha', 'hub-results-beta')
  and template.id = '60000000-0000-4000-8000-000000000001'
on conflict do nothing;

insert into learning.groups (
  id, academic_year_id, course_id, code, name, active, year_group,
  registration_key, registration_open
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
      '38c10000-0000-4000-8000-000000000001'::uuid,
      'HUB-RES-A',
      'Hub Results Group A',
      'hub-res-a'
    ),
    (
      '38c10000-0000-4000-8000-000000000002'::uuid,
      'HUB-RES-B',
      'Hub Results Group B',
      'hub-res-b'
    )
) as mapping(id, code, name, registration_key)
where template.id = '60000000-0000-4000-8000-000000000001';

insert into platform.hub_group_links (hub_id, group_id, active, join_policy)
values
  (
    '38a10000-0000-4000-8000-000000000001',
    '38c10000-0000-4000-8000-000000000001',
    true,
    'closed'
  ),
  (
    '38a10000-0000-4000-8000-000000000002',
    '38c10000-0000-4000-8000-000000000002',
    true,
    'closed'
  );

insert into learning.teacher_group_access (teacher_id, group_id, role, granted_at)
values (
  '31000000-0000-4000-8000-000000000002',
  '38c10000-0000-4000-8000-000000000001',
  'teacher',
  '2026-09-01T00:00:00Z'
);

insert into learning.students (
  id, student_number, first_name, surname, display_name, active
) values
  (
    '38d10000-0000-4000-8000-000000000001',
    'HUB-RES-S1',
    'Results',
    'One',
    'Results One',
    true
  ),
  (
    '38d10000-0000-4000-8000-000000000002',
    'HUB-RES-S2',
    'Results',
    'Two',
    'Results Two',
    true
  ),
  (
    '38d10000-0000-4000-8000-000000000003',
    'HUB-RES-S3',
    'Results',
    'Three',
    'Results Three',
    true
  ),
  (
    '38d10000-0000-4000-8000-000000000004',
    'HUB-RES-S4',
    'Results',
    'Left',
    'Results Left',
    true
  ),
  (
    '38d10000-0000-4000-8000-000000000005',
    'HUB-RES-S5',
    'Results',
    'Beta',
    'Results Beta',
    true
  );

insert into learning.enrolments (
  id, student_id, group_id, joined_on, left_on, status
) values
  (
    '38e10000-0000-4000-8000-000000000001',
    '38d10000-0000-4000-8000-000000000001',
    '38c10000-0000-4000-8000-000000000001',
    '2026-09-01',
    null,
    'active'
  ),
  (
    '38e10000-0000-4000-8000-000000000002',
    '38d10000-0000-4000-8000-000000000002',
    '38c10000-0000-4000-8000-000000000001',
    '2026-09-01',
    null,
    'active'
  ),
  (
    '38e10000-0000-4000-8000-000000000003',
    '38d10000-0000-4000-8000-000000000003',
    '38c10000-0000-4000-8000-000000000001',
    '2026-09-01',
    null,
    'active'
  ),
  (
    '38e10000-0000-4000-8000-000000000004',
    '38d10000-0000-4000-8000-000000000004',
    '38c10000-0000-4000-8000-000000000001',
    '2026-08-01',
    '2026-09-01',
    'withdrawn'
  ),
  (
    '38e10000-0000-4000-8000-000000000005',
    '38d10000-0000-4000-8000-000000000005',
    '38c10000-0000-4000-8000-000000000002',
    '2026-09-01',
    null,
    'active'
  );

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
) values
  (
    '38f10000-0000-4000-8000-000000000001',
    '38b10000-0000-4000-8000-000000000001',
    'hub-results-scored',
    'Hub Results Scored',
    'retrieval-quiz',
    'tests/hub-results-scored.html',
    true
  ),
  (
    '38f10000-0000-4000-8000-000000000002',
    '38b10000-0000-4000-8000-000000000001',
    'hub-results-practice',
    'Hub Results Practice',
    'retrieval-quiz',
    'tests/hub-results-practice.html',
    true
  ),
  (
    '38f10000-0000-4000-8000-000000000003',
    '38b10000-0000-4000-8000-000000000001',
    'hub-results-draft',
    'Hub Results Draft',
    'retrieval-quiz',
    'tests/hub-results-draft.html',
    true
  );

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count
) values
  (
    '39010000-0000-4000-8000-000000000001',
    '38f10000-0000-4000-8000-000000000001',
    '1.0.0',
    repeat('1', 64),
    10,
    1
  ),
  (
    '39010000-0000-4000-8000-000000000002',
    '38f10000-0000-4000-8000-000000000001',
    '1.1.0',
    repeat('2', 64),
    10,
    1
  ),
  (
    '39010000-0000-4000-8000-000000000003',
    '38f10000-0000-4000-8000-000000000002',
    '1.0.0',
    repeat('3', 64),
    5,
    1
  ),
  (
    '39010000-0000-4000-8000-000000000004',
    '38f10000-0000-4000-8000-000000000003',
    '1.0.0',
    repeat('4', 64),
    5,
    1
  );

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score
) values
  (
    '39110000-0000-4000-8000-000000000001',
    '39010000-0000-4000-8000-000000000001',
    'HR-Q1',
    'main',
    'Main',
    'single',
    'Historic Q1',
    1,
    10
  ),
  (
    '39110000-0000-4000-8000-000000000002',
    '39010000-0000-4000-8000-000000000002',
    'HR-Q1',
    'main',
    'Main',
    'single',
    'Current Q1',
    1,
    10
  ),
  (
    '39110000-0000-4000-8000-000000000003',
    '39010000-0000-4000-8000-000000000003',
    'HR-P1',
    'main',
    'Main',
    'single',
    'Practice Q1',
    1,
    5
  ),
  (
    '39110000-0000-4000-8000-000000000004',
    '39010000-0000-4000-8000-000000000004',
    'HR-D1',
    'main',
    'Main',
    'single',
    'Draft Q1',
    1,
    5
  );

insert into learning.question_marking (question_id, spec)
values (
  '39110000-0000-4000-8000-000000000002',
  '{"correctOptionId":"SECRET-KEY-NEVER-LEAK"}'::jsonb
);

update learning.activity_versions
set published_at = case id
  when '39010000-0000-4000-8000-000000000001' then timestamptz '2026-09-01 10:00:00+00'
  when '39010000-0000-4000-8000-000000000002' then timestamptz '2026-09-02 10:00:00+00'
  when '39010000-0000-4000-8000-000000000003' then timestamptz '2026-09-01 11:00:00+00'
  when '39010000-0000-4000-8000-000000000004' then timestamptz '2026-09-01 12:00:00+00'
end
where id in (
  '39010000-0000-4000-8000-000000000001',
  '39010000-0000-4000-8000-000000000002',
  '39010000-0000-4000-8000-000000000003',
  '39010000-0000-4000-8000-000000000004'
);

insert into learning.activity_delivery (
  id, activity_version_id, academic_year_id, group_id, curriculum_week_id,
  week_number, session_number, sort_order, active
)
select
  '39210000-0000-4000-8000-000000000001',
  '39010000-0000-4000-8000-000000000002',
  academic_year.id,
  null,
  '38b10000-0000-4000-8000-000000000011',
  4,
  2,
  1,
  true
from learning.academic_years as academic_year
where academic_year.active
order by academic_year.code
limit 1;

insert into learning.activity_assignments (
  id, group_id, activity_version_id, required, active
) values
  (
    '39310000-0000-4000-8000-000000000001',
    '38c10000-0000-4000-8000-000000000001',
    '39010000-0000-4000-8000-000000000001',
    true,
    true
  ),
  (
    '39310000-0000-4000-8000-000000000002',
    '38c10000-0000-4000-8000-000000000001',
    '39010000-0000-4000-8000-000000000002',
    true,
    true
  ),
  (
    '39310000-0000-4000-8000-000000000003',
    '38c10000-0000-4000-8000-000000000001',
    '39010000-0000-4000-8000-000000000003',
    true,
    true
  ),
  (
    '39310000-0000-4000-8000-000000000004',
    '38c10000-0000-4000-8000-000000000001',
    '39010000-0000-4000-8000-000000000004',
    true,
    true
  ),
  (
    '39310000-0000-4000-8000-000000000005',
    '38c10000-0000-4000-8000-000000000002',
    '39010000-0000-4000-8000-000000000002',
    true,
    true
  );

-- Historic completion against older 1.0.0. Current work is 1.1.0.
insert into learning.attempts (
  id, client_attempt_id, student_id, enrolment_id, assignment_id,
  activity_version_id, attempt_number, status, score, max_score,
  marking_source, evidence_level, submission_hash, received_at, completed_at
) values
  (
    '39410000-0000-4000-8000-000000000001',
    'hr-hist-1',
    '38d10000-0000-4000-8000-000000000001',
    '38e10000-0000-4000-8000-000000000001',
    '39310000-0000-4000-8000-000000000001',
    '39010000-0000-4000-8000-000000000001',
    1,
    'completed',
    10,
    10,
    'server',
    'question_level',
    repeat('5', 64),
    timestamptz '2026-09-01 12:00:00+00',
    timestamptz '2026-09-01 12:05:00+00'
  ),
  (
    '39410000-0000-4000-8000-000000000002',
    'hr-current-s1',
    '38d10000-0000-4000-8000-000000000001',
    '38e10000-0000-4000-8000-000000000001',
    '39310000-0000-4000-8000-000000000002',
    '39010000-0000-4000-8000-000000000002',
    1,
    'completed',
    8,
    10,
    'server',
    'question_level',
    repeat('6', 64),
    timestamptz '2026-09-03 12:00:00+00',
    timestamptz '2026-09-03 12:05:00+00'
  ),
  (
    '39410000-0000-4000-8000-000000000003',
    'hr-beta-s5',
    '38d10000-0000-4000-8000-000000000005',
    '38e10000-0000-4000-8000-000000000005',
    '39310000-0000-4000-8000-000000000005',
    '39010000-0000-4000-8000-000000000002',
    1,
    'completed',
    4,
    10,
    'server',
    'question_level',
    repeat('7', 64),
    timestamptz '2026-09-03 13:00:00+00',
    timestamptz '2026-09-03 13:05:00+00'
  );

insert into learning.responses (
  id, attempt_id, question_id, response_payload, awarded_score, max_score,
  is_correct, requires_review, marking_source, feedback_summary
) values
  (
    '39510000-0000-4000-8000-000000000001',
    '39410000-0000-4000-8000-000000000002',
    '39110000-0000-4000-8000-000000000002',
    '{"selected":"A"}'::jsonb,
    8,
    10,
    true,
    false,
    'server',
    'Keep using the official method.'
  ),
  (
    '39510000-0000-4000-8000-000000000002',
    '39410000-0000-4000-8000-000000000003',
    '39110000-0000-4000-8000-000000000002',
    '{"selected":"B"}'::jsonb,
    4,
    10,
    false,
    false,
    'server',
    null
  );

insert into learning.formative_checks (
  client_check_id, student_id, assignment_id, activity_version_id, question_id,
  check_number, response_type, response_payload, awarded_score, max_score,
  is_correct, requires_review, marking_source, request_hash, source_page
) values (
  'hr-formative-1',
  '38d10000-0000-4000-8000-000000000002',
  '39310000-0000-4000-8000-000000000003',
  '39010000-0000-4000-8000-000000000003',
  '39110000-0000-4000-8000-000000000003',
  1,
  'single-choice',
  '{"optionId":"practice-choice"}'::jsonb,
  5,
  5,
  true,
  false,
  'server',
  repeat('9', 64),
  '/hub-results/'
);

insert into learning.activity_states (
  student_id, assignment_id, activity_version_id, state_payload, status
) values (
  '38d10000-0000-4000-8000-000000000002',
  '39310000-0000-4000-8000-000000000004',
  '39010000-0000-4000-8000-000000000004',
  '{"responses":{"HR-D1":"draft-only"}}'::jsonb,
  'in_progress'
);

-- Learner identity cannot read staff hub results.
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*)::int
    from admin_api.list_hub_learning_results('hub-results-alpha')
  ),
  0,
  'a learner receives no hub learning results'
);

reset role;

-- Ordinary teacher without the hub group sees nothing.
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*)::int
    from admin_api.list_hub_learning_results('hub-results-alpha')
  ),
  0,
  'a teacher without the hub group cannot read its results'
);

reset role;

-- Teacher B can read HUB-RES-A only.
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(distinct group_code)::int
    from admin_api.list_hub_learning_results('hub-results-alpha')
  ),
  1,
  'a group teacher only sees the permitted hub group'
);

select is(
  (
    select count(*)::int
    from admin_api.list_hub_learning_results('hub-results-beta')
  ),
  0,
  'a group teacher cannot read an unbound hub'
);

reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select count(*)::int
    from admin_api.list_hub_learning_results('hub-results-alpha')
    where student_number = 'HUB-RES-S4'
  ),
  0,
  'historic membership does not appear in current class reporting'
);

select is(
  (
    select count(*)::int
    from admin_api.list_hub_learning_results(
      'hub-results-alpha',
      null,
      null,
      null,
      null,
      null,
      'hub-results-scored'
    )
    where assignment_id = '39310000-0000-4000-8000-000000000001'
  ),
  0,
  'historical assignments are not current required work'
);

select is(
  (
    select completion_status
    from admin_api.list_hub_learning_results(
      'hub-results-alpha',
      null,
      'HUB-RES-A',
      'HUB-RES-S1',
      null,
      null,
      'hub-results-scored'
    )
  ),
  'completed',
  'official completed attempts are reported as completed'
);

select is(
  (
    select scored and score_percentage = 80
    from admin_api.list_hub_learning_results(
      'hub-results-alpha',
      null,
      'HUB-RES-A',
      'HUB-RES-S1',
      null,
      null,
      'hub-results-scored'
    )
  ),
  true,
  'percentages come only from official completed attempts'
);

select is(
  (
    select completion_status || ':' || result_source || ':' || scored::text
    from admin_api.list_hub_learning_results(
      'hub-results-alpha',
      null,
      'HUB-RES-A',
      'HUB-RES-S2',
      null,
      null,
      'hub-results-practice'
    )
  ),
  'in_progress:formative:false',
  'formative practice is in progress and is not scored as an assignment'
);

select ok(
  (
    select last_activity_at is not null
    from admin_api.list_hub_learning_results(
      'hub-results-alpha',
      null,
      'HUB-RES-A',
      'HUB-RES-S2',
      null,
      null,
      'hub-results-practice'
    )
  ),
  'formative practice contributes to last_activity_at'
);

select is(
  (
    select completion_status || ':' || result_source || ':' || coalesce(score_percentage::text, '-')
    from admin_api.list_hub_learning_results(
      'hub-results-alpha',
      null,
      'HUB-RES-A',
      'HUB-RES-S2',
      null,
      null,
      'hub-results-draft'
    )
  ),
  'in_progress:activity_state:-',
  'activity drafts are in progress and do not manufacture a percentage'
);

select is(
  (
    select completion_status
    from admin_api.list_hub_learning_results(
      'hub-results-alpha',
      null,
      'HUB-RES-A',
      'HUB-RES-S3',
      null,
      null,
      'hub-results-scored'
    )
  ),
  'not_started',
  'assigned learners with no evidence are not started'
);

select is(
  (
    select count(*)::int
    from admin_api.list_hub_learning_results(
      'hub-results-alpha',
      null,
      'HUB-RES-A'
    )
    where student_number = 'HUB-RES-S5'
  ),
  0,
  'alpha reporting does not include beta-hub learners'
);

select is(
  (
    select count(*)::int
    from admin_api.list_hub_learning_results('hub-results-beta')
    where student_number = 'HUB-RES-S1'
  ),
  0,
  'beta reporting does not include alpha-hub learners'
);

select is(
  (
    select count(*)::int
    from admin_api.list_hub_learning_results(
      'hub-results-alpha',
      null,
      null,
      'HUB-RES-S1'
    )
  ),
  (
    select count(*)::int
    from admin_api.list_hub_learning_results('hub-results-alpha')
    where student_number = 'HUB-RES-S1'
  ),
  'learner filtering uses student_number rather than a browser learner_id'
);

select is(
  (
    select count(*)::int
    from admin_api.list_hub_learning_results(
      'hub-results-alpha',
      null,
      null,
      null,
      4,
      2,
      'hub-results-scored',
      'completed'
    )
  ),
  1,
  'week, session, activity and status filters apply together'
);

select is(
  (
    select average_score_percentage
    from admin_api.summarise_hub_learning_results('hub-results-alpha', null, 'HUB-RES-A')
  ),
  80.00,
  'average score ignores formative and unscored rows'
);

select is(
  (
    select completed_count
    from admin_api.summarise_hub_learning_results(
      'hub-results-alpha',
      null,
      'HUB-RES-A',
      null,
      null,
      null,
      'hub-results-scored'
    )
  ),
  1::bigint,
  'scored activity summary counts only official completions'
);

select ok(
  (
    select jsonb_pretty(to_jsonb(evidence)) not like '%SECRET-KEY-NEVER-LEAK%'
      and evidence.response_payload ? 'selected'
      and evidence.feedback_summary = 'Keep using the official method.'
    from admin_api.list_hub_learning_result_evidence(
      'hub-results-alpha',
      'HUB-RES-S1',
      '39310000-0000-4000-8000-000000000002'
    ) as evidence
    limit 1
  ),
  'evidence returns the learner response and feedback, not the answer key'
);

select is(
  (
    select source
    from admin_api.list_hub_learning_result_evidence(
      'hub-results-alpha',
      'HUB-RES-S2',
      '39310000-0000-4000-8000-000000000003'
    )
  ),
  'formative',
  'practice drill-down uses formative evidence when there is no official attempt'
);

select is(
  (
    select count(*)::int
    from admin_api.list_hub_learning_result_evidence(
      'hub-results-beta',
      'HUB-RES-S1',
      '39310000-0000-4000-8000-000000000002'
    )
  ),
  0,
  'evidence is hub-isolated'
);

select ok(
  (
    select bool_and(week_number = 4)
    from admin_api.list_hub_learning_result_filters('hub-results-alpha')
    where activity_key = 'hub-results-scored'
  ),
  'filter options expose week and activity metadata for the hub'
);

reset role;

select * from finish();
rollback;
