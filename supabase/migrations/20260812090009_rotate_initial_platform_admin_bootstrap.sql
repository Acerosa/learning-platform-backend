-- Rotate the unused initial administrator credential after its plaintext was
-- exposed. The replacement keeps the existing 30-day expiry policy and makes
-- every post-consumption retry fail.

do $$
begin
  if exists (
    select 1
    from platform.staff_roles as staff_role
    where staff_role.role = 'platform_admin'
      and staff_role.revoked_at is null
  ) then
    raise exception using
      errcode = '55000',
      message = 'ADMIN_BOOTSTRAP_ROTATION_NOT_AVAILABLE';
  end if;

  update platform.admin_bootstrap_credentials
  set
    token_hash = '5b306f51af48bfd06bf045e49877f624e42bf04abbadb91640156862d4eb33e9',
    expires_at = clock_timestamp() + interval '30 days',
    consumed_at = null,
    consumed_by_auth_user_id = null
  where bootstrap_key = 'initial-platform-admin'
    and consumed_at is null;

  if not found then
    raise exception using
      errcode = '55000',
      message = 'ADMIN_BOOTSTRAP_ROTATION_NOT_AVAILABLE';
  end if;
end
$$;

create or replace function platform.claim_initial_platform_admin(
  p_bootstrap_token text
)
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

  if v_credential.consumed_at is not null
     or v_credential.expires_at <= clock_timestamp()
     or exists (
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
    update learning.teachers
    set
      active = true,
      updated_at = clock_timestamp()
    where id = v_teacher.id
    returning * into v_teacher;
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

revoke all on function platform.claim_initial_platform_admin(text)
  from public, anon, authenticated;
grant execute on function platform.claim_initial_platform_admin(text)
  to authenticated;

comment on function platform.claim_initial_platform_admin(text) is
  'Consumes the one-time initial platform administrator credential for the current confirmed Auth identity; retries fail after consumption.';
