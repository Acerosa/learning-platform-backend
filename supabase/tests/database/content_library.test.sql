begin;
select plan(16);

-- 1. Schema exists
select has_schema('library', 'library schema exists');

-- 2. Core tables exist
select has_table('library', 'questions', 'library.questions exists');
select has_table('library', 'activities', 'library.activities exists');
select has_table('library', 'templates', 'library.templates exists');
select has_table('library', 'resources', 'library.resources exists');
select has_table('library', 'feedback', 'library.feedback exists');
select has_table('library', 'hints', 'library.hints exists');
select has_table('library', 'code_templates', 'library.code_templates exists');
select has_table('library', 'assessment_templates', 'library.assessment_templates exists');

-- 3. Join tables exist
select has_table('library', 'activity_questions', 'library.activity_questions exists');
select has_table('library', 'usage_references', 'library.usage_references exists');

-- 4. RLS enabled on questions
select is(
  (select relrowsecurity from pg_class
   where oid = 'library.questions'::regclass),
  true,
  'RLS is enabled on library.questions'
);

-- 5. Content author function exists
select has_function('library', 'is_content_author', '{}', 'library.is_content_author() exists');

-- 6. Anonymous callers cannot execute library SECURITY DEFINER RPCs
select is(
  has_function_privilege(
    'anon',
    'admin_api.search_library(text, text[], text, text, text, text[], integer, integer)',
    'EXECUTE'
  ),
  false,
  'anon cannot execute admin_api.search_library'
);
select is(
  has_function_privilege(
    'authenticated',
    'admin_api.search_library(text, text[], text, text, text, text[], integer, integer)',
    'EXECUTE'
  ),
  true,
  'authenticated can execute admin_api.search_library'
);

-- 7. Staff library views use invoker security
select is(
  coalesce((
    select option_value = 'true'
    from pg_options_to_table((select reloptions from pg_class where oid = 'admin_api.library_questions'::regclass))
    where option_name = 'security_invoker'
  ), false),
  true,
  'admin_api.library_questions uses security_invoker'
);

select * from finish();
rollback;
