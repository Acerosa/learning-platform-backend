-- Contextual assessment analytics read models.
-- Additive staff-only views: no warehouse tables, no attempt/response
-- semantic changes, and no response payload or answer-key exposure.

create view admin_api.learner_activity_performance
with (security_invoker = true)
as
select
  student.id as learner_id,
  student.student_number,
  student.display_name,
  course.id as course_id,
  course.stable_key as course_key,
  course.title as course_title,
  learner_group.id as group_id,
  learner_group.code as group_code,
  learner_group.name as group_name,
  assignment.id as assignment_id,
  activity.id as activity_id,
  activity.stable_key as activity_key,
  activity.title as activity_title,
  activity_version.version as activity_version,
  coalesce(hub_summary.hub_codes, '{}'::text[]) as hub_codes,
  coalesce(hub_summary.hub_names, '{}'::text[]) as hub_names,
  week_context.week_number,
  week_context.week_title,
  coalesce(attempt_summary.attempt_count, 0::bigint) as attempt_count,
  coalesce(attempt_summary.completed_attempt_count, 0::bigint) as completed_attempt_count,
  attempt_summary.first_score_percentage,
  attempt_summary.latest_score_percentage,
  attempt_summary.best_score_percentage,
  attempt_summary.average_score_percentage,
  attempt_summary.first_completed_at,
  attempt_summary.latest_completed_at,
  coalesce(review_summary.requires_review_count, 0::bigint) as requires_review_count,
  coalesce(review_summary.reviewed_response_count, 0::bigint) as reviewed_response_count
from learning.enrolments as enrolment
join learning.students as student on student.id = enrolment.student_id
join learning.groups as learner_group on learner_group.id = enrolment.group_id
join learning.courses as course on course.id = learner_group.course_id
join learning.activity_assignments as assignment
  on assignment.group_id = learner_group.id
join learning.activity_versions as activity_version
  on activity_version.id = assignment.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
left join lateral (
  select
    coalesce(
      array_agg(hub.hub_code order by hub.hub_code),
      '{}'::text[]
    ) as hub_codes,
    coalesce(
      array_agg(hub.hub_name order by hub.hub_code),
      '{}'::text[]
    ) as hub_names
  from platform.hub_course_links as link
  join platform.hubs as hub on hub.id = link.hub_id
  where link.course_id = course.id
    and link.active
) as hub_summary on true
left join lateral (
  select
    week.week_number,
    week.title as week_title
  from learning.activity_delivery as delivery
  left join learning.curriculum_weeks as week
    on week.id = delivery.curriculum_week_id
  where delivery.activity_version_id = activity_version.id
    and delivery.active
    and (
      delivery.group_id = learner_group.id
      or delivery.group_id is null
    )
  order by
    delivery.group_id nulls last,
    delivery.sort_order,
    delivery.id
  limit 1
) as week_context on true
left join lateral (
  select
    count(*) as attempt_count,
    count(*) filter (where attempt.status = 'completed') as completed_attempt_count,
    round(
      (
        select (first_attempt.score / nullif(first_attempt.max_score, 0)) * 100
        from learning.attempts as first_attempt
        where first_attempt.student_id = student.id
          and first_attempt.assignment_id = assignment.id
          and first_attempt.status = 'completed'
        order by
          first_attempt.completed_at asc nulls last,
          first_attempt.attempt_number asc
        limit 1
      ),
      2
    ) as first_score_percentage,
    round(
      (
        select (latest_attempt.score / nullif(latest_attempt.max_score, 0)) * 100
        from learning.attempts as latest_attempt
        where latest_attempt.student_id = student.id
          and latest_attempt.assignment_id = assignment.id
          and latest_attempt.status = 'completed'
        order by
          latest_attempt.completed_at desc nulls last,
          latest_attempt.attempt_number desc
        limit 1
      ),
      2
    ) as latest_score_percentage,
    round(
      max((attempt.score / nullif(attempt.max_score, 0)) * 100)
        filter (where attempt.status = 'completed'),
      2
    ) as best_score_percentage,
    round(
      avg((attempt.score / nullif(attempt.max_score, 0)) * 100)
        filter (where attempt.status = 'completed'),
      2
    ) as average_score_percentage,
    min(attempt.completed_at) filter (where attempt.status = 'completed') as first_completed_at,
    max(attempt.completed_at) filter (where attempt.status = 'completed') as latest_completed_at
  from learning.attempts as attempt
  where attempt.student_id = student.id
    and attempt.assignment_id = assignment.id
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
    and reviewed_attempt.assignment_id = assignment.id
) as review_summary on true
where student.active
  and enrolment.status = 'active'
  and (select platform.current_staff_has_role('platform_admin'));

create view admin_api.question_group_performance
with (security_invoker = true)
as
select
  learner_group.code as group_code,
  learner_group.name as group_name,
  course.stable_key as course_key,
  course.title as course_title,
  assignment.id as assignment_id,
  activity.stable_key as activity_key,
  activity.title as activity_title,
  activity_version.version as activity_version,
  question.stable_key as question_key,
  question.analytics_title as question_title,
  question.question_type,
  question.section_key,
  question.ordinal,
  coalesce(topic_summary.topic_keys, '{}'::text[]) as topic_keys,
  coalesce(skill_summary.skill_keys, '{}'::text[]) as skill_keys,
  coalesce(response_summary.response_count, 0::bigint) as response_count,
  coalesce(response_summary.correct_count, 0::bigint) as correct_count,
  coalesce(response_summary.incorrect_count, 0::bigint) as incorrect_count,
  coalesce(response_summary.unanswered_count, 0::bigint) as unanswered_count,
  coalesce(response_summary.requires_review_count, 0::bigint) as requires_review_count,
  coalesce(response_summary.reviewed_response_count, 0::bigint) as reviewed_response_count,
  round(
    100.0 * coalesce(response_summary.correct_count, 0::bigint)
      / nullif(coalesce(response_summary.marked_count, 0::bigint), 0),
    2
  ) as correctness_percentage,
  response_summary.average_awarded_score,
  response_summary.average_max_score
from learning.activity_assignments as assignment
join learning.groups as learner_group on learner_group.id = assignment.group_id
join learning.courses as course on course.id = learner_group.course_id
join learning.activity_versions as activity_version
  on activity_version.id = assignment.activity_version_id
join learning.activities as activity on activity.id = activity_version.activity_id
join learning.questions as question
  on question.activity_version_id = activity_version.id
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
left join lateral (
  select
    count(response.id) as response_count,
    count(*) filter (where response.is_correct = true) as correct_count,
    count(*) filter (where response.is_correct = false) as incorrect_count,
    count(*) filter (where response.is_correct is not null) as marked_count,
    count(*) filter (
      where completed_attempt.id is not null
        and response.id is null
    ) as unanswered_count,
    count(*) filter (where response.requires_review) as requires_review_count,
    count(*) filter (
      where response.marking_source = 'teacher'
        and response.requires_review = false
    ) as reviewed_response_count,
    round(avg(response.awarded_score), 2) as average_awarded_score,
    round(avg(response.max_score), 2) as average_max_score
  from learning.attempts as completed_attempt
  left join learning.responses as response
    on response.attempt_id = completed_attempt.id
    and response.question_id = question.id
  where completed_attempt.assignment_id = assignment.id
    and completed_attempt.status = 'completed'
) as response_summary on true
where (select platform.current_staff_has_role('platform_admin'));

create or replace view admin_api.activity_analytics
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
  attempt_summary.latest_completed_at,
  assignment.id as assignment_id,
  activity.id as activity_id,
  learner_group.name as group_name,
  course.title as course_title,
  activity.title as activity_title,
  round(
    100.0 * coalesce(attempt_summary.attempted_learner_count, 0::bigint)
      / nullif(coalesce(enrolment_summary.assigned_learner_count, 0::bigint), 0),
    2
  ) as participation_percentage
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

create or replace view admin_api.group_performance
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
  count(distinct assignment.id) as assignment_count,
  course.title as course_title,
  learner_group.id as group_id,
  course.id as course_id
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
  course.id,
  course.stable_key,
  course.title,
  review_summary.requires_review_count,
  review_summary.reviewed_response_count;

revoke all on
  admin_api.learner_activity_performance,
  admin_api.question_group_performance
from public, anon, authenticated;

grant select on
  admin_api.learner_activity_performance,
  admin_api.question_group_performance,
  admin_api.activity_analytics,
  admin_api.group_performance
to authenticated;

comment on view admin_api.learner_activity_performance is
  'Platform-admin per learner/assignment/activity-version metrics. First/latest/best/attempt-average scores are completed attempts for that same learner and assignment only. Includes assigned learners with zero attempts. No response payloads.';
comment on view admin_api.question_group_performance is
  'Platform-admin question aggregates scoped to a teaching group assignment. Unanswered counts completed attempts with no response for that question. Does not expose answer keys or response payloads.';
comment on view admin_api.activity_analytics is
  'Platform-admin per-assignment activity analytics including assigned vs attempted learners, participation, completion, staff-readable titles and review backlog.';
comment on view admin_api.group_performance is
  'Platform-admin per-group participation, completion, performance and review backlog aggregates with canonical course titles.';
