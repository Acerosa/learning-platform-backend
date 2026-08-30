-- Library writes go through staff SECURITY DEFINER RPCs. Direct table DML
-- from the authenticated role is not required and widens the grant surface.

revoke insert, update, delete on all tables in schema library from authenticated;
grant select on all tables in schema library to authenticated;

revoke insert, update, delete on library.composition_references from authenticated;
revoke insert, update, delete on library.composition_templates from authenticated;
revoke insert, update, delete on library.curriculum_recipes from authenticated;
grant select on library.composition_references to authenticated;
grant select on library.composition_templates to authenticated;
grant select on library.curriculum_recipes to authenticated;
