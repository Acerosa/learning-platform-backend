-- Bind a server-side marking rule to the learner-facing question structure.
-- Adding a rule to an unchanged question does not require a new activity version.
-- The correct answer is not part of the fingerprint and is not added to learner packages.

alter table learning.question_marking
  add column structure_fingerprint text,
  add column bound_activity_id uuid,
  add column bound_question_key text;

comment on column learning.question_marking.structure_fingerprint is
  'SHA-256 of the mark-relevant question structure. Does not include the correct answer, week, or teaching text around the question.';

create unique index question_marking_structure_fingerprint_unique
  on learning.question_marking (bound_activity_id, bound_question_key, structure_fingerprint)
  where structure_fingerprint is not null;

create or replace function learning.question_structure_fingerprint(
  p_activity_key text,
  p_question_key text,
  p_question_type text,
  p_prompt text,
  p_parts jsonb
)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'activityKey', lower(btrim(coalesce(p_activity_key, ''))),
          'questionKey', upper(btrim(coalesce(p_question_key, ''))),
          'questionType', lower(btrim(coalesce(p_question_type, ''))),
          'prompt', regexp_replace(btrim(coalesce(p_prompt, '')), '\s+', ' ', 'g'),
          'parts', coalesce(p_parts, '[]'::jsonb)
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

revoke all on function learning.question_structure_fingerprint(text, text, text, text, jsonb)
  from public, anon, authenticated;

comment on function learning.question_structure_fingerprint(text, text, text, text, jsonb) is
  'Deterministic fingerprint of a learner-facing question. Excludes the correct answer, placement, and surrounding teaching text.';

create or replace function learning.canonical_option_parts(p_options jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', btrim(coalesce(option_row.value->>'id', '')),
        'label', regexp_replace(btrim(coalesce(option_row.value->>'label', option_row.value->>'text', '')), '\s+', ' ', 'g')
      )
      order by option_row.ordinality
    ),
    '[]'::jsonb
  )
  from jsonb_array_elements(coalesce(p_options, '[]'::jsonb)) with ordinality as option_row(value, ordinality);
$$;

revoke all on function learning.canonical_option_parts(jsonb)
  from public, anon, authenticated;

create or replace function learning.block_question_fingerprint(
  p_activity_key text,
  p_question_key text,
  p_block jsonb
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_type text;
  v_content jsonb;
  v_key text;
  v_source text;
  v_item jsonb;
  v_item_id text;
  v_parts jsonb;
begin
  v_type := lower(btrim(coalesce(p_block->>'type', '')));
  v_content := coalesce(p_block->'content', '{}'::jsonb);
  v_key := upper(btrim(coalesce(p_question_key, '')));
  v_source := upper(btrim(coalesce(
    nullif(v_content->>'sourceQuestionId', ''),
    nullif(split_part(coalesce(v_content->>'questionId', ''), ':', 2), ''),
    ''
  )));

  if v_type in ('single-choice', 'true-false', 'option-cards', 'picture-quiz') then
    if v_source <> '' and v_source <> v_key then
      return null;
    end if;
    if v_source = '' and v_key <> '' and upper(btrim(coalesce(p_block->>'id', ''))) <> v_key then
      return null;
    end if;
    return learning.question_structure_fingerprint(
      p_activity_key,
      v_key,
      v_type,
      coalesce(v_content->>'prompt', ''),
      learning.canonical_option_parts(v_content->'options')
    );
  end if;

  if v_type in ('classification', 'drag-drop') then
    v_parts := jsonb_build_array(
      jsonb_build_object(
        'categories', learning.canonical_option_parts(coalesce(v_content->'categories', v_content->'targets'))
      )
    );
    for v_item in
      select value from jsonb_array_elements(coalesce(v_content->'items', '[]'::jsonb))
    loop
      v_item_id := upper(btrim(coalesce(v_item->>'id', '')));
      if v_key = v_item_id or v_key = upper(btrim(coalesce(v_source, ''))) || ':' || v_item_id
         or right(v_key, length(v_item_id) + 1) = ':' || v_item_id then
        return learning.question_structure_fingerprint(
          p_activity_key,
          v_key,
          v_type,
          coalesce(v_item->>'prompt', v_item->>'label', v_item->>'text', v_content->>'prompt', ''),
          v_parts || jsonb_build_array(
            jsonb_build_object(
              'id', btrim(coalesce(v_item->>'id', '')),
              'label', regexp_replace(btrim(coalesce(v_item->>'label', v_item->>'text', '')), '\s+', ' ', 'g')
            )
          )
        );
      end if;
    end loop;
    return null;
  end if;

  if v_type in ('ordering', 'sequence') then
    return learning.question_structure_fingerprint(
      p_activity_key,
      case when v_source <> '' then v_source else v_key end,
      v_type,
      coalesce(v_content->>'prompt', ''),
      learning.canonical_option_parts(coalesce(v_content->'items', v_content->'steps'))
    );
  end if;

  return null;
end;
$$;

revoke all on function learning.block_question_fingerprint(text, text, jsonb)
  from public, anon, authenticated;

create or replace function learning.published_question_fingerprint(
  p_activity_key text,
  p_activity_version text,
  p_question_key text
)
returns text
language sql
stable
set search_path = ''
as $$
  select learning.block_question_fingerprint(p_activity_key, p_question_key, block.value)
  from platform.curriculum_publications as publication
  cross join lateral jsonb_array_elements(publication.package->'activities') as activity(value)
  cross join lateral jsonb_array_elements(coalesce(activity.value->'blocks', '[]'::jsonb)) as block(value)
  where publication.status = 'published'
    and activity.value->>'id' = p_activity_key
    and activity.value->>'version' = p_activity_version
    and learning.block_question_fingerprint(p_activity_key, p_question_key, block.value) is not null
  order by publication.published_at desc
  limit 1;
$$;

revoke all on function learning.published_question_fingerprint(text, text, text)
  from public, anon, authenticated;

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

  if tg_op = 'UPDATE'
     and old.spec = new.spec
     and old.structure_fingerprint is null
     and new.structure_fingerprint is not null then
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

create or replace function learning.bind_question_marking_fingerprint()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_activity_key text;
  v_activity_id uuid;
  v_version text;
  v_question_key text;
  v_fingerprint text;
begin
  select activity.stable_key, activity.id, activity_version.version, question.stable_key
  into v_activity_key, v_activity_id, v_version, v_question_key
  from learning.questions as question
  join learning.activity_versions as activity_version
    on activity_version.id = question.activity_version_id
  join learning.activities as activity
    on activity.id = activity_version.activity_id
  where question.id = new.question_id;

  new.bound_activity_id := v_activity_id;
  new.bound_question_key := v_question_key;

  if new.structure_fingerprint is null and v_activity_key is not null then
    v_fingerprint := learning.published_question_fingerprint(v_activity_key, v_version, v_question_key);
    if v_fingerprint is not null then
      new.structure_fingerprint := v_fingerprint;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function learning.bind_question_marking_fingerprint()
  from public, anon, authenticated;

drop trigger if exists question_marking_bind_fingerprint on learning.question_marking;

create trigger question_marking_bind_fingerprint
before insert or update on learning.question_marking
for each row execute function learning.bind_question_marking_fingerprint();

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

  if v_computed is null then
    return null;
  end if;

  select count(*)::integer, (array_agg(marking.question_id))[1]
  into v_match_count, v_match_id
  from learning.question_marking as marking
  where marking.bound_activity_id = v_activity_id
    and marking.bound_question_key = v_question_key
    and marking.structure_fingerprint = v_computed;

  if v_match_count = 1 then
    return v_match_id;
  end if;

  return null;
end;
$$;

revoke all on function learning.resolve_marking_question(uuid)
  from public, anon, authenticated;

comment on function learning.resolve_marking_question(uuid) is
  'Uses the exact version rule when it is compatible. Otherwise uses the single rule with the same activity, question key, and structure fingerprint. Never guesses and never prefers the newest version.';
