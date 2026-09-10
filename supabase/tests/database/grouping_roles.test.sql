begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

create temporary table pg_temp.roles_ctx (
  label text primary key,
  session_id uuid,
  join_code text,
  participant_token uuid,
  participant_id uuid,
  team_id uuid,
  role_type text
);

grant all on table pg_temp.roles_ctx to authenticated, anon;

select has_function(
  'learning',
  'planned_grouping_role_types',
  array['integer'],
  'planned role helper exists'
);

select is(
  learning.planned_grouping_role_types(1),
  array['project_manager']::text[],
  'group of 1 → Project Manager'
);

select is(
  learning.planned_grouping_role_types(2),
  array['project_manager', 'tester']::text[],
  'group of 2 → Project Manager + Tester'
);

select is(
  learning.planned_grouping_role_types(4),
  array['project_manager', 'tester', 'specialist', 'specialist']::text[],
  'group of 4 → 1 PM, 1 Tester, 2 specialists'
);

select is(
  learning.planned_grouping_role_types(8),
  array[
    'project_manager',
    'tester',
    'specialist',
    'specialist',
    'specialist',
    'specialist',
    'specialist',
    'specialist'
  ]::text[],
  'group of 8 → 1 PM, 1 Tester, 6 specialists'
);

select is(
  learning.planned_grouping_role_types(9),
  array[
    'project_manager',
    'tester',
    'tester',
    'specialist',
    'specialist',
    'specialist',
    'specialist',
    'specialist',
    'specialist'
  ]::text[],
  'group of 9 → 1 PM, 2 Testers, 6 specialists'
);

select is(
  learning.planned_grouping_role_types(12),
  array[
    'project_manager',
    'tester',
    'tester',
    'specialist',
    'specialist',
    'specialist',
    'specialist',
    'specialist',
    'specialist',
    'specialist',
    'specialist',
    'specialist'
  ]::text[],
  'group of 12 → 1 PM, 2 Testers, 9 specialists'
);

select is(
  learning.grouping_role_display_title('project_manager', 'Developer'),
  'Project Manager',
  'PM display title is fixed'
);

select is(
  learning.grouping_role_display_title('tester', 'Developer'),
  'Tester',
  'Tester display title is fixed'
);

select is(
  learning.grouping_role_display_title('specialist', 'Cyber Security Analyst'),
  'Cyber Security Analyst',
  'Cyber Security specialist display title'
);

select is(
  learning.grouping_role_display_title('specialist', 'Developer'),
  'Developer',
  'Software Development specialist display title'
);

-- Platform admin from shared fixtures
set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

-- Legacy session without specialist role
insert into pg_temp.roles_ctx (label, session_id, join_code)
select
  'legacy',
  (payload ->> 'id')::uuid,
  payload ->> 'joinCode'
from (
  select admin_api.create_grouping_session('Legacy no roles', 5, null) as payload
) as created;

reset role;
set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

do $$
declare
  v_code text;
  v_i integer;
begin
  select join_code into v_code from pg_temp.roles_ctx where label = 'legacy';
  for v_i in 1..4 loop
    perform api.join_grouping_session(
      v_code,
      'Legacy ' || v_i::text,
      'legacy-client-' || v_i::text
    );
  end loop;
end;
$$;

set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

select lives_ok(
  $sql$
    select admin_api.generate_grouping_teams(
      (select session_id from pg_temp.roles_ctx where label = 'legacy'),
      4
    )
  $sql$,
  'legacy session without specialist role still generates'
);

select is(
  (
    select count(*)::integer
    from learning.grouping_participants
    where session_id = (select session_id from pg_temp.roles_ctx where label = 'legacy')
      and role_type is not null
  ),
  0,
  'legacy session without specialist role assigns no roles'
);

-- Cyber Security session
insert into pg_temp.roles_ctx (label, session_id, join_code)
select
  'cyber',
  (payload ->> 'id')::uuid,
  payload ->> 'joinCode'
from (
  select admin_api.create_grouping_session(
    'Cyber roles',
    5,
    'Cyber Security Analyst'
  ) as payload
) as created;

select is(
  (
    select specialist_role_title
    from learning.grouping_sessions
    where id = (select session_id from pg_temp.roles_ctx where label = 'cyber')
  ),
  'Cyber Security Analyst',
  'specialist role can be stored on a grouping session'
);

reset role;
set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

do $$
declare
  v_code text;
  v_i integer;
begin
  select join_code into v_code from pg_temp.roles_ctx where label = 'cyber';
  for v_i in 1..6 loop
    perform api.join_grouping_session(
      v_code,
      'Cyber ' || v_i::text,
      'cyber-client-' || v_i::text
    );
  end loop;
end;
$$;

set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

select lives_ok(
  $sql$
    select admin_api.generate_grouping_teams(
      (select session_id from pg_temp.roles_ctx where label = 'cyber'),
      6
    )
  $sql$,
  'cyber session generates with roles'
);

select is(
  (
    select count(*)::integer
    from learning.grouping_participants
    where session_id = (select session_id from pg_temp.roles_ctx where label = 'cyber')
      and removed_at is null
      and team_id is not null
      and role_type is null
  ),
  0,
  'every participant receives exactly one role'
);

select is(
  (
    select count(*)::integer
    from learning.grouping_participants
    where session_id = (select session_id from pg_temp.roles_ctx where label = 'cyber')
      and role_type = 'project_manager'
  ),
  (
    select count(*)::integer
    from learning.grouping_teams
    where session_id = (select session_id from pg_temp.roles_ctx where label = 'cyber')
  ),
  'every normal group receives exactly one Project Manager'
);

select ok(
  (
    select bool_and(tester_count <= 1)
    from (
      select count(*) filter (where participant.role_type = 'tester') as tester_count
      from learning.grouping_teams as team
      join learning.grouping_participants as participant
        on participant.team_id = team.id
       and participant.removed_at is null
      where team.session_id = (select session_id from pg_temp.roles_ctx where label = 'cyber')
      group by team.id
    ) counts
  ),
  'groups of 8 or below receive at most one Tester'
);

select ok(
  exists (
    select 1
    from learning.grouping_participants as participant
    where participant.session_id = (select session_id from pg_temp.roles_ctx where label = 'cyber')
      and learning.grouping_role_display_title(
        participant.role_type,
        'Cyber Security Analyst'
      ) = 'Cyber Security Analyst'
  ),
  'Cyber Security session can return Cyber Security Analyst'
);

-- Software Development
insert into pg_temp.roles_ctx (label, session_id, join_code)
select
  'sd',
  (payload ->> 'id')::uuid,
  payload ->> 'joinCode'
from (
  select admin_api.create_grouping_session('SD roles', 5, 'Developer') as payload
) as created;

reset role;
set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

do $$
declare
  v_code text;
  v_i integer;
begin
  select join_code into v_code from pg_temp.roles_ctx where label = 'sd';
  for v_i in 1..4 loop
    perform api.join_grouping_session(
      v_code,
      'Dev ' || v_i::text,
      'sd-client-' || v_i::text
    );
  end loop;
end;
$$;

set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

select lives_ok(
  $sql$
    select admin_api.generate_grouping_teams(
      (select session_id from pg_temp.roles_ctx where label = 'sd'),
      4
    )
  $sql$,
  'software development session generates with roles'
);

select ok(
  exists (
    select 1
    from learning.grouping_participants as participant
    where participant.session_id = (select session_id from pg_temp.roles_ctx where label = 'sd')
      and learning.grouping_role_display_title(participant.role_type, 'Developer') = 'Developer'
  ),
  'Software Development session can return Developer'
);

-- Large group for two-tester rule
insert into pg_temp.roles_ctx (label, session_id, join_code)
select
  'large',
  (payload ->> 'id')::uuid,
  payload ->> 'joinCode'
from (
  select admin_api.create_grouping_session('Large roles', 12, 'Developer') as payload
) as created;

reset role;
set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

do $$
declare
  v_code text;
  v_i integer;
begin
  select join_code into v_code from pg_temp.roles_ctx where label = 'large';
  for v_i in 1..9 loop
    perform api.join_grouping_session(
      v_code,
      'Large ' || v_i::text,
      'large-client-' || v_i::text
    );
  end loop;
end;
$$;

set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

select lives_ok(
  $sql$
    select admin_api.generate_grouping_teams(
      (select session_id from pg_temp.roles_ctx where label = 'large'),
      12
    )
  $sql$,
  'large session generates with roles'
);

select ok(
  coalesce(
    (
      select bool_and(tester_count = 2)
      from (
        select count(*) filter (where participant.role_type = 'tester') as tester_count,
               count(*) as member_count
        from learning.grouping_teams as team
        join learning.grouping_participants as participant
          on participant.team_id = team.id
         and participant.removed_at is null
        where team.session_id = (select session_id from pg_temp.roles_ctx where label = 'large')
        group by team.id
      ) counts
      where member_count > 8
    ),
    true
  ),
  'groups above 8 receive exactly two Testers'
);

-- Manual override
insert into pg_temp.roles_ctx (label, participant_id, team_id, role_type)
select
  'override',
  participant.id,
  participant.team_id,
  participant.role_type
from learning.grouping_participants as participant
where participant.session_id = (select session_id from pg_temp.roles_ctx where label = 'sd')
  and participant.role_type = 'specialist'
limit 1;

select lives_ok(
  $sql$
    select admin_api.set_grouping_participant_role(
      (select participant_id from pg_temp.roles_ctx where label = 'override'),
      'project_manager'
    )
  $sql$,
  'staff can override an individual role'
);

select is(
  (
    select role_type
    from learning.grouping_participants
    where id = (select participant_id from pg_temp.roles_ctx where label = 'override')
  ),
  'project_manager',
  'manual staff override persists'
);

select is(
  (
    select team_id
    from learning.grouping_participants
    where id = (select participant_id from pg_temp.roles_ctx where label = 'override')
  ),
  (select team_id from pg_temp.roles_ctx where label = 'override'),
  'manual override does not alter team membership'
);

reset role;
set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

select throws_ok(
  format(
    $sql$select admin_api.set_grouping_participant_role(%L::uuid, 'tester')$sql$,
    (select participant_id from pg_temp.roles_ctx where label = 'override')
  ),
  '42501',
  null,
  'anonymous learner cannot override roles'
);

-- Publication rules for learner role visibility
set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

insert into pg_temp.roles_ctx (label, session_id, join_code)
select
  'publish',
  (payload ->> 'id')::uuid,
  payload ->> 'joinCode'
from (
  select admin_api.create_grouping_session(
    'Publish roles',
    5,
    'Network Engineer'
  ) as payload
) as created;

reset role;
set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

do $$
declare
  v_code text;
  v_i integer;
  v_payload jsonb;
begin
  select join_code into v_code from pg_temp.roles_ctx where label = 'publish';
  for v_i in 1..4 loop
    v_payload := api.join_grouping_session(
      v_code,
      'Pub ' || v_i::text,
      'pub-client-' || v_i::text
    );
    if v_i = 1 then
      insert into pg_temp.roles_ctx (label, participant_token)
      values ('publish-token', (v_payload ->> 'participantToken')::uuid);
    end if;
  end loop;
end;
$$;

set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

select lives_ok(
  $sql$
    select admin_api.generate_grouping_teams(
      (select session_id from pg_temp.roles_ctx where label = 'publish'),
      4
    )
  $sql$,
  'publish session generates with roles'
);

reset role;
set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (
    select payload ->> 'state'
    from (
      select api.my_grouping_status(
        (select participant_token from pg_temp.roles_ctx where label = 'publish-token')
      ) as payload
    ) as status
  ),
  'waiting',
  'learner result API hides roles before publication'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

select lives_ok(
  $sql$
    select admin_api.publish_grouping_session(
      (select session_id from pg_temp.roles_ctx where label = 'publish')
    )
  $sql$,
  'publish session publishes'
);

reset role;
set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (
    select payload ->> 'state'
    from (
      select api.my_grouping_status(
        (select participant_token from pg_temp.roles_ctx where label = 'publish-token')
      ) as payload
    ) as status
  ),
  'assigned',
  'learner result API exposes assigned state after publication'
);

select ok(
  (
    select
      (payload ->> 'roleTitle') is not null
      and jsonb_typeof(payload -> 'teammates') = 'array'
      and (payload -> 'teammates' -> 0 ->> 'roleTitle') is not null
    from (
      select api.my_grouping_status(
        (select participant_token from pg_temp.roles_ctx where label = 'publish-token')
      ) as payload
    ) as status
  ),
  'published learner status exposes own and teammate role titles'
);

-- Regeneration regenerates roles
set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

insert into pg_temp.roles_ctx (label, session_id, join_code)
select
  'regen',
  (payload ->> 'id')::uuid,
  payload ->> 'joinCode'
from (
  select admin_api.create_grouping_session('Regen roles', 5, 'Researcher') as payload
) as created;

reset role;
set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

do $$
declare
  v_code text;
  v_i integer;
begin
  select join_code into v_code from pg_temp.roles_ctx where label = 'regen';
  for v_i in 1..6 loop
    perform api.join_grouping_session(
      v_code,
      'Regen ' || v_i::text,
      'regen-client-' || v_i::text
    );
  end loop;
end;
$$;

set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

select lives_ok(
  $sql$
    select admin_api.generate_grouping_teams(
      (select session_id from pg_temp.roles_ctx where label = 'regen'),
      6
    )
  $sql$,
  'regen session initial generate'
);

select lives_ok(
  $sql$
    select admin_api.generate_grouping_teams(
      (select session_id from pg_temp.roles_ctx where label = 'regen'),
      6
    )
  $sql$,
  'regen session regenerates'
);

select is(
  (
    select count(*)::integer
    from learning.grouping_participants
    where session_id = (select session_id from pg_temp.roles_ctx where label = 'regen')
      and role_type is not null
  ),
  6,
  'regeneration regenerates roles'
);

select is(
  (
    select count(*)::integer
    from learning.grouping_participants
    where session_id = (select session_id from pg_temp.roles_ctx where label = 'regen')
      and role_type = 'project_manager'
  ),
  (
    select count(*)::integer
    from learning.grouping_teams
    where session_id = (select session_id from pg_temp.roles_ctx where label = 'regen')
  ),
  'regeneration still yields one Project Manager per team'
);

select finish();
rollback;
