-- Explicit class-key standardisation for Unit 3, T Level, and L2E (ET).
-- Stored keys remain lowercase kebab-case (groups_registration_key_valid unchanged).
-- Does not recreate groups, rewrite enrolments, or alter Auth identities.

-- Unit 3: keep open_explicit; retire temporary QA key.
update learning.groups
set registration_key = 'nhc-cyber-26'
where code = 'CYBER-TEST-A'
  and registration_key = 'cyber-year-1-test';

-- T Level + Emerging Technologies: delivery keys.
update learning.groups
set registration_key = 'nhc-tlevel-26'
where code = 'TLEVEL-DSD-Y2'
  and registration_key = 'tlevel-dsd-y2';

update learning.groups
set registration_key = 'nhc-et-26'
where code = 'L2E-DELIVERY-A'
  and registration_key = 'l2e-year-1-delivery';

-- Flip auto-enrol hubs to explicit JoinClass (same model as Unit 3).
update platform.hub_group_links as link
set join_policy = 'open_explicit'
from platform.hubs as hub
join learning.groups as learner_group
  on learner_group.id = link.group_id
where link.hub_id = hub.id
  and link.active
  and link.join_policy = 'open_auto'
  and (
    (hub.hub_code = 'tlevel-software-development' and learner_group.code = 'TLEVEL-DSD-Y2')
    or (
      hub.hub_code = 'l2e-exploring-emerging-digital-technologies'
      and learner_group.code = 'L2E-DELIVERY-A'
    )
  );

comment on column learning.groups.registration_key is
  'Lowercase kebab-case class registration key. Learners may type mixed case; hubs normalise before join_learner_hub_group. Tutor-facing display may show uppercase (e.g. NHC-CYBER-26).';
