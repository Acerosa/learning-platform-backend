begin;
select plan(27);

-- 1. Composition tables exist
select has_table('library', 'composition_references', 'library.composition_references exists');
select has_table('library', 'composition_templates', 'library.composition_templates exists');
select has_table('library', 'curriculum_recipes', 'library.curriculum_recipes exists');

-- 2. RLS enabled
select is(
  (select relrowsecurity from pg_class where oid = 'library.composition_references'::regclass),
  true, 'RLS on composition_references'
);
select is(
  (select relrowsecurity from pg_class where oid = 'library.composition_templates'::regclass),
  true, 'RLS on composition_templates'
);
select is(
  (select relrowsecurity from pg_class where oid = 'library.curriculum_recipes'::regclass),
  true, 'RLS on curriculum_recipes'
);

-- 3. State constraint
select col_has_check('library', 'composition_references', 'state', 'state has CHECK constraint');

-- 4. Admin API functions exist
select has_function('admin_api', 'save_composition_reference',
  array['uuid','text','text','uuid','text','text','jsonb'],
  'save_composition_reference exists');
select has_function('admin_api', 'detach_composition_reference',
  array['uuid','text','text'],
  'detach_composition_reference exists');
select has_function('admin_api', 'composition_update_check',
  array['uuid'],
  'composition_update_check exists');

select has_function('admin_api', 'save_composition_template',
  array['uuid','text','text','text','text','jsonb','text[]','text','text'],
  'save_composition_template exists');
select has_function('admin_api', 'archive_composition_template',
  array['uuid'],
  'archive_composition_template exists');
select has_function('admin_api', 'restore_composition_template',
  array['uuid'],
  'restore_composition_template exists');
select has_function('admin_api', 'duplicate_composition_template',
  array['uuid','text','text'],
  'duplicate_composition_template exists');
select has_function('admin_api', 'list_composition_templates',
  array['boolean'],
  'list_composition_templates exists');
select has_function('admin_api', 'save_curriculum_recipe',
  array['uuid','text','text','text','text','jsonb','text[]','text','text'],
  'save_curriculum_recipe exists');
select has_function('admin_api', 'archive_curriculum_recipe',
  array['uuid'],
  'archive_curriculum_recipe exists');
select has_function('admin_api', 'restore_curriculum_recipe',
  array['uuid'],
  'restore_curriculum_recipe exists');
select has_function('admin_api', 'duplicate_curriculum_recipe',
  array['uuid','text','text'],
  'duplicate_curriculum_recipe exists');
select has_function('admin_api', 'list_curriculum_recipes',
  array['boolean'],
  'list_curriculum_recipes exists');
select has_function('admin_api', 'save_composition_draft_state',
  array['uuid','jsonb'],
  'save_composition_draft_state exists');
select has_function('admin_api', 'get_composition_draft_state',
  array['uuid'],
  'get_composition_draft_state exists');

select is(
  has_function_privilege(
    'anon',
    'admin_api.list_composition_templates(boolean)',
    'EXECUTE'
  ),
  false,
  'anon cannot execute admin_api.list_composition_templates'
);
select is(
  has_function_privilege(
    'authenticated',
    'admin_api.list_composition_templates(boolean)',
    'EXECUTE'
  ),
  true,
  'authenticated can execute admin_api.list_composition_templates'
);

set local role anon;
select throws_like(
  $$select * from admin_api.composition_templates$$,
  '%permission denied%',
  'anonymous users cannot read composition templates view directly'
);
reset role;

set local role authenticated;
select is(
  (select count(*) from admin_api.list_composition_templates(false)),
  0::bigint,
  'authenticated users without content-author context do not receive composition templates'
);
select is(
  (select count(*) from admin_api.list_curriculum_recipes(false)),
  0::bigint,
  'authenticated users without content-author context do not receive curriculum recipes'
);
reset role;

select * from finish();
rollback;
