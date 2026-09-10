-- When Auth has no learning.students row but Auth email uniquely matches
-- exactly one active unlinked roster learner (contact_email), link them.
-- This recovers tutors/learners who created Auth after roster seeding and
-- otherwise remain stuck in profile_required / complete ONBOARDING_CONFLICT
-- when they enter a different Student ID than the email-matched row.
--
-- Does not claim Student IDs already linked to another Auth.
-- Does nothing when 0 or >1 unlinked matches (ambiguous).

create or replace function api.ensure_learner_auth_link()
returns table (
  linked boolean,
  student_number text,
  first_name text,
  surname text,
  contact_email text
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_auth_email text;
  v_match_count integer;
  v_student learning.students%rowtype;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;

  select lower(btrim(auth_user.email))
  into v_auth_email
  from auth.users as auth_user
  where auth_user.id = v_auth_user_id
    and auth_user.email is not null
    and auth_user.email_confirmed_at is not null;

  if v_auth_email is null then
    raise exception using errcode = '28000', message = 'AUTH_REQUIRED';
  end if;

  select student.*
  into v_student
  from learning.students as student
  where student.auth_user_id = v_auth_user_id;

  if found then
    return query
    select
      false,
      v_student.student_number,
      v_student.first_name,
      v_student.surname,
      v_student.contact_email;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('learner-onboarding-auth:' || v_auth_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('learner-onboarding-email:' || v_auth_email, 0)
  );

  select count(*)::integer
  into v_match_count
  from learning.students as student
  where student.active
    and student.auth_user_id is null
    and lower(btrim(coalesce(student.contact_email, ''))) = v_auth_email;

  if v_match_count <> 1 then
    return query
    select false, null::text, null::text, null::text, null::text;
    return;
  end if;

  select student.*
  into v_student
  from learning.students as student
  where student.active
    and student.auth_user_id is null
    and lower(btrim(coalesce(student.contact_email, ''))) = v_auth_email
  for update;

  begin
    update learning.students
    set auth_user_id = v_auth_user_id,
        updated_at = clock_timestamp()
    where id = v_student.id
    returning * into v_student;
  exception
    when unique_violation then
      return query
      select false, null::text, null::text, null::text, null::text;
      return;
  end;

  return query
  select
    true,
    v_student.student_number,
    v_student.first_name,
    v_student.surname,
    v_student.contact_email;
end
$$;

comment on function api.ensure_learner_auth_link() is
  'Links auth.uid() to the unique active unlinked learning.students row whose contact_email matches the Auth email. No-op when already linked or match is missing/ambiguous.';

revoke all on function api.ensure_learner_auth_link()
  from public, anon, authenticated;
grant execute on function api.ensure_learner_auth_link()
  to authenticated;
