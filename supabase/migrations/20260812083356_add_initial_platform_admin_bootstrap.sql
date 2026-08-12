-- One-time, expiring bootstrap for the first production platform
-- administrator. The browser supplies only the out-of-band bootstrap token;
-- Auth identity and the fixed role are derived and enforced in the backend.

update platform.contract_versions
set
  compatibility = '{"previousVersion":"0.1.0","mode":"read-models-with-one-time-bootstrap"}'::jsonb,
  contract_document = '{"schema":"admin_api","boundary":"authenticated staff read models and one-time initial administrator bootstrap"}'::jsonb
where contract_key = 'admin-api'
  and version = '0.2.0'
  and status = 'draft';

create table platform.admin_bootstrap_credentials (
  bootstrap_key text primary key,
  token_hash text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by_auth_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  constraint admin_bootstrap_key_valid
    check (bootstrap_key = 'initial-platform-admin'),
  constraint admin_bootstrap_token_hash_valid
    check (token_hash ~ '^[a-f0-9]{64}$'),
  constraint admin_bootstrap_consumption_valid
    check (
      (consumed_at is null and consumed_by_auth_user_id is null)
      or consumed_at is not null
    )
);

alter table platform.admin_bootstrap_credentials enable row level security;

revoke all on platform.admin_bootstrap_credentials
  from public, anon, authenticated;

insert into platform.admin_bootstrap_credentials (
  bootstrap_key,
  token_hash,
  expires_at
) values (
  'initial-platform-admin',
  '7e33adc820a85ed2d28acc86bce70b82dcca7eca19836fc1b6b99e84d88ec4b9',
  clock_timestamp() + interval '30 days'
);

create function platform.claim_initial_platform_admin(p_bootstrap_token text)
returns table (
  teacher_id uuid,
  staff_reference text,
  display_name text,
  active_roles text[],
  idempotent boolean
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_auth_email text;
  v_bootstrap_token text;
  v_credential platform.admin_bootstrap_credentials%rowtype;
  v_teacher learning.teachers%rowtype;
  v_role platform.staff_roles%rowtype;
begin
  v_auth_user_id := auth.uid();

  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  select lower(btrim(auth_user.email))
  into v_auth_email
  from auth.users as auth_user
  where auth_user.id = v_auth_user_id
    and auth_user.email is not null
    and auth_user.email_confirmed_at is not null;

  if v_auth_email is null then
    raise exception using errcode = '28000', message = 'EMAIL_CONFIRMATION_REQUIRED';
  end if;

  v_bootstrap_token := lower(nullif(btrim(p_bootstrap_token), ''));

  if v_bootstrap_token is null
     or v_bootstrap_token !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'BOOTSTRAP_NOT_AUTHORISED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('initial-platform-admin-bootstrap', 0)
  );

  select credential.*
  into v_credential
  from platform.admin_bootstrap_credentials as credential
  where credential.bootstrap_key = 'initial-platform-admin'
  for update;

  if not found
     or v_credential.token_hash <> encode(
       extensions.digest(v_bootstrap_token, 'sha256'),
       'hex'
     ) then
    raise exception using errcode = '28000', message = 'BOOTSTRAP_NOT_AUTHORISED';
  end if;

  if v_credential.consumed_at is not null then
    select teacher.*
    into v_teacher
    from learning.teachers as teacher
    join platform.staff_roles as staff_role
      on staff_role.teacher_id = teacher.id
     and staff_role.role = 'platform_admin'
     and staff_role.revoked_at is null
    where teacher.auth_user_id = v_auth_user_id
      and teacher.active
      and v_credential.consumed_by_auth_user_id = v_auth_user_id;

    if found then
      return query
      select
        v_teacher.id,
        v_teacher.staff_reference,
        v_teacher.display_name,
        array['platform_admin']::text[],
        true;
      return;
    end if;

    raise exception using errcode = '28000', message = 'BOOTSTRAP_UNAVAILABLE';
  end if;

  if v_credential.expires_at <= clock_timestamp() then
    raise exception using errcode = '28000', message = 'BOOTSTRAP_UNAVAILABLE';
  end if;

  if exists (
    select 1
    from platform.staff_roles as staff_role
    where staff_role.role = 'platform_admin'
      and staff_role.revoked_at is null
  ) then
    raise exception using errcode = '28000', message = 'BOOTSTRAP_UNAVAILABLE';
  end if;

  select teacher.*
  into v_teacher
  from learning.teachers as teacher
  where teacher.auth_user_id = v_auth_user_id
  for update;

  if found and not v_teacher.active then
    raise exception using errcode = '28000', message = 'STAFF_IDENTITY_INACTIVE';
  end if;

  if not found then
    insert into learning.teachers (
      auth_user_id,
      staff_reference,
      display_name,
      active
    ) values (
      v_auth_user_id,
      'PLATFORM-ADMIN-' || upper(v_auth_user_id::text),
      'Initial Platform Administrator',
      true
    )
    returning * into v_teacher;
  end if;

  insert into platform.staff_roles (
    teacher_id,
    role,
    granted_at
  ) values (
    v_teacher.id,
    'platform_admin',
    clock_timestamp()
  )
  returning * into v_role;

  update platform.admin_bootstrap_credentials
  set
    consumed_at = clock_timestamp(),
    consumed_by_auth_user_id = v_auth_user_id
  where bootstrap_key = 'initial-platform-admin';

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'staff.bootstrap.platform-admin',
    v_auth_user_id,
    'staff',
    'staff-role',
    v_role.id::text,
    'succeeded',
    jsonb_build_object('bootstrap', 'initial-platform-admin')
  );

  return query
  select
    v_teacher.id,
    v_teacher.staff_reference,
    v_teacher.display_name,
    array['platform_admin']::text[],
    false;
end
$$;

create function admin_api.claim_initial_platform_admin(p_bootstrap_token text)
returns table (
  teacher_id uuid,
  staff_reference text,
  display_name text,
  active_roles text[],
  idempotent boolean
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from platform.claim_initial_platform_admin(p_bootstrap_token)
$$;

revoke all on function platform.claim_initial_platform_admin(text)
  from public, anon, authenticated;
revoke all on function admin_api.claim_initial_platform_admin(text)
  from public, anon, authenticated;

grant execute on function platform.claim_initial_platform_admin(text)
  to authenticated;
grant execute on function admin_api.claim_initial_platform_admin(text)
  to authenticated;

comment on table platform.admin_bootstrap_credentials is
  'Private, expiring and single-use credentials for controlled platform bootstrap operations.';

comment on function platform.claim_initial_platform_admin(text) is
  'Claims the one-time initial platform administrator grant for the current confirmed Auth identity.';

comment on function admin_api.claim_initial_platform_admin(text) is
  'Browser-safe wrapper for the one-time initial platform administrator claim.';
