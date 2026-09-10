-- Classroom Group Generator: automatic context-aware role assignment.
-- Additive extension. Legacy sessions with null specialist_role_title keep
-- existing no-role behaviour.

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

alter table learning.grouping_sessions
  add column if not exists specialist_role_title text;

alter table learning.grouping_sessions
  drop constraint if exists grouping_sessions_specialist_role_title_valid;

alter table learning.grouping_sessions
  add constraint grouping_sessions_specialist_role_title_valid check (
    specialist_role_title is null
    or (
      char_length(btrim(specialist_role_title)) between 1 and 80
      and specialist_role_title !~ '[[:cntrl:]]'
    )
  );

comment on column learning.grouping_sessions.specialist_role_title is
  'Display title for the session specialist role (e.g. Developer, Cyber Security Analyst). Null means roles are not used for this session.';

alter table learning.grouping_participants
  add column if not exists role_type text;

alter table learning.grouping_participants
  drop constraint if exists grouping_participants_role_type_valid;

alter table learning.grouping_participants
  add constraint grouping_participants_role_type_valid check (
    role_type is null
    or role_type in ('project_manager', 'tester', 'specialist')
  );

comment on column learning.grouping_participants.role_type is
  'Assigned structural role: project_manager, tester, or specialist. Null for legacy/no-role sessions.';

-- ---------------------------------------------------------------------------
-- Pure planners / display helpers
-- ---------------------------------------------------------------------------

create or replace function learning.planned_grouping_role_types(
  p_group_size integer
)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_roles text[] := array[]::text[];
  v_testers integer;
  v_specialists integer;
  v_i integer;
begin
  if p_group_size is null or p_group_size < 1 then
    return v_roles;
  end if;

  if p_group_size = 1 then
    return array['project_manager'];
  end if;

  if p_group_size = 2 then
    return array['project_manager', 'tester'];
  end if;

  v_testers := case when p_group_size > 8 then 2 else 1 end;
  v_specialists := p_group_size - 1 - v_testers;
  v_roles := array['project_manager'];

  for v_i in 1..v_testers loop
    v_roles := v_roles || array['tester'];
  end loop;

  for v_i in 1..v_specialists loop
    v_roles := v_roles || array['specialist'];
  end loop;

  return v_roles;
end;
$$;

comment on function learning.planned_grouping_role_types(integer) is
  'Returns the ordered multiset of role_type values for a group of the given size.';

revoke all on function learning.planned_grouping_role_types(integer)
  from public, anon, authenticated;
grant execute on function learning.planned_grouping_role_types(integer)
  to postgres, service_role, authenticated;

create or replace function learning.grouping_role_display_title(
  p_role_type text,
  p_specialist_role_title text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_role_type
    when 'project_manager' then 'Project Manager'
    when 'tester' then 'Tester'
    when 'specialist' then nullif(btrim(coalesce(p_specialist_role_title, '')), '')
    else null
  end;
$$;

revoke all on function learning.grouping_role_display_title(text, text)
  from public, anon, authenticated;
grant execute on function learning.grouping_role_display_title(text, text)
  to postgres, service_role, authenticated;

create or replace function learning.normalise_grouping_specialist_role_title(
  p_title text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_title text;
begin
  v_title := nullif(btrim(coalesce(p_title, '')), '');
  if v_title is null then
    return null;
  end if;
  if char_length(v_title) > 80 or v_title ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'GROUPING_SPECIALIST_ROLE_INVALID';
  end if;
  return v_title;
end;
$$;

revoke all on function learning.normalise_grouping_specialist_role_title(text)
  from public, anon, authenticated;
grant execute on function learning.normalise_grouping_specialist_role_title(text)
  to postgres, service_role;

-- ---------------------------------------------------------------------------
-- Role assignment
-- ---------------------------------------------------------------------------

create or replace function learning.assign_roles_for_grouping_team(
  p_team_id uuid,
  p_specialist_role_title text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member_ids uuid[];
  v_roles text[];
  v_count integer;
  v_i integer;
  v_j integer;
  v_tmp uuid;
begin
  if nullif(btrim(coalesce(p_specialist_role_title, '')), '') is null then
    update learning.grouping_participants
    set role_type = null
    where team_id = p_team_id
      and removed_at is null;
    return;
  end if;

  select coalesce(array_agg(participant.id), array[]::uuid[])
  into v_member_ids
  from learning.grouping_participants as participant
  where participant.team_id = p_team_id
    and participant.removed_at is null;

  v_count := coalesce(array_length(v_member_ids, 1), 0);
  if v_count = 0 then
    return;
  end if;

  -- Shuffle so Project Manager / Tester are not always the same join order.
  for v_i in reverse array_length(v_member_ids, 1)..2 loop
    v_j := 1 + floor(random() * v_i)::integer;
    v_tmp := v_member_ids[v_i];
    v_member_ids[v_i] := v_member_ids[v_j];
    v_member_ids[v_j] := v_tmp;
  end loop;

  v_roles := learning.planned_grouping_role_types(v_count);

  for v_i in 1..v_count loop
    update learning.grouping_participants
    set role_type = v_roles[v_i]
    where id = v_member_ids[v_i];
  end loop;
end;
$$;

revoke all on function learning.assign_roles_for_grouping_team(uuid, text)
  from public, anon, authenticated;
grant execute on function learning.assign_roles_for_grouping_team(uuid, text)
  to postgres, service_role;

create or replace function learning.assign_roles_for_grouping_session(
  p_session_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_team record;
begin
  select learning.normalise_grouping_specialist_role_title(session.specialist_role_title)
  into v_title
  from learning.grouping_sessions as session
  where session.id = p_session_id;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NOT_FOUND';
  end if;

  if v_title is null then
    update learning.grouping_participants
    set role_type = null
    where session_id = p_session_id
      and removed_at is null;
    return;
  end if;

  for v_team in
    select team.id
    from learning.grouping_teams as team
    where team.session_id = p_session_id
    order by team.sort_order, team.display_name
  loop
    perform learning.assign_roles_for_grouping_team(v_team.id, v_title);
  end loop;

  -- Unassigned participants keep no role until placed on a team.
  update learning.grouping_participants
  set role_type = null
  where session_id = p_session_id
    and removed_at is null
    and team_id is null;
end;
$$;

revoke all on function learning.assign_roles_for_grouping_session(uuid)
  from public, anon, authenticated;
grant execute on function learning.assign_roles_for_grouping_session(uuid)
  to postgres, service_role;

-- ---------------------------------------------------------------------------
-- Patch apply_balanced_grouping to clear/regenerate roles
-- ---------------------------------------------------------------------------

create or replace function learning.apply_balanced_grouping(
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
  v_specialist text;
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

  v_specialist := learning.normalise_grouping_specialist_role_title(
    v_session.specialist_role_title
  );

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
        needs_assignment = false,
        role_type = null
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

  for v_i in reverse array_length(v_participant_ids, 1)..2 loop
    v_j := 1 + floor(random() * v_i)::integer;
    v_tmp := v_participant_ids[v_i];
    v_participant_ids[v_i] := v_participant_ids[v_j];
    v_participant_ids[v_j] := v_tmp;
  end loop;

  if p_preserve_published_assignments then
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
          joined_after_publication = true,
          role_type = case
            when v_specialist is null then null
            else 'specialist'
          end
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

  perform learning.assign_roles_for_grouping_session(p_session_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Payload + student status
-- ---------------------------------------------------------------------------

create or replace function learning.grouping_session_payload(
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
  v_specialist text;
begin
  select *
  into v_session
  from learning.grouping_sessions as session
  where session.id = p_session_id;

  if not found then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_NOT_FOUND';
  end if;

  v_specialist := learning.normalise_grouping_specialist_role_title(
    v_session.specialist_role_title
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', participant.id,
        'displayName', participant.display_name,
        'joinedAt', participant.joined_at,
        'joinedAfterPublication', participant.joined_after_publication,
        'needsAssignment', participant.needs_assignment,
        'teamId', participant.team_id,
        'removedAt', participant.removed_at,
        'roleType', participant.role_type,
        'roleTitle', learning.grouping_role_display_title(
          participant.role_type,
          v_specialist
        )
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
              'needsAssignment', member.needs_assignment,
              'roleType', member.role_type,
              'roleTitle', learning.grouping_role_display_title(
                member.role_type,
                v_specialist
              )
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
    'specialistRoleTitle', v_specialist,
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

create or replace function api.my_grouping_status(
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
  v_specialist text;
  v_role_title text;
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

  v_specialist := learning.normalise_grouping_specialist_role_title(
    v_session.specialist_role_title
  );

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

  v_role_title := learning.grouping_role_display_title(
    v_participant.role_type,
    v_specialist
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'displayName', teammate.display_name,
        'roleType', teammate.role_type,
        'roleTitle', learning.grouping_role_display_title(
          teammate.role_type,
          v_specialist
        )
      )
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
    'roleType', v_participant.role_type,
    'roleTitle', v_role_title,
    'specialistRoleTitle', v_specialist,
    'teammates', v_teammates
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Create / configure specialist role / override role
-- ---------------------------------------------------------------------------

drop function if exists platform.create_grouping_session(text, integer);
drop function if exists admin_api.create_grouping_session(text, integer);

create function platform.create_grouping_session(
  p_session_name text default null,
  p_preferred_group_size integer default 5,
  p_specialist_role_title text default null
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
  v_specialist text;
  v_session learning.grouping_sessions%rowtype;
begin
  v_teacher := learning.require_grouping_platform_admin();
  v_name := nullif(btrim(coalesce(p_session_name, '')), '');
  v_preferred := coalesce(p_preferred_group_size, 5);
  v_specialist := learning.normalise_grouping_specialist_role_title(
    p_specialist_role_title
  );

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
    specialist_role_title,
    status,
    created_by
  ) values (
    v_name,
    learning.generate_grouping_join_code(),
    v_preferred,
    v_specialist,
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
      'preferredGroupSize', v_session.preferred_group_size,
      'specialistRoleTitle', v_session.specialist_role_title
    )
  );

  return learning.grouping_session_payload(v_session.id);
end;
$$;

create function admin_api.create_grouping_session(
  p_session_name text default null,
  p_preferred_group_size integer default 5,
  p_specialist_role_title text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.create_grouping_session(
    p_session_name,
    p_preferred_group_size,
    p_specialist_role_title
  );
$$;

create or replace function platform.set_grouping_session_specialist_role(
  p_session_id uuid,
  p_specialist_role_title text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session learning.grouping_sessions%rowtype;
  v_specialist text;
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
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_CLOSED';
  end if;

  v_specialist := learning.normalise_grouping_specialist_role_title(
    p_specialist_role_title
  );

  update learning.grouping_sessions
  set specialist_role_title = v_specialist
  where id = p_session_id;

  -- If teams already exist, refresh automatic roles to the new title.
  if exists (
    select 1
    from learning.grouping_teams as team
    where team.session_id = p_session_id
  ) then
    perform learning.assign_roles_for_grouping_session(p_session_id);
  end if;

  return learning.grouping_session_payload(p_session_id);
end;
$$;

create or replace function platform.set_grouping_participant_role(
  p_participant_id uuid,
  p_role_type text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_participant learning.grouping_participants%rowtype;
  v_session learning.grouping_sessions%rowtype;
  v_role text;
begin
  perform learning.require_grouping_platform_admin();

  v_role := nullif(btrim(coalesce(p_role_type, '')), '');
  if v_role is null
     or v_role not in ('project_manager', 'tester', 'specialist') then
    raise exception using errcode = '22023', message = 'GROUPING_ROLE_TYPE_INVALID';
  end if;

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

  if v_session.status = 'closed' then
    raise exception using errcode = '22023', message = 'GROUPING_SESSION_CLOSED';
  end if;

  if v_session.specialist_role_title is null then
    raise exception using errcode = '22023', message = 'GROUPING_ROLES_NOT_ENABLED';
  end if;

  if v_participant.team_id is null then
    raise exception using errcode = '22023', message = 'GROUPING_PARTICIPANT_UNASSIGNED';
  end if;

  update learning.grouping_participants
  set role_type = v_role
  where id = p_participant_id;

  return learning.grouping_session_payload(v_session.id);
end;
$$;

create or replace function admin_api.set_grouping_session_specialist_role(
  p_session_id uuid,
  p_specialist_role_title text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.set_grouping_session_specialist_role(
    p_session_id,
    p_specialist_role_title
  );
$$;

create or replace function admin_api.set_grouping_participant_role(
  p_participant_id uuid,
  p_role_type text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select platform.set_grouping_participant_role(
    p_participant_id,
    p_role_type
  );
$$;

-- Late arrivals joining a published team receive the specialist role when roles are enabled.
create or replace function platform.assign_late_grouping_participant(
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
  v_specialist text;
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

  v_specialist := learning.normalise_grouping_specialist_role_title(
    v_session.specialist_role_title
  );

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
      joined_after_publication = true,
      role_type = case
        when v_specialist is null then null
        else 'specialist'
      end
  where id = p_participant_id;

  return learning.grouping_session_payload(v_session.id);
end;
$$;

-- Grants for new / replaced staff functions
do $$
declare
  v_fn text;
begin
  foreach v_fn in array array[
    'platform.create_grouping_session(text,integer,text)',
    'platform.set_grouping_session_specialist_role(uuid,text)',
    'platform.set_grouping_participant_role(uuid,text)',
    'platform.assign_late_grouping_participant(uuid,uuid,boolean)',
    'admin_api.create_grouping_session(text,integer,text)',
    'admin_api.set_grouping_session_specialist_role(uuid,text)',
    'admin_api.set_grouping_participant_role(uuid,text)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
    execute format('grant execute on function %s to authenticated, service_role', v_fn);
  end loop;
end;
$$;
