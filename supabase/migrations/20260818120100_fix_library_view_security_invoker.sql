-- Phase 5: library/composition admin views were created without security_invoker.
-- Staff API views must use invoker security so underlying library RLS applies.

alter view admin_api.library_questions set (security_invoker = true);
alter view admin_api.library_activities set (security_invoker = true);
alter view admin_api.library_templates set (security_invoker = true);
alter view admin_api.library_resources set (security_invoker = true);
alter view admin_api.library_feedback set (security_invoker = true);
alter view admin_api.library_hints set (security_invoker = true);
alter view admin_api.composition_references set (security_invoker = true);
alter view admin_api.composition_templates set (security_invoker = true);
alter view admin_api.curriculum_recipes set (security_invoker = true);
