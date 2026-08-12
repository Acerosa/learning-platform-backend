begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_schema('platform', 'protected platform schema exists');
select has_schema('admin_api', 'staff-only API schema exists');
select has_table('platform', 'hubs', 'hub registry table exists');
select has_table('platform', 'contract_versions', 'contract version table exists');
select has_table('platform', 'staff_roles', 'platform staff role table exists');
select has_table('platform', 'audit_events', 'audit event table exists');
select has_table('platform', 'operational_health', 'operational health table exists');

select has_function(
  'api',
  'registered_hubs',
  array[]::text[],
  'learner-safe hub registry RPC exists'
);
select has_function(
  'api',
  'platform_contract_versions',
  array[]::text[],
  'public platform contract RPC exists'
);
select has_function(
  'api',
  'platform_health',
  array[]::text[],
  'safe operational health RPC exists'
);

select is(
  (
    select count(*)
    from platform.contract_versions
    where status = 'active'
  ),
  4::bigint,
  'hub manifest, core, learner API and submission contracts are active'
);

select is(
  (
    select count(*)
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'admin_api'
      and relation.relkind = 'v'
      and coalesce((
        select option_value = 'true'
        from pg_options_to_table(relation.reloptions)
        where option_name = 'security_invoker'
      ), false)
  ),
  14::bigint,
  'all staff API views use invoker security'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'platform.record_audit_event(text,text,text,text,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated browsers cannot append audit events directly'
);

select ok(
  has_function_privilege(
    'service_role',
    'platform.record_audit_event(text,text,text,text,text,jsonb)',
    'EXECUTE'
  ),
  'the service role can append controlled audit events'
);

set local role anon;

select is(
  (select count(*) from api.registered_hubs()),
  2::bigint,
  'anonymous clients can discover active local hub fixtures through the safe RPC'
);

select is(
  (select count(*) from api.platform_contract_versions()),
  4::bigint,
  'anonymous clients can negotiate active platform contract versions'
);

select is(
  (select count(*) from api.platform_health()),
  1::bigint,
  'anonymous clients can read the current public health summary'
);

select throws_like(
  $$select * from admin_api.learners$$,
  '%permission denied%',
  'anonymous clients cannot use the staff API schema'
);

select throws_like(
  $$select platform.current_staff_has_role('platform_admin')$$,
  '%permission denied%',
  'anonymous clients cannot execute staff authorisation helpers'
);

reset role;

select * from finish();
rollback;
