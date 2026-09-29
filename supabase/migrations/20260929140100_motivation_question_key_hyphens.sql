-- Learner packages identify Week 4 motivation questions as mot-kc1.
-- The server marking rules use the catalogue key MOTKC1.
-- A hyphen is not a different question. Other key differences still do not match.

create or replace function learning.question_keys_compatible(
  p_left text,
  p_right text
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select btrim(coalesce(p_left, '')) <> ''
    and btrim(coalesce(p_right, '')) <> ''
    and (
      upper(btrim(p_left)) = upper(btrim(p_right))
      or replace(upper(btrim(p_left)), '-', '') = replace(upper(btrim(p_right)), '-', '')
    );
$$;

revoke all on function learning.question_keys_compatible(text, text)
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
    if v_source <> '' and not learning.question_keys_compatible(v_source, v_key) then
      return null;
    end if;
    if v_source = '' and v_key <> ''
       and not learning.question_keys_compatible(coalesce(p_block->>'id', ''), v_key) then
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
      if learning.question_keys_compatible(v_key, v_item_id)
         or v_key = upper(btrim(coalesce(v_source, ''))) || ':' || v_item_id
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

-- Bind only Motivations for Attack, and only where the published option id
-- is the server answer. Historical checks, assignments and other activities stay as they are.

update learning.question_marking as marking
set
  structure_fingerprint = learned.fingerprint,
  bound_activity_id = learned.activity_id,
  bound_question_key = learned.question_key
from (
  select
    marking.question_id,
    activity.id as activity_id,
    question.stable_key as question_key,
    learning.published_question_fingerprint(
      activity.stable_key,
      published.package_version,
      question.stable_key
    ) as fingerprint
  from learning.question_marking as marking
  join learning.questions as question
    on question.id = marking.question_id
  join learning.activity_versions as activity_version
    on activity_version.id = question.activity_version_id
  join learning.activities as activity
    on activity.id = activity_version.activity_id
  join lateral (
    select activity_json->>'version' as package_version
    from platform.curriculum_publications as publication
    cross join lateral jsonb_array_elements(publication.package->'activities') as activity_json
    where publication.status = 'published'
      and publication.hub_code = 'unit-3-cyber-security'
      and activity_json->>'id' = activity.stable_key
    order by publication.published_at desc
    limit 1
  ) as published on true
  where activity.stable_key = 'week4-motivations-learning'
    and marking.structure_fingerprint is null
    and marking.spec->>'mode' = 'single-choice'
    and exists (
      select 1
      from platform.curriculum_publications as publication
      cross join lateral jsonb_array_elements(publication.package->'activities') as activity_json
      cross join lateral jsonb_array_elements(coalesce(activity_json->'blocks', '[]'::jsonb)) as block
      cross join lateral jsonb_array_elements(coalesce(block->'content'->'options', '[]'::jsonb)) as option
      where publication.status = 'published'
        and publication.hub_code = 'unit-3-cyber-security'
        and activity_json->>'id' = activity.stable_key
        and learning.question_keys_compatible(
          coalesce(block->'content'->>'sourceQuestionId', ''),
          question.stable_key
        )
        and upper(option->>'id') = upper(marking.spec->>'correctOptionId')
    )
) as learned
where marking.question_id = learned.question_id
  and learned.fingerprint is not null
  and not exists (
    select 1
    from learning.question_marking as other
    where other.bound_activity_id = learned.activity_id
      and other.bound_question_key = learned.question_key
      and other.structure_fingerprint = learned.fingerprint
      and other.question_id <> learned.question_id
  );
