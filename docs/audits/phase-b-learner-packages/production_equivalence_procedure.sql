-- Read-only / transactional verification for production Phase B backfill.
-- Do NOT run the write section until production deployment is approved.
-- The SELECT-only section is safe for pre-deployment inspection.
--
-- Captured read-only baseline (hubwpkrqndorznwzvaer, Phase A only, no content export):
--   unit-14 0.2.14 / 24  → learner md5 2ae5bae4212343eeacb1f316bff49efc / 100553 bytes
--   unit-3  0.2.45 / 132 → learner md5 a745eabf45cda0d41d8d7c112503195c / 741365 bytes
--   l2e     0.3.39 / 172 → learner md5 a4384600a8a4badfe9bdd5c0a2b80e4e / 591517 bytes
--   tlevel  0.4.47 / 408 → learner md5 882cebc4141ba81729e3fe4abb44de53 / 961645 bytes

-- ============================================================================
-- A. READ-ONLY PRECHECK (safe now)
-- ============================================================================
select hub_code, package_version, status,
  jsonb_array_length(coalesce(package->'activities', '[]'::jsonb)) as activities,
  pg_column_size(package) as staff_bytes,
  md5(package::text) as staff_md5,
  md5(
    platform.learner_curriculum_package(
      package, package_version, source_package_version
    )::text
  ) as expected_learner_md5,
  pg_column_size(
    platform.learner_curriculum_package(
      package, package_version, source_package_version
    )
  ) as expected_learner_bytes
from (
  select distinct on (hub_code) *
  from platform.curriculum_publications
  where status = 'published'
    and hub_code in (
      'tlevel-software-development',
      'unit-3-cyber-security',
      'l2e-exploring-emerging-digital-technologies',
      'unit-14-software-engineering-for-business'
    )
  order by hub_code, published_at desc
) s
order by activities;

-- ============================================================================
-- B. TRANSACTIONAL POST-BACKFILL ASSERTION (run inside deployment txn /
--    immediately after 20261127110200, before releasing traffic)
-- ============================================================================
-- begin;
-- do $$
-- declare
--   v_bad int;
-- begin
--   select count(*) into v_bad
--   from platform.curriculum_publications
--   where learner_package is distinct from platform.learner_curriculum_package(
--           package, package_version, source_package_version
--         )
--      or learner_package_sanitisation_version
--           is distinct from platform.learner_package_sanitisation_version();
--   if v_bad > 0 then
--     raise exception using errcode = '22023',
--       message = format('LEARNER_PACKAGE_EQUIVALENCE_FAILED:%s', v_bad);
--   end if;
-- end $$;
-- -- commit only after assertion passes
