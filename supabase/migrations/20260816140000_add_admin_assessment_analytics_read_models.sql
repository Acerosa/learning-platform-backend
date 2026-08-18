-- Phase 9 Assessment & Analytics MVP.
-- Additive staff read models only: no analytics warehouse tables and no
-- response payload exposure in aggregates.

update platform.contract_versions
set
  compatibility = jsonb_set(
    coalesce(compatibility, '{}'::jsonb),
    '{mode}',
    to_jsonb(
      'read-models-with-hub-registration-curriculum-publication-teacher-review-and-assessment-analytics'::text
    )
  ),
  contract_document = jsonb_set(
    coalesce(contract_document, '{}'::jsonb),
    '{boundary}',
    to_jsonb(
      'authenticated staff read models, hub registration, curriculum publication, teacher response review and assessment analytics'::text
    )
  )
where contract_key = 'admin-api'
  and version = '0.2.0';

create view admin_api.assessment_overview
with (security_invoker = true)
as
select
  (select count(*) from learning.students where active) as active_learners,
  (select count(*) from learning.groups where active) as active_groups,
  (select count(*) from learning.attempts) as attempt_count,
  (
    select count(*)
    from learning.attempts
    where status = 'completed'
  ) as completed_attempts,
  (
    select round(
      100.0 * count(*) filter (where status = 'completed')
        / nullif(count(*), 0),
      2
    )
    from learning.attempts
  ) as completion_percentage,
  (
    select round(avg((score / nullif(max_score, 0)) * 100), 2)
    from learning.attempts
    where status = 'completed'
  ) as average_score_percentage,
  (
    select count(*)
    from learning.responses
    where requires_review
  ) as requires_review_count,
  (
    select count(*)
    from learning.responses
    where marking_source = 'teacher'
      and requires_review = false
  ) as reviewed_response_count,
  (
    select count(distinct assignment.id)
    from learning.activity_assignments as assignment
  ) as assignment_count,
  (
    select count(distinct attempt.student_id)
    from learning.attempts as attempt
    where attempt.status = 'completed'
  ) as participating_learner_count,
  (
    select count(*)
    from learning.question_topics
  ) as topic_link_count,
  (
    select count(*)
    from learning.question_skills
  ) as skill_link_count
where (select platform.current_staff_has_role('platform_admin'));

create view admin_api.group_performance
with (security_invoker = true)
as
select
  learner_group.code as group_code,
  learner_group.name as group_name,
  course.stable_key as course_key,
  (
    select count(*)
    from learning.enrolments as enrolment
    where enrolment.group_id = learner_group.id
      and enrolment.status = 'active'
  ) as active_learner_count,
  count(distinct attempt.student_id) filter (
    where attempt.id is not null
  ) as participating_learner_count,
  count(*) filter (where attempt.status = 'completed') as completed_attempts,
  count(distinct attempt.id) as attempt_count,
  round(
    avg((attempt.score / nullif(attempt.max_score, 0)) * 100)
      filter (where attempt.status = 'completed'),
    2
  ) as average_score_percentage,
  round(
    max((attempt.score / nullif(attempt.max_score, 0)) * 100)
      filter (where attempt.status = 'completed'),
    2
  ) as best_score_percentage,
  round(
    (
      select avg((latest.score / nullif(latest.max_score, 0)) * 100)
      from (
        select distinct on (inner_attempt.student_id, inner_attempt.assignment_id)
          inner_attempt.score,
          inner_attempt.max_score
        from learning.attempts as inner_attempt
        join learning.activity_assignments as inner_assignment
          on inner_assignment.id = inner_attempt.assignment_id
        where inner_assignment.group_id = learner_group.id
          and inner_attempt.status = 'completed'
        order by
          inner_attempt.student_id,
          inner_attempt.assignment_id,
          inner_attempt.completed_at desc nulls last,
          inner_attempt.attempt_number desc
      ) as latest
    ),
    2
  ) as latest_score_percentage,
  coalesce(review_summary.requires_review_count, 0::bigint) as requires_review_count,
  coalesce(review_summary.reviewed_response_count, 0::bigint) as reviewed_response_count,
  count(distinct assignment.id) as assignment_count
from learning.groups as learner_group
join learning.courses as course on course.id = learner_group.course_id
left join learning.activity_assignments as assignment
  on assignment.group_id = learner_group.id
left join learning.attempts as attempt
  on attempt.assignment_id = assignment.id
left join lateral (
  select
    count(*) filter (where response.requires_review) as requires_review_count,
    count(*) filter (
      where response.marking_source = 'teacher'
        and response.requires_review = false
    ) as reviewed_response_count
  from learning.responses as response
  join learning.attempts as reviewed_attempt
    on reviewed_attempt.id = response.attempt_id
  join learning.activity_assignments as reviewed_assignment
    on reviewed_assignment.id = reviewed_attempt.assignment_id
  where reviewed_assignment.group_id = learner_group.id
) as review_summary on true
where (select platform.current_staff_has_role('platform_admin'))
group by
  learner_group.id,
  learner_group.code,
  learner_group.name,
  course.stable_key,
  review_summary.requires_review_count,
  review_summary.reviewed_response_count;

create view admin_api.learner_performance
with (security_invoker = true)
as
select
  student.id as learner_id,
  student.student_number,
  student.display_name,
  coalesce(enrolment_summary.group_codes, '{}'::text[]) as group_codes,
  coalesce(assignment_summary.assigned_activity_count, 0::bigint) as assigned_activity_count,
  coalesce(attempt_summary.completed_activity_count, 0::bigint) as completed_activity_count,
  coalesce(attempt_summary.attempt_count, 0::bigint) as attempt_count,
  coalesce(attempt_summary.completed_attempts, 0::bigint) as completed_attempts,
  attempt_summary.average_score_percentage,
  attempt_summary.best_score_percentage,
  attempt_summary.latest_score_percentage,
  attempt_summary.first_score_percentage,
  coalesce(review_summary.requires_review_count, 0::bigint) as requires_review_count,
  coalesce(review_summary.reviewed_response_count, 0::bigint) as reviewed_response_count,
  attempt_summary.latest_completed_at
from learning.students as student
left join lateral (
  select
    array_agg(learner_group.code order by learner_group.code)
      filter (where enrolment.status = 'active') as group_codes
  from learning.enrolments as enrolment
  join learning.groups as learner_group on learner_group.id = enrolment.group_id
  where enrolment.student_id = student.id
) as enrolment_summary on true
left join lateral (
  select count(distinct assignment.id) as assigned_activity_count
  from learning.enrolments as enrolment
  join learning.activity_assignments as assignment
    on assignment.group_id = enrolment.group_id
  where enrolment.student_id = student.id
    and enrolment.status = 'active'
) as assignment_summary on true
left join lateral (
  select
    count(*) as attempt_count,
    count(*) filter (where attempt.status = 'completed') as completed_attempts,
    count(distinct attempt.assignment_id) filter (
      where attempt.status = 'completed'
    ) as completed_activity_count,
    round(
      avg((attempt.score / nullif(attempt.max_score, 0)) * 100)
        filter (where attempt.status = 'completed'),
      2
    ) as average_score_percentage,
    round(
      max((attempt.score / nullif(attempt.max_score, 0)) * 100)
        filter (where attempt.status = 'completed'),
      2
    ) as best_score_percentage,
    round(
      (
        select (latest.score / nullif(latest.max_score, 0)) * 100
        from learning.attempts as latest
        where latest.student_id = student.id
          and latest.status = 'completed'
        order by latest.completed_at desc nulls last, latest.attempt_number desc
        limit 1
      ),
      2
    ) as latest_score_percentage,
    round(
      (
        select (first_attempt.score / nullif(first_attempt.max_score, 0)) * 100
        from learning.attempts as first_attempt
        where first_attempt.student_id = student.id
          and first_attempt.status = 'completed'
        order by first_attempt.completed_at asc nulls last, first_attempt.attempt_number asc
        limit 1
      ),
      2
    ) as first_score_percentage,
    max(attempt.completed_at) as latest_completed_at
  from learning.attempts as attempt
  where attempt.student_id = student.id
) as attempt_summary on true
left join lateral (
  select
    count(*) filter (where response.requires_review) as requires_review_count,
    count(*) filter (
      where response.marking_source = 'teacher'
        and response.requires_review = false
    ) as reviewed_response_count
  from learning.responses as response
  join learning.attempts as reviewed_attempt
    on reviewed_attempt.id = response.attempt_id
  where reviewed_attempt.student_id = student.id
) as review_summary on true
where student.active
  and (select platform.current_staff_has_role('platform_admin'));

create view admin_api.activity_analytics
with (security_invoker = true)
as
select
  learner_group.code as group_code,
  course.stable_key as course_key,
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  coalesce(enrolment_summary.assigned_learner_count, 0::bigint) as assigned_learner_count,
  coalesce(attempt_summary.attempted_learner_count, 0::bigint) as attempted_learner_count,
  coalesce(attempt_summary.completed_learner_count, 0::bigint) as completed_learner_count,
  round(
    100.0 * coalesce(attempt_summary.completed_learner_count, 0::bigint)
      / nullif(coalesce(enrolment_summary.assigned_learner_count, 0::bigint), 0),
    2
  ) as completion_percentage,
  coalesce(attempt_summary.attempt_count, 0::bigint) as attempt_count,
  coalesce(attempt_summary.completed_attempts, 0::bigint) as completed_attempts,
  attempt_summary.average_score_percentage,
  attempt_summary.best_score_percentage,
  attempt_summary.latest_score_percentage,
  coalesce(review_summary.requires_review_count, 0::bigint) as requires_review_count,
  coalesce(review_summary.reviewed_response_count, 0::bigint) as reviewed_response_count,
  attempt_summary.latest_completed_at
from learning.activity_assignments as assignment
join learning.groups as learner_group on learner_group.id = assignment.group_id
join learning.courses as course on course.id = learner_group.course_id
join learning.activity_versions as activity_version
  on activity_version.id = assignment.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
left join lateral (
  select count(distinct enrolment.student_id) as assigned_learner_count
  from learning.enrolments as enrolment
  where enrolment.group_id = learner_group.id
    and enrolment.status = 'active'
) as enrolment_summary on true
left join lateral (
  select
    count(distinct attempt.student_id) as attempted_learner_count,
    count(distinct attempt.student_id) filter (
      where attempt.status = 'completed'
    ) as completed_learner_count,
    count(*) as attempt_count,
    count(*) filter (where attempt.status = 'completed') as completed_attempts,
    round(
      avg((attempt.score / nullif(attempt.max_score, 0)) * 100)
        filter (where attempt.status = 'completed'),
      2
    ) as average_score_percentage,
    round(
      max((attempt.score / nullif(attempt.max_score, 0)) * 100)
        filter (where attempt.status = 'completed'),
      2
    ) as best_score_percentage,
    round(
      (
        select avg((latest.score / nullif(latest.max_score, 0)) * 100)
        from (
          select distinct on (inner_attempt.student_id)
            inner_attempt.score,
            inner_attempt.max_score
          from learning.attempts as inner_attempt
          where inner_attempt.assignment_id = assignment.id
            and inner_attempt.status = 'completed'
          order by
            inner_attempt.student_id,
            inner_attempt.completed_at desc nulls last,
            inner_attempt.attempt_number desc
        ) as latest
      ),
      2
    ) as latest_score_percentage,
    max(attempt.completed_at) as latest_completed_at
  from learning.attempts as attempt
  where attempt.assignment_id = assignment.id
) as attempt_summary on true
left join lateral (
  select
    count(*) filter (where response.requires_review) as requires_review_count,
    count(*) filter (
      where response.marking_source = 'teacher'
        and response.requires_review = false
    ) as reviewed_response_count
  from learning.responses as response
  join learning.attempts as reviewed_attempt
    on reviewed_attempt.id = response.attempt_id
  where reviewed_attempt.assignment_id = assignment.id
) as review_summary on true
where (select platform.current_staff_has_role('platform_admin'));

create view admin_api.question_performance
with (security_invoker = true)
as
select
  activity.stable_key as activity_key,
  activity_version.version as activity_version,
  question.stable_key as question_key,
  question.question_type,
  question.section_key,
  coalesce(topic_summary.topic_keys, '{}'::text[]) as topic_keys,
  coalesce(skill_summary.skill_keys, '{}'::text[]) as skill_keys,
  count(response.id) as response_count,
  count(*) filter (where response.is_correct = true) as correct_count,
  count(*) filter (where response.is_correct = false) as incorrect_count,
  count(*) filter (where response.requires_review) as requires_review_count,
  count(*) filter (
    where response.marking_source = 'teacher'
      and response.requires_review = false
  ) as reviewed_response_count,
  round(
    100.0 * count(*) filter (where response.is_correct = true)
      / nullif(count(*) filter (where response.is_correct is not null), 0),
    2
  ) as correctness_percentage,
  round(avg(response.awarded_score), 2) as average_awarded_score,
  round(avg(response.max_score), 2) as average_max_score
from learning.questions as question
join learning.activity_versions as activity_version
  on activity_version.id = question.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
left join learning.responses as response on response.question_id = question.id
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
where (select platform.current_staff_has_role('platform_admin'))
group by
  activity.stable_key,
  activity_version.version,
  question.id,
  question.stable_key,
  question.question_type,
  question.section_key,
  topic_summary.topic_keys,
  skill_summary.skill_keys;

create view admin_api.topic_performance
with (security_invoker = true)
as
select
  topic.stable_key as topic_key,
  count(response.id) as response_count,
  count(distinct response.attempt_id) as attempt_count,
  count(distinct attempt.student_id) as learner_count,
  count(*) filter (where response.is_correct = true) as correct_count,
  count(*) filter (where response.is_correct = false) as incorrect_count,
  count(*) filter (where response.requires_review) as requires_review_count,
  round(
    100.0 * count(*) filter (where response.is_correct = true)
      / nullif(count(*) filter (where response.is_correct is not null), 0),
    2
  ) as success_percentage,
  round(avg(response.awarded_score), 2) as average_awarded_score
from learning.topics as topic
join learning.question_topics as question_topic
  on question_topic.topic_id = topic.id
join learning.questions as question on question.id = question_topic.question_id
left join learning.responses as response on response.question_id = question.id
left join learning.attempts as attempt on attempt.id = response.attempt_id
where (select platform.current_staff_has_role('platform_admin'))
group by topic.id, topic.stable_key;

create view admin_api.skill_performance
with (security_invoker = true)
as
select
  skill.stable_key as skill_key,
  count(response.id) as response_count,
  count(distinct response.attempt_id) as attempt_count,
  count(distinct attempt.student_id) as learner_count,
  count(*) filter (where response.is_correct = true) as correct_count,
  count(*) filter (where response.is_correct = false) as incorrect_count,
  count(*) filter (where response.requires_review) as requires_review_count,
  round(
    100.0 * count(*) filter (where response.is_correct = true)
      / nullif(count(*) filter (where response.is_correct is not null), 0),
    2
  ) as success_percentage,
  round(avg(response.awarded_score), 2) as average_awarded_score
from learning.skills as skill
join learning.question_skills as question_skill
  on question_skill.skill_id = skill.id
join learning.questions as question on question.id = question_skill.question_id
left join learning.responses as response on response.question_id = question.id
left join learning.attempts as attempt on attempt.id = response.attempt_id
where (select platform.current_staff_has_role('platform_admin'))
group by skill.id, skill.stable_key;

revoke all on
  admin_api.assessment_overview,
  admin_api.group_performance,
  admin_api.learner_performance,
  admin_api.activity_analytics,
  admin_api.question_performance,
  admin_api.topic_performance,
  admin_api.skill_performance
from public, anon, authenticated;

grant select on
  admin_api.assessment_overview,
  admin_api.group_performance,
  admin_api.learner_performance,
  admin_api.activity_analytics,
  admin_api.question_performance,
  admin_api.topic_performance,
  admin_api.skill_performance
to authenticated;

comment on view admin_api.assessment_overview is
  'Platform-admin assessment KPIs derived from authoritative attempts, responses and curriculum metadata links. No response payloads.';
comment on view admin_api.group_performance is
  'Platform-admin per-group participation, completion, performance and review backlog aggregates.';
comment on view admin_api.learner_performance is
  'Platform-admin per-learner assignment participation, attempt performance and review counts.';
comment on view admin_api.activity_analytics is
  'Platform-admin per-assignment activity analytics including assigned vs attempted learners and review backlog.';
comment on view admin_api.question_performance is
  'Platform-admin question aggregates with topic/skill keys. Does not expose answer keys or response payloads.';
comment on view admin_api.topic_performance is
  'Platform-admin topic_key aggregates from existing question_topics metadata only.';
comment on view admin_api.skill_performance is
  'Platform-admin skill_key aggregates from existing question_skills metadata only.';
