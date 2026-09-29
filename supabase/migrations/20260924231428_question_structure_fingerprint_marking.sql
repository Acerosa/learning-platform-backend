create or replace function learning.mark_evidence_response(
  p_question_id uuid,
  p_payload jsonb,
  p_max_score numeric
)
returns table (
  awarded_score numeric(8,2),
  is_correct boolean,
  requires_review boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_spec jsonb;
  v_mode text;
  v_source text;
  v_pattern text;
  v_ok boolean;
  v_option text;
  v_category text;
  v_fields jsonb;
  v_field text;
  v_item jsonb;
  v_expected text;
  v_actual text;
  v_malformed boolean;
  v_case_insensitive boolean;
  v_mark_question_id uuid;
begin
  v_mark_question_id := learning.resolve_marking_question(p_question_id);

  if v_mark_question_id is null then
    awarded_score := 0;
    is_correct := null;
    requires_review := true;
    return next;
    return;
  end if;

  select marking.spec
  into v_spec
  from learning.question_marking as marking
  where marking.question_id = v_mark_question_id;

  v_mode := coalesce(v_spec ->> 'mode', 'completion');
  v_option := coalesce(
    nullif(p_payload ->> 'optionId', ''),
    nullif(p_payload ->> 'selectedOptionId', ''),
    nullif(p_payload ->> 'option_id', ''),
    nullif(p_payload ->> 'selected_option_id', '')
  );
  v_category := coalesce(
    nullif(p_payload ->> 'categoryId', ''),
    nullif(p_payload ->> 'category', ''),
    nullif(p_payload ->> 'category_id', '')
  );

  if v_mode = 'single-choice' then
    v_ok := coalesce(v_option, '') = coalesce(v_spec ->> 'correctOptionId', '');
    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    requires_review := false;
    return next;
    return;
  end if;

  if v_mode = 'classification' then
    v_ok := coalesce(v_category, '') = coalesce(v_spec ->> 'correctCategoryId', '');
    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    requires_review := false;
    return next;
    return;
  end if;

  if v_mode = 'python-patterns' then
    v_source := coalesce(p_payload ->> 'sourceCode', '');
    v_ok := true;
    for v_pattern in
      select jsonb_array_elements_text(coalesce(v_spec -> 'required', '[]'::jsonb))
    loop
      if v_source !~ v_pattern then
        v_ok := false;
      end if;
    end loop;
    for v_pattern in
      select jsonb_array_elements_text(coalesce(v_spec -> 'prohibited', '[]'::jsonb))
    loop
      if v_source ~ v_pattern then
        v_ok := false;
      end if;
    end loop;
    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    requires_review := false;
    return next;
    return;
  end if;

  if v_mode = 'ordering-exact' then
    if jsonb_typeof(coalesce(v_spec -> 'correctOrder', 'null'::jsonb))
         is distinct from 'array'
       or jsonb_array_length(coalesce(v_spec -> 'correctOrder', '[]'::jsonb)) = 0 then
      awarded_score := 0;
      is_correct := null;
      requires_review := true;
      return next;
      return;
    end if;

    if jsonb_typeof(coalesce(p_payload -> 'itemIds', 'null'::jsonb))
         is distinct from 'array' then
      awarded_score := 0;
      is_correct := false;
      requires_review := false;
      return next;
      return;
    end if;

    if jsonb_array_length(p_payload -> 'itemIds')
         is distinct from jsonb_array_length(v_spec -> 'correctOrder') then
      awarded_score := 0;
      is_correct := false;
      requires_review := false;
      return next;
      return;
    end if;

    v_ok := (
      select bool_and(coalesce(actual.val, '') = coalesce(expected.val, ''))
      from jsonb_array_elements_text(v_spec -> 'correctOrder')
           with ordinality as expected(val, ord)
      left join jsonb_array_elements_text(p_payload -> 'itemIds')
           with ordinality as actual(val, ord)
        on actual.ord = expected.ord
    );

    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    requires_review := false;
    return next;
    return;
  end if;

  if v_mode = 'multi-field-exact' then
    if jsonb_typeof(coalesce(v_spec -> 'correctValues', 'null'::jsonb))
         is distinct from 'object'
       or coalesce(v_spec -> 'correctValues', '{}'::jsonb) = '{}'::jsonb then
      awarded_score := 0;
      is_correct := null;
      requires_review := true;
      return next;
      return;
    end if;

    if jsonb_typeof(v_spec -> 'requiredFields') = 'array' then
      v_fields := v_spec -> 'requiredFields';
    else
      select coalesce(jsonb_agg(key), '[]'::jsonb)
      into v_fields
      from jsonb_object_keys(v_spec -> 'correctValues') as key;
    end if;

    if jsonb_typeof(v_fields) is distinct from 'array'
       or jsonb_array_length(v_fields) = 0 then
      awarded_score := 0;
      is_correct := null;
      requires_review := true;
      return next;
      return;
    end if;

    v_malformed := false;
    for v_item in
      select value from jsonb_array_elements(v_fields)
    loop
      if jsonb_typeof(v_item) is distinct from 'string' then
        v_malformed := true;
        exit;
      end if;
      v_field := btrim(v_item #>> '{}');
      if v_field = '' then
        v_malformed := true;
        exit;
      end if;
      if jsonb_typeof(v_spec -> 'correctValues' -> v_field) is null then
        v_malformed := true;
        exit;
      end if;
      v_expected := btrim(coalesce(v_spec -> 'correctValues' ->> v_field, ''));
      if v_expected = '' then
        v_malformed := true;
        exit;
      end if;
    end loop;

    if v_malformed then
      awarded_score := 0;
      is_correct := null;
      requires_review := true;
      return next;
      return;
    end if;

    if jsonb_typeof(p_payload) is distinct from 'object' then
      awarded_score := 0;
      is_correct := false;
      requires_review := false;
      return next;
      return;
    end if;

    v_case_insensitive :=
      lower(coalesce(v_spec ->> 'caseInsensitive', 'false')) in ('true', 't', '1');
    v_ok := true;
    for v_item in
      select value from jsonb_array_elements(v_fields)
    loop
      v_field := btrim(v_item #>> '{}');
      v_expected := btrim(v_spec -> 'correctValues' ->> v_field);
      v_actual := btrim(coalesce(p_payload ->> v_field, ''));
      if v_case_insensitive then
        if lower(v_actual) is distinct from lower(v_expected) then
          v_ok := false;
          exit;
        end if;
      elsif v_actual is distinct from v_expected then
        v_ok := false;
        exit;
      end if;
    end loop;

    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    requires_review := false;
    return next;
    return;
  end if;

  if v_mode in ('completion', 'requires_review') then
    awarded_score := 0;
    is_correct := null;
    requires_review := true;
    return next;
    return;
  end if;

  awarded_score := 0;
  is_correct := null;
  requires_review := true;
  return next;
end;
$$;

revoke all on function learning.mark_evidence_response(uuid, jsonb, numeric)
  from public, anon, authenticated;

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
  join learning.modules as module
    on module.id = activity.module_id
   and module.stable_key = 'unit-3-cyber-security'
  join lateral (
    select activity_json->>'version' as package_version, activity_json as body
    from platform.curriculum_publications as publication
    cross join lateral jsonb_array_elements(publication.package->'activities') as activity_json
    where publication.status = 'published'
      and publication.hub_code = 'unit-3-cyber-security'
      and activity_json->>'id' = activity.stable_key
    order by publication.published_at desc
    limit 1
  ) as published on true
  where marking.structure_fingerprint is null
    and marking.spec->>'mode' = 'single-choice'
    and exists (
      select 1
      from jsonb_array_elements(coalesce(published.body->'blocks', '[]'::jsonb)) as block
      cross join lateral jsonb_array_elements(coalesce(block->'content'->'options', '[]'::jsonb)) as option
      where upper(btrim(coalesce(block->'content'->>'sourceQuestionId', ''))) = upper(question.stable_key)
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
