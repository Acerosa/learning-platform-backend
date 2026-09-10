begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_function(
  'api',
  'ensure_learner_auth_link',
  array[]::text[],
  'ensure_learner_auth_link exists'
);

select is(
  (
    select prosecdef
    from pg_proc
    where pronamespace = 'api'::regnamespace
      and proname = 'ensure_learner_auth_link'
  ),
  true,
  'ensure_learner_auth_link is SECURITY DEFINER'
);

select * from finish();
rollback;
