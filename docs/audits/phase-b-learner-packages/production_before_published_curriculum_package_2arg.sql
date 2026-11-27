CREATE OR REPLACE FUNCTION api.published_curriculum_package(p_hub_code text, p_course_key text)
 RETURNS TABLE(hub_code text, course_key text, package_version text, schema_version text, source_package_version text, published_at timestamp with time zone, content_hash text, package jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select *
  from api.published_curriculum_package(p_hub_code, p_course_key, null::text);
$function$

