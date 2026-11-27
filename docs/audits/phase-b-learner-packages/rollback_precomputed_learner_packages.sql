-- Rollback for Phase B precomputed learner packages.
-- Restores Phase A retrieval and publication behaviour.
-- Keeps learner_package columns in place (unused) to avoid destructive schema churn.
-- Does not modify staff packages, publication history or learner records.
--
-- Apply only the function/view restores below. Do not drop publications.
-- Source bodies: production_before_*.sql in this directory.

\ir production_before_protect_curriculum_publication.sql
\ir production_before_publish_curriculum.sql
\ir production_before_set_session_visibility.sql
\ir production_before_published_curriculum_package_3arg.sql
\ir production_before_published_curriculum_package_2arg.sql

-- Recreate staff history view without Phase B columns if the protect restore
-- left the table columns intact (expected). DROP first: CREATE OR REPLACE
-- cannot remove columns that Phase B added to the view.
drop view if exists admin_api.publications_missing_learner_packages;
drop view if exists admin_api.curriculum_publications;

create view admin_api.curriculum_publications
with (security_invoker = true)
as
select
  publication.id,
  publication.hub_code,
  publication.course_key,
  publication.package_version,
  publication.schema_version,
  publication.source_package_version,
  publication.status,
  publication.author,
  publication.reviewer,
  publication.publication_notes,
  publication.published_by_staff_reference,
  publication.created_at,
  publication.published_at,
  publication.content_hash
from platform.curriculum_publications as publication
where (select platform.current_staff_has_any_role(
  array['platform_admin', 'curriculum_admin', 'operations', 'auditor']
));

revoke all on admin_api.curriculum_publications
  from public, anon, authenticated;
grant select on admin_api.curriculum_publications to authenticated;

revoke all on function platform.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text)
  from public, anon, authenticated;
grant execute on function platform.publish_curriculum(text, text, text, text, text, text, jsonb, text, text, text)
  to authenticated;

revoke all on function platform.set_session_visibility(text, text, text, text)
  from public, anon, authenticated;
grant execute on function platform.set_session_visibility(text, text, text, text)
  to authenticated, service_role;

revoke all on function api.published_curriculum_package(text, text, text)
  from public, anon, authenticated;
revoke all on function api.published_curriculum_package(text, text)
  from public, anon, authenticated;
grant execute on function api.published_curriculum_package(text, text, text)
  to anon, authenticated;
grant execute on function api.published_curriculum_package(text, text)
  to anon, authenticated;

-- Optional helpers introduced by Phase B may remain; revoke execute if present.
do $$
begin
  if to_regprocedure('platform.regenerate_curriculum_learner_packages(text,text,boolean)') is not null then
    execute 'revoke all on function platform.regenerate_curriculum_learner_packages(text, text, boolean) from public, anon, authenticated';
  end if;
end;
$$;
