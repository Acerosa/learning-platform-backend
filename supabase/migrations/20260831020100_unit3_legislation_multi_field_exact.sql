-- New published version of week6-legislation-matching with shared
-- multi-field-exact specs from the hub source pairs. Does not mutate
-- published 1.0.0 / 1.1.0 rows, learner evidence, or curriculum publication.

begin;

do $apply$
declare
  v_activity_key text := 'week6-legislation-matching';
  v_marking_source text := '1.1.0';
  v_new_version text := '1.2.0';
  v_ns uuid := '8c1b6c04-5ac5-4b36-bd1e-f2f8c2b2a0b1';
  v_activity_id uuid;
  v_source learning.activity_versions%rowtype;
  v_new learning.activity_versions%rowtype;
  v_new_id uuid;
  v_question_id uuid;
  v_week_id uuid;
  v_hash text;
  v_expected_count integer := 6;
  source_question learning.questions%rowtype;
  item jsonb;
  catalogue jsonb := $catalogue$[
    {
      "k": "M1",
      "spec": {
        "mode": "multi-field-exact",
        "requiredFields": ["legislation", "duty"],
        "correctValues": {
          "legislation": "Computer Misuse Act 1990",
          "duty": "Unauthorised access to computer material"
        }
      }
    },
    {
      "k": "M2",
      "spec": {
        "mode": "multi-field-exact",
        "requiredFields": ["legislation", "duty"],
        "correctValues": {
          "legislation": "Current United Kingdom data protection legislation",
          "duty": "Processing personal data without appropriate security or lawful basis"
        }
      }
    },
    {
      "k": "M3",
      "spec": {
        "mode": "multi-field-exact",
        "requiredFields": ["legislation", "duty"],
        "correctValues": {
          "legislation": "Police and Justice Act 2006 amendments (supplying tools for misuse)",
          "duty": "Supplying tools knowing they are likely to be used for computer misuse"
        }
      }
    },
    {
      "k": "M4",
      "spec": {
        "mode": "multi-field-exact",
        "requiredFields": ["legislation", "duty"],
        "correctValues": {
          "legislation": "Computer Misuse Act 1990",
          "duty": "Unauthorised modification of computer material"
        }
      }
    },
    {
      "k": "M5",
      "spec": {
        "mode": "multi-field-exact",
        "requiredFields": ["legislation", "duty"],
        "correctValues": {
          "legislation": "Current United Kingdom data protection legislation",
          "duty": "Handling a personal data breach under current duties"
        }
      }
    },
    {
      "k": "M6",
      "spec": {
        "mode": "multi-field-exact",
        "requiredFields": ["legislation", "duty"],
        "correctValues": {
          "legislation": "Not primarily a criminal statute scenario",
          "duty": "Not primarily a criminal statute scenario"
        }
      }
    }
  ]$catalogue$::jsonb;
begin
  select id into strict v_activity_id
  from learning.activities
  where stable_key = v_activity_key;

  select version.* into v_source
  from learning.activity_versions as version
  where version.activity_id = v_activity_id
    and version.version = v_marking_source;

  if not found or v_source.published_at is null or v_source.retired_at is not null then
    raise exception 'UNIT3_LEGISLATION_1_2_0_CONFLICT: missing published source % %',
      v_activity_key, v_marking_source;
  end if;

  if (
    select count(*)::integer
    from learning.questions
    where activity_version_id = v_source.id
  ) is distinct from v_expected_count then
    raise exception 'UNIT3_LEGISLATION_1_2_0_CONFLICT: % % question count drifted',
      v_activity_key, v_marking_source;
  end if;

  if (
    select count(*)::integer
    from jsonb_array_elements(catalogue) as expected
    join learning.questions as question
      on question.activity_version_id = v_source.id
     and question.stable_key = expected.value->>'k'
  ) is distinct from v_expected_count then
    raise exception 'UNIT3_LEGISLATION_1_2_0_CONFLICT: % % question keys drifted',
      v_activity_key, v_marking_source;
  end if;

  v_new_id := extensions.uuid_generate_v5(
    v_ns,
    'version:' || v_activity_key || ':' || v_new_version
  );
  v_hash := encode(extensions.digest(catalogue::text, 'sha256'), 'hex');

  insert into learning.activity_versions (
    id, activity_id, version, content_hash, max_score, question_count, published_at
  )
  values (
    v_new_id,
    v_activity_id,
    v_new_version,
    v_hash,
    v_source.max_score,
    v_expected_count,
    null
  )
  on conflict (activity_id, version) do nothing;

  select * into strict v_new
  from learning.activity_versions
  where id = v_new_id;

  if v_new.published_at is null then
  for item in
    select value from jsonb_array_elements(catalogue)
  loop
    select * into strict source_question
    from learning.questions
    where activity_version_id = v_source.id
      and stable_key = item->>'k';

    v_question_id := extensions.uuid_generate_v5(
      v_ns,
      'question:' || v_activity_key || ':' || v_new_version || ':' || (item->>'k')
    );

    insert into learning.questions (
      id,
      activity_version_id,
      stable_key,
      section_key,
      section_title,
      question_type,
      analytics_title,
      ordinal,
      max_score,
      authored_difficulty
    )
    values (
      v_question_id,
      v_new.id,
      source_question.stable_key,
      source_question.section_key,
      source_question.section_title,
      source_question.question_type,
      source_question.analytics_title,
      source_question.ordinal,
      source_question.max_score,
      source_question.authored_difficulty
    )
    on conflict (activity_version_id, stable_key) do nothing;

    insert into learning.question_marking (question_id, spec)
    values (v_question_id, item->'spec')
    on conflict (question_id) do nothing;
  end loop;

  update learning.activity_versions
  set max_score = v_source.max_score,
      content_hash = v_hash,
      published_at = '2026-08-31T00:00:00Z'::timestamptz
  where id = v_new.id
    and published_at is null;

  v_week_id := (
    select id
    from learning.curriculum_weeks
    where module_id = (
      select id from learning.modules
      where course_id = (select id from learning.courses where stable_key = 'ocr-level-3-it')
        and stable_key = 'unit-3-cyber-security'
    )
      and stable_key = 'week-6'
  );

  insert into learning.activity_delivery (
    activity_version_id, academic_year_id, curriculum_week_id, week_number, session_number, sort_order, active
  )
  select
    v_new.id,
    academic_year.id,
    v_week_id,
    6,
    coalesce(
      (
        select delivery.session_number
        from learning.activity_delivery as delivery
        where delivery.activity_version_id = v_source.id
        order by delivery.active desc
        limit 1
      ),
      1
    ),
    0,
    true
  from learning.academic_years as academic_year
  where academic_year.active
    and not exists (
      select 1
      from learning.activity_delivery as delivery
      where delivery.activity_version_id = v_new.id
        and delivery.academic_year_id = academic_year.id
        and delivery.group_id is null
    )
  order by academic_year.code
  limit 1;

  insert into learning.activity_assignments (id, group_id, activity_version_id, required, active)
  select
    extensions.uuid_generate_v5(
      v_ns,
      'assignment:CYBER-TEST-A:' || v_activity_key || ':' || v_new_version
    ),
    learner_group.id,
    v_new.id,
    true,
    true
  from learning.groups as learner_group
  where learner_group.code = 'CYBER-TEST-A'
  on conflict (group_id, activity_version_id) do nothing;
  end if;
end;
$apply$;

commit;
