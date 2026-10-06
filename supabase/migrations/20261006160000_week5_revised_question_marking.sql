-- Register revised Week 5 questions on activity version 1.2.0.
-- Publication 0.2.35 replaced learner activity JSON on the already published
-- 1.0.0 activity versions. Those versions are immutable, so new question keys
-- and changed answer specs could not be written onto them. The catalogue
-- client sends the package activity version. These nine activities therefore
-- move to 1.2.0, with the stable keys mark_formative_response receives.
-- Week 5 OCR remains on host catalogue version 1.1.0. Week 4 is untouched.
-- Existing question rows, learner attempts and class assignments are kept.
-- Assignments and delivery for 1.2.0 are copied from the previous version.

do $w5$
declare
  v_registry jsonb := $w5reg$[{"activityId":"week5-session1-retrieval","stableKey":"S1Q1","questionType":"single","ordinal":1,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session1-retrieval","stableKey":"S1Q2","questionType":"single","ordinal":2,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session1-retrieval","stableKey":"S1Q3","questionType":"single","ordinal":3,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session1-retrieval","stableKey":"S1Q4","questionType":"single","ordinal":4,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session1-retrieval","stableKey":"S1Q5","questionType":"single","ordinal":5,"spec":{"mode":"single-choice","correctOptionId":"c"}},{"activityId":"week5-session1-retrieval","stableKey":"S1Q6","questionType":"single","ordinal":6,"spec":{"mode":"single-choice","correctOptionId":"c"}},{"activityId":"week5-session1-retrieval","stableKey":"S1Q7","questionType":"single","ordinal":7,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session1-retrieval","stableKey":"S1Q8","questionType":"single","ordinal":8,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-impacts-learning","stableKey":"K1","questionType":"single","ordinal":1,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-impacts-learning","stableKey":"K2","questionType":"single","ordinal":2,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-impacts-learning","stableKey":"K3","questionType":"single","ordinal":3,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-impacts-learning","stableKey":"K4","questionType":"single","ordinal":4,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-impacts-learning","stableKey":"K5","questionType":"single","ordinal":5,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-impacts-learning","stableKey":"K6","questionType":"single","ordinal":6,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-impacts-learning","stableKey":"K7","questionType":"single","ordinal":7,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-impacts-learning","stableKey":"K8","questionType":"single","ordinal":8,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-impacts-learning","stableKey":"K9","questionType":"single","ordinal":9,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-impacts-learning","stableKey":"CHECKPOINT","questionType":"text","ordinal":10,"spec":{"mode":"completion"}},{"activityId":"week5-impact-classification","stableKey":"C1","questionType":"matching","ordinal":1,"spec":{"mode":"classification","correctCategoryId":"Loss"}},{"activityId":"week5-impact-classification","stableKey":"C2","questionType":"matching","ordinal":2,"spec":{"mode":"classification","correctCategoryId":"Disruption"}},{"activityId":"week5-impact-classification","stableKey":"C3","questionType":"matching","ordinal":3,"spec":{"mode":"classification","correctCategoryId":"Safety"}},{"activityId":"week5-impact-classification","stableKey":"C4","questionType":"matching","ordinal":4,"spec":{"mode":"classification","correctCategoryId":"Loss"}},{"activityId":"week5-impact-classification","stableKey":"C5","questionType":"matching","ordinal":5,"spec":{"mode":"classification","correctCategoryId":"Loss"}},{"activityId":"week5-impact-classification","stableKey":"C6","questionType":"matching","ordinal":6,"spec":{"mode":"classification","correctCategoryId":"More than one category"}},{"activityId":"week5-impact-classification","stableKey":"C7","questionType":"matching","ordinal":7,"spec":{"mode":"classification","correctCategoryId":"More than one category"}},{"activityId":"week5-impact-classification","stableKey":"C8","questionType":"matching","ordinal":8,"spec":{"mode":"classification","correctCategoryId":"Disruption"}},{"activityId":"week5-impact-classification","stableKey":"JUSTIFY","questionType":"text","ordinal":9,"spec":{"mode":"completion"}},{"activityId":"week5-ransomware-companion","stableKey":"SPOT-1","questionType":"matching","ordinal":1,"spec":{"mode":"classification","correctCategoryId":"Disruption"}},{"activityId":"week5-ransomware-companion","stableKey":"SPOT-2","questionType":"matching","ordinal":2,"spec":{"mode":"classification","correctCategoryId":"Loss"}},{"activityId":"week5-ransomware-companion","stableKey":"SPOT-3","questionType":"matching","ordinal":3,"spec":{"mode":"classification","correctCategoryId":"Disruption"}},{"activityId":"week5-ransomware-companion","stableKey":"SPOT-4","questionType":"matching","ordinal":4,"spec":{"mode":"classification","correctCategoryId":"Not supported"}},{"activityId":"week5-ransomware-companion","stableKey":"RC2","questionType":"text","ordinal":5,"spec":{"mode":"completion"}},{"activityId":"week5-ransomware-companion","stableKey":"RC3","questionType":"order","ordinal":6,"spec":{"mode":"ordering-exact","correctOrder":["stolen","offline","complaints","trust"]}},{"activityId":"week5-ransomware-companion","stableKey":"RC4","questionType":"text","ordinal":7,"spec":{"mode":"completion"}},{"activityId":"week5-exercise-debrief","stableKey":"T1","questionType":"matching","ordinal":1,"spec":{"mode":"classification","correctCategoryId":"Immediate"}},{"activityId":"week5-exercise-debrief","stableKey":"T2","questionType":"matching","ordinal":2,"spec":{"mode":"classification","correctCategoryId":"Immediate"}},{"activityId":"week5-exercise-debrief","stableKey":"T3","questionType":"matching","ordinal":3,"spec":{"mode":"classification","correctCategoryId":"Longer term"}},{"activityId":"week5-exercise-debrief","stableKey":"T4","questionType":"matching","ordinal":4,"spec":{"mode":"classification","correctCategoryId":"Longer term"}},{"activityId":"week5-exercise-debrief","stableKey":"T5","questionType":"matching","ordinal":5,"spec":{"mode":"classification","correctCategoryId":"Could be either"}},{"activityId":"week5-exercise-debrief","stableKey":"T6","questionType":"matching","ordinal":6,"spec":{"mode":"classification","correctCategoryId":"Longer term"}},{"activityId":"week5-exercise-debrief","stableKey":"DB2","questionType":"order","ordinal":7,"spec":{"mode":"ordering-exact","correctOrder":["encrypt","confirm","cancel","complaints"]}},{"activityId":"week5-exercise-debrief","stableKey":"DB3","questionType":"text","ordinal":8,"spec":{"mode":"completion"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q1","questionType":"single","ordinal":1,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q2","questionType":"single","ordinal":2,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q3","questionType":"single","ordinal":3,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q4","questionType":"single","ordinal":4,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q5","questionType":"single","ordinal":5,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q6","questionType":"single","ordinal":6,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q7","questionType":"single","ordinal":7,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q8","questionType":"single","ordinal":8,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q9","questionType":"single","ordinal":9,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q10","questionType":"single","ordinal":10,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q11","questionType":"single","ordinal":11,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-session2-retrieval","stableKey":"S2Q12","questionType":"single","ordinal":12,"spec":{"mode":"single-choice","correctOptionId":"c"}},{"activityId":"week5-secure-rewrite","stableKey":"R1","questionType":"single","ordinal":1,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-secure-rewrite","stableKey":"R2","questionType":"single","ordinal":2,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-secure-rewrite","stableKey":"R3","questionType":"single","ordinal":3,"spec":{"mode":"single-choice","correctOptionId":"b"}},{"activityId":"week5-secure-rewrite","stableKey":"R4","questionType":"single","ordinal":4,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-secure-rewrite","stableKey":"R5","questionType":"single","ordinal":5,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-secure-rewrite","stableKey":"R6","questionType":"single","ordinal":6,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-secure-rewrite","stableKey":"EXPLAIN","questionType":"text","ordinal":7,"spec":{"mode":"completion"}},{"activityId":"week5-threat-vulnerability-risk","stableKey":"T1","questionType":"matching","ordinal":1,"spec":{"mode":"classification","correctCategoryId":"Vulnerability"}},{"activityId":"week5-threat-vulnerability-risk","stableKey":"T2","questionType":"matching","ordinal":2,"spec":{"mode":"classification","correctCategoryId":"Threat"}},{"activityId":"week5-threat-vulnerability-risk","stableKey":"T3","questionType":"matching","ordinal":3,"spec":{"mode":"classification","correctCategoryId":"Risk"}},{"activityId":"week5-threat-vulnerability-risk","stableKey":"T4","questionType":"matching","ordinal":4,"spec":{"mode":"classification","correctCategoryId":"Vulnerability"}},{"activityId":"week5-threat-vulnerability-risk","stableKey":"T5","questionType":"matching","ordinal":5,"spec":{"mode":"classification","correctCategoryId":"Threat"}},{"activityId":"week5-threat-vulnerability-risk","stableKey":"T6","questionType":"matching","ordinal":6,"spec":{"mode":"classification","correctCategoryId":"Risk"}},{"activityId":"week5-threat-vulnerability-risk","stableKey":"T7","questionType":"matching","ordinal":7,"spec":{"mode":"classification","correctCategoryId":"Vulnerability"}},{"activityId":"week5-threat-vulnerability-risk","stableKey":"T8","questionType":"matching","ordinal":8,"spec":{"mode":"classification","correctCategoryId":"Vulnerability"}},{"activityId":"week5-threat-vulnerability-risk","stableKey":"EXPLAIN","questionType":"text","ordinal":9,"spec":{"mode":"completion"}},{"activityId":"week5-vulnerability-patterns","stableKey":"P1","questionType":"single","ordinal":1,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-vulnerability-patterns","stableKey":"P2","questionType":"single","ordinal":2,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-vulnerability-patterns","stableKey":"P3","questionType":"single","ordinal":3,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-vulnerability-patterns","stableKey":"P4","questionType":"single","ordinal":4,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-vulnerability-patterns","stableKey":"P5","questionType":"single","ordinal":5,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-vulnerability-patterns","stableKey":"P6","questionType":"single","ordinal":6,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-vulnerability-patterns","stableKey":"P7","questionType":"single","ordinal":7,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-vulnerability-patterns","stableKey":"P8","questionType":"single","ordinal":8,"spec":{"mode":"single-choice","correctOptionId":"a"}},{"activityId":"week5-vulnerability-patterns","stableKey":"CHECKPOINT","questionType":"text","ordinal":9,"spec":{"mode":"completion"}}]$w5reg$;
  v_activity text;
  v_activity_id uuid;
  v_version_id uuid;
  v_source_version_id uuid;
  v_count integer;
  v_item jsonb;
  v_question_id uuid;
begin
  for v_activity in
    select distinct item->>'activityId'
    from jsonb_array_elements(v_registry) as item
    order by 1
  loop
    if v_activity not like 'week5-%'
       or v_activity in (
         'week5-ocr-question-practice',
         'week5-answer-improvement',
         'week5-controls-matching',
         'week5-stakeholder-grid',
         'week5-impact-analysis'
       ) then
      raise exception using errcode = '55000', message = 'WEEK5_MARKING_ACTIVITY_NOT_ALLOWED';
    end if;

    select activity.id
    into v_activity_id
    from learning.activities as activity
    where activity.stable_key = v_activity
      and activity.active;

    if v_activity_id is null then
      raise exception using errcode = '55000', message = 'WEEK5_MARKING_ACTIVITY_MISSING';
    end if;

    if exists (
      select 1
      from learning.activity_versions as activity_version
      where activity_version.activity_id = v_activity_id
        and activity_version.version = '1.2.0'
    ) then
      raise exception using errcode = '55000', message = 'WEEK5_MARKING_VERSION_EXISTS';
    end if;

    select count(*)::integer
    into v_count
    from jsonb_array_elements(v_registry) as item
    where item->>'activityId' = v_activity;

    insert into learning.activity_versions (
      activity_id, version, content_hash, max_score, question_count, published_at
    ) values (
      v_activity_id,
      '1.2.0',
      encode(
        extensions.digest(
          pg_catalog.convert_to('week5-marking-registration:' || v_activity || ':1.2.0', 'UTF8'),
          'sha256'
        ),
        'hex'
      ),
      v_count,
      v_count,
      null
    )
    returning id into v_version_id;

    for v_item in
      select item.value
      from jsonb_array_elements(v_registry) as item(value)
      where item.value->>'activityId' = v_activity
      order by (item.value->>'ordinal')::integer
    loop
      insert into learning.questions (
        activity_version_id, stable_key, section_key, section_title,
        question_type, analytics_title, ordinal, max_score
      ) values (
        v_version_id,
        v_item->>'stableKey',
        'week-5',
        'Week 5',
        v_item->>'questionType',
        v_item->>'stableKey',
        (v_item->>'ordinal')::integer,
        1
      )
      returning id into v_question_id;

      insert into learning.question_marking (question_id, spec)
      values (v_question_id, v_item->'spec');
    end loop;

    insert into learning.activity_assignments (
      group_id, activity_version_id, opens_at, due_at, required, active
    )
    select distinct on (existing.group_id)
      existing.group_id,
      v_version_id,
      existing.opens_at,
      existing.due_at,
      existing.required,
      true
    from learning.activity_assignments as existing
    join learning.activity_versions as old_version
      on old_version.id = existing.activity_version_id
    where old_version.activity_id = v_activity_id
      and old_version.version in ('1.0.0', '1.1.0')
      and existing.active
    order by existing.group_id, old_version.version desc
    on conflict (group_id, activity_version_id) do nothing;

    select activity_version.id
    into v_source_version_id
    from learning.activity_versions as activity_version
    where activity_version.activity_id = v_activity_id
      and activity_version.version = '1.0.0';

    if not exists (
      select 1
      from learning.activity_delivery as delivery
      where delivery.activity_version_id = v_source_version_id
    ) then
      select activity_version.id
      into v_source_version_id
      from learning.activity_versions as activity_version
      where activity_version.activity_id = v_activity_id
        and activity_version.version = '1.1.0';
    end if;

    insert into learning.activity_delivery (
      activity_version_id, academic_year_id, group_id, curriculum_week_id,
      week_number, session_number, sort_order, active, available_from, available_until
    )
    select
      v_version_id,
      delivery.academic_year_id,
      delivery.group_id,
      delivery.curriculum_week_id,
      delivery.week_number,
      delivery.session_number,
      delivery.sort_order,
      delivery.active,
      delivery.available_from,
      delivery.available_until
    from learning.activity_delivery as delivery
    where delivery.activity_version_id = v_source_version_id
      and not exists (
        select 1
        from learning.activity_delivery as existing
        where existing.activity_version_id = v_version_id
          and existing.academic_year_id = delivery.academic_year_id
          and existing.group_id is not distinct from delivery.group_id
      );

    update learning.activity_versions
    set published_at = clock_timestamp()
    where id = v_version_id
      and published_at is null;
  end loop;
end
$w5$;

-- Bind fingerprints once publication activity version 1.2.0 is live.
-- Before that publication exists this updates nothing. A null fingerprint
-- still uses the 1.2.0 rule. Binding after publication stops a later
-- structure change from being marked by this rule.
update learning.question_marking as marking
set structure_fingerprint = learned.fingerprint
from (
  select
    marking.question_id,
    learning.published_question_fingerprint(
      activity.stable_key,
      '1.2.0',
      question.stable_key
    ) as fingerprint
  from learning.question_marking as marking
  join learning.questions as question
    on question.id = marking.question_id
  join learning.activity_versions as activity_version
    on activity_version.id = question.activity_version_id
  join learning.activities as activity
    on activity.id = activity_version.activity_id
  where activity_version.version = '1.2.0'
    and activity.stable_key like 'week5-%'
    and activity.stable_key <> 'week5-ocr-question-practice'
    and marking.structure_fingerprint is null
) as learned
where marking.question_id = learned.question_id
  and learned.fingerprint is not null
  and not exists (
    select 1
    from learning.question_marking as other
    where other.bound_activity_id = marking.bound_activity_id
      and other.bound_question_key = marking.bound_question_key
      and other.structure_fingerprint = learned.fingerprint
      and other.question_id <> marking.question_id
  );
