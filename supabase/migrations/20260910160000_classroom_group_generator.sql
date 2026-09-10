-- Classroom Group Generator (temporary classroom teams).
-- Not tied to courses, hubs, qualifications, or learning.groups.
-- Anonymous students join via short codes; staff manage via admin_api.
-- Permission decision: staff mutations require platform_admin (MVP).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table learning.grouping_sessions (
  id uuid primary key default gen_random_uuid(),
  session_name text,
  join_code text not null,
  preferred_group_size integer not null default 5,
  status text not null default 'joining',
  created_by uuid not null
    references learning.teachers (id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  published_at timestamptz,
  closed_at timestamptz,
  constraint grouping_sessions_join_code_format check (
    join_code ~ '^[A-Z2-9]{6}$'
  ),
  constraint grouping_sessions_join_code_unique unique (join_code),
  constraint grouping_sessions_preferred_size_valid check (
    preferred_group_size between 2 and 12
  ),
  constraint grouping_sessions_status_valid check (
    status in ('joining', 'proposed', 'published', 'closed')
  ),
  constraint grouping_sessions_name_valid check (
    session_name is null
    or (
      char_length(btrim(session_name)) between 1 and 80
      and session_name !~ '[[:cntrl:]]'
    )
  ),
  constraint grouping_sessions_published_timestamp_valid check (
    (status = 'published' and published_at is not null)
    or (status <> 'published')
  ),
  constraint grouping_sessions_closed_timestamp_valid check (
    (status = 'closed' and closed_at is not null)
    or (status <> 'closed' and closed_at is null)
  )
);

comment on table learning.grouping_sessions is
  'Temporary classroom grouping sessions. Independent of hubs, courses and learning.groups.';

create index grouping_sessions_status_created_idx
  on learning.grouping_sessions (status, created_at desc);

create index grouping_sessions_created_by_idx
  on learning.grouping_sessions (created_by, created_at desc);

create table learning.grouping_teams (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null
    references learning.grouping_sessions (id) on delete cascade,
  team_key text not null,
  display_name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  constraint grouping_teams_session_key_unique unique (session_id, team_key),
  constraint grouping_teams_key_valid check (
    team_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    and char_length(team_key) between 1 and 64
  ),
  constraint grouping_teams_display_name_valid check (
    char_length(btrim(display_name)) between 1 and 80
    and display_name !~ '[[:cntrl:]]'
  ),
  constraint grouping_teams_sort_order_valid check (sort_order >= 0)
);

comment on table learning.grouping_teams is
  'Proposed or published classroom teams. team_key is stable; display_name is editable.';

create index grouping_teams_session_sort_idx
  on learning.grouping_teams (session_id, sort_order);

create table learning.grouping_participants (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null
    references learning.grouping_sessions (id) on delete cascade,
  display_name text not null,
  participant_token uuid not null default gen_random_uuid(),
  client_key text,
  team_id uuid
    references learning.grouping_teams (id) on delete set null,
  joined_at timestamptz not null default clock_timestamp(),
  joined_after_publication boolean not null default false,
  needs_assignment boolean not null default false,
  removed_at timestamptz,
  constraint grouping_participants_display_name_valid check (
    char_length(btrim(display_name)) between 2 and 80
    and display_name !~ '[[:cntrl:]]'
  ),
  constraint grouping_participants_token_unique unique (participant_token),
  constraint grouping_participants_client_key_valid check (
    client_key is null
    or (
      char_length(client_key) between 8 and 128
      and client_key !~ '[[:cntrl:]]'
    )
  )
);

comment on table learning.grouping_participants is
  'Anonymous classroom grouping participants. Duplicate display names are allowed; client_key limits obvious same-browser resubmits.';

create index grouping_participants_session_active_idx
  on learning.grouping_participants (session_id, joined_at)
  where removed_at is null;

create unique index grouping_participants_session_client_active_uidx
  on learning.grouping_participants (session_id, client_key)
  where removed_at is null and client_key is not null;

create index grouping_participants_team_idx
  on learning.grouping_participants (team_id)
  where removed_at is null and team_id is not null;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table learning.grouping_sessions enable row level security;
alter table learning.grouping_teams enable row level security;
alter table learning.grouping_participants enable row level security;

revoke all on table learning.grouping_sessions from public, anon, authenticated;
revoke all on table learning.grouping_teams from public, anon, authenticated;
revoke all on table learning.grouping_participants from public, anon, authenticated;

grant select on table learning.grouping_sessions to authenticated;
grant select on table learning.grouping_teams to authenticated;
grant select on table learning.grouping_participants to authenticated;

create policy grouping_sessions_platform_admin_read
on learning.grouping_sessions
for select
to authenticated
using ((select platform.current_staff_has_role('platform_admin')));

create policy grouping_teams_platform_admin_read
on learning.grouping_teams
for select
to authenticated
using ((select platform.current_staff_has_role('platform_admin')));

create policy grouping_participants_platform_admin_read
on learning.grouping_participants
for select
to authenticated
using ((select platform.current_staff_has_role('platform_admin')));

-- ---------------------------------------------------------------------------
-- Pure helpers
-- ---------------------------------------------------------------------------

create function learning.balanced_group_sizes(
  p_participant_count integer,
  p_preferred_size integer
)
returns integer[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_n integer := coalesce(p_participant_count, 0);
  v_preferred integer := coalesce(p_preferred_size, 5);
  v_g integer;
  v_base integer;
  v_rem integer;
  v_sizes integer[];
  v_min integer;
  v_max integer;
  v_max_dev integer;
  v_range integer;
  v_avg_dev numeric;
  v_best_sizes integer[];
  v_best_max_dev integer;
  v_best_range integer;
  v_best_avg_dev numeric;
  v_best_g integer;
  v_i integer;
  v_candidate_ok boolean;
begin
  if v_n <= 0 then
    return array[]::integer[];
  end if;

  if v_preferred < 2 then
    v_preferred := 2;
  end if;
  if v_preferred > 12 then
    v_preferred := 12;
  end if;

  if v_n = 1 then
    return array[1];
  end if;

  for v_g in 1..v_n loop
    v_base := v_n / v_g;
    v_rem := v_n % v_g;
    v_sizes := array[]::integer[];

    for v_i in 1..v_rem loop
      v_sizes := v_sizes || (v_base + 1);
    end loop;
    for v_i in 1..(v_g - v_rem) loop
      v_sizes := v_sizes || v_base;
    end loop;

    v_min := v_sizes[1];
    v_max := v_sizes[1];
    for v_i in 1..array_length(v_sizes, 1) loop
      if v_sizes[v_i] < v_min then
        v_min := v_sizes[v_i];
      end if;
      if v_sizes[v_i] > v_max then
        v_max := v_sizes[v_i];
      end if;
    end loop;

    -- Avoid singleton leftovers when a larger group is possible.
    if v_n >= 2 and v_min < 2 then
      continue;
    end if;

    v_max_dev := 0;
    for v_i in 1..array_length(v_sizes, 1) loop
      if abs(v_sizes[v_i] - v_preferred) > v_max_dev then
        v_max_dev := abs(v_sizes[v_i] - v_preferred);
      end if;
    end loop;

    v_range := v_max - v_min;
    v_avg_dev := abs((v_n::numeric / v_g) - v_preferred);

    v_candidate_ok := false;
    if v_best_sizes is null then
      v_candidate_ok := true;
    elsif v_max_dev < v_best_max_dev then
      v_candidate_ok := true;
    elsif v_max_dev = v_best_max_dev and v_range < v_best_range then
      v_candidate_ok := true;
    elsif v_max_dev = v_best_max_dev
      and v_range = v_best_range
      and v_avg_dev < v_best_avg_dev then
      v_candidate_ok := true;
    elsif v_max_dev = v_best_max_dev
      and v_range = v_best_range
      and v_avg_dev = v_best_avg_dev
      and v_g < v_best_g then
      v_candidate_ok := true;
    end if;

    if v_candidate_ok then
      v_best_sizes := v_sizes;
      v_best_max_dev := v_max_dev;
      v_best_range := v_range;
      v_best_avg_dev := v_avg_dev;
      v_best_g := v_g;
    end if;
  end loop;

  return coalesce(v_best_sizes, array[v_n]);
end;
$$;

comment on function learning.balanced_group_sizes(integer, integer) is
  'Chooses balanced classroom group sizes near a preferred size, avoiding tiny leftover groups.';

revoke all on function learning.balanced_group_sizes(integer, integer)
  from public, anon, authenticated;
grant execute on function learning.balanced_group_sizes(integer, integer)
  to postgres, service_role, authenticated;

create function learning.grouping_team_name_pool()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'Dream Team',
    'The Impeccables',
    'Mavericks',
    'Trailblazers',
    'Visionaries',
    'Titans',
    'Pioneers',
    'Legends',
    'Game Changers',
    'All-Stars',
    'Innovators',
    'Explorers',
    'Champions',
    'Navigators',
    'Achievers'
  ]::text[];
$$;

revoke all on function learning.grouping_team_name_pool()
  from public, anon, authenticated;
grant execute on function learning.grouping_team_name_pool()
  to postgres, service_role;

create function learning.generate_grouping_join_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
  v_i integer;
  v_attempts integer := 0;
begin
  loop
    v_attempts := v_attempts + 1;
    if v_attempts > 40 then
      raise exception using errcode = 'P0001', message = 'GROUPING_JOIN_CODE_EXHAUSTED';
    end if;

    v_code := '';
    for v_i in 1..6 loop
      v_code := v_code || substr(
        v_alphabet,
        1 + floor(random() * char_length(v_alphabet))::integer,
        1
      );
    end loop;

    exit when not exists (
      select 1
      from learning.grouping_sessions as session
      where session.join_code = v_code
    );
  end loop;

  return v_code;
end;
$$;

revoke all on function learning.generate_grouping_join_code()
  from public, anon, authenticated;
grant execute on function learning.generate_grouping_join_code()
  to postgres, service_role;

create function learning.require_grouping_platform_admin()
returns learning.teachers
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid;
  v_teacher learning.teachers%rowtype;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  select teacher.*
  into v_teacher
  from learning.teachers as teacher
  where teacher.auth_user_id = v_auth_user_id
    and teacher.active;

  if not found
     or not platform.current_staff_has_role('platform_admin') then
    raise exception using errcode = '28000', message = 'GROUPING_NOT_AUTHORISED';
  end if;

  return v_teacher;
end;
$$;

revoke all on function learning.require_grouping_platform_admin()
  from public, anon, authenticated;
grant execute on function learning.require_grouping_platform_admin()
  to postgres, service_role;

create function learning.grouping_session_payload(
  p_session_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session learning.grouping_sessions%rowtype;
  v_participants jsonb;
  v_teams jsonb;
begin
  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = p_session_id;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NOT_FOUND';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', participant.id,
        'displayName', participant.display_name,
        'joinedAt', participant.joined_at,
        'joinedAfterPublication', participant.joined_after_publication,
        'needsAssignment', participant.needs_assignment,
        'teamId', participant.team_id,
        'removedAt', participant.removed_at
      )
      order by participant.joined_at, participant.display_name
    ),
    '[]'::jsonb
  )
  into v_participants
  from learning.grouping_participants as participant
  where participant.session_id = p_session_id
    and participant.removed_at is null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', team.id,
        'teamKey', team.team_key,
        'displayName', team.display_name,
        'sortOrder', team.sort_order,
        'memberIds', coalesce((
          select jsonb_agg(member.id order by member.display_name, member.joined_at)
          from learning.grouping_participants as member
          where member.team_id = team.id
            and member.removed_at is null
        ), '[]'::jsonb),
        'members', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', member.id,
              'displayName', member.display_name,
              'needsAssignment', member.needs_assignment
            )
            order by member.display_name, member.joined_at
          )
          from learning.grouping_participants as member
          where member.team_id = team.id
            and member.removed_at is null
        ), '[]'::jsonb)
      )
      order by team.sort_order, team.display_name
    ),
    '[]'::jsonb
  )
  into v_teams
  from learning.grouping_teams as team
  where team.session_id = p_session_id;

  return jsonb_build_object(
    'id', v_session.id,
    'sessionName', v_session.session_name,
    'joinCode', v_session.join_code,
    'preferredGroupSize', v_session.preferred_group_size,
    'status', v_session.status,
    'createdAt', v_session.created_at,
    'publishedAt', v_session.published_at,
    'closedAt', v_session.closed_at,
    'participantCount', jsonb_array_length(v_participants),
    'participants', v_participants,
    'teams', v_teams,
    'visibleToStudents', v_session.status = 'published'
  );
end;
$$;

revoke all on function learning.grouping_session_payload(uuid)
  from public, anon, authenticated;
grant execute on function learning.grouping_session_payload(uuid)
  to postgres, service_role;

create function learning.apply_balanced_grouping(
  p_session_id uuid,
  p_preferred_size integer,
  p_preserve_published_assignments boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session learning.grouping_sessions%rowtype;
  v_preferred integer;
  v_participant_ids uuid[];
  v_count integer;
  v_sizes integer[];
  v_name_pool text[];
  v_shuffled_names text[];
  v_name_idx integer;
  v_participant_idx integer := 1;
  v_team_idx integer;
  v_size integer;
  v_team_id uuid;
  v_team_key text;
  v_display_name text;
  v_i integer;
  v_j integer;
  v_tmp uuid;
  v_tmp_name text;
begin
  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = p_session_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NOT_FOUND';
  end if;

  v_preferred := coalesce(p_preferred_size, v_session.preferred_group_size);
  if v_preferred < 2 or v_preferred > 12 then
    raise exception using errcode = '22023', message = 'GROUPING_PREFERRED_SIZE_INVALID';
  end if;

  update learning.grouping_sessions
  set preferred_group_size = v_preferred
  where id = p_session_id;

  if p_preserve_published_assignments then
    select coalesce(array_agg(participant.id order by random()), array[]::uuid[])
    into v_participant_ids
    from learning.grouping_participants as participant
    where participant.session_id = p_session_id
      and participant.removed_at is null
      and (
        participant.needs_assignment
        or participant.team_id is null
        or participant.joined_after_publication
      );
  else
    delete from learning.grouping_teams
    where session_id = p_session_id;

    update learning.grouping_participants
    set team_id = null,
        needs_assignment = false
    where session_id = p_session_id
      and removed_at is null;

    select coalesce(array_agg(participant.id), array[]::uuid[])
    into v_participant_ids
    from learning.grouping_participants as participant
    where participant.session_id = p_session_id
      and participant.removed_at is null;
  end if;

  v_count := coalesce(array_length(v_participant_ids, 1), 0);
  if v_count = 0 then
    if not p_preserve_published_assignments then
      update learning.grouping_sessions
      set status = 'joining',
          published_at = null
      where id = p_session_id;
    end if;
    return;
  end if;

  -- Fisher–Yates shuffle
  for v_i in reverse array_length(v_participant_ids, 1)..2 loop
    v_j := 1 + floor(random() * v_i)::integer;
    v_tmp := v_participant_ids[v_i];
    v_participant_ids[v_i] := v_participant_ids[v_j];
    v_participant_ids[v_j] := v_tmp;
  end loop;

  if p_preserve_published_assignments then
    -- Assign unassigned participants into existing teams, filling smallest first.
    for v_i in 1..v_count loop
      select team.id
      into v_team_id
      from learning.grouping_teams as team
      left join learning.grouping_participants as member
        on member.team_id = team.id
       and member.removed_at is null
      where team.session_id = p_session_id
      group by team.id, team.sort_order
      order by count(member.id), team.sort_order
      limit 1;

      if v_team_id is null then
        raise exception using errcode = '22023', message = 'GROUPING_NO_TEAMS';
      end if;

      update learning.grouping_participants
      set team_id = v_team_id,
          needs_assignment = false,
          joined_after_publication = true
      where id = v_participant_ids[v_i];
    end loop;
    return;
  end if;

  v_sizes := learning.balanced_group_sizes(v_count, v_preferred);
  v_name_pool := learning.grouping_team_name_pool();
  v_shuffled_names := v_name_pool;

  for v_i in reverse array_length(v_shuffled_names, 1)..2 loop
    v_j := 1 + floor(random() * v_i)::integer;
    v_tmp_name := v_shuffled_names[v_i];
    v_shuffled_names[v_i] := v_shuffled_names[v_j];
    v_shuffled_names[v_j] := v_tmp_name;
  end loop;

  v_name_idx := 1;
  for v_team_idx in 1..array_length(v_sizes, 1) loop
    v_size := v_sizes[v_team_idx];
    v_team_key := 'team-' || lpad(v_team_idx::text, 2, '0');
    if v_name_idx <= array_length(v_shuffled_names, 1) then
      v_display_name := v_shuffled_names[v_name_idx];
      v_name_idx := v_name_idx + 1;
    else
      v_display_name := 'Team ' || v_team_idx::text;
    end if;

    insert into learning.grouping_teams (
      session_id,
      team_key,
      display_name,
      sort_order
    ) values (
      p_session_id,
      v_team_key,
      v_display_name,
      v_team_idx - 1
    )
    returning id into v_team_id;

    for v_i in 1..v_size loop
      update learning.grouping_participants
      set team_id = v_team_id,
          needs_assignment = false
      where id = v_participant_ids[v_participant_idx];
      v_participant_idx := v_participant_idx + 1;
    end loop;
  end loop;
end;
$$;

revoke all on function learning.apply_balanced_grouping(uuid, integer, boolean)
  from public, anon, authenticated;
grant execute on function learning.apply_balanced_grouping(uuid, integer, boolean)
  to postgres, service_role;

-- ---------------------------------------------------------------------------
-- Student API (anonymous)
-- ---------------------------------------------------------------------------

create function api.join_grouping_session(
  p_join_code text,
  p_display_name text,
  p_client_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_name text;
  v_client_key text;
  v_session learning.grouping_sessions%rowtype;
  v_existing learning.grouping_participants%rowtype;
  v_participant learning.grouping_participants%rowtype;
  v_late boolean;
begin
  v_code := upper(nullif(btrim(coalesce(p_join_code, '')), ''));
  v_name := btrim(coalesce(p_display_name, ''));
  v_client_key := nullif(btrim(coalesce(p_client_key, '')), '');

  if v_code is null or v_code !~ '^[A-Z2-9]{6}$' then
    raise exception using errcode = '22023', message = 'GROUPING_JOIN_CODE_INVALID';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 or v_name ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'GROUPING_DISPLAY_NAME_INVALID';
  end if;
  if v_client_key is not null
     and (
       char_length(v_client_key) < 8
       or char_length(v_client_key) > 128
       or v_client_key ~ '[[:cntrl:]]'
     ) then
    raise exception using errcode = '22023', message = 'GROUPING_CLIENT_KEY_INVALID';
  end if;

  select *
  into v_session
  from learning.grouping_sessions as session
  where session.join_code = v_code
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NOT_FOUND';
  end if;

  if v_session.status = 'closed' then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_CLOSED';
  end if;

  if v_client_key is not null then
    select *
    into v_existing
    from learning.grouping_participants as participant
    where participant.session_id = v_session.id
      and participant.client_key = v_client_key
      and participant.removed_at is null;

    if found then
      return jsonb_build_object(
        'sessionId', v_session.id,
        'joinCode', v_session.join_code,
        'status', v_session.status,
        'participantId', v_existing.id,
        'participantToken', v_existing.participant_token,
        'displayName', v_existing.display_name,
        'resumed', true
      );
    end if;
  end if;

  v_late := v_session.status = 'published';

  insert into learning.grouping_participants (
    session_id,
    display_name,
    client_key,
    joined_after_publication,
    needs_assignment
  ) values (
    v_session.id,
    v_name,
    v_client_key,
    v_late,
    v_late
  )
  returning * into v_participant;

  return jsonb_build_object(
    'sessionId', v_session.id,
    'joinCode', v_session.join_code,
    'status', v_session.status,
    'participantId', v_participant.id,
    'participantToken', v_participant.participant_token,
    'displayName', v_participant.display_name,
    'resumed', false,
    'joinedAfterPublication', v_participant.joined_after_publication
  );
end;
$$;

comment on function api.join_grouping_session(text, text, text) is
  'Anonymous join for a classroom grouping session. Returns a participant token for later status checks.';

create function api.my_grouping_status(
  p_participant_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_participant learning.grouping_participants%rowtype;
  v_session learning.grouping_sessions%rowtype;
  v_team learning.grouping_teams%rowtype;
  v_teammates jsonb;
begin
  if p_participant_token is null then
    raise exception using errcode = '22023', message = 'GROUPING_TOKEN_INVALID';
  end if;

  select *
  into v_participant
  from learning.grouping_participants as participant
  where participant.participant_token = p_participant_token;

  if not found or v_participant.removed_at is not null then
    raise exception using errcode = '22023', message = 'GROUPING_PARTICIPANT_NOT_FOUND';
  end if;

  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = v_participant.session_id;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NOT_FOUND';
  end if;

  if v_session.status <> 'published' then
    return jsonb_build_object(
      'state', 'waiting',
      'sessionStatus', v_session.status,
      'displayName', v_participant.display_name,
      'joinCode', v_session.join_code,
      'sessionName', v_session.session_name
    );
  end if;

  if v_participant.team_id is null or v_participant.needs_assignment then
    return jsonb_build_object(
      'state', 'awaiting_assignment',
      'sessionStatus', v_session.status,
      'displayName', v_participant.display_name,
      'joinCode', v_session.join_code,
      'sessionName', v_session.session_name
    );
  end if;

  select *
  into v_team
  from learning.grouping_teams as team
  where team.id = v_participant.team_id;

  select coalesce(
    jsonb_agg(
      teammate.display_name
      order by teammate.display_name, teammate.joined_at
    ),
    '[]'::jsonb
  )
  into v_teammates
  from learning.grouping_participants as teammate
  where teammate.team_id = v_team.id
    and teammate.removed_at is null;

  return jsonb_build_object(
    'state', 'assigned',
    'sessionStatus', v_session.status,
    'displayName', v_participant.display_name,
    'joinCode', v_session.join_code,
    'sessionName', v_session.session_name,
    'groupName', v_team.display_name,
    'teammates', v_teammates
  );
end;
$$;

comment on function api.my_grouping_status(uuid) is
  'Returns only the calling participant''s published group. Proposed groups are never exposed.';

revoke all on function api.join_grouping_session(text, text, text)
  from public, anon, authenticated;
revoke all on function api.my_grouping_status(uuid)
  from public, anon, authenticated;

grant execute on function api.join_grouping_session(text, text, text)
  to anon, authenticated;
grant execute on function api.my_grouping_status(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Admin / platform mutations
-- ---------------------------------------------------------------------------

create function platform.create_grouping_session(
  p_session_name text default null,
  p_preferred_group_size integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_teacher learning.teachers%rowtype;
  v_name text;
  v_preferred integer;
  v_session learning.grouping_sessions%rowtype;
begin
  v_teacher := learning.require_grouping_platform_admin();
  v_name := nullif(btrim(coalesce(p_session_name, '')), '');
  v_preferred := coalesce(p_preferred_group_size, 5);

  if v_name is not null
     and (
       char_length(v_name) > 80
       or v_name ~ '[[:cntrl:]]'
     ) then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NAME_INVALID';
  end if;
  if v_preferred < 2 or v_preferred > 12 then
    raise exception using errcode = '22023', message = 'GROUPING_PREFERRED_SIZE_INVALID';
  end if;

  insert into learning.grouping_sessions (
    session_name,
    join_code,
    preferred_group_size,
    status,
    created_by
  ) values (
    v_name,
    learning.generate_grouping_join_code(),
    v_preferred,
    'joining',
    v_teacher.id
  )
  returning * into v_session;

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'grouping.session.created',
    auth.uid(),
    'staff',
    'grouping-session',
    v_session.id::text,
    'succeeded',
    jsonb_build_object(
      'joinCode', v_session.join_code,
      'preferredGroupSize', v_session.preferred_group_size
    )
  );

  return learning.grouping_session_payload(v_session.id);
end;
$$;

create function platform.get_grouping_session(
  p_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform learning.require_grouping_platform_admin();
  return learning.grouping_session_payload(p_session_id);
end;
$$;

create function platform.remove_grouping_participant(
  p_participant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_participant learning.grouping_participants%rowtype;
  v_session learning.grouping_sessions%rowtype;
begin
  perform learning.require_grouping_platform_admin();

  select *
  into v_participant
  from learning.grouping_participants as participant
  where participant.id = p_participant_id
  for update;

  if not found or v_participant.removed_at is not null then
    raise exception using errcode = '22023', message = 'GROUPING_PARTICIPANT_NOT_FOUND';
  end if;

  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = v_participant.session_id
  for update;

  if v_session.status = 'closed' then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_CLOSED';
  end if;

  update learning.grouping_participants
  set removed_at = clock_timestamp(),
      team_id = null,
      needs_assignment = false
  where id = p_participant_id;

  return learning.grouping_session_payload(v_session.id);
end;
$$;

create function platform.generate_grouping_teams(
  p_session_id uuid,
  p_preferred_group_size integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session learning.grouping_sessions%rowtype;
  v_preferred integer;
  v_count integer;
begin
  perform learning.require_grouping_platform_admin();

  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = p_session_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NOT_FOUND';
  end if;

  if v_session.status not in ('joining', 'proposed') then
    raise exception using errcode = '22023', message = 'GROUPING_GENERATE_NOT_ALLOWED';
  end if;

  select count(*)::integer
  into v_count
  from learning.grouping_participants as participant
  where participant.session_id = p_session_id
    and participant.removed_at is null;

  if v_count < 1 then
    raise exception using errcode = '22023', message = 'GROUPING_NO_PARTICIPANTS';
  end if;

  v_preferred := coalesce(p_preferred_group_size, v_session.preferred_group_size);
  perform learning.apply_balanced_grouping(p_session_id, v_preferred, false);

  update learning.grouping_sessions
  set status = 'proposed',
      published_at = null
  where id = p_session_id;

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'grouping.session.generated',
    auth.uid(),
    'staff',
    'grouping-session',
    p_session_id::text,
    'succeeded',
    jsonb_build_object('preferredGroupSize', v_preferred, 'participantCount', v_count)
  );

  return learning.grouping_session_payload(p_session_id);
end;
$$;

create function platform.move_grouping_participant(
  p_participant_id uuid,
  p_team_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_participant learning.grouping_participants%rowtype;
  v_team learning.grouping_teams%rowtype;
  v_session learning.grouping_sessions%rowtype;
begin
  perform learning.require_grouping_platform_admin();

  select *
  into v_participant
  from learning.grouping_participants as participant
  where participant.id = p_participant_id
    and participant.removed_at is null
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_PARTICIPANT_NOT_FOUND';
  end if;

  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = v_participant.session_id
  for update;

  if v_session.status not in ('proposed', 'published') then
    raise exception using errcode = '22023', message = 'GROUPING_MOVE_NOT_ALLOWED';
  end if;

  select *
  into v_team
  from learning.grouping_teams as team
  where team.id = p_team_id
    and team.session_id = v_session.id;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_TEAM_NOT_FOUND';
  end if;

  update learning.grouping_participants
  set team_id = p_team_id,
      needs_assignment = false
  where id = p_participant_id;

  return learning.grouping_session_payload(v_session.id);
end;
$$;

create function platform.rename_grouping_team(
  p_team_id uuid,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team learning.grouping_teams%rowtype;
  v_name text;
  v_session learning.grouping_sessions%rowtype;
begin
  perform learning.require_grouping_platform_admin();
  v_name := btrim(coalesce(p_display_name, ''));

  if char_length(v_name) < 1 or char_length(v_name) > 80 or v_name ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'GROUPING_TEAM_NAME_INVALID';
  end if;

  select *
  into v_team
  from learning.grouping_teams as team
  where team.id = p_team_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_TEAM_NOT_FOUND';
  end if;

  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = v_team.session_id;

  if v_session.status = 'closed' then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_CLOSED';
  end if;

  update learning.grouping_teams
  set display_name = v_name
  where id = p_team_id;

  return learning.grouping_session_payload(v_team.session_id);
end;
$$;

create function platform.publish_grouping_session(
  p_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session learning.grouping_sessions%rowtype;
  v_unassigned integer;
begin
  perform learning.require_grouping_platform_admin();

  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = p_session_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NOT_FOUND';
  end if;

  if v_session.status <> 'proposed' then
    raise exception using errcode = '22023', message = 'GROUPING_PUBLISH_NOT_ALLOWED';
  end if;

  select count(*)::integer
  into v_unassigned
  from learning.grouping_participants as participant
  where participant.session_id = p_session_id
    and participant.removed_at is null
    and participant.team_id is null;

  if v_unassigned > 0 then
    raise exception using errcode = '22023', message = 'GROUPING_UNASSIGNED_PARTICIPANTS';
  end if;

  if not exists (
    select 1
    from learning.grouping_teams as team
    where team.session_id = p_session_id
  ) then
    raise exception using errcode = '22023', message = 'GROUPING_NO_TEAMS';
  end if;

  update learning.grouping_sessions
  set status = 'published',
      published_at = clock_timestamp()
  where id = p_session_id;

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'grouping.session.published',
    auth.uid(),
    'staff',
    'grouping-session',
    p_session_id::text,
    'succeeded',
    '{}'::jsonb
  );

  return learning.grouping_session_payload(p_session_id);
end;
$$;

create function platform.assign_late_grouping_participant(
  p_participant_id uuid,
  p_team_id uuid default null,
  p_to_smallest boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_participant learning.grouping_participants%rowtype;
  v_session learning.grouping_sessions%rowtype;
  v_team_id uuid;
begin
  perform learning.require_grouping_platform_admin();

  select *
  into v_participant
  from learning.grouping_participants as participant
  where participant.id = p_participant_id
    and participant.removed_at is null
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_PARTICIPANT_NOT_FOUND';
  end if;

  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = v_participant.session_id
  for update;

  if v_session.status <> 'published' then
    raise exception using errcode = '22023', message = 'GROUPING_LATE_ASSIGN_NOT_ALLOWED';
  end if;

  if coalesce(p_to_smallest, false) then
    select team.id
    into v_team_id
    from learning.grouping_teams as team
    left join learning.grouping_participants as member
      on member.team_id = team.id
     and member.removed_at is null
    where team.session_id = v_session.id
    group by team.id, team.sort_order
    order by count(member.id), team.sort_order
    limit 1;
  else
    v_team_id := p_team_id;
  end if;

  if v_team_id is null
     or not exists (
       select 1
       from learning.grouping_teams as team
       where team.id = v_team_id
         and team.session_id = v_session.id
     ) then
    raise exception using errcode = '22023', message = 'GROUPING_TEAM_NOT_FOUND';
  end if;

  update learning.grouping_participants
  set team_id = v_team_id,
      needs_assignment = false,
      joined_after_publication = true
  where id = p_participant_id;

  return learning.grouping_session_payload(v_session.id);
end;
$$;

create function platform.rebalance_grouping_session(
  p_session_id uuid,
  p_preferred_group_size integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session learning.grouping_sessions%rowtype;
  v_preferred integer;
begin
  perform learning.require_grouping_platform_admin();

  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = p_session_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NOT_FOUND';
  end if;

  if v_session.status <> 'published' then
    raise exception using errcode = '22023', message = 'GROUPING_REBALANCE_NOT_ALLOWED';
  end if;

  v_preferred := coalesce(p_preferred_group_size, v_session.preferred_group_size);
  perform learning.apply_balanced_grouping(p_session_id, v_preferred, false);

  update learning.grouping_sessions
  set status = 'published',
      published_at = coalesce(published_at, clock_timestamp())
  where id = p_session_id;

  update learning.grouping_participants
  set needs_assignment = false
  where session_id = p_session_id
    and removed_at is null
    and team_id is not null;

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'grouping.session.rebalanced',
    auth.uid(),
    'staff',
    'grouping-session',
    p_session_id::text,
    'succeeded',
    jsonb_build_object('preferredGroupSize', v_preferred)
  );

  return learning.grouping_session_payload(p_session_id);
end;
$$;

create function platform.close_grouping_session(
  p_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session learning.grouping_sessions%rowtype;
begin
  perform learning.require_grouping_platform_admin();

  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = p_session_id
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NOT_FOUND';
  end if;

  if v_session.status = 'closed' then
    return learning.grouping_session_payload(p_session_id);
  end if;

  update learning.grouping_sessions
  set status = 'closed',
      closed_at = clock_timestamp()
  where id = p_session_id;

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'grouping.session.closed',
    auth.uid(),
    'staff',
    'grouping-session',
    p_session_id::text,
    'succeeded',
    '{}'::jsonb
  );

  return learning.grouping_session_payload(p_session_id);
end;
$$;

-- Thin admin_api wrappers
create function admin_api.create_grouping_session(
  p_session_name text default null,
  p_preferred_group_size integer default 5
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.create_grouping_session(p_session_name, p_preferred_group_size);
$$;

create function admin_api.get_grouping_session(
  p_session_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.get_grouping_session(p_session_id);
$$;

create function admin_api.remove_grouping_participant(
  p_participant_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.remove_grouping_participant(p_participant_id);
$$;

create function admin_api.generate_grouping_teams(
  p_session_id uuid,
  p_preferred_group_size integer default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.generate_grouping_teams(p_session_id, p_preferred_group_size);
$$;

create function admin_api.move_grouping_participant(
  p_participant_id uuid,
  p_team_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.move_grouping_participant(p_participant_id, p_team_id);
$$;

create function admin_api.rename_grouping_team(
  p_team_id uuid,
  p_display_name text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.rename_grouping_team(p_team_id, p_display_name);
$$;

create function admin_api.publish_grouping_session(
  p_session_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.publish_grouping_session(p_session_id);
$$;

create function admin_api.assign_late_grouping_participant(
  p_participant_id uuid,
  p_team_id uuid default null,
  p_to_smallest boolean default false
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.assign_late_grouping_participant(
    p_participant_id,
    p_team_id,
    p_to_smallest
  );
$$;

create function admin_api.rebalance_grouping_session(
  p_session_id uuid,
  p_preferred_group_size integer default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.rebalance_grouping_session(p_session_id, p_preferred_group_size);
$$;

create function admin_api.close_grouping_session(
  p_session_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.close_grouping_session(p_session_id);
$$;

create view admin_api.grouping_sessions
with (security_invoker = true)
as
select
  session.id,
  session.session_name,
  session.join_code,
  session.preferred_group_size,
  session.status,
  session.created_at,
  session.published_at,
  session.closed_at,
  (
    select count(*)::integer
    from learning.grouping_participants as participant
    where participant.session_id = session.id
      and participant.removed_at is null
  ) as participant_count
from learning.grouping_sessions as session
where (select platform.current_staff_has_role('platform_admin'));

comment on view admin_api.grouping_sessions is
  'Staff list of classroom grouping sessions. platform_admin only.';

revoke all on admin_api.grouping_sessions from public, anon, authenticated;
grant select on admin_api.grouping_sessions to authenticated;

-- Grants for platform + admin_api functions
do $$
declare
  v_fn text;
begin
  foreach v_fn in array array[
    'platform.create_grouping_session(text,integer)',
    'platform.get_grouping_session(uuid)',
    'platform.remove_grouping_participant(uuid)',
    'platform.generate_grouping_teams(uuid,integer)',
    'platform.move_grouping_participant(uuid,uuid)',
    'platform.rename_grouping_team(uuid,text)',
    'platform.publish_grouping_session(uuid)',
    'platform.assign_late_grouping_participant(uuid,uuid,boolean)',
    'platform.rebalance_grouping_session(uuid,integer)',
    'platform.close_grouping_session(uuid)',
    'admin_api.create_grouping_session(text,integer)',
    'admin_api.get_grouping_session(uuid)',
    'admin_api.remove_grouping_participant(uuid)',
    'admin_api.generate_grouping_teams(uuid,integer)',
    'admin_api.move_grouping_participant(uuid,uuid)',
    'admin_api.rename_grouping_team(uuid,text)',
    'admin_api.publish_grouping_session(uuid)',
    'admin_api.assign_late_grouping_participant(uuid,uuid,boolean)',
    'admin_api.rebalance_grouping_session(uuid,integer)',
    'admin_api.close_grouping_session(uuid)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
    execute format('grant execute on function %s to authenticated, service_role', v_fn);
  end loop;
end;
$$;
