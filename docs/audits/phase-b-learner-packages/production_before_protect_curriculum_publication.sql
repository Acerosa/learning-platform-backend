CREATE OR REPLACE FUNCTION platform.protect_curriculum_publication()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '22023', message = 'PUBLISHED_CURRICULUM_IMMUTABLE';
  end if;

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
     and new.id = old.id then
    return new;
  end if;

  raise exception using errcode = '22023', message = 'PUBLISHED_CURRICULUM_IMMUTABLE';
end;
$function$

