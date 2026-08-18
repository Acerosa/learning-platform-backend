-- Staff curriculum drafts and a staff-only read of the live published package.
-- Publication remains admin_api.publish_curriculum. Drafts are never learner-visible.

create table platform.curriculum_drafts (
  id uuid primary key default gen_random_uuid(),
  hub_code text not null,
  course_key text not null,
  title text not null,
  lifecycle_status text not null default 'draft'
    check (lifecycle_status in (
      'draft',
      'ready-for-review',
      'in-review',
      'approved'
    )),
  revision integer not null default 1 check (revision > 0),
  package jsonb not null,
  based_on_package_version text,
  updated_by_auth_user_id uuid,
  updated_by_staff_reference text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create unique index curriculum_drafts_hub_course_idx
  on platform.curriculum_drafts (hub_code, course_key, id);

alter table platform.curriculum_drafts enable row level security;

revoke all on platform.curriculum_drafts from anon, authenticated, public;
grant select on platform.curriculum_drafts to authenticated;

create policy curriculum_drafts_staff_read
on platform.curriculum_drafts
for select
to authenticated
using (
  platform.current_staff_has_role('platform_admin')
  or platform.current_staff_has_role('curriculum_admin')
);

create function platform.require_curriculum_author()
returns learning.teachers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_teacher learning.teachers%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  select teacher.*
  into v_teacher
  from learning.teachers as teacher
  where teacher.auth_user_id = auth.uid()
    and teacher.active;

  if not found
     or (
       not platform.current_staff_has_role('platform_admin')
       and not platform.current_staff_has_role('curriculum_admin')
     ) then
    raise exception using errcode = '28000', message = 'CURRICULUM_AUTHORING_NOT_AUTHORISED';
  end if;

  return v_teacher;
end;
$$;

create function platform.save_curriculum_draft(
  p_draft_id uuid,
  p_hub_code text,
  p_course_key text,
  p_title text,
  p_lifecycle_status text,
  p_expected_revision integer,
  p_package jsonb,
  p_based_on_package_version text
)
returns table (
  id uuid,
  hub_code text,
  course_key text,
  title text,
  lifecycle_status text,
  revision integer,
  based_on_package_version text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_teacher learning.teachers%rowtype;
  v_hub text;
  v_course text;
  v_title text;
  v_status text;
  v_expected integer;
  v_existing platform.curriculum_drafts%rowtype;
  v_saved platform.curriculum_drafts%rowtype;
  v_created boolean := false;
begin
  v_teacher := platform.require_curriculum_author();
  v_hub := lower(nullif(btrim(p_hub_code), ''));
  v_course := lower(nullif(btrim(p_course_key), ''));
  v_title := nullif(btrim(p_title), '');
  v_status := lower(coalesce(nullif(btrim(p_lifecycle_status), ''), 'draft'));
  v_expected := coalesce(p_expected_revision, 0);

  if v_hub is null or v_course is null or v_title is null or p_package is null then
    raise exception using errcode = '22023', message = 'DRAFT_PAYLOAD_INVALID';
  end if;

  if v_status not in ('draft', 'ready-for-review', 'in-review', 'approved') then
    raise exception using errcode = '22023', message = 'DRAFT_STATUS_INVALID';
  end if;

  if p_draft_id is not null then
    select * into v_existing
    from platform.curriculum_drafts as draft
    where draft.id = p_draft_id;
  end if;

  if v_existing.id is null then
    if v_expected not in (0, 1) then
      raise exception using errcode = '22023', message = 'DRAFT_REVISION_CONFLICT';
    end if;

    insert into platform.curriculum_drafts (
      id,
      hub_code,
      course_key,
      title,
      lifecycle_status,
      revision,
      package,
      based_on_package_version,
      updated_by_auth_user_id,
      updated_by_staff_reference
    ) values (
      coalesce(p_draft_id, gen_random_uuid()),
      v_hub,
      v_course,
      v_title,
      v_status,
      1,
      p_package,
      nullif(btrim(p_based_on_package_version), ''),
      auth.uid(),
      v_teacher.staff_reference
    )
    returning * into v_saved;
    v_created := true;
  else
    if v_existing.revision is distinct from v_expected then
      raise exception using errcode = '22023', message = 'DRAFT_REVISION_CONFLICT';
    end if;

    update platform.curriculum_drafts
    set
      hub_code = v_hub,
      course_key = v_course,
      title = v_title,
      lifecycle_status = v_status,
      revision = v_existing.revision + 1,
      package = p_package,
      based_on_package_version = nullif(btrim(p_based_on_package_version), ''),
      updated_by_auth_user_id = auth.uid(),
      updated_by_staff_reference = v_teacher.staff_reference,
      updated_at = clock_timestamp()
    where platform.curriculum_drafts.id = v_existing.id
    returning * into v_saved;
  end if;

  perform platform.record_audit_event(
    case when v_created then 'curriculum.draft.saved' else 'curriculum.draft.updated' end,
    'staff',
    'curriculum-draft',
    v_saved.id::text,
    'succeeded',
    jsonb_build_object(
      'hubCode', v_saved.hub_code,
      'courseKey', v_saved.course_key,
      'revision', v_saved.revision,
      'lifecycleStatus', v_saved.lifecycle_status,
      'basedOnPackageVersion', v_saved.based_on_package_version
    )
  );

  return query
  select
    v_saved.id,
    v_saved.hub_code,
    v_saved.course_key,
    v_saved.title,
    v_saved.lifecycle_status,
    v_saved.revision,
    v_saved.based_on_package_version,
    v_saved.updated_at;
end;
$$;

create function platform.get_curriculum_draft(p_draft_id uuid)
returns table (
  id uuid,
  hub_code text,
  course_key text,
  title text,
  lifecycle_status text,
  revision integer,
  package jsonb,
  based_on_package_version text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform platform.require_curriculum_author();
  if p_draft_id is null then
    raise exception using errcode = '22023', message = 'DRAFT_NOT_FOUND';
  end if;

  return query
  select
    draft.id,
    draft.hub_code,
    draft.course_key,
    draft.title,
    draft.lifecycle_status,
    draft.revision,
    draft.package,
    draft.based_on_package_version,
    draft.updated_at
  from platform.curriculum_drafts as draft
  where draft.id = p_draft_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'DRAFT_NOT_FOUND';
  end if;
end;
$$;

create function platform.discard_curriculum_draft(p_draft_id uuid)
returns table (
  id uuid,
  discarded boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing platform.curriculum_drafts%rowtype;
begin
  perform platform.require_curriculum_author();

  select * into v_existing
  from platform.curriculum_drafts as draft
  where draft.id = p_draft_id;

  if v_existing.id is null then
    raise exception using errcode = 'P0002', message = 'DRAFT_NOT_FOUND';
  end if;

  delete from platform.curriculum_drafts where platform.curriculum_drafts.id = v_existing.id;

  perform platform.record_audit_event(
    'curriculum.draft.discarded',
    'staff',
    'curriculum-draft',
    v_existing.id::text,
    'succeeded',
    jsonb_build_object(
      'hubCode', v_existing.hub_code,
      'courseKey', v_existing.course_key,
      'revision', v_existing.revision
    )
  );

  return query select v_existing.id, true;
end;
$$;

create function platform.current_curriculum_package(p_hub_code text, p_course_key text)
returns table (
  id uuid,
  hub_code text,
  course_key text,
  package_version text,
  schema_version text,
  source_package_version text,
  status text,
  package jsonb,
  content_hash text,
  published_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform platform.require_curriculum_author();

  return query
  select
    publication.id,
    publication.hub_code,
    publication.course_key,
    publication.package_version,
    publication.schema_version,
    publication.source_package_version,
    publication.status,
    publication.package,
    publication.content_hash,
    publication.published_at
  from platform.curriculum_publications as publication
  where publication.hub_code = lower(btrim(p_hub_code))
    and publication.course_key = lower(btrim(p_course_key))
    and publication.status = 'published';

  if not found then
    raise exception using errcode = 'P0002', message = 'PUBLICATION_NOT_FOUND';
  end if;
end;
$$;

create function admin_api.save_curriculum_draft(
  p_draft_id uuid,
  p_hub_code text,
  p_course_key text,
  p_title text,
  p_lifecycle_status text,
  p_expected_revision integer,
  p_package jsonb,
  p_based_on_package_version text
)
returns table (
  id uuid,
  hub_code text,
  course_key text,
  title text,
  lifecycle_status text,
  revision integer,
  based_on_package_version text,
  updated_at timestamptz
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from platform.save_curriculum_draft(
    p_draft_id,
    p_hub_code,
    p_course_key,
    p_title,
    p_lifecycle_status,
    p_expected_revision,
    p_package,
    p_based_on_package_version
  );
$$;

create function admin_api.get_curriculum_draft(p_draft_id uuid)
returns table (
  id uuid,
  hub_code text,
  course_key text,
  title text,
  lifecycle_status text,
  revision integer,
  package jsonb,
  based_on_package_version text,
  updated_at timestamptz
)
language sql
security invoker
set search_path = ''
as $$
  select * from platform.get_curriculum_draft(p_draft_id);
$$;

create function admin_api.discard_curriculum_draft(p_draft_id uuid)
returns table (
  id uuid,
  discarded boolean
)
language sql
security invoker
set search_path = ''
as $$
  select * from platform.discard_curriculum_draft(p_draft_id);
$$;

create function admin_api.current_curriculum_package(p_hub_code text, p_course_key text)
returns table (
  id uuid,
  hub_code text,
  course_key text,
  package_version text,
  schema_version text,
  source_package_version text,
  status text,
  package jsonb,
  content_hash text,
  published_at timestamptz
)
language sql
security invoker
set search_path = ''
as $$
  select * from platform.current_curriculum_package(p_hub_code, p_course_key);
$$;

create view admin_api.curriculum_drafts
with (security_invoker = true)
as
select
  draft.id,
  draft.hub_code,
  draft.course_key,
  draft.title,
  draft.lifecycle_status,
  draft.revision,
  draft.based_on_package_version,
  draft.updated_by_staff_reference,
  draft.created_at,
  draft.updated_at
from platform.curriculum_drafts as draft
where (
  select platform.current_staff_has_role('platform_admin')
  or platform.current_staff_has_role('curriculum_admin')
);

revoke all on function platform.require_curriculum_author() from public, anon, authenticated;
revoke all on function platform.save_curriculum_draft(uuid, text, text, text, text, integer, jsonb, text) from public, anon, authenticated;
revoke all on function platform.get_curriculum_draft(uuid) from public, anon, authenticated;
revoke all on function platform.discard_curriculum_draft(uuid) from public, anon, authenticated;
revoke all on function platform.current_curriculum_package(text, text) from public, anon, authenticated;
revoke all on function admin_api.save_curriculum_draft(uuid, text, text, text, text, integer, jsonb, text) from public, anon, authenticated;
revoke all on function admin_api.get_curriculum_draft(uuid) from public, anon, authenticated;
revoke all on function admin_api.discard_curriculum_draft(uuid) from public, anon, authenticated;
revoke all on function admin_api.current_curriculum_package(text, text) from public, anon, authenticated;
revoke all on admin_api.curriculum_drafts from public, anon, authenticated;

grant execute on function platform.save_curriculum_draft(uuid, text, text, text, text, integer, jsonb, text) to authenticated;
grant execute on function platform.get_curriculum_draft(uuid) to authenticated;
grant execute on function platform.discard_curriculum_draft(uuid) to authenticated;
grant execute on function platform.current_curriculum_package(text, text) to authenticated;
grant execute on function admin_api.save_curriculum_draft(uuid, text, text, text, text, integer, jsonb, text) to authenticated;
grant execute on function admin_api.get_curriculum_draft(uuid) to authenticated;
grant execute on function admin_api.discard_curriculum_draft(uuid) to authenticated;
grant execute on function admin_api.current_curriculum_package(text, text) to authenticated;
grant select on admin_api.curriculum_drafts to authenticated;

comment on table platform.curriculum_drafts is
  'Staff-only curriculum drafts. Never exposed to learner api. Live teaching content remains curriculum_publications.';
comment on function admin_api.save_curriculum_draft(uuid, text, text, text, text, integer, jsonb, text) is
  'Create or update a staff curriculum draft with optimistic revision checks.';
comment on function admin_api.current_curriculum_package(text, text) is
  'Staff read of the currently published package body for authoring a working copy.';
