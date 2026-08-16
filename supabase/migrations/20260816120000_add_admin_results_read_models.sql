-- Staff-only read models for the Admin Results / Markbook module.
-- Additive projections only: no new persistence tables.

create or replace view admin_api.attempts
with (security_invoker = true)
as
select
  attempt.id as attempt_id,
  attempt.student_id as learner_id,
  student.student_number,
  attempt.enrolment_id,
  attempt.assignment_id,
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  attempt.attempt_number,
  attempt.status,
  attempt.score,
  attempt.max_score,
  attempt.marking_source,
  attempt.evidence_level,
  attempt.received_at,
  attempt.completed_at,
  learner_group.code as group_code,
  exists (
    select 1
    from learning.responses as response
    where response.attempt_id = attempt.id
      and response.requires_review
  ) as requires_review,
  activity_version.question_count
from learning.attempts as attempt
join learning.students as student on student.id = attempt.student_id
join learning.activity_versions as activity_version
  on activity_version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
join learning.activity_assignments as assignment
  on assignment.id = attempt.assignment_id
join learning.groups as learner_group on learner_group.id = assignment.group_id
where (select platform.current_staff_has_role('platform_admin'));

create view admin_api.responses
with (security_invoker = true)
as
select
  response.id as response_id,
  response.attempt_id,
  student.student_number,
  learner_group.code as group_code,
  activity.stable_key as activity_key,
  question.stable_key as question_key,
  question.question_type,
  question.section_key,
  question.section_title,
  question.ordinal,
  coalesce(topic_summary.topic_keys, '{}'::text[]) as topic_keys,
  coalesce(skill_summary.skill_keys, '{}'::text[]) as skill_keys,
  response.response_payload,
  response.awarded_score,
  response.max_score,
  response.is_correct,
  response.requires_review,
  response.marking_source,
  response.marked_at
from learning.responses as response
join learning.attempts as attempt on attempt.id = response.attempt_id
join learning.students as student on student.id = attempt.student_id
join learning.questions as question on question.id = response.question_id
join learning.activity_versions as activity_version
  on activity_version.id = attempt.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
join learning.activity_assignments as assignment
  on assignment.id = attempt.assignment_id
join learning.groups as learner_group on learner_group.id = assignment.group_id
left join lateral (
  select array_agg(topic.stable_key order by topic.stable_key) as topic_keys
  from learning.question_topics as question_topic
  join learning.topics as topic on topic.id = question_topic.topic_id
  where question_topic.question_id = question.id
) as topic_summary on true
left join lateral (
  select array_agg(skill.stable_key order by skill.stable_key) as skill_keys
  from learning.question_skills as question_skill
  join learning.skills as skill on skill.id = question_skill.skill_id
  where question_skill.question_id = question.id
) as skill_summary on true
where (select platform.current_staff_has_role('platform_admin'));

revoke all on admin_api.attempts, admin_api.responses
  from public, anon, authenticated;

grant select on admin_api.attempts, admin_api.responses
  to authenticated;

comment on view admin_api.attempts is
  'Platform-admin attempt summaries with review flag and question count. Response payloads remain on admin_api.responses.';
comment on view admin_api.responses is
  'Platform-admin question-level evidence and marks for Results / Markbook inspection.';
