-- Phase 5 production hardening:
-- library/composition SECURITY DEFINER RPCs inherited PUBLIC EXECUTE.
-- Match the curriculum-draft grant pattern: authenticated only, never anon.

revoke all on function library.is_content_author() from public, anon, authenticated;

revoke all on function admin_api.search_library(text, text[], text, text, text, text[], integer, integer) from public, anon, authenticated;
revoke all on function admin_api.get_library_question_detail(uuid) from public, anon, authenticated;
revoke all on function admin_api.delete_library_item(text, uuid) from public, anon, authenticated;
revoke all on function admin_api.save_library_question(uuid, text, text, text, text, smallint, numeric, integer, text, text, text, text, text, text, text, text[], text, text, jsonb, text[]) from public, anon, authenticated;
revoke all on function admin_api.save_library_activity(uuid, text, text, text, text, text, text, text, text, text, text, text, integer, text[], text, text, jsonb, text[], uuid[]) from public, anon, authenticated;

revoke all on function admin_api.save_composition_reference(uuid, text, text, uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function admin_api.detach_composition_reference(uuid, text, text) from public, anon, authenticated;
revoke all on function admin_api.composition_update_check(uuid) from public, anon, authenticated;
revoke all on function admin_api.composition_impact_analysis(text, uuid) from public, anon, authenticated;

revoke all on function admin_api.save_composition_template(uuid, text, text, text, text, jsonb, text[], text, text) from public, anon, authenticated;
revoke all on function admin_api.archive_composition_template(uuid) from public, anon, authenticated;
revoke all on function admin_api.restore_composition_template(uuid) from public, anon, authenticated;
revoke all on function admin_api.duplicate_composition_template(uuid, text, text) from public, anon, authenticated;
revoke all on function admin_api.list_composition_templates(boolean) from public, anon, authenticated;
revoke all on function admin_api.save_curriculum_recipe(uuid, text, text, text, text, jsonb, text[], text, text) from public, anon, authenticated;
revoke all on function admin_api.archive_curriculum_recipe(uuid) from public, anon, authenticated;
revoke all on function admin_api.restore_curriculum_recipe(uuid) from public, anon, authenticated;
revoke all on function admin_api.duplicate_curriculum_recipe(uuid, text, text) from public, anon, authenticated;
revoke all on function admin_api.list_curriculum_recipes(boolean) from public, anon, authenticated;
revoke all on function admin_api.save_composition_draft_state(uuid, jsonb) from public, anon, authenticated;
revoke all on function admin_api.get_composition_draft_state(uuid) from public, anon, authenticated;

grant execute on function admin_api.search_library(text, text[], text, text, text, text[], integer, integer) to authenticated;
grant execute on function admin_api.get_library_question_detail(uuid) to authenticated;
grant execute on function admin_api.delete_library_item(text, uuid) to authenticated;
grant execute on function admin_api.save_library_question(uuid, text, text, text, text, smallint, numeric, integer, text, text, text, text, text, text, text, text[], text, text, jsonb, text[]) to authenticated;
grant execute on function admin_api.save_library_activity(uuid, text, text, text, text, text, text, text, text, text, text, text, integer, text[], text, text, jsonb, text[], uuid[]) to authenticated;

grant execute on function admin_api.save_composition_reference(uuid, text, text, uuid, text, text, jsonb) to authenticated;
grant execute on function admin_api.detach_composition_reference(uuid, text, text) to authenticated;
grant execute on function admin_api.composition_update_check(uuid) to authenticated;
grant execute on function admin_api.composition_impact_analysis(text, uuid) to authenticated;

grant execute on function admin_api.save_composition_template(uuid, text, text, text, text, jsonb, text[], text, text) to authenticated;
grant execute on function admin_api.archive_composition_template(uuid) to authenticated;
grant execute on function admin_api.restore_composition_template(uuid) to authenticated;
grant execute on function admin_api.duplicate_composition_template(uuid, text, text) to authenticated;
grant execute on function admin_api.list_composition_templates(boolean) to authenticated;
grant execute on function admin_api.save_curriculum_recipe(uuid, text, text, text, text, jsonb, text[], text, text) to authenticated;
grant execute on function admin_api.archive_curriculum_recipe(uuid) to authenticated;
grant execute on function admin_api.restore_curriculum_recipe(uuid) to authenticated;
grant execute on function admin_api.duplicate_curriculum_recipe(uuid, text, text) to authenticated;
grant execute on function admin_api.list_curriculum_recipes(boolean) to authenticated;
grant execute on function admin_api.save_composition_draft_state(uuid, jsonb) to authenticated;
grant execute on function admin_api.get_composition_draft_state(uuid) to authenticated;
