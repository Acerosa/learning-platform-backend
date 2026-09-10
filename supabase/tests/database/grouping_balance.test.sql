begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

select has_function(
  'learning',
  'balanced_group_sizes',
  array['integer', 'integer'],
  'balanced group size helper exists'
);

-- Preferred size 5 acceptance cases
select is(
  learning.balanced_group_sizes(10, 5),
  array[5, 5],
  '10 students preferred 5 → 5,5'
);

select is(
  learning.balanced_group_sizes(11, 5),
  array[6, 5],
  '11 students preferred 5 → 6,5'
);

select is(
  learning.balanced_group_sizes(14, 5),
  array[5, 5, 4],
  '14 students preferred 5 → 5,5,4'
);

select is(
  learning.balanced_group_sizes(16, 5),
  array[4, 4, 4, 4],
  '16 students preferred 5 → 4,4,4,4'
);

select is(
  learning.balanced_group_sizes(19, 5),
  array[5, 5, 5, 4],
  '19 students preferred 5 → 5,5,5,4'
);

select is(
  learning.balanced_group_sizes(23, 5),
  array[5, 5, 5, 4, 4],
  '23 students preferred 5 → 5,5,5,4,4'
);

-- Small / uneven / other preferred sizes
select is(
  learning.balanced_group_sizes(0, 5),
  array[]::integer[],
  'zero students yields empty sizes'
);

select is(
  learning.balanced_group_sizes(1, 5),
  array[1],
  'single student yields one group'
);

select is(
  learning.balanced_group_sizes(3, 5),
  array[3],
  'three students stay together near preferred 5'
);

select is(
  learning.balanced_group_sizes(8, 4),
  array[4, 4],
  '8 students preferred 4 → 4,4'
);

select ok(
  (
    select sum(size) = 9
      and max(size) - min(size) <= 1
      and min(size) >= 2
    from unnest(learning.balanced_group_sizes(9, 4)) as size
  ),
  '9 students preferred 4 stay balanced without tiny leftovers'
);

select is(
  learning.balanced_group_sizes(12, 3),
  array[3, 3, 3, 3],
  '12 students preferred 3 → four groups of 3'
);

select ok(
  (
    select sum(size) = 23
    from unnest(learning.balanced_group_sizes(23, 5)) as size
  ),
  'size arrays always sum to the participant count'
);

select ok(
  (
    select max(size) - min(size) <= 1
    from unnest(learning.balanced_group_sizes(23, 5)) as size
  ),
  'largest and smallest groups differ by at most one for 23/5'
);

select ok(
  (
    select min(size) >= 2
    from unnest(learning.balanced_group_sizes(11, 5)) as size
  ),
  'avoids singleton leftovers for 11/5'
);

select * from finish();
rollback;
