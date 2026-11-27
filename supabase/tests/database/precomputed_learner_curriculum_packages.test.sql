-- Phase B: precomputed learner packages at publication time.

begin;
select plan(31);

select has_column(
  'platform',
  'curriculum_publications',
  'learner_package',
  'learner_package column exists'
);

select has_column(
  'platform',
  'curriculum_publications',
  'learner_package_sanitisation_version',
  'learner_package_sanitisation_version column exists'
);

select is(
  platform.learner_package_sanitisation_version(),
  'lp.strip.v1',
  'sanitisation version constant is stable'
);

select ok(
  not exists (
    select 1
    from platform.curriculum_publications
    where learner_package is null
       or learner_package_sanitisation_version
         is distinct from platform.learner_package_sanitisation_version()
  ),
  'all publications have a current learner_package after backfill'
);

select ok(
  (
    select bool_and(
      publication.learner_package
        = platform.learner_curriculum_package(
            publication.package,
            publication.package_version,
            publication.source_package_version
          )
    )
    from platform.curriculum_publications as publication
  ),
  'stored learner packages match Phase A generation for every publication'
);

create or replace function pg_temp.has_protected_keys(p jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p is null then false
    when jsonb_typeof(p) = 'array' then
      exists (
        select 1
        from jsonb_array_elements(p) as element(value)
        where pg_temp.has_protected_keys(element.value)
      )
    when jsonb_typeof(p) = 'object' then
      (
        p ?| array[
          'correctOptionId',
          'correctCategoryId',
          'correctValues',
          'correctOrder',
          'accepted',
          'checks',
          'modelAnswer',
          'markScheme',
          'answerKey',
          'correctAnswers',
          'correctOption',
          'correctOptions'
        ]
      )
      or (
        p ? 'correct'
        and jsonb_typeof(p->'correct') in ('boolean', 'object')
      )
      or exists (
        select 1
        from jsonb_each(p) as field(key, value)
        where pg_temp.has_protected_keys(field.value)
      )
    else false
  end
$$;

select ok(
  not exists (
    select 1
    from platform.curriculum_publications as publication
    where pg_temp.has_protected_keys(publication.learner_package)
  ),
  'no stored learner package contains protected answer-key structures'
);

select ok(
  not exists (
    select 1
    from platform.curriculum_publications as publication,
         lateral jsonb_array_elements(
           coalesce(publication.learner_package->'activities', '[]'::jsonb)
         ) as activity(value),
         lateral jsonb_array_elements(
           coalesce(activity.value->'blocks', '[]'::jsonb)
         ) as block(value)
    where coalesce(block.value->>'type', '') = 'teacher-note'
  ),
  'no stored learner package retains teacher-note blocks'
);

select ok(
  not has_table_privilege('anon', 'platform.curriculum_publications', 'select'),
  'anon cannot select curriculum_publications'
);

select ok(
  not has_function_privilege(
    'anon',
    'platform.learner_curriculum_package(jsonb, text, text)',
    'execute'
  ),
  'anon cannot execute learner_curriculum_package'
);

select ok(
  not has_function_privilege(
    'anon',
    'platform.regenerate_curriculum_learner_packages(text, text, boolean)',
    'execute'
  ),
  'anon cannot execute regenerate_curriculum_learner_packages'
);

select ok(
  has_function_privilege('anon', 'api.published_curriculum_package(text, text)', 'execute'),
  'anon retains execute on public curriculum package API'
);

select ok(
  has_function_privilege(
    'authenticated',
    'api.published_curriculum_package(text, text, text)',
    'execute'
  ),
  'authenticated retains execute on versioned curriculum package API'
);

-- Compatibility fallback fixture without learner_package.
insert into platform.curriculum_publications (
  hub_code,
  course_key,
  package_version,
  schema_version,
  source_package_version,
  status,
  package,
  content_hash,
  author,
  reviewer,
  publication_notes,
  published_by_auth_user_id,
  published_by_staff_reference
)
select
  'unit-14-software-engineering-for-business',
  'ocr-level-3-it',
  '0.0.99',
  '0.1.0',
  '0.1.0',
  'superseded',
  jsonb_build_object(
    'id', 'unit-14-software-engineering-for-business',
    'hub', jsonb_build_object('id', 'unit-14-software-engineering-for-business'),
    'schemaVersion', '0.1.0',
    'activities', jsonb_build_array(
      jsonb_build_object(
        'id', 'fallback-act',
        'version', '1.0.0',
        'blocks', jsonb_build_array(
          jsonb_build_object(
            'type', 'paragraph',
            'content', jsonb_build_object('text', 'ok')
          ),
          jsonb_build_object(
            'type', 'teacher-note',
            'content', jsonb_build_object('text', 'staff')
          ),
          jsonb_build_object(
            'type', 'single-choice',
            'content', jsonb_build_object(
              'prompt', 'q',
              'correctOptionId', 'A',
              'options', jsonb_build_array(jsonb_build_object('id', 'A'))
            )
          )
        )
      )
    )
  ),
  encode(extensions.digest('phase-b-fallback', 'sha256'), 'hex'),
  'phase-b-test',
  '',
  'fallback fixture',
  published_by_auth_user_id,
  published_by_staff_reference
from platform.curriculum_publications
where hub_code = 'unit-14-software-engineering-for-business'
order by published_at desc
limit 1;

select ok(
  (
    select learner_package is null
    from platform.curriculum_publications
    where package_version = '0.0.99'
  ),
  'fallback fixture can exist without a stored learner_package'
);

select is(
  (
    select package->'activities'->0->>'id'
    from api.published_curriculum_package(
      'unit-14-software-engineering-for-business',
      'ocr-level-3-it',
      '0.0.99'
    )
  ),
  'fallback-act',
  'API falls back to Phase A construction when learner_package is null'
);

select ok(
  (
    select
      not pg_temp.has_protected_keys(package)
      and not exists (
        select 1
        from jsonb_array_elements(coalesce(package->'activities', '[]'::jsonb)) as activity(value),
             lateral jsonb_array_elements(coalesce(activity.value->'blocks', '[]'::jsonb)) as block(value)
        where coalesce(block.value->>'type', '') = 'teacher-note'
      )
    from api.published_curriculum_package(
      'unit-14-software-engineering-for-business',
      'ocr-level-3-it',
      '0.0.99'
    )
  ),
  'fallback path strips protected keys and teacher notes'
);

select is(
  (
    select api_row.package
    from platform.curriculum_publications as publication
    cross join lateral api.published_curriculum_package(
      publication.hub_code,
      publication.course_key,
      publication.package_version
    ) as api_row
    where publication.status = 'published'
      and publication.learner_package is not null
    order by jsonb_array_length(coalesce(publication.package->'activities', '[]'::jsonb)) desc
    limit 1
  ),
  (
    select publication.learner_package
    from platform.curriculum_publications as publication
    where publication.status = 'published'
      and publication.learner_package is not null
    order by jsonb_array_length(coalesce(publication.package->'activities', '[]'::jsonb)) desc
    limit 1
  ),
  'API returns the stored learner_package for published rows'
);

select throws_ok(
  $$
    update platform.curriculum_publications
    set package = package || '{"mutated": true}'::jsonb
    where id = (
      select id
      from platform.curriculum_publications
      where status = 'published'
      limit 1
    )
  $$,
  '22023',
  'PUBLISHED_CURRICULUM_IMMUTABLE',
  'staff package remains immutable'
);

select throws_ok(
  $$
    update platform.curriculum_publications
    set learner_package = '{"activities":[],"correctOptionId":"leak"}'::jsonb,
        learner_package_sanitisation_version = platform.learner_package_sanitisation_version()
    where id = (
      select id
      from platform.curriculum_publications
      where status = 'published'
      limit 1
    )
  $$,
  '22023',
  'PUBLISHED_CURRICULUM_IMMUTABLE',
  'arbitrary learner_package JSON with protected keys is rejected'
);

select throws_ok(
  $$
    update platform.curriculum_publications
    set learner_package_sanitisation_version = 'lp.strip.forged'
    where id = (
      select id
      from platform.curriculum_publications
      where status = 'published'
      limit 1
    )
  $$,
  '22023',
  'PUBLISHED_CURRICULUM_IMMUTABLE',
  'forged sanitisation versions are rejected'
);

select lives_ok(
  $$
    update platform.curriculum_publications as publication
    set
      learner_package = platform.learner_curriculum_package(
        publication.package,
        publication.package_version,
        publication.source_package_version
      ),
      learner_package_sanitisation_version = platform.learner_package_sanitisation_version()
    where publication.id = (
      select id
      from platform.curriculum_publications
      where status = 'published'
        and (
          learner_package is distinct from platform.learner_curriculum_package(
            package,
            package_version,
            source_package_version
          )
          or learner_package_sanitisation_version
            is distinct from platform.learner_package_sanitisation_version()
        )
      limit 1
    )
  $$,
  'canonical Phase A learner_package regeneration update is permitted'
);

-- Outdated sanitisation version must not be served; API rebuilds with current rules.
-- Temporarily disable the protect trigger only to install a poisoned fixture.
alter table platform.curriculum_publications disable trigger protect_curriculum_publication;
update platform.curriculum_publications
set
  learner_package = '{"activities":[{"id":"poison","correctOptionId":"A"}],"schema":"lp.content.package"}'::jsonb,
  learner_package_sanitisation_version = 'lp.strip.outdated'
where package_version = '0.0.99';
alter table platform.curriculum_publications enable trigger protect_curriculum_publication;

select ok(
  (
    select
      not pg_temp.has_protected_keys(package)
      and package->'activities'->0->>'id' = 'fallback-act'
    from api.published_curriculum_package(
      'unit-14-software-engineering-for-business',
      'ocr-level-3-it',
      '0.0.99'
    )
  ),
  'outdated sanitisation version forces Phase A rebuild instead of serving poisoned package'
);

-- Pairing constraint: learner_package cannot exist without a sanitisation version.
alter table platform.curriculum_publications disable trigger protect_curriculum_publication;
select throws_like(
  $$
    update platform.curriculum_publications
    set
      learner_package = '{"activities":[{"id":"poison-null","correctOptionId":"A"}]}'::jsonb,
      learner_package_sanitisation_version = null
    where package_version = '0.0.99'
  $$,
  '%curriculum_publication_learner_sanitisation_present%',
  'learner_package without sanitisation version is rejected by pairing constraint'
);
alter table platform.curriculum_publications enable trigger protect_curriculum_publication;

select throws_ok(
  $$select * from platform.regenerate_curriculum_learner_packages(null, null, false)$$,
  '28000',
  'AUTHENTICATION_REQUIRED',
  'regenerate requires authentication'
);

set local role authenticated;
select throws_like(
  $$
    update platform.curriculum_publications
    set learner_package = '{}'::jsonb
    where status = 'published'
  $$,
  '%permission denied%',
  'authenticated role cannot update learner_package directly'
);
reset role;

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'admin_api'
      and table_name = 'publications_missing_learner_packages'
      and column_name in ('package', 'learner_package')
  ),
  'diagnostic view does not expose staff or learner package bodies'
);

select is(
  platform.learner_curriculum_package('{"activities":[]}'::jsonb, '1.0.0', '0.1.0')->'activities',
  '[]'::jsonb,
  'empty activities remain empty arrays'
);

select is(
  platform.strip_learner_answer_keys('{"a": null, "correctOptionId": "x"}'::jsonb),
  '{"a": null}'::jsonb,
  'null values are preserved while protected keys are removed'
);

select ok(
  (
    select bool_and(
      exists (
        select 1
        from jsonb_array_elements(
          coalesce(publication.package->'activities', '[]'::jsonb)
        ) as staff(value)
        where staff.value->>'id' = activity.value->>'id'
          and staff.value->>'version' is not distinct from activity.value->>'version'
      )
    )
    from platform.curriculum_publications as publication
    cross join lateral jsonb_array_elements(
      coalesce(publication.learner_package->'activities', '[]'::jsonb)
    ) as activity(value)
    where publication.status = 'published'
      and jsonb_typeof(activity.value) = 'object'
      and activity.value ? 'id'
  ),
  'stored learner activities preserve ids and versions from staff packages'
);

select ok(
  exists (
    select 1
    from information_schema.views
    where table_schema = 'admin_api'
      and table_name = 'publications_missing_learner_packages'
  ),
  'staff diagnostic view for missing learner packages exists'
);

select ok(
  not exists (
    select 1
    from platform.curriculum_publications
    where status = 'published'
      and (
        learner_package is null
        or learner_package_sanitisation_version
          is distinct from platform.learner_package_sanitisation_version()
      )
  ),
  'no published row is missing a current learner_package'
);

select ok(
  (
    select bool_and(
      jsonb_array_length(coalesce(publication.package->'activities', '[]'::jsonb))
        = jsonb_array_length(coalesce(publication.learner_package->'activities', '[]'::jsonb))
    )
    from platform.curriculum_publications as publication
    where publication.status = 'published'
  ),
  'published learner packages preserve activity counts'
);

select * from finish();
rollback;
