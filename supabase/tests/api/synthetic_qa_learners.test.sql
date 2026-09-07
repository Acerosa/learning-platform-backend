begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

insert into learning.courses (
  id, stable_key, code, title, qualification_level, active
)
select
  'c2000000-0000-4000-8000-000000000001',
  'gateway-level-2-digital-it-skills',
  'GW-L2E',
  'Gateway Qualifications Level 2 Certificate in Digital and IT Skills',
  'Level 2',
  true
where not exists (
  select 1 from learning.courses where stable_key = 'gateway-level-2-digital-it-skills'
);

insert into learning.modules (
  id, course_id, stable_key, title, sort_order, active
)
select
  'c2100000-0000-4000-8000-000000000001',
  course.id,
  'l2e-exploring-emerging-digital-technologies',
  'Exploring New and Emerging Digital Technologies',
  1,
  true
from learning.courses as course
where course.stable_key = 'gateway-level-2-digital-it-skills'
  and not exists (
    select 1
    from learning.modules as module
    where module.course_id = course.id
      and module.stable_key = 'l2e-exploring-emerging-digital-technologies'
  );

insert into learning.modules (
  id, course_id, stable_key, title, sort_order, active
)
select
  'c2200000-0000-4000-8000-000000000001',
  course.id,
  'tlevel-software-development',
  'T Level Digital Software Development',
  2,
  true
from learning.courses as course
where course.stable_key = 't-level-digital-software-development'
  and not exists (
    select 1
    from learning.modules as module
    where module.course_id = course.id
      and module.stable_key = 'tlevel-software-development'
  );

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
)
select
  'a2100000-0000-4000-8000-000000000001',
  module.id,
  'week-1-knowledge-check',
  'L2E synthetic QA knowledge check',
  'retrieval-quiz',
  'supabase/tests/api/synthetic_qa_learners.test.sql',
  true
from learning.modules as module
where module.stable_key = 'l2e-exploring-emerging-digital-technologies'
  and not exists (
    select 1 from learning.activities where stable_key = 'week-1-knowledge-check'
  );

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count, published_at
)
select
  'a2100000-0000-4000-8000-000000000002',
  activity.id,
  '0.1.0',
  repeat('e', 64),
  1,
  1,
  null
from learning.activities as activity
where activity.stable_key = 'week-1-knowledge-check'
  and not exists (
    select 1
    from learning.activity_versions as version
    where version.activity_id = activity.id
  );

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score
)
select
  'a2100000-0000-4000-8000-000000000003',
  version.id,
  'l2e-qa-q1',
  'week-1',
  'Week 1',
  'single',
  'L2E QA question',
  1,
  1
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where activity.stable_key = 'week-1-knowledge-check'
  and not exists (
    select 1 from learning.questions where stable_key = 'l2e-qa-q1'
  );

insert into learning.question_marking (question_id, spec)
select question.id, '{"mode":"single-choice","correctOptionId":"qa-correct"}'::jsonb
from learning.questions as question
where question.stable_key = 'l2e-qa-q1'
  and not exists (
    select 1 from learning.question_marking as marking
    where marking.question_id = question.id
  );

update learning.activity_versions as version
set published_at = clock_timestamp()
from learning.activities as activity
where activity.id = version.activity_id
  and activity.stable_key = 'week-1-knowledge-check'
  and version.published_at is null;

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
)
select
  'a2200000-0000-4000-8000-000000000001',
  module.id,
  'week-1-lesson-1-ex-01',
  'T Level synthetic QA retrieval',
  'retrieval-quiz',
  'supabase/tests/api/synthetic_qa_learners.test.sql',
  true
from learning.modules as module
where module.stable_key = 'tlevel-software-development'
  and not exists (
    select 1 from learning.activities where stable_key = 'week-1-lesson-1-ex-01'
  );

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count, published_at
)
select
  'a2200000-0000-4000-8000-000000000002',
  activity.id,
  '0.1.0',
  repeat('f', 64),
  1,
  1,
  null
from learning.activities as activity
where activity.stable_key = 'week-1-lesson-1-ex-01'
  and not exists (
    select 1
    from learning.activity_versions as version
    where version.activity_id = activity.id
  );

insert into learning.questions (
  id, activity_version_id, stable_key, section_key, section_title,
  question_type, analytics_title, ordinal, max_score
)
select
  'a2200000-0000-4000-8000-000000000003',
  version.id,
  'tlevel-qa-q1',
  'week-1',
  'Week 1',
  'single',
  'T Level QA question',
  1,
  1
from learning.activity_versions as version
join learning.activities as activity on activity.id = version.activity_id
where activity.stable_key = 'week-1-lesson-1-ex-01'
  and not exists (
    select 1 from learning.questions where stable_key = 'tlevel-qa-q1'
  );

insert into learning.question_marking (question_id, spec)
select question.id, '{"mode":"single-choice","correctOptionId":"qa-correct"}'::jsonb
from learning.questions as question
where question.stable_key = 'tlevel-qa-q1'
  and not exists (
    select 1 from learning.question_marking as marking
    where marking.question_id = question.id
  );

update learning.activity_versions as version
set published_at = clock_timestamp()
from learning.activities as activity
where activity.id = version.activity_id
  and activity.stable_key = 'week-1-lesson-1-ex-01'
  and version.published_at is null;

insert into learning.activities (
  id, module_id, stable_key, title, activity_type, git_path, active
)
select extra.id, module.id, extra.stable_key, extra.title, 'retrieval-quiz',
  'supabase/tests/api/synthetic_qa_learners.test.sql', true
from learning.modules as module
cross join (
  values
    (
      'a2300000-0000-4000-8000-000000000001'::uuid,
      'week-1-lesson-1-ex-07',
      'T Level classification QA'
    ),
    (
      'a2300000-0000-4000-8000-000000000011'::uuid,
      'week-1-lesson-1-ex-13',
      'T Level drag-drop QA'
    ),
    (
      'a2300000-0000-4000-8000-000000000021'::uuid,
      'week-1-lesson-1-ex-20',
      'T Level short-response QA'
    )
) as extra(id, stable_key, title)
where module.stable_key = 'tlevel-software-development'
  and not exists (
    select 1 from learning.activities where stable_key = extra.stable_key
  );

insert into learning.activity_versions (
  id, activity_id, version, content_hash, max_score, question_count, published_at
)
select extra.version_id, activity.id, '0.1.0', extra.content_hash, 1, 1, clock_timestamp()
from (
  values
    (
      'a2300000-0000-4000-8000-000000000002'::uuid,
      'week-1-lesson-1-ex-07',
      repeat('7', 64)
    ),
    (
      'a2300000-0000-4000-8000-000000000012'::uuid,
      'week-1-lesson-1-ex-13',
      repeat('d', 64)
    ),
    (
      'a2300000-0000-4000-8000-000000000022'::uuid,
      'week-1-lesson-1-ex-20',
      repeat('2', 64)
    )
) as extra(version_id, stable_key, content_hash)
join learning.activities as activity on activity.stable_key = extra.stable_key
where not exists (
  select 1
  from learning.activity_versions as version
  where version.activity_id = activity.id
);

insert into learning.groups (
  id, academic_year_id, course_id, code, name, active, year_group,
  registration_key, registration_open, is_synthetic
)
select
  '60000000-0000-4000-8000-000000000031',
  academic_year.id,
  course.id,
  'TLEVEL-DSD-Y2',
  'T Level Digital Software Development - Year 2',
  true,
  'Year 2',
  'tlevel-dsd-y2-reg',
  true,
  false
from learning.academic_years as academic_year
join learning.courses as course
  on course.stable_key = 't-level-digital-software-development'
where academic_year.active
on conflict (academic_year_id, course_id, code) do update
set
  name = excluded.name,
  active = true,
  year_group = excluded.year_group,
  registration_key = excluded.registration_key,
  registration_open = excluded.registration_open,
  is_synthetic = false,
  synthetic_purpose = null;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  '13000000-0000-4000-8000-000000000007'::uuid,
  'authenticated',
  'authenticated',
  'tlevel.y2.teaching@local.invalid',
  null,
  clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"fixture":"tlevel-dsd-y2-teaching"}'::jsonb,
  clock_timestamp(),
  clock_timestamp()
where not exists (
  select 1 from auth.users where id = '13000000-0000-4000-8000-000000000007'
);

insert into learning.students (
  id, auth_user_id, student_number, first_name, surname, display_name, active,
  is_synthetic
) values (
  '30000000-0000-4000-8000-000000000031',
  '13000000-0000-4000-8000-000000000007',
  'TLEVEL-Y2-0001',
  'Year',
  'Two',
  'T Level Year 2 Learner',
  true,
  false
)
on conflict (student_number) do update
set
  auth_user_id = excluded.auth_user_id,
  first_name = excluded.first_name,
  surname = excluded.surname,
  display_name = excluded.display_name,
  active = true,
  is_synthetic = false;

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
  on learner_group.code = 'TLEVEL-DSD-Y2'
where student.student_number = 'TLEVEL-Y2-0001'
on conflict (student_id, group_id, joined_on) do nothing;

insert into learning.activity_assignments (
  id, group_id, activity_version_id, required, active
)
select
  md5('dsd-y2-teaching:' || activity.stable_key)::uuid,
  learner_group.id,
  version.id,
  true,
  true
from learning.groups as learner_group
join learning.activities as activity
  on activity.stable_key in (
    'week-1-lesson-1-ex-07',
    'week-1-lesson-1-ex-13',
    'week-1-lesson-1-ex-20'
  )
join learning.activity_versions as version
  on version.activity_id = activity.id
where learner_group.code = 'TLEVEL-DSD-Y2'
on conflict (group_id, activity_version_id) do update
set active = true, required = true;

create temporary table dsd_y2_teaching_snapshot as
select
  student.id,
  student.auth_user_id,
  student.student_number,
  student.first_name,
  student.surname,
  student.display_name,
  student.active,
  student.is_synthetic,
  student.updated_at,
  enrolment.id as enrolment_id,
  enrolment.status as enrolment_status,
  enrolment.group_id
from learning.students as student
join learning.enrolments as enrolment
  on enrolment.student_id = student.id
join learning.groups as learner_group
  on learner_group.id = enrolment.group_id
where student.student_number = 'TLEVEL-Y2-0001'
  and learner_group.code = 'TLEVEL-DSD-Y2'
  and enrolment.status = 'active';

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  fixture.id,
  'authenticated',
  'authenticated',
  fixture.email,
  null,
  clock_timestamp(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object(
    'synthetic', true,
    'purpose', 'formative-smoke-test',
    'persona', fixture.persona
  ),
  clock_timestamp(),
  clock_timestamp()
from (
  values
    (
      '13000000-0000-4000-8000-000000000001'::uuid,
      'qa.unit3@local.invalid',
      'UNIT3_TEST_LEARNER'
    ),
    (
      '13000000-0000-4000-8000-000000000002'::uuid,
      'qa.tlevel@local.invalid',
      'TLEVEL_TEST_LEARNER'
    ),
    (
      '13000000-0000-4000-8000-000000000003'::uuid,
      'qa.unit14@local.invalid',
      'UNIT14_TEST_LEARNER'
    ),
    (
      '13000000-0000-4000-8000-000000000004'::uuid,
      'qa.l2e@local.invalid',
      'L2E_TEST_LEARNER'
    ),
    (
      '13000000-0000-4000-8000-000000000006'::uuid,
      'qa.tlevel.dsd.y2@local.invalid',
      'TLEVEL_DSD_Y2_TEST_LEARNER'
    ),
    (
      '13000000-0000-4000-8000-000000000005'::uuid,
      'qa.conflict@local.invalid',
      'CONFLICT'
    )
) as fixture(id, email, persona);

select lives_ok(
  $$select * from learning.ensure_synthetic_qa_groups()$$,
  'ensure_synthetic_qa_groups is idempotent for the catalogued fixtures'
);

select is(
  (
    select count(*)
    from learning.groups
    where code in ('CYBER-TEST-QA', 'TLEVEL-TEST-A', 'UNIT14-TEST-A', 'L2E-TEST-A')
      and is_synthetic
      and active
      and not registration_open
  ),
  4::bigint,
  'four isolated synthetic QA groups are active and closed for self-registration'
);

select is(
  (
    select created_or_reused
    from learning.ensure_synthetic_qa_groups()
    where persona = 'TLEVEL_DSD_Y2_TEST_LEARNER'
  ),
  'joined',
  'DSD Y2 QA fixture joins the existing teaching group instead of creating one'
);

select ok(
  exists (
    select 1
    from learning.groups
    where code = 'TLEVEL-DSD-Y2'
      and active
      and not is_synthetic
      and registration_open
      and registration_key = 'tlevel-dsd-y2-reg'
      and year_group = 'Year 2'
      and name = 'T Level Digital Software Development - Year 2'
      and synthetic_purpose is null
  ),
  'joining TLEVEL-DSD-Y2 does not convert the teaching group to synthetic or close registration'
);

select is(
  (
    select count(*)
    from learning.groups
    where code = 'TLEVEL-DSD-Y2'
  ),
  1::bigint,
  'ensure does not create a second TLEVEL-DSD-Y2 group'
);

select ok(
  not exists (
    select 1
    from learning.groups
    where code in ('TLEVEL-TEST-B', 'TLEVEL-DSD-Y2-QA')
  ),
  'ensure does not create a substitute T Level QA group'
);

select is(
  (
    select count(distinct activity.stable_key)
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where learner_group.code = 'CYBER-TEST-QA'
      and assignment.active
  ),
  1::bigint,
  'CYBER-TEST-QA is assigned only the explicit Unit 3 smoke activity, not the full catalogue'
);

select ok(
  exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where learner_group.code = 'CYBER-TEST-QA'
      and assignment.active
      and activity.stable_key = 'week2-malware-symptoms'
  ),
  'CYBER-TEST-QA includes week2-malware-symptoms as its smoke assignment'
);

select is(
  (
    select count(*)
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where learner_group.code = 'TLEVEL-TEST-A'
      and assignment.active
      and activity.stable_key = 'week-1-lesson-1-ex-01'
  ),
  1::bigint,
  'TLEVEL-TEST-A has the explicit T Level smoke assignment when the module exists'
);

select ok(
  not exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where learner_group.code = 'TLEVEL-TEST-A'
      and assignment.active
      and activity.stable_key <> 'week-1-lesson-1-ex-01'
  ),
  'TLEVEL-TEST-A remains exclusive to week-1-lesson-1-ex-01 after the DSD Y2 fixture'
);

select is(
  (
    select array_agg(activity.stable_key order by activity.stable_key)
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where learner_group.code = 'TLEVEL-DSD-Y2'
      and assignment.active
      and activity.stable_key in (
        'week-1-lesson-1-ex-07',
        'week-1-lesson-1-ex-13',
        'week-1-lesson-1-ex-20'
      )
  ),
  array[
    'week-1-lesson-1-ex-07',
    'week-1-lesson-1-ex-13',
    'week-1-lesson-1-ex-20'
  ]::text[],
  'TLEVEL-DSD-Y2 keeps its teaching assignments for ex-07, ex-13 and ex-20'
);

select ok(
  exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where learner_group.code = 'UNIT14-TEST-A'
      and assignment.active
      and activity.stable_key = 'week-1-variables-and-data-types'
  ),
  'UNIT14-TEST-A retains the explicit Unit 14 smoke assignment'
);

select is(
  (
    select count(*)
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where learner_group.code = 'L2E-TEST-A'
      and assignment.active
      and activity.stable_key = 'week-1-knowledge-check'
  ),
  1::bigint,
  'L2E-TEST-A has the explicit L2E smoke assignment when the module exists'
);

select ok(
  not exists (
    select 1
    from learning.synthetic_qa_allowed_activity_keys('L2E_TEST_LEARNER') as allowed
    join learning.activities as activity
      on activity.stable_key = allowed.activity_key
    join learning.modules as module
      on module.id = activity.module_id
    join learning.activity_versions as version
      on version.activity_id = activity.id
    where module.stable_key = 'l2e-exploring-emerging-digital-technologies'
      and version.published_at is not null
      and version.retired_at is null
      and not exists (
        select 1
        from learning.activity_assignments as assignment
        join learning.groups as learner_group on learner_group.id = assignment.group_id
        where learner_group.code = 'L2E-TEST-A'
          and assignment.active
          and assignment.activity_version_id = version.id
      )
  ),
  'every published catalogued L2E Week 1 smoke activity is assigned to L2E-TEST-A'
);

select ok(
  not exists (
    select 1
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as version on version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    where learner_group.code = 'L2E-TEST-A'
      and assignment.active
      and activity.stable_key not in (
        select allowed.activity_key
        from learning.synthetic_qa_allowed_activity_keys('L2E_TEST_LEARNER') as allowed
      )
  ),
  'L2E-TEST-A is not assigned unpublished, review-only, or Week 2/3 L2E activities'
);

set local role anon;
select throws_like(
  $$select * from admin_api.ensure_synthetic_qa_groups()$$,
  '%permission denied%',
  'anonymous callers cannot refresh synthetic QA groups'
);
select throws_like(
  $$select * from admin_api.inspect_synthetic_qa_learners()$$,
  '%permission denied%',
  'anonymous callers cannot inspect synthetic QA readiness'
);
reset role;

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from admin_api.provision_synthetic_qa_learner(
    '13000000-0000-4000-8000-000000000001',
    'UNIT3_TEST_LEARNER'
  )$$,
  '42501',
  'SYNTHETIC_QA_NOT_AUTHORISED',
  'ordinary learners cannot provision synthetic QA accounts'
);
select throws_ok(
  $$select * from admin_api.inspect_synthetic_qa_learners()$$,
  '42501',
  'SYNTHETIC_QA_NOT_AUTHORISED',
  'ordinary learners cannot inspect synthetic QA readiness'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select lives_ok(
  $$select * from admin_api.ensure_synthetic_qa_groups()$$,
  'a platform administrator can refresh synthetic QA groups'
);

select is(
  (
    select group_code
    from admin_api.provision_synthetic_qa_learner(
      '13000000-0000-4000-8000-000000000001',
      'UNIT3_TEST_LEARNER'
    )
  ),
  'CYBER-TEST-QA',
  'Unit 3 QA learner is enrolled only through the isolated Cyber QA group'
);

select is(
  (
    select idempotent
    from admin_api.provision_synthetic_qa_learner(
      '13000000-0000-4000-8000-000000000001',
      'UNIT3_TEST_LEARNER'
    )
  ),
  true,
  're-provisioning the same Auth user and persona is idempotent'
);

select is(
  (
    select group_code
    from admin_api.provision_synthetic_qa_learner(
      '13000000-0000-4000-8000-000000000002',
      'TLEVEL_TEST_LEARNER'
    )
  ),
  'TLEVEL-TEST-A',
  'T Level QA learner is enrolled in TLEVEL-TEST-A'
);

select is(
  (
    select group_code
    from admin_api.provision_synthetic_qa_learner(
      '13000000-0000-4000-8000-000000000003',
      'UNIT14_TEST_LEARNER'
    )
  ),
  'UNIT14-TEST-A',
  'Unit 14 QA learner reuses UNIT14-TEST-A'
);

select is(
  (
    select group_code
    from admin_api.provision_synthetic_qa_learner(
      '13000000-0000-4000-8000-000000000004',
      'L2E_TEST_LEARNER'
    )
  ),
  'L2E-TEST-A',
  'L2E QA learner is enrolled in L2E-TEST-A'
);

select is(
  (
    select group_code
    from admin_api.provision_synthetic_qa_learner(
      '13000000-0000-4000-8000-000000000006',
      'TLEVEL_DSD_Y2_TEST_LEARNER'
    )
  ),
  'TLEVEL-DSD-Y2',
  'DSD Y2 QA learner is enrolled in the existing TLEVEL-DSD-Y2 teaching group'
);

select is(
  (
    select idempotent
    from admin_api.provision_synthetic_qa_learner(
      '13000000-0000-4000-8000-000000000006',
      'TLEVEL_DSD_Y2_TEST_LEARNER'
    )
  ),
  true,
  're-provisioning the DSD Y2 QA learner is idempotent'
);

select throws_ok(
  $$select * from admin_api.provision_synthetic_qa_learner(
    '13000000-0000-4000-8000-000000000007',
    'TLEVEL_DSD_Y2_TEST_LEARNER'
  )$$,
  '23000',
  'AUTH_ACCOUNT_ALREADY_LINKED',
  'the real TLEVEL-DSD-Y2 teaching Auth user cannot be converted into the QA persona'
);

select throws_ok(
  $$select * from admin_api.provision_synthetic_qa_learner(
    '13000000-0000-4000-8000-000000000001',
    'TLEVEL_TEST_LEARNER'
  )$$,
  '23000',
  'AUTH_ACCOUNT_ALREADY_LINKED',
  'an Auth user already linked to one persona cannot be enrolled in another hub fixture'
);

select throws_ok(
  $$select * from admin_api.provision_synthetic_qa_learner(
    '20000000-0000-4000-8000-000000000003',
    'UNIT3_TEST_LEARNER'
  )$$,
  '42501',
  'SYNTHETIC_STAFF_FORBIDDEN',
  'staff Auth identities cannot be provisioned as synthetic learners'
);
reset role;

select is(
  (
    select contact_email
    from learning.students
    where student_number = 'QA-UNIT3'
  ),
  null,
  'synthetic provisioning does not copy Auth email into learning.students'
);

select is(
  (
    select count(*)
    from learning.students
    where student_number in (
      'QA-UNIT3', 'QA-TLEVEL', 'QA-UNIT14', 'QA-L2E', 'QA-TLEVEL-DSD-Y2'
    )
      and is_synthetic
      and contact_email is null
      and active
  ),
  5::bigint,
  'five synthetic QA learners exist without duplicated contact email'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;
select is(
  (
    select student_present and student_active and is_synthetic
      and not contact_email_copied
      and smoke_assigned
      and enrolment_codes = array['CYBER-TEST-QA']::text[]
    from admin_api.inspect_synthetic_qa_learners()
    where persona = 'UNIT3_TEST_LEARNER'
  ),
  true,
  'platform admin inspect reports Unit 3 QA readiness without copied email'
);

select is(
  (
    select student_present and student_active and is_synthetic
      and not contact_email_copied
      and smoke_assigned
      and enrolment_codes = array['TLEVEL-TEST-A']::text[]
    from admin_api.inspect_synthetic_qa_learners()
    where persona = 'TLEVEL_TEST_LEARNER'
  ),
  true,
  'existing TLEVEL_TEST_LEARNER remains enrolled only in exclusive TLEVEL-TEST-A'
);

select is(
  (
    select student_present and student_active and is_synthetic
      and not contact_email_copied
      and smoke_assigned
      and enrolment_codes = array['TLEVEL-DSD-Y2']::text[]
      and smoke_activity_key = 'week-1-lesson-1-ex-07'
    from admin_api.inspect_synthetic_qa_learners()
    where persona = 'TLEVEL_DSD_Y2_TEST_LEARNER'
  ),
  true,
  'DSD Y2 QA inspect shows a synthetic learner on TLEVEL-DSD-Y2 with the teaching assignment probe'
);
reset role;

set local "request.jwt.claim.role" = 'service_role';
set local "request.jwt.claims" = '{"role":"service_role"}';
set local role service_role;
select lives_ok(
  $$select * from admin_api.inspect_synthetic_qa_learners()$$,
  'service_role can inspect synthetic QA readiness'
);
select is(
  (
    select count(*)::integer
    from admin_api.inspect_synthetic_qa_learners()
  ),
  5,
  'service_role inspect returns one row per QA persona'
);
reset role;

select is(
  has_schema_privilege('service_role', 'admin_api', 'USAGE'),
  true,
  'service_role has usage on admin_api for inspect and provision RPCs'
);

select is(
  has_schema_privilege('service_role', 'learning', 'USAGE'),
  false,
  'service_role is not granted usage on the unexposed learning schema'
);

select is(
  (
    select count(*)
    from learning.teachers as teacher
    join learning.students as student
      on student.auth_user_id = teacher.auth_user_id
    where student.student_number like 'QA-%'
  ),
  0::bigint,
  'synthetic QA learners are not linked to staff profiles'
);

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    join learning.groups as learner_group on learner_group.id = enrolment.group_id
    where student.student_number = 'QA-UNIT3'
      and enrolment.status = 'active'
      and learner_group.code <> 'CYBER-TEST-QA'
  ),
  0::bigint,
  'Unit 3 QA learner has no active enrolment outside CYBER-TEST-QA'
);

select is(
  (
    select array_agg(learner_group.code order by learner_group.code)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    join learning.groups as learner_group on learner_group.id = enrolment.group_id
    where student.student_number in (
      'QA-UNIT3', 'QA-TLEVEL', 'QA-UNIT14', 'QA-L2E', 'QA-TLEVEL-DSD-Y2'
    )
      and enrolment.status = 'active'
  ),
  array[
    'CYBER-TEST-QA',
    'L2E-TEST-A',
    'TLEVEL-DSD-Y2',
    'TLEVEL-TEST-A',
    'UNIT14-TEST-A'
  ]::text[],
  'each synthetic QA learner is enrolled in exactly one matching catalogued group'
);

select throws_ok(
  $$
    insert into learning.teachers (
      auth_user_id, staff_reference, display_name, active
    ) values (
      '13000000-0000-4000-8000-000000000001',
      'QA-FORBIDDEN',
      'Should not exist',
      true
    )
  $$,
  '42501',
  'SYNTHETIC_STAFF_FORBIDDEN',
  'a synthetic learner Auth identity cannot be given a staff profile'
);

create function pg_temp.qa_latest_version(p_activity_key text)
returns text
language sql
stable
as $$
  select version.version
  from learning.activities as activity
  join learning.activity_versions as version
    on version.activity_id = activity.id
  where activity.stable_key = p_activity_key
    and version.published_at is not null
    and version.retired_at is null
  order by version.published_at desc, version.version desc
  limit 1
$$;

create function pg_temp.qa_choice_question(p_activity_key text)
returns table (question_key text, correct_option text)
language sql
stable
as $$
  select question.stable_key, marking.spec ->> 'correctOptionId'
  from learning.activities as activity
  join learning.activity_versions as version
    on version.activity_id = activity.id
   and version.version = pg_temp.qa_latest_version(p_activity_key)
  join learning.questions as question
    on question.activity_version_id = version.id
  join learning.question_marking as marking
    on marking.question_id = question.id
  where activity.stable_key = p_activity_key
    and marking.spec ->> 'mode' = 'single-choice'
    and coalesce(marking.spec ->> 'correctOptionId', '') <> ''
  order by question.ordinal
  limit 1
$$;

select set_config('test.qa.unit3_version', pg_temp.qa_latest_version('week2-malware-symptoms'), true);
select set_config('test.qa.unit3_question', (select question_key from pg_temp.qa_choice_question('week2-malware-symptoms')), true);
select set_config('test.qa.unit3_correct', (select correct_option from pg_temp.qa_choice_question('week2-malware-symptoms')), true);
select set_config('test.qa.tlevel_version', pg_temp.qa_latest_version('week-1-lesson-1-ex-01'), true);
select set_config('test.qa.tlevel_question', (select question_key from pg_temp.qa_choice_question('week-1-lesson-1-ex-01')), true);
select set_config('test.qa.tlevel_correct', (select correct_option from pg_temp.qa_choice_question('week-1-lesson-1-ex-01')), true);
select set_config('test.qa.u14_version', pg_temp.qa_latest_version('week-1-variables-and-data-types'), true);
select set_config('test.qa.u14_question', (select question_key from pg_temp.qa_choice_question('week-1-variables-and-data-types')), true);
select set_config('test.qa.u14_correct', (select correct_option from pg_temp.qa_choice_question('week-1-variables-and-data-types')), true);
select set_config('test.qa.l2e_version', pg_temp.qa_latest_version('week-1-knowledge-check'), true);
select set_config('test.qa.l2e_question', (select question_key from pg_temp.qa_choice_question('week-1-knowledge-check')), true);
select set_config('test.qa.l2e_correct', (select correct_option from pg_temp.qa_choice_question('week-1-knowledge-check')), true);
select set_config('test.qa.l2e_welcome_version', pg_temp.qa_latest_version('week-1-welcome'), true);
select set_config('test.qa.l2e_welcome_question', (select question_key from pg_temp.qa_choice_question('week-1-welcome')), true);
select set_config('test.qa.l2e_welcome_correct', (select correct_option from pg_temp.qa_choice_question('week-1-welcome')), true);

select ok(
  current_setting('test.qa.unit3_version', true) is not null
    and current_setting('test.qa.unit3_question', true) is not null,
  'week2-malware-symptoms has a published single-choice question for Unit 3 smoke testing'
);

set local "request.jwt.claim.sub" = '13000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"13000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select is(
  (select student_number from api.my_profile),
  'QA-UNIT3',
  'Unit 3 QA Auth session resolves the synthetic learner profile'
);

select is(
  (select array_agg(group_code order by group_code) from api.my_enrolments where status = 'active'),
  array['CYBER-TEST-QA']::text[],
  'Unit 3 QA learner sees only the Cyber QA enrolment'
);

select ok(
  exists (
    select 1
    from api.my_assignments
    where activity_key = 'week2-malware-symptoms'
  ),
  'Unit 3 QA learner can see the assigned malware-symptoms activity'
);

select ok(
  not exists (
    select 1
    from api.my_assignments
    where activity_key in (
      'week-1-lesson-1-ex-01',
      'week-1-variables-and-data-types',
      'week-1-knowledge-check'
    )
  ),
  'Unit 3 QA learner cannot see other-hub QA assignments'
);

select throws_ok(
  format(
    $$select * from api.mark_formative_response(%L, %L, %L::jsonb, %L)$$,
    'week-1-lesson-1-ex-01',
    pg_temp.qa_latest_version('week-1-lesson-1-ex-01'),
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'ignored',
        'response_payload', jsonb_build_object('optionId', 'wrong')
      )
    ),
    'unit3-cross-tlevel'
  ),
  '42501',
  'ACTIVITY_NOT_ASSIGNED',
  'Unit 3 QA learner cannot mark a T Level assigned activity'
);

select lives_ok(
  $$select hub_code from api.published_curriculum() where hub_code = 'tlevel-software-development'$$,
  'published teaching metadata remains publicly listed and is not an assignment grant'
);

select ok(
  (
    select is_correct = false
    from api.mark_formative_response(
      'week2-malware-symptoms',
      pg_temp.qa_latest_version('week2-malware-symptoms'),
      jsonb_build_array(
        jsonb_build_object(
          'question_id', current_setting('test.qa.unit3_question', true),
          'response_payload', jsonb_build_object('optionId', 'qa-incorrect-option')
        )
      ),
      'unit3-malware-incorrect'
    )
  ),
  'Unit 3 smoke: a known-incorrect option is marked Incorrect'
);

select ok(
  (
    select is_correct
    from api.mark_formative_response(
      'week2-malware-symptoms',
      pg_temp.qa_latest_version('week2-malware-symptoms'),
      jsonb_build_array(
        jsonb_build_object(
          'question_id', current_setting('test.qa.unit3_question', true),
          'response_payload', jsonb_build_object(
            'optionId', current_setting('test.qa.unit3_correct', true)
          )
        )
      ),
      'unit3-malware-correct'
    )
  ),
  'Unit 3 smoke: the authored correct option is marked Correct'
);
reset role;

select is(
  (
    select count(*)
    from learning.formative_checks as check_row
    join learning.students as student on student.id = check_row.student_id
    where student.student_number = 'QA-UNIT3'
  ),
  2::bigint,
  'Unit 3 smoke writes two formative_checks rows and no extra identity fields'
);

select is(
  (
    select count(*)
    from learning.attempts as attempt
    join learning.students as student on student.id = attempt.student_id
    where student.student_number = 'QA-UNIT3'
  ),
  0::bigint,
  'formative checks do not create official attempts'
);

set local "request.jwt.claim.sub" = '13000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"13000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;

select ok(
  exists (
    select 1 from api.my_assignments
    where activity_key = 'week-1-lesson-1-ex-01'
  )
  or pg_temp.qa_latest_version('week-1-lesson-1-ex-01') is null,
  'T Level QA learner sees the assigned Weeks 1–3 retrieval activity when published'
);

select ok(
  not exists (
    select 1 from api.my_assignments
    where activity_key in ('week2-malware-symptoms', 'week-1-variables-and-data-types', 'week-1-knowledge-check')
  ),
  'T Level QA learner cannot see other-hub QA assignments'
);

select ok(
  not exists (
    select 1 from api.my_assignments
    where activity_key in (
      'week-1-lesson-1-ex-07',
      'week-1-lesson-1-ex-13',
      'week-1-lesson-1-ex-20'
    )
  ),
  'exclusive TLEVEL-TEST-A learner cannot see DSD Y2 teaching assignments'
);

select throws_ok(
  format(
    $$select * from api.mark_formative_response(%L, %L, %L::jsonb, %L)$$,
    'week2-malware-symptoms',
    pg_temp.qa_latest_version('week2-malware-symptoms'),
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'ignored',
        'response_payload', jsonb_build_object('optionId', 'wrong')
      )
    ),
    'tlevel-cross-unit3'
  ),
  '42501',
  'ACTIVITY_NOT_ASSIGNED',
  'T Level QA learner cannot mark a Unit 3 assigned activity'
);

select ok(
  (
    select is_correct = false
    from api.mark_formative_response(
      'week-1-lesson-1-ex-01',
      pg_temp.qa_latest_version('week-1-lesson-1-ex-01'),
      jsonb_build_array(
        jsonb_build_object(
          'question_id', current_setting('test.qa.tlevel_question', true),
          'response_payload', jsonb_build_object('optionId', 'qa-incorrect-option')
        )
      ),
      'tlevel-retrieval-incorrect'
    )
  ),
  'T Level smoke: incorrect option is marked Incorrect'
);

select ok(
  (
    select is_correct
    from api.mark_formative_response(
      'week-1-lesson-1-ex-01',
      pg_temp.qa_latest_version('week-1-lesson-1-ex-01'),
      jsonb_build_array(
        jsonb_build_object(
          'question_id', current_setting('test.qa.tlevel_question', true),
          'response_payload', jsonb_build_object(
            'optionId', current_setting('test.qa.tlevel_correct', true)
          )
        )
      ),
      'tlevel-retrieval-correct'
    )
  ),
  'T Level smoke: authored correct option is marked Correct'
);
reset role;

select is(
  (
    select student.auth_user_id = snapshot.auth_user_id
      and student.student_number = snapshot.student_number
      and student.first_name = snapshot.first_name
      and student.surname = snapshot.surname
      and student.display_name = snapshot.display_name
      and student.active = snapshot.active
      and student.is_synthetic = snapshot.is_synthetic
      and student.updated_at = snapshot.updated_at
      and enrolment.id = snapshot.enrolment_id
      and enrolment.status = snapshot.enrolment_status
      and enrolment.group_id = snapshot.group_id
    from pg_temp.dsd_y2_teaching_snapshot as snapshot
    join learning.students as student on student.id = snapshot.id
    join learning.enrolments as enrolment on enrolment.id = snapshot.enrolment_id
  ),
  true,
  'the real TLEVEL-DSD-Y2 teaching learner is not modified by QA ensure or provision'
);

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    join learning.groups as learner_group on learner_group.id = enrolment.group_id
    where student.student_number = 'TLEVEL-Y2-0001'
      and learner_group.code = 'TLEVEL-DSD-Y2'
      and enrolment.status = 'active'
  ),
  1::bigint,
  'the real TLEVEL-DSD-Y2 learner keeps a single active teaching enrolment'
);

set local "request.jwt.claim.sub" = '13000000-0000-4000-8000-000000000006';
set local "request.jwt.claims" = '{"sub":"13000000-0000-4000-8000-000000000006","role":"authenticated"}';
set local role authenticated;

select is(
  (select student_number from api.my_profile),
  'QA-TLEVEL-DSD-Y2',
  'DSD Y2 QA Auth session resolves the synthetic learner profile'
);

select is(
  (select array_agg(group_code order by group_code) from api.my_enrolments where status = 'active'),
  array['TLEVEL-DSD-Y2']::text[],
  'DSD Y2 QA learner sees only the TLEVEL-DSD-Y2 enrolment'
);

select ok(
  exists (select 1 from api.my_assignments where activity_key = 'week-1-lesson-1-ex-07')
  and exists (select 1 from api.my_assignments where activity_key = 'week-1-lesson-1-ex-13')
  and exists (select 1 from api.my_assignments where activity_key = 'week-1-lesson-1-ex-20'),
  'DSD Y2 QA learner can see the teaching-group assignments for ex-07, ex-13 and ex-20'
);

select ok(
  not exists (
    select 1 from api.my_assignments
    where activity_key in ('week2-malware-symptoms', 'week-1-knowledge-check')
  ),
  'DSD Y2 QA learner cannot see other-hub QA assignments'
);
reset role;

select is(
  (
    select created_or_reused
    from learning.ensure_synthetic_qa_groups()
    where persona = 'TLEVEL_DSD_Y2_TEST_LEARNER'
  ),
  'joined',
  'repeated ensure remains idempotent for the DSD Y2 teaching-group join'
);

select is(
  (
    select count(*)
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where learner_group.code = 'TLEVEL-TEST-A'
      and assignment.active
  ),
  1::bigint,
  'repeated ensure does not enlarge exclusive TLEVEL-TEST-A'
);

select is(
  (
    select count(*)
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where learner_group.code = 'TLEVEL-DSD-Y2'
      and assignment.active
      and activity.stable_key in (
        'week-1-lesson-1-ex-07',
        'week-1-lesson-1-ex-13',
        'week-1-lesson-1-ex-20'
      )
  ),
  3::bigint,
  'repeated ensure does not duplicate TLEVEL-DSD-Y2 teaching assignments'
);

select is(
  (
    select count(distinct activity.stable_key)
    from learning.activity_assignments as assignment
    join learning.groups as learner_group on learner_group.id = assignment.group_id
    join learning.activity_versions as activity_version
      on activity_version.id = assignment.activity_version_id
    join learning.activities as activity on activity.id = activity_version.activity_id
    where learner_group.code = 'CYBER-TEST-QA'
      and assignment.active
  ),
  1::bigint,
  'repeated ensure does not modify unrelated CYBER-TEST-QA assignments'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'learning'
      and table_name = 'synthetic_qa_fixtures'
      and column_name in ('email', 'password', 'encrypted_password', 'secret')
  ),
  'synthetic QA fixtures do not store credentials'
);

select ok(
  not exists (
    select 1
    from learning.students
    where student_number = 'QA-TLEVEL-DSD-Y2'
      and contact_email is not null
  ),
  'DSD Y2 QA learner does not copy Auth email into learning.students'
);

set local "request.jwt.claim.sub" = '13000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"13000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select ok(
  exists (
    select 1 from api.my_assignments
    where activity_key = 'week-1-variables-and-data-types'
  )
  or pg_temp.qa_latest_version('week-1-variables-and-data-types') is null,
  'Unit 14 QA learner sees the assigned variables activity when published'
);

select ok(
  not exists (
    select 1 from api.my_assignments
    where activity_key in ('week2-malware-symptoms', 'week-1-lesson-1-ex-01', 'week-1-knowledge-check')
  ),
  'Unit 14 QA learner cannot see other-hub QA assignments'
);

select ok(
  (
    select is_correct = false
    from api.mark_formative_response(
      'week-1-variables-and-data-types',
      pg_temp.qa_latest_version('week-1-variables-and-data-types'),
      jsonb_build_array(
        jsonb_build_object(
          'question_id', current_setting('test.qa.u14_question', true),
          'response_payload', jsonb_build_object('optionId', 'qa-incorrect-option')
        )
      ),
      'u14-variables-incorrect'
    )
  ),
  'Unit 14 smoke: incorrect option is marked Incorrect'
);

select ok(
  (
    select is_correct
    from api.mark_formative_response(
      'week-1-variables-and-data-types',
      pg_temp.qa_latest_version('week-1-variables-and-data-types'),
      jsonb_build_array(
        jsonb_build_object(
          'question_id', current_setting('test.qa.u14_question', true),
          'response_payload', jsonb_build_object(
            'optionId', current_setting('test.qa.u14_correct', true)
          )
        )
      ),
      'u14-variables-correct'
    )
  ),
  'Unit 14 smoke: authored correct option is marked Correct'
);
reset role;

set local "request.jwt.claim.sub" = '13000000-0000-4000-8000-000000000004';
set local "request.jwt.claims" = '{"sub":"13000000-0000-4000-8000-000000000004","role":"authenticated"}';
set local role authenticated;

select ok(
  exists (
    select 1 from api.my_assignments
    where activity_key = 'week-1-knowledge-check'
  ),
  'L2E QA learner sees the assigned knowledge-check activity'
);

select ok(
  exists (
    select 1 from api.my_assignments
    where activity_key = 'week-1-welcome'
  )
  or pg_temp.qa_latest_version('week-1-welcome') is null,
  'L2E QA learner sees week-1-welcome when that published activity exists'
);

select ok(
  not exists (
    select 1 from api.my_assignments
    where activity_key in (
      'week-1-reflection',
      'week-2-classify',
      'week-2-retrieval',
      'week-3-classify'
    )
  ),
  'L2E QA learner cannot see review-only or later-week L2E activities'
);

select ok(
  not exists (
    select 1 from api.my_assignments
    where activity_key in (
      'week2-malware-symptoms',
      'week-1-lesson-1-ex-01',
      'week-1-variables-and-data-types'
    )
  ),
  'L2E QA learner cannot see other-hub QA assignments'
);

select throws_ok(
  format(
    $$select * from api.mark_formative_response(%L, %L, %L::jsonb, %L)$$,
    'week2-malware-symptoms',
    pg_temp.qa_latest_version('week2-malware-symptoms'),
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'ignored',
        'response_payload', jsonb_build_object('optionId', 'wrong')
      )
    ),
    'l2e-cross-unit3'
  ),
  '42501',
  'ACTIVITY_NOT_ASSIGNED',
  'L2E QA learner cannot mark a Unit 3 assigned activity'
);

select throws_ok(
  format(
    $$select * from api.mark_formative_response(%L, %L, %L::jsonb, %L)$$,
    'week-1-lesson-1-ex-01',
    coalesce(pg_temp.qa_latest_version('week-1-lesson-1-ex-01'), '0.1.0'),
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'ignored',
        'response_payload', jsonb_build_object('optionId', 'wrong')
      )
    ),
    'l2e-cross-tlevel'
  ),
  '42501',
  'ACTIVITY_NOT_ASSIGNED',
  'L2E QA learner cannot mark a T Level assigned activity'
);

select throws_ok(
  format(
    $$select * from api.mark_formative_response(%L, %L, %L::jsonb, %L)$$,
    'week-1-variables-and-data-types',
    coalesce(pg_temp.qa_latest_version('week-1-variables-and-data-types'), '0.1.0'),
    jsonb_build_array(
      jsonb_build_object(
        'question_id', 'ignored',
        'response_payload', jsonb_build_object('optionId', 'wrong')
      )
    ),
    'l2e-cross-unit14'
  ),
  '42501',
  'ACTIVITY_NOT_ASSIGNED',
  'L2E QA learner cannot mark a Unit 14 assigned activity'
);

select ok(
  (
    select is_correct = false
    from api.mark_formative_response(
      'week-1-knowledge-check',
      pg_temp.qa_latest_version('week-1-knowledge-check'),
      jsonb_build_array(
        jsonb_build_object(
          'question_id', current_setting('test.qa.l2e_question', true),
          'response_payload', jsonb_build_object('optionId', 'qa-incorrect-option')
        )
      ),
      'l2e-knowledge-incorrect'
    )
  ),
  'L2E smoke: incorrect option is marked Incorrect'
);

select ok(
  (
    select is_correct
    from api.mark_formative_response(
      'week-1-knowledge-check',
      pg_temp.qa_latest_version('week-1-knowledge-check'),
      jsonb_build_array(
        jsonb_build_object(
          'question_id', current_setting('test.qa.l2e_question', true),
          'response_payload', jsonb_build_object(
            'optionId', current_setting('test.qa.l2e_correct', true)
          )
        )
      ),
      'l2e-knowledge-correct'
    )
  ),
  'L2E smoke: authored correct option is marked Correct'
);

select ok(
  pg_temp.qa_latest_version('week-1-welcome') is null
  or (
    select is_correct = false
    from api.mark_formative_response(
      'week-1-welcome',
      pg_temp.qa_latest_version('week-1-welcome'),
      jsonb_build_array(
        jsonb_build_object(
          'question_id', current_setting('test.qa.l2e_welcome_question', true),
          'response_payload', jsonb_build_object('optionId', 'qa-incorrect-option')
        )
      ),
      'l2e-welcome-incorrect'
    )
  ),
  'L2E Week 1 starter: incorrect option is marked Incorrect when published'
);

select ok(
  pg_temp.qa_latest_version('week-1-welcome') is null
  or (
    select is_correct
    from api.mark_formative_response(
      'week-1-welcome',
      pg_temp.qa_latest_version('week-1-welcome'),
      jsonb_build_array(
        jsonb_build_object(
          'question_id', current_setting('test.qa.l2e_welcome_question', true),
          'response_payload', jsonb_build_object(
            'optionId', current_setting('test.qa.l2e_welcome_correct', true)
          )
        )
      ),
      'l2e-welcome-correct'
    )
  ),
  'L2E Week 1 starter: authored correct option is marked Correct when published'
);
reset role;

select is(
  (
    select count(*)
    from learning.attempts as attempt
    join learning.students as student on student.id = attempt.student_id
    where student.student_number like 'QA-%'
  ),
  0::bigint,
  'no synthetic QA learner created an official attempt during formative smoke'
);

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;

select is(
  (
    select active
    from admin_api.set_synthetic_qa_learner_active('UNIT3_TEST_LEARNER', false)
  ),
  false,
  'a platform administrator can temporarily disable a synthetic QA learner'
);
reset role;

set local "request.jwt.claim.sub" = '13000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"13000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select is(
  (select count(*) from api.my_profile),
  0::bigint,
  'a disabled synthetic QA learner no longer resolves through current_student_id()'
);
reset role;

set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;
select is(
  (
    select active
    from admin_api.set_synthetic_qa_learner_active('UNIT3_TEST_LEARNER', true)
  ),
  true,
  'a platform administrator can re-enable a synthetic QA learner'
);
reset role;

select is(
  (
    select count(*)
    from platform.audit_events
    where event_key like 'learning.synthetic-qa.%'
      and context ? 'email' = false
      and entity_key in (
        'UNIT3_TEST_LEARNER',
        'TLEVEL_TEST_LEARNER',
        'TLEVEL_DSD_Y2_TEST_LEARNER',
        'UNIT14_TEST_LEARNER',
        'L2E_TEST_LEARNER'
      )
  ) > 0,
  true,
  'synthetic QA audit events record persona keys without email'
);

select finish();
rollback;
