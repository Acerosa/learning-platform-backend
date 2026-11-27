begin;
select plan(3);

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

select lives_ok(
  $$
    select platform.assert_package_marking_coverage(
      jsonb_build_object(
        'activities',
        jsonb_build_array(
          jsonb_build_object(
            'id', 'foundations-programming-diagnostic',
            'version', '2.0.0'
          )
        )
      )
    )
  $$,
  'Foundations language-aware specs satisfy coverage assert'
);

select * from finish();
rollback;
