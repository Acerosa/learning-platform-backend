begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, pg_catalog;

select no_plan();

create temporary table pg_temp.grouping_ctx (
  label text primary key,
  session_id uuid,
  join_code text,
  participant_token uuid,
  participant_id uuid,
  team_id uuid
);

grant all on table pg_temp.grouping_ctx to authenticated, anon;

select has_table('learning', 'grouping_sessions', 'grouping sessions table exists');
select has_table('learning', 'grouping_teams', 'grouping teams table exists');
select has_table('learning', 'grouping_participants', 'grouping participants table exists');
select has_function(
  'api',
  'join_grouping_session',
  array['text', 'text', 'text'],
  'anonymous join RPC exists'
);
select has_function(
  'api',
  'my_grouping_status',
  array['uuid'],
  'anonymous status RPC exists'
);
select has_function(
  'admin_api',
  'create_grouping_session',
  array['text', 'integer'],
  'admin create session RPC exists'
);
select has_function(
  'admin_api',
  'generate_grouping_teams',
  array['uuid', 'integer'],
  'admin generate RPC exists'
);
select has_function(
  'admin_api',
  'publish_grouping_session',
  array['uuid'],
  'admin publish RPC exists'
);

select ok(
  has_function_privilege(
    'anon',
    'api.join_grouping_session(text,text,text)',
    'EXECUTE'
  ),
  'anonymous clients can join grouping sessions'
);
select ok(
  has_function_privilege(
    'anon',
    'api.my_grouping_status(uuid)',
    'EXECUTE'
  ),
  'anonymous clients can read their grouping status'
);
select ok(
  not has_function_privilege(
    'anon',
    'admin_api.create_grouping_session(text,integer)',
    'EXECUTE'
  ),
  'anonymous clients cannot create grouping sessions'
);
select ok(
  not has_function_privilege(
    'anon',
    'admin_api.generate_grouping_teams(uuid,integer)',
    'EXECUTE'
  ),
  'anonymous clients cannot generate groups'
);
select ok(
  not has_function_privilege(
    'anon',
    'admin_api.publish_grouping_session(uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot publish groups'
);
select ok(
  not has_table_privilege('anon', 'learning.grouping_sessions', 'SELECT'),
  'anonymous clients cannot select grouping sessions directly'
);
select ok(
  not has_table_privilege('anon', 'learning.grouping_participants', 'INSERT'),
  'anonymous clients cannot insert participants directly'
);

-- Ordinary teacher denied
set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}';

select throws_ok(
  $$select admin_api.create_grouping_session('Denied', 5)$$,
  '28000',
  'GROUPING_NOT_AUTHORISED',
  'ordinary teachers cannot create grouping sessions'
);

reset role;

-- Platform admin creates a session
set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

insert into pg_temp.grouping_ctx (label, session_id, join_code)
select
  'main',
  (payload ->> 'id')::uuid,
  payload ->> 'joinCode'
from (
  select admin_api.create_grouping_session('Client Brief Activity', 5) as payload
) as created;

select ok(
  (
    select join_code ~ '^[A-Z2-9]{6}$'
    from pg_temp.grouping_ctx
    where label = 'main'
  ),
  'created sessions receive a classroom-friendly join code'
);

select is(
  (
    select payload ->> 'status'
    from (
      select admin_api.get_grouping_session(session_id) as payload
      from pg_temp.grouping_ctx
      where label = 'main'
    ) as got
  ),
  'joining',
  'new sessions start in joining status'
);

reset role;

-- Anonymous students join
set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

select lives_ok(
  format(
    $sql$
      insert into pg_temp.grouping_ctx (label, participant_token, participant_id)
      select
        'p1',
        (payload ->> 'participantToken')::uuid,
        (payload ->> 'participantId')::uuid
      from (
        select api.join_grouping_session(
          (select join_code from pg_temp.grouping_ctx where label = 'main'),
          'Ricky Rosa',
          'client-key-ricky-01'
        ) as payload
      ) as joined
    $sql$
  ),
  'anonymous student can join an active session'
);

select lives_ok(
  format(
    $sql$
      select api.join_grouping_session(
        (select join_code from pg_temp.grouping_ctx where label = 'main'),
        'Sarah Chen',
        'client-key-sarah-01'
      )
    $sql$
  ),
  'second anonymous student can join'
);

select lives_ok(
  format(
    $sql$
      select api.join_grouping_session(
        (select join_code from pg_temp.grouping_ctx where label = 'main'),
        'James Patel',
        'client-key-james-01'
      )
    $sql$
  ),
  'third anonymous student can join'
);

-- Same browser client key resumes instead of duplicating
select is(
  (
    select payload ->> 'resumed'
    from (
      select api.join_grouping_session(
        (select join_code from pg_temp.grouping_ctx where label = 'main'),
        'Ricky Rosa Again',
        'client-key-ricky-01'
      ) as payload
    ) as resumed
  ),
  'true',
  'same client key resumes the existing participant'
);

-- Duplicate names from different clients are allowed
select lives_ok(
  format(
    $sql$
      select api.join_grouping_session(
        (select join_code from pg_temp.grouping_ctx where label = 'main'),
        'Ricky Rosa',
        'client-key-other-ricky'
      )
    $sql$
  ),
  'duplicate display names from different clients are allowed'
);

reset role;

select is(
  (
    select count(*)::integer
    from learning.grouping_participants as participant
    join pg_temp.grouping_ctx as ctx
      on ctx.session_id = participant.session_id
    where ctx.label = 'main'
      and participant.removed_at is null
  ),
  4,
  'active participants include resumed and duplicate-name joins correctly'
);

set local role anon;
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claims" = '{"role":"anon"}';

-- Waiting status before publication; no group data
select is(
  (
    select payload ->> 'state'
    from (
      select api.my_grouping_status(
        (select participant_token from pg_temp.grouping_ctx where label = 'p1')
      ) as payload
    ) as status
  ),
  'waiting',
  'students see waiting before publication'
);

select ok(
  (
    select payload ? 'groupName' = false
      and payload ? 'teams' = false
      and payload ? 'participants' = false
    from (
      select api.my_grouping_status(
        (select participant_token from pg_temp.grouping_ctx where label = 'p1')
      ) as payload
    ) as status
  ),
  'student status does not expose proposed groups or class lists'
);

reset role;

-- Seed additional participants as the migration owner (not via browser roles)
do $$
declare
  v_session_id uuid;
  v_i integer;
begin
  select session_id into v_session_id from pg_temp.grouping_ctx where label = 'main';
  for v_i in 5..10 loop
    insert into learning.grouping_participants (session_id, display_name, client_key)
    values (
      v_session_id,
      'Student ' || v_i::text,
      'seed-client-' || v_i::text
    );
  end loop;
end;
$$;

-- Admin generate + verify proposal invisible to students
set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

select is(
  (
    select payload ->> 'status'
    from (
      select admin_api.generate_grouping_teams(
        (select session_id from pg_temp.grouping_ctx where label = 'main'),
        5
      ) as payload
    ) as generated
  ),
  'proposed',
  'generate moves the session to proposed'
);

select ok(
  (
    select jsonb_array_length(payload -> 'teams') >= 2
    from (
      select admin_api.get_grouping_session(
        (select session_id from pg_temp.grouping_ctx where label = 'main')
      ) as payload
    ) as got
  ),
  'generate creates proposed teams for staff'
);

select ok(
  (
    select bool_and(participant.team_id is not null)
    from learning.grouping_participants as participant
    join pg_temp.grouping_ctx as ctx
      on ctx.session_id = participant.session_id
    where ctx.label = 'main'
      and participant.removed_at is null
  ),
  'generate assigns every active participant exactly once'
);

select ok(
  (
    select count(*) = count(distinct participant.id)
    from learning.grouping_participants as participant
    join pg_temp.grouping_ctx as ctx
      on ctx.session_id = participant.session_id
    where ctx.label = 'main'
      and participant.removed_at is null
      and participant.team_id is not null
  ),
  'no participant is duplicated across teams'
);

reset role;
set local role anon;

select is(
  (
    select payload ->> 'state'
    from (
      select api.my_grouping_status(
        (select participant_token from pg_temp.grouping_ctx where label = 'p1')
      ) as payload
    ) as status
  ),
  'waiting',
  'proposed groups remain invisible to students'
);

select ok(
  (
    select payload ? 'groupName' = false
    from (
      select api.my_grouping_status(
        (select participant_token from pg_temp.grouping_ctx where label = 'p1')
      ) as payload
    ) as status
  ),
  'regeneration/proposal does not leak group names to students'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

-- Rename + move while proposed
update pg_temp.grouping_ctx
set team_id = (
  select (team ->> 'id')::uuid
  from (
    select jsonb_array_elements(payload -> 'teams') as team
    from (
      select admin_api.get_grouping_session(
        (select session_id from pg_temp.grouping_ctx where label = 'main')
      ) as payload
    ) as got
  ) as teams
  order by (team ->> 'sortOrder')::integer
  limit 1
)
where label = 'main';

select lives_ok(
  format(
    $sql$
      select admin_api.rename_grouping_team(
        (select team_id from pg_temp.grouping_ctx where label = 'main'),
        'The Mavericks'
      )
    $sql$
  ),
  'staff can rename a proposed team'
);

select is(
  (
    select payload ->> 'status'
    from (
      select admin_api.publish_grouping_session(
        (select session_id from pg_temp.grouping_ctx where label = 'main')
      ) as payload
    ) as published
  ),
  'published',
  'publish makes groups visible to students'
);

reset role;
set local role anon;

select is(
  (
    select payload ->> 'state'
    from (
      select api.my_grouping_status(
        (select participant_token from pg_temp.grouping_ctx where label = 'p1')
      ) as payload
    ) as status
  ),
  'assigned',
  'students retrieve their own published group'
);

select ok(
  (
    select
      payload ? 'groupName'
      and payload ? 'teammates'
      and payload ? 'displayName'
      and payload ? 'teams' = false
    from (
      select api.my_grouping_status(
        (select participant_token from pg_temp.grouping_ctx where label = 'p1')
      ) as payload
    ) as status
  ),
  'published status returns only the student group, not all teams'
);

-- Late arrival after publish
select lives_ok(
  format(
    $sql$
      insert into pg_temp.grouping_ctx (label, participant_token, participant_id)
      select
        'late',
        (payload ->> 'participantToken')::uuid,
        (payload ->> 'participantId')::uuid
      from (
        select api.join_grouping_session(
          (select join_code from pg_temp.grouping_ctx where label = 'main'),
          'Late Arrival',
          'client-key-late-01'
        ) as payload
      ) as joined
    $sql$
  ),
  'late arrivals can still join a published session'
);

select is(
  (
    select payload ->> 'state'
    from (
      select api.my_grouping_status(
        (select participant_token from pg_temp.grouping_ctx where label = 'late')
      ) as payload
    ) as status
  ),
  'awaiting_assignment',
  'late arrivals are marked as needing assignment'
);

reset role;

select ok(
  (
    select participant.needs_assignment
      and participant.team_id is null
      and participant.joined_after_publication
    from learning.grouping_participants as participant
    where participant.id = (
      select participant_id from pg_temp.grouping_ctx where label = 'late'
    )
  ),
  'late join marks the new participant as needing assignment'
);

select ok(
  (
    select bool_and(participant.team_id is not null and not participant.needs_assignment)
    from learning.grouping_participants as participant
    join pg_temp.grouping_ctx as ctx
      on ctx.session_id = participant.session_id
    where ctx.label = 'main'
      and participant.removed_at is null
      and participant.id <> (
        select participant_id from pg_temp.grouping_ctx where label = 'late'
      )
  ),
  'late join does not automatically move existing published assignments'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '20000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}';

select lives_ok(
  format(
    $sql$
      select admin_api.assign_late_grouping_participant(
        (select participant_id from pg_temp.grouping_ctx where label = 'late'),
        null,
        true
      )
    $sql$
  ),
  'staff can assign a late arrival to the smallest group'
);

select lives_ok(
  format(
    $sql$
      select admin_api.close_grouping_session(
        (select session_id from pg_temp.grouping_ctx where label = 'main')
      )
    $sql$
  ),
  'staff can close a session'
);

reset role;
set local role anon;

select throws_ok(
  format(
    $sql$
      select api.join_grouping_session(
        (select join_code from pg_temp.grouping_ctx where label = 'main'),
        'Too Late',
        'client-key-closed-01'
      )
    $sql$
  ),
  '22023',
  'GROUPING_SESSION_CLOSED',
  'closed sessions reject new joins'
);

select * from finish();
rollback;
