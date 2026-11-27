-- Restore resolvable marking for published curriculum questions using
-- authoritative staff package answer keys already stored in
-- platform.curriculum_publications.package.
--
-- Prefer the unique automatic published unbound spec when multiple catalogue
-- versions collide (e.g. week6-legislation-matching 1.1.0 requires_review vs
-- 1.2.0 multi-field-exact). Still fail closed when automatic specs disagree.
--
-- Refreshes structure fingerprints when own marking exists but the published
-- structure fingerprint drifted. Temporarily disables the publication
-- immutability trigger only for this restore DO block.

begin;

-- ---------------------------------------------------------------------------
-- 0) Allow fingerprint/bound metadata refresh without changing marking specs
-- ---------------------------------------------------------------------------
create or replace function learning.reject_published_question_marking_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_question_id uuid;
begin
  target_question_id := case when tg_op = 'DELETE'
    then old.question_id
    else new.question_id
  end;

  -- Allow attaching/updating fingerprint and binding metadata when the
  -- protected marking specification itself is unchanged.
  if tg_op = 'UPDATE'
     and old.spec = new.spec
     and old.question_id = new.question_id then
    return new;
  end if;

  if exists (
    select 1
    from learning.questions as question
    join learning.activity_versions as activity_version
      on activity_version.id = question.activity_version_id
    where question.id = target_question_id
      and activity_version.published_at is not null
  ) then
    raise exception using
      errcode = '55000',
      message = 'PUBLISHED_QUESTION_MARKING_IMMUTABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function learning.reject_published_question_marking_change()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1) Prefer a unique automatic published spec when unbound candidates collide
--    (e.g. week6-legislation-matching 1.1.0 requires_review vs 1.2.0 exact).
--    Still fail closed when multiple automatic specs disagree.
-- ---------------------------------------------------------------------------
create or replace function learning.resolve_marking_question(p_question_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_activity_id uuid;
  v_activity_key text;
  v_version text;
  v_question_key text;
  v_own_fingerprint text;
  v_computed text;
  v_match_count integer;
  v_match_id uuid;
begin
  select activity.id, activity.stable_key, activity_version.version, question.stable_key, marking.structure_fingerprint
  into v_activity_id, v_activity_key, v_version, v_question_key, v_own_fingerprint
  from learning.questions as question
  join learning.activity_versions as activity_version
    on activity_version.id = question.activity_version_id
  join learning.activities as activity
    on activity.id = activity_version.activity_id
  left join learning.question_marking as marking
    on marking.question_id = question.id
  where question.id = p_question_id;

  v_computed := learning.published_question_fingerprint(v_activity_key, v_version, v_question_key);

  if exists (
    select 1 from learning.question_marking as marking
    where marking.question_id = p_question_id
  ) and (
    v_own_fingerprint is null
    or v_computed is null
    or v_own_fingerprint = v_computed
  ) then
    return p_question_id;
  end if;

  if v_computed is not null then
    select count(*)::integer, (array_agg(marking.question_id))[1]
    into v_match_count, v_match_id
    from learning.question_marking as marking
    where marking.bound_activity_id = v_activity_id
      and marking.bound_question_key = v_question_key
      and marking.structure_fingerprint = v_computed;

    if v_match_count = 1 then
      return v_match_id;
    end if;
  end if;

  if v_activity_id is null or v_question_key is null then
    return null;
  end if;

  select count(*)::integer, (array_agg(marking.question_id))[1]
  into v_match_count, v_match_id
  from learning.question_marking as marking
  join learning.questions as other_question
    on other_question.id = marking.question_id
  join learning.activity_versions as other_version
    on other_version.id = other_question.activity_version_id
  where other_version.activity_id = v_activity_id
    and other_question.stable_key = v_question_key
    and other_question.id is distinct from p_question_id
    and other_version.published_at is not null
    and other_version.retired_at is null;

  if v_match_count = 1 then
    return v_match_id;
  end if;

  if v_match_count > 1 then
    select count(*)::integer, (array_agg(marking.question_id))[1]
    into v_match_count, v_match_id
    from learning.question_marking as marking
    join learning.questions as other_question
      on other_question.id = marking.question_id
    join learning.activity_versions as other_version
      on other_version.id = other_question.activity_version_id
    where other_version.activity_id = v_activity_id
      and other_question.stable_key = v_question_key
      and other_question.id is distinct from p_question_id
      and other_version.published_at is not null
      and other_version.retired_at is null
      and coalesce(marking.spec->>'mode', 'completion')
        not in ('requires_review', 'completion');

    if v_match_count = 1 then
      return v_match_id;
    end if;
  end if;

  return null;
end;
$$;

revoke all on function learning.resolve_marking_question(uuid)
  from public, anon, authenticated;

comment on function learning.resolve_marking_question(uuid) is
  'Uses exact-version and fingerprint rules first, then the single published unbound spec. When multiple unbound specs exist, uses the unique automatic (non-review/completion) spec if exactly one is present; otherwise fails closed.';

-- ---------------------------------------------------------------------------
-- 2) Helpers: derive a marking spec from a staff package interactive block
-- ---------------------------------------------------------------------------
create or replace function platform.marking_spec_from_staff_block(p_block jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_content jsonb := coalesce(p_block->'content', '{}'::jsonb);
  v_type text := coalesce(p_block->>'type', '');
  v_answer jsonb := v_content->'answer';
  v_fields text[];
begin
  if v_content ? 'correctOptionId'
     and nullif(btrim(coalesce(v_content->>'correctOptionId', '')), '') is not null then
    return jsonb_build_object(
      'mode', 'single-choice',
      'correctOptionId', v_content->>'correctOptionId'
    );
  end if;

  if v_content ? 'correctCategoryId'
     and nullif(btrim(coalesce(v_content->>'correctCategoryId', '')), '') is not null then
    return jsonb_build_object(
      'mode', 'classification',
      'correctCategoryId', v_content->>'correctCategoryId'
    );
  end if;

  if v_type in ('classification', 'matching', 'drag-drop')
     and jsonb_typeof(v_answer) = 'string'
     and nullif(btrim(coalesce(v_content->>'answer', '')), '') is not null then
    return jsonb_build_object(
      'mode', 'classification',
      'correctCategoryId', v_content->>'answer'
    );
  end if;

  if jsonb_typeof(v_answer) = 'object'
     and v_answer <> '{}'::jsonb then
    select coalesce(array_agg(key order by key), array[]::text[])
    into v_fields
    from jsonb_object_keys(v_answer) as key;

    if coalesce(cardinality(v_fields), 0) > 0 then
      return jsonb_build_object(
        'mode', 'multi-field-exact',
        'requiredFields', to_jsonb(v_fields),
        'correctValues', v_answer
      );
    end if;
  end if;

  if v_content ? 'correctOrder'
     and jsonb_typeof(v_content->'correctOrder') = 'array' then
    return jsonb_build_object(
      'mode', 'ordering-exact',
      'correctOrder', v_content->'correctOrder'
    );
  end if;

  return null;
end;
$$;

revoke all on function platform.marking_spec_from_staff_block(jsonb)
  from public, anon, authenticated;

comment on function platform.marking_spec_from_staff_block(jsonb) is
  'Derives a server marking spec from an authoritative staff curriculum block. Returns null when the block has no supported automatic answer keys.';

create or replace function platform.find_staff_block_for_question(
  p_activity jsonb,
  p_question_key text
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select block.value
  from jsonb_array_elements(coalesce(p_activity->'blocks', '[]'::jsonb)) as block(value)
  where coalesce(block.value->'content'->>'questionId', '') in (
          p_question_key,
          (p_activity->>'id') || ':' || p_question_key
        )
     or coalesce(block.value->>'id', '') like '%-' || p_question_key
     or coalesce(block.value->>'id', '') like '%:' || p_question_key
  order by
    case
      when coalesce(block.value->'content'->>'questionId', '') in (
        p_question_key,
        (p_activity->>'id') || ':' || p_question_key
      ) then 0
      else 1
    end
  limit 1;
$$;

revoke all on function platform.find_staff_block_for_question(jsonb, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Restore missing specs + refresh drifted fingerprints for published hubs
-- ---------------------------------------------------------------------------
do $restore$
declare
  v_hub text;
  v_activity jsonb;
  v_activity_key text;
  v_activity_version text;
  v_question record;
  v_block jsonb;
  v_spec jsonb;
  v_fingerprint text;
  v_inserted int := 0;
  v_refreshed int := 0;
begin
  -- Authoritative recovery of missing published marking rows. Spec content
  -- comes only from existing staff packages; never invent answers.
  alter table learning.question_marking
    disable trigger question_marking_immutable_after_publication;

  begin
    for v_hub in
      select unnest(array[
        'tlevel-software-development',
        'unit-3-cyber-security',
        'l2e-exploring-emerging-digital-technologies',
        'unit-14-software-engineering-for-business'
      ])
    loop
      for v_activity in
        select act
        from platform.curriculum_publications as publication
        cross join lateral jsonb_array_elements(
          coalesce(publication.package->'activities', '[]'::jsonb)
        ) as act
        where publication.hub_code = v_hub
          and publication.status = 'published'
      loop
        v_activity_key := v_activity->>'id';
        v_activity_version := v_activity->>'version';

        for v_question in
          select
            question.id,
            question.stable_key,
            activity.id as activity_id,
            exists (
              select 1
              from learning.question_marking as marking
              where marking.question_id = question.id
            ) as has_own,
            learning.resolve_marking_question(question.id) as resolved_id
          from learning.activities as activity
          join learning.activity_versions as activity_version
            on activity_version.activity_id = activity.id
           and activity_version.version = v_activity_version
          join learning.questions as question
            on question.activity_version_id = activity_version.id
          where activity.stable_key = v_activity_key
        loop
          if v_question.resolved_id is not null then
            continue;
          end if;

          v_fingerprint := learning.published_question_fingerprint(
            v_activity_key,
            v_activity_version,
            v_question.stable_key
          );

          if v_question.has_own and v_fingerprint is not null then
            update learning.question_marking as marking
            set
              structure_fingerprint = v_fingerprint,
              bound_activity_id = coalesce(marking.bound_activity_id, v_question.activity_id),
              bound_question_key = coalesce(nullif(btrim(marking.bound_question_key), ''), v_question.stable_key)
            where marking.question_id = v_question.id
              and marking.structure_fingerprint is distinct from v_fingerprint
              and not exists (
                select 1
                from learning.question_marking as other
                where other.bound_activity_id = coalesce(marking.bound_activity_id, v_question.activity_id)
                  and other.bound_question_key = coalesce(nullif(btrim(marking.bound_question_key), ''), v_question.stable_key)
                  and other.structure_fingerprint = v_fingerprint
                  and other.question_id is distinct from marking.question_id
              );
            if found then
              v_refreshed := v_refreshed + 1;
            end if;
            continue;
          end if;

          if v_question.has_own then
            continue;
          end if;

          v_block := platform.find_staff_block_for_question(v_activity, v_question.stable_key);
          if v_block is null then
            continue;
          end if;

          v_spec := platform.marking_spec_from_staff_block(v_block);
          if v_spec is null then
            continue;
          end if;

          insert into learning.question_marking (
            question_id,
            spec,
            structure_fingerprint,
            bound_activity_id,
            bound_question_key
          )
          values (
            v_question.id,
            v_spec,
            v_fingerprint,
            v_question.activity_id,
            v_question.stable_key
          )
          on conflict (question_id) do nothing;

          if found then
            v_inserted := v_inserted + 1;
          end if;
        end loop;
      end loop;
    end loop;
  exception
    when others then
      alter table learning.question_marking
        enable trigger question_marking_immutable_after_publication;
      raise;
  end;

  alter table learning.question_marking
    enable trigger question_marking_immutable_after_publication;

  raise notice 'marking coverage restore inserted=% refreshed_fingerprints=%', v_inserted, v_refreshed;
end;
$restore$;

-- ---------------------------------------------------------------------------
-- 4) Diagnostic: published marking coverage gaps (no answer keys exposed)
-- ---------------------------------------------------------------------------
create or replace view admin_api.published_marking_coverage_gaps
with (security_invoker = true)
as
select
  publication.hub_code,
  publication.course_key,
  publication.package_version,
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  question.stable_key as question_key,
  question.question_type,
  exists (
    select 1
    from learning.question_marking as marking
    where marking.question_id = question.id
  ) as has_own_marking,
  learning.resolve_marking_question(question.id) is null as unresolved
from platform.curriculum_publications as publication
cross join lateral jsonb_array_elements(
  coalesce(publication.package->'activities', '[]'::jsonb)
) as act(value)
join learning.activities as activity
  on activity.stable_key = act.value->>'id'
join learning.activity_versions as activity_version
  on activity_version.activity_id = activity.id
 and activity_version.version = act.value->>'version'
join learning.questions as question
  on question.activity_version_id = activity_version.id
where publication.status = 'published'
  and learning.resolve_marking_question(question.id) is null
  and (select platform.current_staff_has_any_role(
    array['platform_admin', 'curriculum_admin', 'operations', 'auditor']
  ));

revoke all on admin_api.published_marking_coverage_gaps
  from public, anon, authenticated;
grant select on admin_api.published_marking_coverage_gaps to authenticated;

comment on view admin_api.published_marking_coverage_gaps is
  'Staff diagnostic of published questions that cannot resolve a marking specification. Does not expose marking specs or answer keys.';

-- ---------------------------------------------------------------------------
-- 5) Assert restore success for auto-scored coverage on published hubs
-- ---------------------------------------------------------------------------
do $assert$
declare
  v_remaining int;
begin
  select count(*) into v_remaining
  from admin_api.published_marking_coverage_gaps;

  -- Staff role context is not set during migrations; count directly instead.
  select count(*) into v_remaining
  from platform.curriculum_publications as publication
  cross join lateral jsonb_array_elements(
    coalesce(publication.package->'activities', '[]'::jsonb)
  ) as act(value)
  join learning.activities as activity
    on activity.stable_key = act.value->>'id'
  join learning.activity_versions as activity_version
    on activity_version.activity_id = activity.id
   and activity_version.version = act.value->>'version'
  join learning.questions as question
    on question.activity_version_id = activity_version.id
  where publication.status = 'published'
    and publication.hub_code in (
      'tlevel-software-development',
      'unit-3-cyber-security',
      'l2e-exploring-emerging-digital-technologies',
      'unit-14-software-engineering-for-business'
    )
    and learning.resolve_marking_question(question.id) is null;

  if v_remaining > 0 then
    raise notice 'published marking coverage gaps remaining after restore: %', v_remaining;
  end if;
end;
$assert$;

commit;
