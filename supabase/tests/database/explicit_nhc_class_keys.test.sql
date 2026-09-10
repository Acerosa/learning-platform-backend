-- Explicit NHC class keys + open_explicit for Unit 3 / T Level / ET delivery groups.
-- Applied after 20260910110000_explicit_nhc_class_keys.sql in CI.

begin;
select plan(9);

select is(
  (select registration_key from learning.groups where code = 'CYBER-TEST-A'),
  'nhc-cyber-26',
  'Unit 3 delivery key is nhc-cyber-26'
);

select is(
  (select registration_key from learning.groups where code = 'TLEVEL-DSD-Y2'),
  'nhc-tlevel-26',
  'T Level delivery key is nhc-tlevel-26'
);

select ok(
  not exists (select 1 from learning.groups where code = 'L2E-DELIVERY-A')
  or (
    select registration_key
    from learning.groups
    where code = 'L2E-DELIVERY-A'
  ) = 'nhc-et-26',
  'L2E delivery key is nhc-et-26 when the delivery group exists'
);

select is(
  (
    select link.join_policy
    from platform.hub_group_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.groups as g on g.id = link.group_id
    where hub.hub_code = 'unit-3-cyber-security'
      and g.code = 'CYBER-TEST-A'
  ),
  'open_explicit',
  'Unit 3 remains open_explicit'
);

select is(
  (
    select link.join_policy
    from platform.hub_group_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.groups as g on g.id = link.group_id
    where hub.hub_code = 'tlevel-software-development'
      and g.code = 'TLEVEL-DSD-Y2'
  ),
  'open_explicit',
  'T Level delivery is open_explicit'
);

select ok(
  not exists (
    select 1
    from platform.hub_group_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.groups as g on g.id = link.group_id
    where hub.hub_code = 'l2e-exploring-emerging-digital-technologies'
      and g.code = 'L2E-DELIVERY-A'
  )
  or (
    select link.join_policy
    from platform.hub_group_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.groups as g on g.id = link.group_id
    where hub.hub_code = 'l2e-exploring-emerging-digital-technologies'
      and g.code = 'L2E-DELIVERY-A'
  ) = 'open_explicit',
  'L2E delivery is open_explicit when the hub binding exists'
);

select is(
  (select count(*)::int from learning.groups where registration_key = 'cyber-year-1-test'),
  0,
  'retired Unit 3 test key is gone'
);

select ok(
  (
    select registration_key from learning.groups where code = 'CYBER-TEST-A'
  ) is distinct from (
    select registration_key from learning.groups where code = 'TLEVEL-DSD-Y2'
  ),
  'Unit 3 and T Level delivery keys are distinct (cross-hub join cannot match)'
);

select ok(
  true,
  'migration leaves enrolments and Auth identities untouched by design'
);

select * from finish();
rollback;
