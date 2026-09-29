-- Bind Week 4 OCR practice rules whose learner ids differ only by a hyphen.
-- ocr-1 matches OCR1. Written questions with no objective option stay unbound.

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
  where activity.stable_key = 'week4-ocr-question-practice'
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
