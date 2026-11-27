-- Language-aware Foundations programming marking (no code execution).
-- Restores authoritative hub-bank language variants, marks via attempt language,
-- enriches publications, and strips nested answer keys (lp.strip.v2).

begin;

-- Language-aware Foundations programming marking (no code execution).
-- 1) mode language-variants resolved by attempt programming language
-- 2) restore 25 FOUND specs from authoritative hub banks
-- 3) enrich publications from package language/rules content
-- 4) strip language answer keys from learner packages (lp.strip.v2)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function learning.normalise_marking_output(p_value text, p_case_insensitive boolean)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_case_insensitive then lower(normalised) else normalised end
  from (
    select trim(both E'\n' from regexp_replace(
      regexp_replace(
        regexp_replace(coalesce(p_value, ''), E'\r\n?', E'\n', 'g'),
        E'[ \t]+$', '', 'gm'
      ),
      E'[ \t]+', ' ', 'g'
    )) as normalised
  ) as t;
$$;

revoke all on function learning.normalise_marking_output(text, boolean)
  from public, anon, authenticated;

create or replace function learning.normalise_marking_code(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select trim(both E'\n' from regexp_replace(
    regexp_replace(coalesce(p_value, ''), E'\r\n?', E'\n', 'g'),
    E'[ \t]+$', '', 'gm'
  ));
$$;

revoke all on function learning.normalise_marking_code(text)
  from public, anon, authenticated;

create or replace function learning.language_variant_matches(p_variant jsonb, p_response text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_kind text := coalesce(p_variant->>'kind', '');
  v_case_insensitive boolean := lower(coalesce(p_variant->>'caseInsensitive', 'false')) in ('true', 't', '1');
  v_accepted text;
  v_response text;
  v_rule jsonb;
  v_pattern text;
  v_flags text;
  v_required_ok boolean := true;
  v_has_rules boolean := false;
begin
  if v_kind = 'exact' then
    v_response := learning.normalise_marking_output(p_response, v_case_insensitive);
    for v_accepted in
      select jsonb_array_elements_text(coalesce(p_variant->'accepted', '[]'::jsonb))
    loop
      if v_response = learning.normalise_marking_output(v_accepted, v_case_insensitive) then
        return true;
      end if;
    end loop;
    return false;
  end if;

  if v_kind <> 'code' then
    return false;
  end if;

  v_response := learning.normalise_marking_code(p_response);
  for v_accepted in
    select jsonb_array_elements_text(coalesce(p_variant->'accepted', '[]'::jsonb))
  loop
    if v_response = learning.normalise_marking_code(v_accepted) then
      return true;
    end if;
  end loop;

  for v_rule in select value from jsonb_array_elements(coalesce(p_variant->'required', '[]'::jsonb))
  loop
    v_has_rules := true;
    v_pattern := platform.posix_js_pattern(coalesce(v_rule->>'pattern', ''));
    v_flags := coalesce(v_rule->>'flags', '');
    if v_pattern = '' then
      continue;
    end if;
    if position('i' in v_flags) > 0 then
      if v_response !~* v_pattern then
        v_required_ok := false;
      end if;
    elsif v_response !~ v_pattern then
      v_required_ok := false;
    end if;
  end loop;

  for v_rule in select value from jsonb_array_elements(coalesce(p_variant->'prohibited', '[]'::jsonb))
  loop
    v_has_rules := true;
    v_pattern := platform.posix_js_pattern(coalesce(v_rule->>'pattern', ''));
    v_flags := coalesce(v_rule->>'flags', '');
    if v_pattern = '' then
      continue;
    end if;
    if position('i' in v_flags) > 0 then
      if v_response ~* v_pattern then
        v_required_ok := false;
      end if;
    elsif v_response ~ v_pattern then
      v_required_ok := false;
    end if;
  end loop;

  return v_has_rules and v_required_ok;
end;
$$;

revoke all on function learning.language_variant_matches(jsonb, text)
  from public, anon, authenticated;

create or replace function platform.language_variants_spec_from_content(p_content jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_languages jsonb := p_content->'languages';
  v_source_type text := coalesce(nullif(p_content->>'sourceType', ''), 'code-editor');
  v_variants jsonb := '{}'::jsonb;
  v_lang text;
  v_variant jsonb;
  v_built jsonb;
  v_rules jsonb;
  v_accepted jsonb;
  v_answers jsonb;
  v_answer text;
begin
  if jsonb_typeof(v_languages) = 'object' and v_languages <> '{}'::jsonb then
    for v_lang, v_variant in select key, value from jsonb_each(v_languages)
    loop
      v_rules := coalesce(v_variant->'rules', '{}'::jsonb);
      v_answers := coalesce(v_variant->'answers', '[]'::jsonb);
      v_accepted := coalesce(v_variant->'accepted', '[]'::jsonb);
      v_answer := nullif(v_variant->>'answer', '');

      if v_source_type = 'line-select' and v_answer is not null then
        v_built := jsonb_build_object(
          'kind', 'exact',
          'accepted', jsonb_build_array(v_answer),
          'caseInsensitive', false
        );
      elsif v_source_type in ('predict-output', 'code-gap')
            and jsonb_typeof(v_answers) = 'array'
            and jsonb_array_length(v_answers) > 0 then
        v_built := jsonb_build_object(
          'kind', 'exact',
          'accepted', v_answers,
          'caseInsensitive', lower(coalesce(v_variant->>'caseSensitive', p_content->>'caseSensitive', 'true')) in ('false', 'f', '0')
        );
      elsif coalesce(v_rules->'required', '[]'::jsonb) <> '[]'::jsonb
            or coalesce(v_rules->'prohibited', '[]'::jsonb) <> '[]'::jsonb
            or (jsonb_typeof(v_accepted) = 'array' and jsonb_array_length(v_accepted) > 0) then
        v_built := jsonb_build_object(
          'kind', 'code',
          'accepted', coalesce(v_accepted, '[]'::jsonb),
          'required', coalesce(v_rules->'required', '[]'::jsonb),
          'prohibited', coalesce(v_rules->'prohibited', '[]'::jsonb)
        );
      else
        continue;
      end if;
      v_variants := v_variants || jsonb_build_object(v_lang, v_built);
    end loop;
  else
    -- Shared (non-language) programming item, e.g. SQL
    v_rules := coalesce(p_content->'rules', '{}'::jsonb);
    v_answers := coalesce(p_content->'answers', '[]'::jsonb);
    v_accepted := coalesce(p_content->'accepted', '[]'::jsonb);
    if v_source_type in ('predict-output', 'code-gap', 'line-select')
       and (
         (jsonb_typeof(v_answers) = 'array' and jsonb_array_length(v_answers) > 0)
         or nullif(p_content->>'answer', '') is not null
       ) then
      v_variants := jsonb_build_object(
        '*',
        jsonb_build_object(
          'kind', 'exact',
          'accepted', case
            when jsonb_typeof(v_answers) = 'array' and jsonb_array_length(v_answers) > 0 then v_answers
            else jsonb_build_array(p_content->>'answer')
          end,
          'caseInsensitive', lower(coalesce(p_content->>'caseSensitive', 'true')) in ('false', 'f', '0')
        )
      );
    elsif coalesce(v_rules->'required', '[]'::jsonb) <> '[]'::jsonb
          or coalesce(v_rules->'prohibited', '[]'::jsonb) <> '[]'::jsonb
          or (jsonb_typeof(v_accepted) = 'array' and jsonb_array_length(v_accepted) > 0) then
      v_variants := jsonb_build_object(
        '*',
        jsonb_build_object(
          'kind', 'code',
          'accepted', coalesce(v_accepted, '[]'::jsonb),
          'required', coalesce(v_rules->'required', '[]'::jsonb),
          'prohibited', coalesce(v_rules->'prohibited', '[]'::jsonb)
        )
      );
    end if;
  end if;

  if v_variants = '{}'::jsonb then
    return null;
  end if;

  return jsonb_build_object(
    'mode', 'language-variants',
    'sourceType', v_source_type,
    'variants', v_variants
  );
end;
$$;

revoke all on function platform.language_variants_spec_from_content(jsonb)
  from public, anon, authenticated;


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
  v_lang text;
  v_variant jsonb;
  v_response text;
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


  if v_mode = 'language-variants' then
    v_lang := nullif(btrim(coalesce(
      nullif(current_setting('learning.marking_programming_language', true), ''),
      case when jsonb_typeof(p_payload) = 'object' then p_payload ->> 'programmingLanguage' else null end,
      case when jsonb_typeof(p_payload) = 'object' then p_payload ->> 'programming_language' else null end,
      ''
    )), '');

    v_variant := case
      when v_lang is not null then coalesce(v_spec -> 'variants' -> v_lang, v_spec -> 'variants' -> '*')
      else v_spec -> 'variants' -> '*'
    end;

    if v_variant is null or jsonb_typeof(v_variant) <> 'object' then
      awarded_score := 0;
      is_correct := null;
      requires_review := true;
      return next;
      return;
    end if;

    if jsonb_typeof(p_payload) = 'string' then
      v_response := p_payload #>> '{}';
    elsif jsonb_typeof(p_payload) = 'object' then
      v_response := coalesce(
        p_payload ->> 'sourceCode',
        p_payload ->> 'text',
        p_payload ->> 'value',
        p_payload ->> 'response',
        ''
      );
    else
      v_response := '';
    end if;

    if learning.language_variant_matches(v_variant, v_response) then
      awarded_score := p_max_score;
      is_correct := true;
      requires_review := false;
    else
      awarded_score := 0;
      is_correct := false;
      requires_review := false;
    end if;
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

comment on function learning.mark_evidence_response(uuid, jsonb, numeric) is
  'Server formative marking. Modes: single-choice, classification, python-patterns, ordering-exact, multi-field-exact, language-variants, completion, requires_review. Language-variants select by learning.marking_programming_language or payload language; missing/ambiguous variants fail closed.';



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
  v_language_spec jsonb;
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

  v_language_spec := platform.language_variants_spec_from_content(v_content);
  if v_language_spec is not null then
    return v_language_spec;
  end if;

  return null;
end;
$$;

revoke all on function platform.marking_spec_from_staff_block(jsonb)
  from public, anon, authenticated;

comment on function platform.marking_spec_from_staff_block(jsonb) is
  'Derives a server marking spec from an authoritative staff curriculum block, including language-variants when languages/rules/answers are present. Returns null when the block has no supported automatic answer keys.';



-- ---------------------------------------------------------------------------
-- Restore Foundations language-variant specs from authoritative hub banks
-- ---------------------------------------------------------------------------
do $restore$
declare
  v_specs jsonb := $foundations_specs${"FOUND-PROG-VAR-002":{"mode":"language-variants","sourceType":"predict-output","variants":{"python":{"kind":"exact","accepted":["11"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["11"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["11"],"caseInsensitive":false}}},"FOUND-PROG-VAR-003":{"mode":"language-variants","sourceType":"code-editor","variants":{"python":{"kind":"code","accepted":["score = 10","# Create the variable below\nscore = 10"],"required":[{"pattern":"^\\s*score\\s*=\\s*10\\s*$","flags":"m"}],"prohibited":[]},"javascript":{"kind":"code","accepted":["let score = 10;","const score = 10;"],"required":[{"pattern":"(?:let|const)\\s+score\\s*=\\s*10\\s*;?","flags":"m"}],"prohibited":[]},"csharp":{"kind":"code","accepted":["int score = 10;"],"required":[{"pattern":"int\\s+score\\s*=\\s*10\\s*;","flags":"m"}],"prohibited":[]}}},"FOUND-PROG-VAR-005":{"mode":"language-variants","sourceType":"code-gap","variants":{"python":{"kind":"exact","accepted":["-"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["-"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["-"],"caseInsensitive":false}}},"FOUND-PROG-SEL-002":{"mode":"language-variants","sourceType":"predict-output","variants":{"python":{"kind":"exact","accepted":["Silver"],"caseInsensitive":true},"javascript":{"kind":"exact","accepted":["Silver"],"caseInsensitive":true},"csharp":{"kind":"exact","accepted":["Silver"],"caseInsensitive":true}}},"FOUND-PROG-SEL-003":{"mode":"language-variants","sourceType":"code-gap","variants":{"python":{"kind":"exact","accepted":[">="],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":[">="],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":[">="],"caseInsensitive":false}}},"FOUND-PROG-SEL-004":{"mode":"language-variants","sourceType":"line-select","variants":{"python":{"kind":"exact","accepted":["2"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["2"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["2"],"caseInsensitive":false}}},"FOUND-PROG-SEL-005":{"mode":"language-variants","sourceType":"code-editor","variants":{"python":{"kind":"code","accepted":[],"required":[{"pattern":"if\\s+age\\s*>=\\s*18\\s*:","flags":"m"},{"pattern":"print\\s*\\(\\s*[\"']Adult[\"']\\s*\\)","flags":"m"}],"prohibited":[{"pattern":"age\\s*>\\s*18","flags":"m"}]},"javascript":{"kind":"code","accepted":[],"required":[{"pattern":"if\\s*\\(\\s*age\\s*>=\\s*18\\s*\\)","flags":"m"},{"pattern":"console\\.log\\s*\\(\\s*[\"']Adult[\"']\\s*\\)","flags":"m"}],"prohibited":[{"pattern":"age\\s*>\\s*18","flags":"m"}]},"csharp":{"kind":"code","accepted":[],"required":[{"pattern":"if\\s*\\(\\s*age\\s*>=\\s*18\\s*\\)","flags":"m"},{"pattern":"Console\\.WriteLine\\s*\\(\\s*[\"']Adult[\"']\\s*\\)","flags":"m"}],"prohibited":[{"pattern":"age\\s*>\\s*18","flags":"m"}]}}},"FOUND-PROG-ITER-002":{"mode":"language-variants","sourceType":"predict-output","variants":{"python":{"kind":"exact","accepted":["5","five"],"caseInsensitive":true},"javascript":{"kind":"exact","accepted":["5","five"],"caseInsensitive":true},"csharp":{"kind":"exact","accepted":["5","five"],"caseInsensitive":true}}},"FOUND-PROG-ITER-003":{"mode":"language-variants","sourceType":"code-gap","variants":{"python":{"kind":"exact","accepted":["range(1, 6)","range(1,6)"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["number <= 5","number<=5"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["number <= 5","number<=5"],"caseInsensitive":false}}},"FOUND-PROG-ITER-004":{"mode":"language-variants","sourceType":"line-select","variants":{"python":{"kind":"exact","accepted":["2"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["2"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["2"],"caseInsensitive":false}}},"FOUND-PROG-FUNC-003":{"mode":"language-variants","sourceType":"predict-output","variants":{"python":{"kind":"exact","accepted":["10"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["10"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["10"],"caseInsensitive":false}}},"FOUND-PROG-FUNC-004":{"mode":"language-variants","sourceType":"code-gap","variants":{"python":{"kind":"exact","accepted":["return number * number","return number*number"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["return number * number;","return number * number","return number*number;"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["return number * number;","return number*number;"],"caseInsensitive":false}}},"FOUND-PROG-FUNC-005":{"mode":"language-variants","sourceType":"code-editor","variants":{"python":{"kind":"code","accepted":[],"required":[{"pattern":"def\\s+double_number\\s*\\(\\s*number\\s*\\)\\s*:","flags":"m"},{"pattern":"return\\s+number\\s*\\*\\s*2","flags":"m"}],"prohibited":[]},"javascript":{"kind":"code","accepted":[],"required":[{"pattern":"function\\s+doubleNumber\\s*\\(\\s*number\\s*\\)","flags":"m"},{"pattern":"return\\s+number\\s*\\*\\s*2\\s*;?","flags":"m"}],"prohibited":[]},"csharp":{"kind":"code","accepted":[],"required":[{"pattern":"static\\s+int\\s+DoubleNumber\\s*\\(\\s*int\\s+number\\s*\\)","flags":"m"},{"pattern":"return\\s+number\\s*\\*\\s*2\\s*;","flags":"m"}],"prohibited":[]}}},"FOUND-PROG-LIST-002":{"mode":"language-variants","sourceType":"predict-output","variants":{"python":{"kind":"exact","accepted":["green"],"caseInsensitive":true},"javascript":{"kind":"exact","accepted":["green"],"caseInsensitive":true},"csharp":{"kind":"exact","accepted":["green"],"caseInsensitive":true}}},"FOUND-PROG-LIST-003":{"mode":"language-variants","sourceType":"code-gap","variants":{"python":{"kind":"exact","accepted":["1"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["1"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["1"],"caseInsensitive":false}}},"FOUND-PROG-LIST-004":{"mode":"language-variants","sourceType":"code-editor","variants":{"python":{"kind":"code","accepted":[],"required":[{"pattern":"students\\s*=\\s*\\[\\s*[\"']Aisha[\"']\\s*,\\s*[\"']Ben[\"']\\s*,\\s*[\"']Chloe[\"']\\s*\\]","flags":"m"}],"prohibited":[]},"javascript":{"kind":"code","accepted":[],"required":[{"pattern":"(?:const|let)\\s+students\\s*=\\s*\\[\\s*[\"']Aisha[\"']\\s*,\\s*[\"']Ben[\"']\\s*,\\s*[\"']Chloe[\"']\\s*\\]\\s*;?","flags":"m"}],"prohibited":[]},"csharp":{"kind":"code","accepted":[],"required":[{"pattern":"string\\s*\\[\\s*\\]\\s+students\\s*=\\s*\\{\\s*\"Aisha\"\\s*,\\s*\"Ben\"\\s*,\\s*\"Chloe\"\\s*\\}\\s*;","flags":"m"}],"prohibited":[]}}},"FOUND-PROG-LIST-005":{"mode":"language-variants","sourceType":"line-select","variants":{"python":{"kind":"exact","accepted":["2"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["2"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["2"],"caseInsensitive":false}}},"FOUND-PROG-DEBUG-001":{"mode":"language-variants","sourceType":"line-select","variants":{"python":{"kind":"exact","accepted":["2"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["2"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["2"],"caseInsensitive":false}}},"FOUND-PROG-DEBUG-002":{"mode":"language-variants","sourceType":"code-gap","variants":{"python":{"kind":"exact","accepted":[">="],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":[">="],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":[">="],"caseInsensitive":false}}},"FOUND-PROG-DEBUG-003":{"mode":"language-variants","sourceType":"line-select","variants":{"python":{"kind":"exact","accepted":["2"],"caseInsensitive":false},"javascript":{"kind":"exact","accepted":["2"],"caseInsensitive":false},"csharp":{"kind":"exact","accepted":["2"],"caseInsensitive":false}}},"FOUND-PROG-DEBUG-004":{"mode":"language-variants","sourceType":"code-editor","variants":{"python":{"kind":"code","accepted":[],"required":[{"pattern":"final_total\\s*=\\s*order_total\\s*\\*","flags":"m"}],"prohibited":[{"pattern":"orderTotal","flags":"m"}]},"javascript":{"kind":"code","accepted":[],"required":[{"pattern":"finalTotal\\s*=\\s*orderTotal\\s*\\*","flags":"m"}],"prohibited":[{"pattern":"order_total","flags":"m"}]},"csharp":{"kind":"code","accepted":[],"required":[{"pattern":"finalTotal\\s*=\\s*orderTotal\\s*\\*","flags":"m"}],"prohibited":[{"pattern":"order_total","flags":"m"}]}}},"FOUND-PROG-DEBUG-005":{"mode":"language-variants","sourceType":"code-editor","variants":{"python":{"kind":"code","accepted":[],"required":[{"pattern":"def\\s+rectangle_area\\s*\\(","flags":"m"},{"pattern":"\\n\\s+return\\s+area","flags":"m"}],"prohibited":[]},"javascript":{"kind":"code","accepted":[],"required":[{"pattern":"function\\s+rectangleArea\\s*\\(","flags":"m"},{"pattern":"return\\s+area\\s*;?","flags":"m"}],"prohibited":[]},"csharp":{"kind":"code","accepted":[],"required":[{"pattern":"static\\s+int\\s+RectangleArea\\s*\\(","flags":"m"},{"pattern":"return\\s+area\\s*;","flags":"m"}],"prohibited":[]}}},"FOUND-PROG-SQL-002":{"mode":"language-variants","sourceType":"predict-output","variants":{"*":{"kind":"exact","accepted":["Amina"],"caseInsensitive":true}}},"FOUND-PROG-SQL-003":{"mode":"language-variants","sourceType":"code-gap","variants":{"*":{"kind":"exact","accepted":["WHERE membership_type = 'Premium'","where membership_type = 'Premium'"],"caseInsensitive":true}}},"FOUND-PROG-SQL-005":{"mode":"language-variants","sourceType":"code-editor","variants":{"*":{"kind":"code","accepted":[],"required":[{"pattern":"UPDATE\\s+customers","flags":"i"},{"pattern":"SET\\s+active\\s*=\\s*true","flags":"i"},{"pattern":"WHERE\\s+customer_id\\s*=\\s*['\"]C02['\"]","flags":"i"}],"prohibited":[]}}}}$foundations_specs$::jsonb;
  v_key text;
  v_spec jsonb;
  v_question_id uuid;
  v_activity_id uuid;
  v_fingerprint text;
  v_inserted int := 0;
begin
  alter table learning.question_marking
    disable trigger question_marking_immutable_after_publication;

  begin
    select activity.id into v_activity_id
    from learning.activities as activity
    where activity.stable_key = 'foundations-programming-diagnostic';

    for v_key, v_spec in select key, value from jsonb_each(v_specs)
    loop
      select question.id into v_question_id
      from learning.questions as question
      join learning.activity_versions as activity_version
        on activity_version.id = question.activity_version_id
      where activity_version.activity_id = v_activity_id
        and activity_version.version = '2.0.0'
        and question.stable_key = v_key;

      if v_question_id is null then
        continue;
      end if;

      v_fingerprint := learning.published_question_fingerprint(
        'foundations-programming-diagnostic',
        '2.0.0',
        v_key
      );

      insert into learning.question_marking (
        question_id,
        spec,
        structure_fingerprint,
        bound_activity_id,
        bound_question_key
      ) values (
        v_question_id,
        v_spec,
        v_fingerprint,
        v_activity_id,
        v_key
      )
      on conflict (question_id) do update
        set spec = excluded.spec,
            structure_fingerprint = coalesce(excluded.structure_fingerprint, learning.question_marking.structure_fingerprint),
            bound_activity_id = coalesce(excluded.bound_activity_id, learning.question_marking.bound_activity_id),
            bound_question_key = coalesce(excluded.bound_question_key, learning.question_marking.bound_question_key);

      v_inserted := v_inserted + 1;
    end loop;
  exception
    when others then
      alter table learning.question_marking
        enable trigger question_marking_immutable_after_publication;
      raise;
  end;

  alter table learning.question_marking
    enable trigger question_marking_immutable_after_publication;

  raise notice 'foundations language-variant specs upserted=%', v_inserted;
end;
$restore$;


-- ---------------------------------------------------------------------------
-- Learner package strip: remove language answer material (lp.strip.v2)
-- ---------------------------------------------------------------------------
create or replace function platform.learner_package_sanitisation_version()
returns text
language sql
immutable
set search_path = ''
as $$
  select 'lp.strip.v2'::text;
$$;

revoke all on function platform.learner_package_sanitisation_version()
  from public, anon, authenticated;
grant execute on function platform.learner_package_sanitisation_version()
  to authenticated;

create or replace function platform.strip_learner_answer_keys(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if p_value is null then
    return p_value;
  end if;

  if jsonb_typeof(p_value) = 'array' then
    select coalesce(
      jsonb_agg(platform.strip_learner_answer_keys(value) order by ordinality),
      '[]'::jsonb
    )
    into v_result
    from jsonb_array_elements(p_value) with ordinality as item(value, ordinality);
    return v_result;
  end if;

  if jsonb_typeof(p_value) <> 'object' then
    return p_value;
  end if;

  select coalesce(
    jsonb_object_agg(key, platform.strip_learner_answer_keys(value)),
    '{}'::jsonb
  )
  into v_result
  from jsonb_each(p_value)
  where key not in (
    'correctOptionId',
    'correctCategoryId',
    'correctValues',
    'correctOrder',
    'accepted',
    'checks',
    'rules',
    'answers',
    'modelAnswer',
    'markScheme',
    'answerKey',
    'correctAnswers',
    'correctOption',
    'correctOptions'
  )
  and not (
    key = 'correct'
    and jsonb_typeof(value) in ('boolean', 'object')
  )
  and not (
    key = 'answer'
    and jsonb_typeof(value) in ('string', 'number', 'object', 'array')
  );
  return v_result;
end;
$$;

revoke all on function platform.strip_learner_answer_keys(jsonb)
  from public, anon, authenticated;

comment on function platform.strip_learner_answer_keys(jsonb) is
  'Removes learner-facing answer keys including language-variant answers/rules/accepted and ordering/multi-field keys. Teaching prompts and code scaffolds are preserved.';


-- ---------------------------------------------------------------------------
-- Publish-time enrichment from package language / programming content
-- ---------------------------------------------------------------------------
create or replace function platform.enrich_language_variant_marking_from_package(p_package jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_activity jsonb;
  v_activity_key text;
  v_activity_version text;
  v_block jsonb;
  v_content jsonb;
  v_question_key text;
  v_spec jsonb;
  v_question_id uuid;
  v_activity_id uuid;
  v_fingerprint text;
  v_updated int := 0;
begin
  alter table learning.question_marking
    disable trigger question_marking_immutable_after_publication;

  begin
    for v_activity in
      select value from jsonb_array_elements(coalesce(p_package->'activities', '[]'::jsonb))
    loop
      v_activity_key := v_activity->>'id';
      v_activity_version := v_activity->>'version';

      select activity.id into v_activity_id
      from learning.activities as activity
      where activity.stable_key = v_activity_key;

      if v_activity_id is null then
        continue;
      end if;

      for v_block in
        select value from jsonb_array_elements(coalesce(v_activity->'blocks', '[]'::jsonb))
      loop
        v_content := coalesce(v_block->'content', '{}'::jsonb);
        v_spec := platform.language_variants_spec_from_content(v_content);
        if v_spec is null then
          continue;
        end if;

        v_question_key := coalesce(
          nullif(split_part(coalesce(v_content->>'questionId', ''), ':', 2), ''),
          nullif(v_content->>'sourceQuestionId', ''),
          nullif(v_content->>'questionId', '')
        );
        if v_question_key is null or v_question_key = '' then
          continue;
        end if;
        -- Prefer short key after activity prefix
        if position(':' in coalesce(v_content->>'questionId', '')) > 0 then
          v_question_key := split_part(v_content->>'questionId', ':', 2);
        end if;

        select question.id into v_question_id
        from learning.questions as question
        join learning.activity_versions as activity_version
          on activity_version.id = question.activity_version_id
        where activity_version.activity_id = v_activity_id
          and activity_version.version = v_activity_version
          and question.stable_key = v_question_key;

        if v_question_id is null then
          continue;
        end if;

        v_fingerprint := learning.published_question_fingerprint(
          v_activity_key,
          v_activity_version,
          v_question_key
        );

        insert into learning.question_marking (
          question_id, spec, structure_fingerprint, bound_activity_id, bound_question_key
        ) values (
          v_question_id, v_spec, v_fingerprint, v_activity_id, v_question_key
        )
        on conflict (question_id) do update
          set spec = excluded.spec,
              structure_fingerprint = coalesce(excluded.structure_fingerprint, learning.question_marking.structure_fingerprint),
              bound_activity_id = coalesce(excluded.bound_activity_id, learning.question_marking.bound_activity_id),
              bound_question_key = coalesce(excluded.bound_question_key, learning.question_marking.bound_question_key)
        where coalesce(learning.question_marking.spec->>'mode', '') in ('completion', 'requires_review', 'language-variants')
           or learning.question_marking.spec is null;

        v_updated := v_updated + 1;
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

  raise notice 'language-variant marking enrich touched=%', v_updated;
end;
$$;

revoke all on function platform.enrich_language_variant_marking_from_package(jsonb)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- Session language for submit_attempt marking
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.submit_attempt(p_activity_key text, p_activity_version text, p_client_attempt_id text, p_responses jsonb, p_source_page text DEFAULT NULL::text, p_started_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_completed_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_programming_language text DEFAULT NULL::text)
 RETURNS TABLE(attempt_id uuid, client_attempt_id text, activity_key text, activity_version text, attempt_number integer, score numeric, max_score numeric, marking_source text, evidence_level text, client_started_at timestamp with time zone, client_completed_at timestamp with time zone, source_page text, programming_language text, received_at timestamp with time zone, idempotent boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $submit_attempt$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_student_id uuid;
  v_enrolment_id uuid;
  v_matching_assignment_count integer;
  v_activity_version_id uuid;
  v_assignment_id uuid;
  v_question_count integer;
  v_activity_max_score numeric(8,2);
  v_programming_language_id uuid;
  v_declared_language_count integer;
  v_attempt_id uuid;
  v_attempt_number integer;
  v_submission_hash text;
  v_existing learning.attempts%rowtype;
  v_item jsonb;
  v_question learning.questions%rowtype;
  v_question_key text;
  v_awarded_score numeric(8,2);
  v_is_correct boolean;
  v_requires_review boolean;
  v_has_score boolean;
  v_has_correct boolean;
  v_marking_source text;
  v_item_source text;
  v_marked jsonb := '[]'::jsonb;
  v_mark jsonb;
  v_total_score numeric(8,2) := 0;
  v_received_at timestamptz;
  v_source_page text;
begin
  v_auth_user_id := auth.uid();
  v_received_at := clock_timestamp();
  v_source_page := nullif(btrim(p_source_page), '');

  if v_auth_user_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if p_activity_key is null or btrim(p_activity_key) = ''
     or p_activity_version is null or btrim(p_activity_version) = '' then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_VERSION';
  end if;

  if p_client_attempt_id is null
     or length(p_client_attempt_id) not between 1 and 128
     or p_client_attempt_id !~ '^[A-Za-z0-9._:-]+$' then
    raise exception using errcode = '22023', message = 'INVALID_CLIENT_ATTEMPT_ID';
  end if;

  if p_responses is null
     or jsonb_typeof(p_responses) <> 'array'
     or jsonb_array_length(p_responses) = 0
     or octet_length(p_responses::text) > 131072 then
    raise exception using errcode = '22023', message = 'INVALID_RESPONSES';
  end if;

  if (p_started_at is null) <> (p_completed_at is null)
     or (
       p_started_at is not null
       and (
         p_completed_at < p_started_at
         or p_completed_at - p_started_at > interval '30 days'
         or p_started_at > v_received_at + interval '5 minutes'
         or p_completed_at > v_received_at + interval '5 minutes'
       )
     ) then
    raise exception using errcode = '22023', message = 'INVALID_CLIENT_TIMESTAMPS';
  end if;

  if v_source_page is not null
     and (
       length(v_source_page) > 300
       or v_source_page !~ '^/'
       or v_source_page ~ '[[:cntrl:]]'
     ) then
    raise exception using errcode = '22023', message = 'INVALID_SOURCE_PAGE';
  end if;

  select student.id
  into v_student_id
  from learning.students as student
  where student.auth_user_id = v_auth_user_id
    and student.active;

  if v_student_id is null then
    raise exception using errcode = '28000', message = 'STUDENT_IDENTITY_NOT_FOUND';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_student_id::text, 0)
  );

  v_submission_hash := encode(
    extensions.digest(
      pg_catalog.convert_to(
        jsonb_build_object(
          'activity_key', p_activity_key,
          'activity_version', p_activity_version,
          'responses', p_responses,
          'source_page', v_source_page,
          'started_at', p_started_at,
          'completed_at', p_completed_at,
          'programming_language', p_programming_language
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select attempt.*
  into v_existing
  from learning.attempts as attempt
  where attempt.student_id = v_student_id
    and attempt.client_attempt_id = p_client_attempt_id;

  if found then
    if v_existing.submission_hash <> v_submission_hash then
      raise exception using errcode = '23505', message = 'CLIENT_ATTEMPT_ID_CONFLICT';
    end if;

    return query
    select
      attempt.id,
      attempt.client_attempt_id,
      activity.stable_key,
      version.version,
      attempt.attempt_number,
      attempt.score,
      attempt.max_score,
      attempt.marking_source,
      attempt.evidence_level,
      attempt.client_started_at,
      attempt.client_completed_at,
      attempt.source_page,
      coding_language.stable_key,
      attempt.received_at,
      true
    from learning.attempts as attempt
    join learning.activity_versions as version
      on version.id = attempt.activity_version_id
    join learning.activities as activity on activity.id = version.activity_id
    left join learning.coding_languages as coding_language
      on coding_language.id = attempt.programming_language_id
    where attempt.id = v_existing.id;
    return;
  end if;

  select version.id, version.question_count, version.max_score
  into v_activity_version_id, v_question_count, v_activity_max_score
  from learning.activity_versions as version
  join learning.activities as activity on activity.id = version.activity_id
  where activity.stable_key = p_activity_key
    and activity.active
    and version.version = p_activity_version
    and version.published_at is not null
    and version.retired_at is null;

  if v_activity_version_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_VERSION';
  end if;

  select count(*)
  into v_declared_language_count
  from learning.activity_version_languages as version_language
  where version_language.activity_version_id = v_activity_version_id;

  if v_declared_language_count = 0 and p_programming_language is not null then
    raise exception using errcode = '22023', message = 'PROGRAMMING_LANGUAGE_NOT_APPLICABLE';
  end if;

  if v_declared_language_count > 0 then
    if p_programming_language is null or btrim(p_programming_language) = '' then
      raise exception using errcode = '22023', message = 'PROGRAMMING_LANGUAGE_REQUIRED';
    end if;

    select coding_language.id
    into v_programming_language_id
    from learning.activity_version_languages as version_language
    join learning.coding_languages as coding_language
      on coding_language.id = version_language.coding_language_id
     and coding_language.active
    where version_language.activity_version_id = v_activity_version_id
      and coding_language.stable_key = p_programming_language;

    if v_programming_language_id is null then
      raise exception using errcode = '22023', message = 'INVALID_PROGRAMMING_LANGUAGE';
    end if;
  end if;

  perform pg_catalog.set_config(
    'learning.marking_programming_language',
    coalesce(nullif(btrim(p_programming_language), ''), ''),
    true
  );

  select count(*)
  into v_matching_assignment_count
  from learning.enrolments as enrolment
  join learning.groups as learner_group
    on learner_group.id = enrolment.group_id
   and learner_group.active
  join learning.activity_assignments as assignment
    on assignment.group_id = enrolment.group_id
   and assignment.activity_version_id = v_activity_version_id
   and assignment.active
   and (assignment.opens_at is null or assignment.opens_at <= v_received_at)
   and (assignment.due_at is null or assignment.due_at >= v_received_at)
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  if v_matching_assignment_count = 0 then
    raise exception using errcode = '42501', message = 'ACTIVITY_NOT_ASSIGNED';
  end if;

  if v_matching_assignment_count > 1 then
    raise exception using errcode = '23514', message = 'ACTIVITY_ASSIGNMENT_AMBIGUOUS';
  end if;

  select enrolment.id, assignment.id
  into v_enrolment_id, v_assignment_id
  from learning.enrolments as enrolment
  join learning.groups as learner_group
    on learner_group.id = enrolment.group_id
   and learner_group.active
  join learning.activity_assignments as assignment
    on assignment.group_id = enrolment.group_id
   and assignment.activity_version_id = v_activity_version_id
   and assignment.active
   and (assignment.opens_at is null or assignment.opens_at <= v_received_at)
   and (assignment.due_at is null or assignment.due_at >= v_received_at)
  where enrolment.student_id = v_student_id
    and enrolment.status = 'active';

  p_responses := learning.prepare_timed_knowledge_report_submission(
    v_student_id,
    v_activity_version_id,
    p_responses
  );

  if jsonb_array_length(p_responses) <> v_question_count then
    raise exception using errcode = '22023', message = 'INCOMPLETE_RESPONSE_SET';
  end if;

  if (
    select count(distinct item ->> 'question_id')
    from jsonb_array_elements(p_responses) as response_item(item)
  ) <> v_question_count then
    raise exception using errcode = '22023', message = 'DUPLICATE_OR_MISSING_QUESTION';
  end if;

  for v_item in select value from jsonb_array_elements(p_responses)
  loop
    v_has_score := (v_item ? 'awarded_score');
    v_has_correct := (v_item ? 'is_correct');

    if jsonb_typeof(v_item) <> 'object'
       or jsonb_typeof(v_item -> 'question_id') <> 'string'
       or not (v_item ? 'response_payload')
       or v_item -> 'response_payload' = 'null'::jsonb
       or jsonb_typeof(v_item -> 'response_payload')
          not in ('string', 'array', 'object')
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'string'
         and btrim(v_item ->> 'response_payload') = ''
       )
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'array'
         and jsonb_array_length(v_item -> 'response_payload') = 0
       )
       or (
         jsonb_typeof(v_item -> 'response_payload') = 'object'
         and v_item -> 'response_payload' = '{}'::jsonb
       )
       or v_has_score <> v_has_correct
       or (
         v_has_score
         and (
           jsonb_typeof(v_item -> 'awarded_score') <> 'number'
           or jsonb_typeof(v_item -> 'is_correct') <> 'boolean'
         )
       )
       or octet_length((v_item -> 'response_payload')::text) > 131072 then
      raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
    end if;

    v_question_key := v_item ->> 'question_id';

    select question.*
    into v_question
    from learning.questions as question
    where question.activity_version_id = v_activity_version_id
      and question.stable_key = v_question_key;

    if not found then
      if exists (
        select 1 from learning.questions as other_question
        where other_question.stable_key = v_question_key
      ) then
        raise exception using
          errcode = '23514',
          message = 'QUESTION_WRONG_ACTIVITY_VERSION';
      end if;
      raise exception using errcode = '22023', message = 'UNKNOWN_QUESTION';
    end if;

    v_awarded_score := null;
    v_is_correct := null;
    if v_has_score then
      begin
        v_awarded_score := (v_item ->> 'awarded_score')::numeric(8,2);
        v_is_correct := (v_item ->> 'is_correct')::boolean;
      exception when others then
        raise exception using errcode = '22023', message = 'INVALID_RESPONSE_ITEM';
      end;
    end if;

    select
      mark.awarded_score,
      mark.is_correct,
      mark.requires_review,
      mark.marking_source
    into
      v_awarded_score,
      v_is_correct,
      v_requires_review,
      v_item_source
    from learning.score_submitted_item(
      v_question.id,
      v_question.max_score,
      v_item -> 'response_payload',
      v_has_score,
      v_awarded_score,
      v_is_correct
    ) as mark;

    if v_marking_source is null then
      v_marking_source := v_item_source;
    elsif v_marking_source <> v_item_source then
      v_marking_source := 'server';
    end if;

    v_total_score := v_total_score + v_awarded_score;
    v_marked := v_marked || jsonb_build_array(
      jsonb_strip_nulls(
        jsonb_build_object(
          'question_id', v_question.id,
          'payload', v_item -> 'response_payload',
          'awarded_score', v_awarded_score,
          'is_correct', v_is_correct,
          'requires_review', v_requires_review,
          'marking_source', v_item_source
        )
      )
    );
  end loop;

  if v_total_score > v_activity_max_score then
    raise exception using
      errcode = '23514',
      message = 'ATTEMPT_SCORE_EXCEEDS_ACTIVITY_MAXIMUM';
  end if;

  select coalesce(max(attempt.attempt_number), 0) + 1
  into v_attempt_number
  from learning.attempts as attempt
  where attempt.student_id = v_student_id
    and attempt.assignment_id = v_assignment_id;

  v_attempt_id := gen_random_uuid();

  insert into learning.attempts (
    id,
    client_attempt_id,
    student_id,
    enrolment_id,
    assignment_id,
    activity_version_id,
    attempt_number,
    status,
    score,
    max_score,
    marking_source,
    evidence_level,
    source_system,
    submission_hash,
    client_started_at,
    client_completed_at,
    source_page,
    programming_language_id,
    received_at,
    completed_at
  ) values (
    v_attempt_id,
    p_client_attempt_id,
    v_student_id,
    v_enrolment_id,
    v_assignment_id,
    v_activity_version_id,
    v_attempt_number,
    'completed',
    v_total_score,
    v_activity_max_score,
    v_marking_source,
    'question_level',
    'supabase',
    v_submission_hash,
    p_started_at,
    p_completed_at,
    v_source_page,
    v_programming_language_id,
    v_received_at,
    v_received_at
  );

  for v_mark in select value from jsonb_array_elements(v_marked)
  loop
    insert into learning.responses (
      attempt_id,
      question_id,
      response_payload,
      awarded_score,
      max_score,
      is_correct,
      requires_review,
      marking_source,
      marked_at
    )
    select
      v_attempt_id,
      (v_mark ->> 'question_id')::uuid,
      v_mark -> 'payload',
      (v_mark ->> 'awarded_score')::numeric(8,2),
      question.max_score,
      case
        when v_mark ? 'is_correct' then (v_mark ->> 'is_correct')::boolean
        else null
      end,
      coalesce((v_mark ->> 'requires_review')::boolean, true),
      v_mark ->> 'marking_source',
      v_received_at
    from learning.questions as question
    where question.id = (v_mark ->> 'question_id')::uuid;
  end loop;

  return query
  select
    attempt.id,
    attempt.client_attempt_id,
    activity.stable_key,
    version.version,
    attempt.attempt_number,
    attempt.score,
    attempt.max_score,
    attempt.marking_source,
    attempt.evidence_level,
    attempt.client_started_at,
    attempt.client_completed_at,
    attempt.source_page,
    coding_language.stable_key,
    attempt.received_at,
    false
  from learning.attempts as attempt
  join learning.activity_versions as version
    on version.id = attempt.activity_version_id
  join learning.activities as activity on activity.id = version.activity_id
  left join learning.coding_languages as coding_language
    on coding_language.id = attempt.programming_language_id
  where attempt.id = v_attempt_id;
end
$submit_attempt$;

-- ---------------------------------------------------------------------------
-- Publish: enrich language variants before coverage assert
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION platform.publish_curriculum(p_lifecycle_status text, p_hub_code text, p_course_key text, p_package_version text, p_schema_version text, p_source_package_version text, p_package jsonb, p_author text, p_reviewer text, p_publication_notes text)
 RETURNS TABLE(id uuid, hub_code text, course_key text, package_version text, status text, published_at timestamp with time zone, idempotent boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $publish_curriculum$
#variable_conflict use_column
declare
  v_auth_user_id uuid;
  v_teacher learning.teachers%rowtype;
  v_hub_code text;
  v_course_key text;
  v_package_version text;
  v_schema_version text;
  v_source_package_version text;
  v_lifecycle_status text;
  v_author text;
  v_reviewer text;
  v_notes text;
  v_hash text;
  v_existing platform.curriculum_publications%rowtype;
  v_latest text;
  v_publication platform.curriculum_publications%rowtype;
  v_learner_package jsonb;
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
    raise exception using errcode = '28000', message = 'PUBLICATION_NOT_AUTHORISED';
  end if;

  v_lifecycle_status := lower(nullif(btrim(p_lifecycle_status), ''));
  if v_lifecycle_status is null
     or v_lifecycle_status not in ('approved', 'published') then
    raise exception using errcode = '22023', message = 'PUBLICATION_STATUS_INVALID';
  end if;

  v_hub_code := lower(nullif(btrim(p_hub_code), ''));
  v_course_key := lower(nullif(btrim(p_course_key), ''));
  v_package_version := nullif(btrim(p_package_version), '');
  v_schema_version := nullif(btrim(p_schema_version), '');
  v_source_package_version := nullif(btrim(p_source_package_version), '');
  v_author := nullif(btrim(p_author), '');
  v_reviewer := coalesce(btrim(p_reviewer), '');
  v_notes := coalesce(btrim(p_publication_notes), '');

  if v_hub_code is null
     or v_course_key is null
     or v_package_version is null
     or v_package_version !~ '^[0-9]+\.[0-9]+\.[0-9]+$'
     or v_author is null then
    raise exception using errcode = '22023', message = 'PUBLICATION_VALIDATION_FAILED';
  end if;

  if v_schema_version is distinct from '0.1.0' then
    raise exception using errcode = '22023', message = 'UNSUPPORTED_SCHEMA_VERSION';
  end if;

  if v_source_package_version is distinct from '0.1.0' then
    raise exception using errcode = '22023', message = 'UNSUPPORTED_PACKAGE_VERSION';
  end if;

  perform platform.validate_curriculum_package(p_package);

  if p_package->'hub'->>'id' is distinct from v_hub_code
     or p_package->'curriculum'->'metadata'->>'course' is distinct from v_course_key then
    raise exception using errcode = '22023', message = 'PUBLICATION_CONTEXT_MISMATCH';
  end if;

  if not exists (
    select 1
    from platform.hubs as hub
    where hub.hub_code = v_hub_code
      and hub.active
  ) then
    raise exception using errcode = '22023', message = 'HUB_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from learning.courses as course
    where course.stable_key = v_course_key
  ) then
    raise exception using errcode = '22023', message = 'COURSE_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from platform.hub_course_links as link
    join platform.hubs as hub on hub.id = link.hub_id
    join learning.courses as course on course.id = link.course_id
    where hub.hub_code = v_hub_code
      and course.stable_key = v_course_key
      and link.active
  ) then
    raise exception using errcode = '22023', message = 'PUBLICATION_CONTEXT_MISMATCH';
  end if;

  v_hash := encode(extensions.digest(p_package::text, 'sha256'), 'hex');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('curriculum-publication:' || v_hub_code || ':' || v_course_key, 0)
  );

  select publication.*
  into v_existing
  from platform.curriculum_publications as publication
  where publication.hub_code = v_hub_code
    and publication.course_key = v_course_key
    and publication.package_version = v_package_version
  for update;

  if found then
    if v_existing.content_hash = v_hash then
      perform platform.project_current_curriculum_catalogue(v_hub_code, v_course_key);
      return query
      select
        v_existing.id,
        v_existing.hub_code,
        v_existing.course_key,
        v_existing.package_version,
        v_existing.status,
        v_existing.published_at,
        true;
      return;
    end if;

    raise exception using errcode = '22023', message = 'DUPLICATE_VERSION';
  end if;

  select publication.package_version
  into v_latest
  from platform.curriculum_publications as publication
  where publication.hub_code = v_hub_code
    and publication.course_key = v_course_key
  order by string_to_array(publication.package_version, '.')::int[] desc
  limit 1;

  if v_latest is not null
     and string_to_array(v_package_version, '.')::int[] <= string_to_array(v_latest, '.')::int[] then
    raise exception using errcode = '22023', message = 'PUBLICATION_VERSION_REGRESSION';
  end if;

  update platform.curriculum_publications
  set status = 'superseded'
  where hub_code = v_hub_code
    and course_key = v_course_key
    and status = 'published';

  v_learner_package := platform.learner_curriculum_package(
    p_package,
    v_package_version,
    v_source_package_version
  );
  if v_learner_package is null or jsonb_typeof(v_learner_package) <> 'object' then
    raise exception using errcode = '22023', message = 'LEARNER_PACKAGE_GENERATION_FAILED';
  end if;

  insert into platform.curriculum_publications (
    hub_code,
    course_key,
    package_version,
    schema_version,
    source_package_version,
    status,
    package,
    learner_package,
    learner_package_sanitisation_version,
    content_hash,
    author,
    reviewer,
    publication_notes,
    published_by_auth_user_id,
    published_by_staff_reference
  ) values (
    v_hub_code,
    v_course_key,
    v_package_version,
    v_schema_version,
    v_source_package_version,
    'published',
    p_package,
    v_learner_package,
    platform.learner_package_sanitisation_version(),
    v_hash,
    v_author,
    v_reviewer,
    v_notes,
    v_auth_user_id,
    v_teacher.staff_reference
  )
  returning * into v_publication;

  insert into platform.audit_events (
    event_key,
    actor_auth_user_id,
    actor_type,
    entity_type,
    entity_key,
    outcome,
    context
  ) values (
    'curriculum.publication.published',
    v_auth_user_id,
    'staff',
    'curriculum-publication',
    v_publication.id::text,
    'succeeded',
    jsonb_build_object(
      'hubCode', v_hub_code,
      'courseKey', v_course_key,
      'version', v_package_version,
      'schemaVersion', v_schema_version,
      'packageVersion', v_source_package_version,
      'author', v_author,
      'reviewer', v_reviewer,
      'publishedBy', v_teacher.staff_reference,
      'notes', v_notes
    )
  );

  perform platform.project_curriculum_package(
    p_package,
    v_hub_code,
    v_course_key,
    v_package_version,
    v_publication.id
  );

  -- Enrich language-variant specs from staff package content before coverage
  -- validation so Foundations programming items are not left as completion gaps.
  perform platform.enrich_language_variant_marking_from_package(p_package);

  -- After catalogue projection/registration, require resolvable marking for
  -- every package question. Failure rolls back this publish transaction.
  perform platform.assert_package_marking_coverage(p_package);

  return query
  select
    v_publication.id,
    v_publication.hub_code,
    v_publication.course_key,
    v_publication.package_version,
    v_publication.status,
    v_publication.published_at,
    false;
end;
$publish_curriculum$;


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

create or replace view admin_api.published_marking_coverage_summary
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
  coalesce(
    (
      select marking.spec->>'mode'
      from learning.question_marking as marking
      where marking.question_id = learning.resolve_marking_question(question.id)
    ),
    'unresolved'
  ) as marking_mode,
  exists (
    select 1
    from learning.question_marking as marking
    where marking.question_id = learning.resolve_marking_question(question.id)
      and coalesce(marking.spec->>'mode', '') = 'language-variants'
      and coalesce(marking.spec->'variants', '{}'::jsonb) <> '{}'::jsonb
  ) as has_language_variants,
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
  and (select platform.current_staff_has_any_role(
    array['platform_admin', 'curriculum_admin', 'operations', 'auditor']
  ));

revoke all on admin_api.published_marking_coverage_summary
  from public, anon, authenticated;
grant select on admin_api.published_marking_coverage_summary to authenticated;

comment on view admin_api.published_marking_coverage_summary is
  'Staff diagnostic of published question marking modes including language-variants. Does not expose answer keys or variant accepted values.';



do $assert$
declare
  v_remaining int;
  v_lang int;
  v_sample text;
  v_target text[] := array['FOUND-PROG-DEBUG-001', 'FOUND-PROG-DEBUG-002', 'FOUND-PROG-DEBUG-003', 'FOUND-PROG-DEBUG-004', 'FOUND-PROG-DEBUG-005', 'FOUND-PROG-FUNC-003', 'FOUND-PROG-FUNC-004', 'FOUND-PROG-FUNC-005', 'FOUND-PROG-ITER-002', 'FOUND-PROG-ITER-003', 'FOUND-PROG-ITER-004', 'FOUND-PROG-LIST-002', 'FOUND-PROG-LIST-003', 'FOUND-PROG-LIST-004', 'FOUND-PROG-LIST-005', 'FOUND-PROG-SEL-002', 'FOUND-PROG-SEL-003', 'FOUND-PROG-SEL-004', 'FOUND-PROG-SEL-005', 'FOUND-PROG-SQL-002', 'FOUND-PROG-SQL-003', 'FOUND-PROG-SQL-005', 'FOUND-PROG-VAR-002', 'FOUND-PROG-VAR-003', 'FOUND-PROG-VAR-005'];
begin
  select count(*)::integer,
         string_agg(question.stable_key, ', ' order by question.stable_key)
  into v_remaining, v_sample
  from learning.activities as activity
  join learning.activity_versions as activity_version
    on activity_version.activity_id = activity.id
   and activity_version.version = '2.0.0'
  join learning.questions as question
    on question.activity_version_id = activity_version.id
  where activity.stable_key = 'foundations-programming-diagnostic'
    and question.stable_key = any (v_target)
    and learning.resolve_marking_question(question.id) is null;

  if coalesce(v_remaining, 0) <> 0 then
    raise exception
      'foundations language-aware restore left % unresolved target questions sample=%',
      v_remaining,
      left(coalesce(v_sample, ''), 300);
  end if;

  select count(*) into v_lang
  from learning.question_marking as marking
  join learning.questions as question on question.id = marking.question_id
  join learning.activity_versions as activity_version
    on activity_version.id = question.activity_version_id
  join learning.activities as activity
    on activity.id = activity_version.activity_id
  where activity.stable_key = 'foundations-programming-diagnostic'
    and activity_version.version = '2.0.0'
    and question.stable_key = any (v_target)
    and marking.spec->>'mode' = 'language-variants';

  if coalesce(v_lang, 0) < 25 then
    raise exception 'expected at least 25 language-variants specs, found %', v_lang;
  end if;
end;
$assert$;


commit;
