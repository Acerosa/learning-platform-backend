begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

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
  jsonb_build_object('synthetic', true, 'fixture', fixture.fixture),
  clock_timestamp(),
  clock_timestamp()
from (
  values
    ('11000000-0000-4000-8000-000000000001'::uuid, 'onboarding.one@local.invalid', 'onboarding-one'),
    ('11000000-0000-4000-8000-000000000002'::uuid, 'onboarding.two@local.invalid', 'onboarding-two'),
    ('11000000-0000-4000-8000-000000000003'::uuid, 'onboarding.atomic@local.invalid', 'onboarding-atomic'),
    ('11000000-0000-4000-8000-000000000004'::uuid, 'onboarding.validation@local.invalid', 'onboarding-validation'),
    ('11000000-0000-4000-8000-000000000005'::uuid, 'onboarding.inactive@local.invalid', 'onboarding-inactive'),
    ('11000000-0000-4000-8000-000000000006'::uuid, 'onboarding.roster@local.invalid', 'onboarding-roster'),
    ('11000000-0000-4000-8000-000000000007'::uuid, 'onboarding.existing@local.invalid', 'onboarding-existing')
) as fixture(id, email, fixture);

insert into learning.academic_years (
  id,
  code,
  starts_on,
  ends_on,
  active
) values (
  '41000000-0000-4000-8000-000000000001',
  '2025-26',
  '2025-09-01',
  '2026-08-31',
  false
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
) values
  (
    '61000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001',
    '50000000-0000-4000-8000-000000000001',
    'INACTIVE-GROUP',
    'Inactive registration group',
    false,
    'Year 1',
    'inactive-group',
    true
  ),
  (
    '61000000-0000-4000-8000-000000000002',
    '41000000-0000-4000-8000-000000000001',
    '50000000-0000-4000-8000-000000000001',
    'INACTIVE-YEAR',
    'Inactive academic year group',
    true,
    'Year 2',
    'inactive-academic-year',
    true
  );

select is(
  (select count(*) from api.registration_options()),
  0::bigint,
  'registration_options does not list class keys or teaching groups'
);

set local role anon;
select throws_like(
  $$select * from api.registration_options()$$,
  '%permission denied%',
  'anonymous users cannot read registration options'
);
select throws_like(
  $$select * from api.complete_learner_onboarding('A', 'Learner', '001', 'synthetic-year-1-a')$$,
  '%permission denied%',
  'anonymous users cannot execute learner onboarding'
);
reset role;

set local "request.jwt.claim.sub" = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
set local "request.jwt.claims" = '{"sub":"ffffffff-ffff-4fff-8fff-ffffffffffff","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from api.complete_learner_onboarding('No', 'Account', '0099', 'synthetic-year-1-a')$$,
  '28000',
  'AUTH_REQUIRED',
  'onboarding requires a current verified Auth account'
);
reset role;

set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000004';
set local "request.jwt.claims" = '{"sub":"11000000-0000-4000-8000-000000000004","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from api.complete_learner_onboarding('   ', 'Learner', '0042', 'synthetic-year-1-a')$$,
  '22023',
  'INVALID_FIRST_NAME',
  'blank first names are rejected'
);
select throws_ok(
  $$select * from api.complete_learner_onboarding('Valid', '   ', '0042', 'synthetic-year-1-a')$$,
  '22023',
  'INVALID_SURNAME',
  'blank surnames are rejected'
);
select throws_ok(
  $$select * from api.complete_learner_onboarding('Valid', 'Learner', '   ', 'synthetic-year-1-a')$$,
  '22023',
  'INVALID_STUDENT_NUMBER',
  'blank student numbers are rejected'
);
select lives_ok(
  $$select * from api.complete_learner_onboarding('Valid', 'Learner', '0042', 'not-a-real-option')$$,
  'p_registration_option is ignored and cannot grant group membership'
);
reset role;

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    where student.auth_user_id = '11000000-0000-4000-8000-000000000004'
  ),
  0::bigint,
  'ignored registration options do not create enrolments'
);

set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated","email":"untrusted@example.invalid"}';
set local role authenticated;
select is(
  (
    select idempotent
    from api.complete_learner_onboarding(
      '  Ada  ',
      '  Lovelace  ',
      '001234',
      'synthetic-year-1-a'
    )
  ),
  false,
  'first valid onboarding call creates the learner profile'
);
reset role;

select is(
  (
    select student.student_number
    from learning.students as student
    where student.auth_user_id = '11000000-0000-4000-8000-000000000001'
  ),
  '001234',
  'student numbers remain text and preserve leading zeroes'
);

select is(
  (
    select student.contact_email
    from learning.students as student
    where student.auth_user_id = '11000000-0000-4000-8000-000000000001'
  ),
  'onboarding.one@local.invalid',
  'contact email is derived from Auth rather than the JWT/browser claim'
);

select is(
  (
    select count(*)
    from learning.students as student
    where student.auth_user_id = '11000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'valid onboarding creates exactly one learner profile'
);

select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    where student.auth_user_id = '11000000-0000-4000-8000-000000000001'
      and enrolment.status = 'active'
  ),
  0::bigint,
  'profile onboarding does not create an enrolment'
);

set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select ok(
  exists (
    select 1
    from api.my_profile
    where first_name = 'Ada'
      and surname = 'Lovelace'
      and student_number = '001234'
      and contact_email = 'onboarding.one@local.invalid'
  ),
  'my_profile exposes the learner surname and Auth-derived contact email'
);
select is(
  (select count(*) from api.my_enrolments),
  0::bigint,
  'my_enrolments is empty until hub access or JoinClass enrols the learner'
);
select is(
  (
    select idempotent
    from api.complete_learner_onboarding('Ada', 'Lovelace', '001234', 'synthetic-year-1-a')
  ),
  true,
  'an identical repeated onboarding call is idempotent'
);
select is(
  (
    select count(*)
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    where student.auth_user_id = '11000000-0000-4000-8000-000000000001'
      and enrolment.status = 'active'
  ),
  0::bigint,
  'an already-linked learner cannot claim another group through complete_learner_onboarding'
);
select is(
  (
    select idempotent
    from api.complete_learner_onboarding('Ada', 'Lovelace', '001234', 'nhc-cyber-26')
  ),
  true,
  'supplying another registration option remains a no-op for enrolment'
);
select throws_ok(
  $$select * from api.complete_learner_onboarding('Ada', 'Lovelace', '009999', 'synthetic-year-1-a')$$,
  '23000',
  'AUTH_ACCOUNT_ALREADY_LINKED',
  'one Auth account cannot create a second learner profile'
);
select throws_ok(
  $$select * from api.complete_learner_onboarding('Augusta', 'Lovelace', '001234', 'synthetic-year-1-a')$$,
  '23000',
  'ONBOARDING_CONFLICT',
  'conflicting repeated onboarding is rejected'
);
reset role;

set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$select * from api.complete_learner_onboarding('Ada', 'Lovelace', '001234', 'synthetic-year-1-a')$$,
  '23505',
  'STUDENT_NUMBER_ALREADY_LINKED',
  'a student number already linked to another Auth account is rejected'
);
reset role;

insert into learning.students (
  id,
  auth_user_id,
  student_number,
  first_name,
  surname,
  display_name,
  contact_email,
  active
) values (
  '32000000-0000-4000-8000-000000000006',
  null,
  '000777',
  'Grace',
  'Hopper',
  'Grace Hopper',
  'onboarding.roster@local.invalid',
  true
);

set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000006';
set local "request.jwt.claims" = '{"sub":"11000000-0000-4000-8000-000000000006","role":"authenticated"}';
set local role authenticated;
select is(
  (
    select student_number
    from api.complete_learner_onboarding('Grace', 'Hopper', '000777', 'synthetic-year-1-a')
  ),
  '000777',
  'a matching unlinked authoritative learner record is linked without duplication'
);
reset role;

select is(
  (select count(*) from learning.students where student_number = '000777'),
  1::bigint,
  'authoritative roster linking does not create a duplicate learner'
);

insert into learning.students (
  id,
  auth_user_id,
  student_number,
  first_name,
  surname,
  display_name,
  contact_email,
  active
) values (
  '32000000-0000-4000-8000-000000000007',
  null,
  '000999',
  'Existing',
  'Enrolment',
  'Existing Enrolment',
  'onboarding.existing@local.invalid',
  true
);

insert into learning.enrolments (
  student_id,
  group_id,
  joined_on,
  status
) values (
  '32000000-0000-4000-8000-000000000007',
  '60000000-0000-4000-8000-000000000001',
  current_date - 7,
  'active'
);

set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000007';
set local "request.jwt.claims" = '{"sub":"11000000-0000-4000-8000-000000000007","role":"authenticated"}';
set local role authenticated;
select is(
  (
    select idempotent
    from api.complete_learner_onboarding('Existing', 'Enrolment', '000999', 'synthetic-year-1-a')
  ),
  false,
  'linking a matching unlinked roster learner does not require a group choice'
);
reset role;

select is(
  (select auth_user_id from learning.students where student_number = '000999'),
  '11000000-0000-4000-8000-000000000007'::uuid,
  'unlinked roster onboarding with an existing enrolment still links the Auth account'
);

insert into learning.students (
  id,
  auth_user_id,
  student_number,
  first_name,
  surname,
  display_name,
  contact_email,
  active
) values (
  '32000000-0000-4000-8000-000000000003',
  null,
  '000888',
  'Atomic',
  'Learner',
  'Atomic Learner',
  'onboarding.atomic@local.invalid',
  true
);

insert into learning.enrolments (
  student_id,
  group_id,
  joined_on,
  left_on,
  status
) values (
  '32000000-0000-4000-8000-000000000003',
  '60000000-0000-4000-8000-000000000001',
  current_date,
  current_date,
  'withdrawn'
);

set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"11000000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;
select is(
  (
    select student_number
    from api.complete_learner_onboarding('Atomic', 'Learner', '000888', 'synthetic-year-1-a')
  ),
  '000888',
  'an unlinked roster learner with an inactive enrolment is still linked'
);
reset role;

select is(
  (select auth_user_id from learning.students where student_number = '000888'),
  '11000000-0000-4000-8000-000000000003'::uuid,
  'profile linking still attaches the Auth account atomically'
);

select is(
  (
    select enrolment.status
    from learning.enrolments as enrolment
    join learning.students as student on student.id = enrolment.student_id
    where student.student_number = '000888'
      and enrolment.group_id = '60000000-0000-4000-8000-000000000001'
  ),
  'withdrawn',
  'complete_learner_onboarding does not reactivate a historical enrolment'
);

select ok(
  not has_function_privilege('anon', 'api.registration_options()', 'EXECUTE')
  and not has_function_privilege(
    'anon',
    'api.complete_learner_onboarding(text,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'api.join_learner_hub_group(text,text)',
    'EXECUTE'
  ),
  'anonymous execution grants are absent'
);

select ok(
  has_function_privilege('authenticated', 'api.registration_options()', 'EXECUTE')
  and has_function_privilege(
    'authenticated',
    'api.complete_learner_onboarding(text,text,text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'api.join_learner_hub_group(text,text)',
    'EXECUTE'
  ),
  'authenticated execution grants are present'
);

select ok(
  (
    select procedure.prosecdef
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'api'
      and procedure.proname = 'complete_learner_onboarding'
  ),
  'complete_learner_onboarding is SECURITY DEFINER'
);

select is(
  (
    select procedure.proconfig
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'api'
      and procedure.proname = 'complete_learner_onboarding'
  ),
  array['search_path=""']::text[],
  'complete_learner_onboarding has an empty fixed search_path'
);

select * from finish();
rollback;
