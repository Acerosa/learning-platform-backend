-- Phase B stage 1: nullable learner_package storage and narrowly scoped
-- immutability exception for backfill / sanitisation regeneration.
-- Staff package remains the authoritative curriculum representation.
-- No public grants are added.

alter table platform.curriculum_publications
  add column if not exists learner_package jsonb,
  add column if not exists learner_package_sanitisation_version text;

alter table platform.curriculum_publications
  drop constraint if exists curriculum_publication_learner_package_object,
  drop constraint if exists curriculum_publication_learner_package_size,
  drop constraint if exists curriculum_publication_learner_sanitisation_present;

alter table platform.curriculum_publications
  add constraint curriculum_publication_learner_package_object
    check (
      learner_package is null
      or jsonb_typeof(learner_package) = 'object'
    ),
  add constraint curriculum_publication_learner_package_size
    check (
      learner_package is null
      or octet_length(learner_package::text) <= 4194304
    ),
  add constraint curriculum_publication_learner_sanitisation_present
    check (
      (learner_package is null and learner_package_sanitisation_version is null)
      or (
        learner_package is not null
        and nullif(btrim(learner_package_sanitisation_version), '') is not null
      )
    );

comment on column platform.curriculum_publications.learner_package is
  'Derived learner-safe teaching package generated at publication time. Not independently editable curriculum.';
comment on column platform.curriculum_publications.learner_package_sanitisation_version is
  'Sanitisation rule version used to generate learner_package. Bump and regenerate when strip rules change.';

create or replace function platform.protect_curriculum_publication()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '22023', message = 'PUBLISHED_CURRICULUM_IMMUTABLE';
  end if;

  -- Controlled supersede: status only, all other fields unchanged.
  if new.status = 'superseded'
     and old.status = 'published'
     and new.hub_code = old.hub_code
     and new.course_key = old.course_key
     and new.package_version = old.package_version
     and new.schema_version = old.schema_version
     and new.source_package_version = old.source_package_version
     and new.package = old.package
     and new.content_hash = old.content_hash
     and new.author = old.author
     and new.reviewer = old.reviewer
     and new.publication_notes = old.publication_notes
     and new.published_by_auth_user_id = old.published_by_auth_user_id
     and new.published_by_staff_reference = old.published_by_staff_reference
     and new.created_at = old.created_at
     and new.published_at = old.published_at
     and new.id = old.id
     and new.learner_package is not distinct from old.learner_package
     and new.learner_package_sanitisation_version
       is not distinct from old.learner_package_sanitisation_version then
    return new;
  end if;

  -- Narrow backfill / sanitisation regeneration: only derived learner fields.
  if new.id = old.id
     and new.hub_code = old.hub_code
     and new.course_key = old.course_key
     and new.package_version = old.package_version
     and new.schema_version = old.schema_version
     and new.source_package_version = old.source_package_version
     and new.status = old.status
     and new.package = old.package
     and new.content_hash = old.content_hash
     and new.author = old.author
     and new.reviewer = old.reviewer
     and new.publication_notes = old.publication_notes
     and new.published_by_auth_user_id = old.published_by_auth_user_id
     and new.published_by_staff_reference = old.published_by_staff_reference
     and new.created_at = old.created_at
     and new.published_at = old.published_at
     and new.learner_package is not null
     and jsonb_typeof(new.learner_package) = 'object'
     and nullif(btrim(coalesce(new.learner_package_sanitisation_version, '')), '') is not null
     and (
       new.learner_package is distinct from old.learner_package
       or new.learner_package_sanitisation_version
         is distinct from old.learner_package_sanitisation_version
     ) then
    return new;
  end if;

  raise exception using errcode = '22023', message = 'PUBLISHED_CURRICULUM_IMMUTABLE';
end;
$$;

revoke all on function platform.protect_curriculum_publication()
  from public, anon, authenticated;

comment on function platform.protect_curriculum_publication() is
  'Blocks destructive publication edits. Allows published→superseded status transitions and derived learner_package backfill/regeneration only.';

create or replace view admin_api.curriculum_publications
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
  publication.content_hash,
  (publication.learner_package is not null) as has_learner_package,
  publication.learner_package_sanitisation_version
from platform.curriculum_publications as publication
where (select platform.current_staff_has_any_role(
  array['platform_admin', 'curriculum_admin', 'operations', 'auditor']
));

revoke all on admin_api.curriculum_publications
  from public, anon, authenticated;
grant select on admin_api.curriculum_publications to authenticated;

comment on view admin_api.curriculum_publications is
  'Staff publication history without package bodies. Exposes learner-package presence and sanitisation version only.';
