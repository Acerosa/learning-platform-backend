-- Extended Phase B rollback verification (local / staging only).
-- Sequence: Phase B present → publish → public API → rollback → Phase A access
-- → integrity → reapply Phase B → equivalence.
-- Does not delete publication history or learner records.

\set ON_ERROR_STOP on

select '1_phase_b_present' as step,
  (select count(*) from information_schema.columns
   where table_schema = 'platform'
     and table_name = 'curriculum_publications'
     and column_name in ('learner_package', 'learner_package_sanitisation_version')) as cols;

create temporary table rb_progress as
select
  (select count(*) from learning.attempts) as attempts,
  (select count(*) from learning.question_marking) as marking,
  (select count(*) from platform.curriculum_publications) as pubs;

-- Publish a new curriculum under Phase B.
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

do $pub$
declare
  v_base jsonb;
  v_pkg jsonb;
  v_acts jsonb;
begin
  select package into v_base
  from platform.curriculum_publications
  where hub_code = 'unit-14-software-engineering-for-business'
    and status = 'published'
  order by published_at desc
  limit 1;

  select coalesce(jsonb_agg(value), '[]'::jsonb) into v_acts
  from (
    select value
    from jsonb_array_elements(coalesce(v_base->'activities', '[]'::jsonb))
    limit 3
  ) s;

  v_pkg := jsonb_set(v_base, '{activities}', v_acts, true);
  v_pkg := jsonb_set(v_pkg, '{packageVersion}', to_jsonb('9.9.77'::text), true);

  perform admin_api.publish_curriculum(
    'published',
    'unit-14-software-engineering-for-business',
    'ocr-level-3-it',
    '9.9.77',
    coalesce(v_base->>'schemaVersion', '0.1.0'),
    coalesce(v_base->>'sourcePackageVersion', '0.1.0'),
    v_pkg,
    'rollback-test',
    '',
    'phase-b extended rollback publish'
  );
end;
$pub$;
commit;

reset role;

select '2_published_has_learner' as step,
  learner_package is not null as has_lp,
  learner_package_sanitisation_version as san,
  learner_package = platform.learner_curriculum_package(
    package, package_version, source_package_version
  ) as eq
from platform.curriculum_publications
where package_version = '9.9.77';

select '3_api_phase_b' as step,
  package->>'packageVersion' as ver,
  jsonb_array_length(coalesce(package->'activities', '[]'::jsonb)) as acts,
  (package::text like '%correctOptionId%') as leaked_correct,
  (package::text like '%teacher-note%') as leaked_teacher
from api.published_curriculum_package(
  'unit-14-software-engineering-for-business',
  'ocr-level-3-it',
  '9.9.77'
);

-- Rollback Phase B retrieval / publish paths (keep columns).
\ir rollback_precomputed_learner_packages.sql

select '4_api_after_rollback' as step,
  package->>'packageVersion' as ver,
  jsonb_array_length(coalesce(package->'activities', '[]'::jsonb)) as acts,
  (package::text like '%correctOptionId%') as leaked_correct
from api.published_curriculum_package(
  'unit-14-software-engineering-for-business',
  'ocr-level-3-it',
  '9.9.77'
);

select '5_existing_published' as step, hub_code, package_version, status
from platform.curriculum_publications
where status = 'published'
order by hub_code;

select '6_progress_intact' as step,
  (select count(*) from learning.attempts) = attempts as attempts_ok,
  (select count(*) from learning.question_marking) = marking as marking_ok,
  (select count(*) from platform.curriculum_publications) >= pubs as pubs_not_deleted
from rb_progress;

-- Reapply Phase B migrations (idempotent function replaces + backfill).
\i ../../migrations/20261127110000_add_curriculum_learner_package_column.sql
\i ../../migrations/20261127110100_publish_time_learner_packages.sql
\i ../../migrations/20261127110200_backfill_curriculum_learner_packages.sql
\i ../../migrations/20261127110300_published_curriculum_uses_learner_package.sql

select '7_reapply_equivalence' as step,
  count(*) filter (
    where learner_package is distinct from platform.learner_curriculum_package(
      package, package_version, source_package_version
    )
    or learner_package_sanitisation_version
      is distinct from platform.learner_package_sanitisation_version()
  ) as bad,
  count(*) as total
from platform.curriculum_publications;

select '8_api_after_reapply' as step,
  package->>'packageVersion' as ver,
  jsonb_array_length(coalesce(package->'activities', '[]'::jsonb)) as acts,
  (package::text like '%correctOptionId%') as leaked_correct
from api.published_curriculum_package(
  'unit-14-software-engineering-for-business',
  'ocr-level-3-it',
  '9.9.77'
);

select '9_done' as step, now() as finished_at;
