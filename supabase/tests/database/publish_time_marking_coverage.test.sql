begin;
select plan(2);

select has_function(
  'platform',
  'assert_package_marking_coverage',
  array['jsonb'],
  'marking coverage assert helper exists'
);

select lives_ok(
  $$
    select platform.assert_package_marking_coverage(
      jsonb_build_object('activities', '[]'::jsonb)
    )
  $$,
  'empty activity list passes coverage assert'
);

select * from finish();
rollback;
