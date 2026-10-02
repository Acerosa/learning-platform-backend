-- Advisory content review for submitted timed knowledge reports.
-- Stored separately from the frozen response. Never updates response_payload.

create table learning.knowledge_report_content_reviews (
  id uuid primary key default gen_random_uuid(),
  response_id uuid not null references learning.responses (id),
  analysis_version text not null,
  analysed_at timestamptz not null default timezone('utc', now()),
  overall_relevance text not null,
  summary text not null,
  topics jsonb not null,
  repetition_flag boolean not null default false,
  repetition_note text,
  constraint knowledge_report_relevance_valid
    check (overall_relevance in ('high', 'moderate', 'low', 'very_low')),
  constraint knowledge_report_analysis_version_not_blank
    check (btrim(analysis_version) <> ''),
  unique (response_id, analysis_version)
);

comment on table learning.knowledge_report_content_reviews is
  'Advisory automated review of a submitted knowledge report. Not student evidence and not a teacher judgement.';

alter table learning.knowledge_report_content_reviews enable row level security;
revoke all on table learning.knowledge_report_content_reviews from public, anon, authenticated;

create or replace function learning.assess_knowledge_report_content(p_text text)
returns jsonb
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_text text := lower(coalesce(p_text, ''));
  v_sentence text;
  v_words text[];
  v_unique int;
  v_max_freq int;
  v_explanatory boolean;
  v_on_topic boolean;
  v_sentence_count int := 0;
  v_on_topic_count int := 0;
  v_topics jsonb := '[]'::jsonb;
  v_demonstrated int := 0;
  v_partial int := 0;
  v_word text;
  v_word_count int := 0;
  v_unique_words int;
  v_top_freq int := 0;
  v_repetition boolean := false;
  v_phrase text;
  v_relevance text;
  v_summary text;
  v_note text;
  v_topic record;
begin
  create temporary table if not exists kr_topic_score (
    topic_key text primary key,
    label text not null,
    explanatory_count int not null default 0
  ) on commit drop;
  truncate kr_topic_score;
  insert into kr_topic_score (topic_key, label) values
    ('introduction', 'Introduction to Cyber Security'),
    ('cia', 'CIA Triad'),
    ('threats', 'Threats and vulnerabilities'),
    ('attacks', 'Cyber attacks'),
    ('impact', 'Organisational impact'),
    ('protection', 'Protection measures'),
    ('conclusion', 'Conclusion');

  for v_sentence in
    select btrim(part)
    from regexp_split_to_table(v_text, '[.!?]+') as part
    where btrim(part) <> ''
  loop
    v_words := array(
      select match[1]
      from regexp_matches(v_sentence, '[[:alpha:]]{2,}', 'g') as match
    );
    if coalesce(cardinality(v_words), 0) < 4 then
      continue;
    end if;
    v_sentence_count := v_sentence_count + 1;
    select count(distinct word), max(freq)
    into v_unique, v_max_freq
    from (
      select word, count(*) as freq
      from unnest(v_words) as word
      group by word
    ) as counted;
    v_explanatory := cardinality(v_words) >= 8
      and v_unique >= 6
      and v_max_freq::numeric / cardinality(v_words) <= 0.34;
    v_on_topic := false;

    if v_sentence ~ '\y(cyber|security|information|protect|organisation|organization)\y' then
      v_on_topic := true;
    end if;

    if v_sentence ~ '\y(cyber\s+security|information\s+security|what\s+is\s+cyber)\y' and v_explanatory then
      update kr_topic_score set explanatory_count = explanatory_count + 1 where topic_key = 'introduction';
      v_on_topic := true;
    end if;
    if v_sentence ~ '\y(cia|confidentiality|integrity|availability)\y' and v_explanatory then
      update kr_topic_score set explanatory_count = explanatory_count + 1 where topic_key = 'cia';
      v_on_topic := true;
    end if;
    if v_sentence ~ '\y(threat|threats|vulnerability|vulnerabilities)\y' and v_explanatory then
      update kr_topic_score set explanatory_count = explanatory_count + 1 where topic_key = 'threats';
      v_on_topic := true;
    end if;
    if v_sentence ~ '\y(attack|attacks|malware|phishing|ransomware)\y' and v_explanatory then
      update kr_topic_score set explanatory_count = explanatory_count + 1 where topic_key = 'attacks';
      v_on_topic := true;
    end if;
    if v_sentence ~ '\y(impact|impacts|consequence|consequences|organisation|organization|affect|affected)\y' and v_explanatory then
      update kr_topic_score set explanatory_count = explanatory_count + 1 where topic_key = 'impact';
      v_on_topic := true;
    end if;
    if v_sentence ~ '\y(firewall|password|passwords|encryption|backup|monitoring|protection|protects|protect)\y' and v_explanatory then
      update kr_topic_score set explanatory_count = explanatory_count + 1 where topic_key = 'protection';
      v_on_topic := true;
    end if;
    if v_sentence ~ '\y(conclusion|overall|prioritise|prioritize|summarise|summarize)\y' and v_explanatory then
      update kr_topic_score set explanatory_count = explanatory_count + 1 where topic_key = 'conclusion';
      v_on_topic := true;
    end if;
    if v_on_topic then
      v_on_topic_count := v_on_topic_count + 1;
    end if;
  end loop;

  for v_topic in
    select topic_key, label, explanatory_count from kr_topic_score order by topic_key
  loop
    v_topics := v_topics || jsonb_build_array(jsonb_build_object(
      'key', v_topic.topic_key,
      'label', v_topic.label,
      'coverage', case
        when v_topic.explanatory_count >= 2 then 'demonstrated'
        when v_topic.explanatory_count = 1 then 'partial'
        else 'not_demonstrated'
      end,
      'reason', case
        when v_topic.explanatory_count >= 2 then 'The writing appears to discuss this area in more than one sentence. This is not a judgement of factual correctness.'
        when v_topic.explanatory_count = 1 then 'The writing appears to mention this area once. This is not a judgement of factual correctness.'
        else 'No apparent discussion of this area was found.'
      end
    ));
    if v_topic.explanatory_count >= 2 then
      v_demonstrated := v_demonstrated + 1;
    elsif v_topic.explanatory_count = 1 then
      v_partial := v_partial + 1;
    end if;
  end loop;

  select coalesce(sum(freq), 0), count(*), coalesce(max(freq), 0)
  into v_word_count, v_unique_words, v_top_freq
  from (
    select word, count(*) as freq
    from regexp_matches(v_text, '[[:alpha:]]{2,}', 'g') as match(word)
    group by word
  ) as counted;

  if v_word_count >= 6 and v_top_freq >= 4 and v_top_freq::numeric / greatest(v_word_count, 1) >= 0.4 then
    v_repetition := true;
  end if;
  if v_word_count >= 20 and v_top_freq::numeric / greatest(v_word_count, 1) >= 0.12 then
    v_repetition := true;
  end if;
  if v_word_count >= 40 and v_unique_words::numeric / v_word_count < 0.35 then
    v_repetition := true;
  end if;
  for v_phrase in
    select phrase
    from (
      select lower(match[1]) as phrase, count(*) as freq
      from regexp_matches(v_text, '([[:alpha:]]{3,}(?:\s+[[:alpha:]]{3,}){2})', 'g') as match
      group by lower(match[1])
    ) as phrases
    where freq >= 4
    limit 1
  loop
    v_repetition := true;
  end loop;

  if v_demonstrated >= 4 and v_sentence_count > 0 and v_on_topic_count::numeric / v_sentence_count >= 0.5 and not v_repetition then
    v_relevance := 'high';
    v_summary := 'High relevance to the task. The response substantially addresses the expected Cyber Security areas. This is not a judgement of factual correctness.';
  elsif v_demonstrated >= 2 or (v_demonstrated >= 1 and v_partial >= 1) then
    v_relevance := 'moderate';
    v_summary := 'Moderate relevance to the task. The writing appears to address some expected areas and leave others thin or absent.';
  elsif v_partial + v_demonstrated >= 1 and v_on_topic_count > 0 then
    v_relevance := 'low';
    v_summary := 'Relevant but limited explanation. The writing appears to touch the task but does not develop the expected areas.';
  else
    v_relevance := 'very_low';
    v_summary := 'Off-topic. Large sections may be unrelated to the task, and the expected subject areas are largely absent.';
  end if;

  v_note := case when v_repetition then 'Possible excessive repetition' else null end;

  return jsonb_build_object(
    'analysisVersion', '1',
    'overallRelevance', v_relevance,
    'summary', v_summary,
    'topics', v_topics,
    'repetitionFlag', v_repetition,
    'repetitionNote', v_note,
    'advisory', 'Automated content analysis is provided to assist teacher review and is not an assessment or support decision.'
  );
end;
$$;

comment on function learning.assess_knowledge_report_content(text) is
  'Advisory topic coverage for a submitted cyber security knowledge report. Keyword repetition alone is not treated as explanation.';

revoke all on function learning.assess_knowledge_report_content(text) from public, anon, authenticated;

create or replace function admin_api.ensure_knowledge_report_content_review(p_response_id uuid)
returns table (
  response_id uuid,
  analysis_version text,
  analysed_at timestamptz,
  overall_relevance text,
  summary text,
  topics jsonb,
  repetition_flag boolean,
  repetition_note text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth uuid := auth.uid();
  v_group_id uuid;
  v_text text;
  v_mode text;
  v_payload jsonb;
  v_existing learning.knowledge_report_content_reviews%rowtype;
  v_assessment jsonb;
begin
  if v_auth is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;
  if not exists (
    select 1 from learning.teachers as teacher
    where teacher.auth_user_id = v_auth and teacher.active
  ) then
    raise exception using errcode = '28000', message = 'REVIEW_NOT_AUTHORISED';
  end if;
  if p_response_id is null then
    raise exception using errcode = '22023', message = 'REVIEW_RESPONSE_REQUIRED';
  end if;

  select assignment.group_id, response.response_payload, marking.spec ->> 'mode'
  into v_group_id, v_payload, v_mode
  from learning.responses as response
  join learning.attempts as attempt on attempt.id = response.attempt_id
  join learning.activity_assignments as assignment on assignment.id = attempt.assignment_id
  left join learning.question_marking as marking on marking.question_id = response.question_id
  where response.id = p_response_id
    and attempt.status = 'completed';

  if v_group_id is null or v_mode is distinct from 'timed-knowledge-report' then
    raise exception using errcode = '22023', message = 'REVIEW_NOT_KNOWLEDGE_REPORT';
  end if;
  if not platform.current_staff_has_role('platform_admin')
     and not learning.teacher_can_access_group(v_group_id) then
    raise exception using errcode = '28000', message = 'REVIEW_NOT_AUTHORISED';
  end if;

  select review.*
  into v_existing
  from learning.knowledge_report_content_reviews as review
  where review.response_id = p_response_id
    and review.analysis_version = '1';

  if not found then
    v_text := coalesce(v_payload ->> 'text', '');
    v_assessment := learning.assess_knowledge_report_content(v_text);
    insert into learning.knowledge_report_content_reviews (
      response_id, analysis_version, overall_relevance, summary, topics, repetition_flag, repetition_note
    ) values (
      p_response_id,
      '1',
      v_assessment ->> 'overallRelevance',
      v_assessment ->> 'summary',
      v_assessment -> 'topics',
      coalesce((v_assessment ->> 'repetitionFlag')::boolean, false),
      v_assessment ->> 'repetitionNote'
    )
    returning * into v_existing;
  end if;

  return query
  select
    v_existing.response_id,
    v_existing.analysis_version,
    v_existing.analysed_at,
    v_existing.overall_relevance,
    v_existing.summary,
    v_existing.topics,
    v_existing.repetition_flag,
    v_existing.repetition_note;
end;
$$;

revoke all on function admin_api.ensure_knowledge_report_content_review(uuid) from public, anon, authenticated;
grant execute on function admin_api.ensure_knowledge_report_content_review(uuid) to authenticated;

drop function admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, integer, integer
);
create or replace function admin_api.list_knowledge_report_cohort(
  p_hub_code text,
  p_course_key text default null,
  p_group_code text default null,
  p_student_number text default null,
  p_activity_key text default null,
  p_completion_status text default null,
  p_minimum_met text default null,
  p_review_status text default null,
  p_relevance text default null,
  p_limit integer default 500,
  p_offset integer default 0
)
returns table (
  student_id uuid,
  student_number text,
  learner_name text,
  group_id uuid,
  group_code text,
  group_name text,
  course_key text,
  activity_id uuid,
  activity_key text,
  activity_version_id uuid,
  report_title text,
  assignment_id uuid,
  completion_status text,
  started_at timestamptz,
  duration_seconds integer,
  word_count integer,
  minimum_words integer,
  minimum_met boolean,
  elapsed_seconds integer,
  submission_method text,
  requires_review boolean,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  response_id uuid,
  overall_relevance text,
  repetition_flag boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with visible as (
    select link.group_id
    from platform.hubs as hub
    join platform.hub_group_links as link
      on link.hub_id = hub.id
     and link.active
    join learning.groups as learner_group
      on learner_group.id = link.group_id
     and learner_group.active
    where hub.hub_code = nullif(btrim(p_hub_code), '')
      and hub.active
      and (
        platform.current_staff_has_role('platform_admin')
        or learning.teacher_can_access_group(link.group_id)
      )
      and (
        platform.current_staff_has_role('platform_admin')
        or exists (
          select 1
          from platform.hubs as readable_hub
          join platform.hub_group_links as readable_link
            on readable_link.hub_id = readable_hub.id
           and readable_link.active
          where readable_hub.hub_code = nullif(btrim(p_hub_code), '')
            and learning.teacher_can_access_group(readable_link.group_id)
        )
      )
  ),
  reports as (
    select
      activity.id as activity_id,
      activity.stable_key as activity_key,
      activity.title as report_title,
      version.id as activity_version_id,
      course.stable_key as course_key,
      (marking.spec ->> 'durationSeconds')::integer as duration_seconds,
      (marking.spec ->> 'minWords')::integer as minimum_words
    from learning.activities as activity
    join learning.activity_versions as version
      on version.activity_id = activity.id
     and version.retired_at is null
    join learning.questions as question
      on question.activity_version_id = version.id
    join learning.question_marking as marking
      on marking.question_id = question.id
     and marking.spec ->> 'mode' = 'timed-knowledge-report'
    join learning.modules as module
      on module.id = activity.module_id
    join learning.courses as course
      on course.id = module.course_id
    join platform.hub_course_links as course_link
      on course_link.course_id = course.id
     and course_link.active
    join platform.hubs as hub
      on hub.id = course_link.hub_id
     and hub.hub_code = nullif(btrim(p_hub_code), '')
     and hub.active
  ),
  cohort as (
    select
      student.id as student_id,
      student.student_number,
      student.display_name as learner_name,
      learner_group.id as group_id,
      learner_group.code as group_code,
      learner_group.name as group_name,
      report.course_key,
      report.activity_id,
      report.activity_key,
      report.activity_version_id,
      report.report_title,
      assignment.id as assignment_id,
      case
        when attempt.status = 'completed' and response.requires_review is false then 'reviewed'
        when attempt.status = 'completed' then 'submitted'
        when sitting.started_at is not null
          and report.duration_seconds is not null
          and sitting.started_at + make_interval(secs => report.duration_seconds) <= pg_catalog.now()
          then 'time_elapsed'
        when sitting.student_id is not null
          or attempt.id is not null
          or coalesce(formative.formative_check_count, 0) > 0
          then 'in_progress'
        else 'not_started'
      end as completion_status,
      sitting.started_at,
      report.duration_seconds,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'wordCount')::integer
      end as word_count,
      report.minimum_words,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'minimumMet')::boolean
      end as minimum_met,
      case
        when attempt.status = 'completed' then (response.response_payload ->> 'elapsedSeconds')::integer
      end as elapsed_seconds,
      case
        when attempt.status = 'completed' then response.response_payload ->> 'submissionMethod'
      end as submission_method,
      case
        when attempt.status = 'completed' then response.requires_review
      end as requires_review,
      case
        when attempt.status = 'completed' then attempt.received_at
      end as submitted_at,
      case
        when attempt.status = 'completed' and response.requires_review is false then response.marked_at
      end as reviewed_at,
      case
        when attempt.status = 'completed' then response.id
      end as response_id,
      case when attempt.status = 'completed' then content_review.overall_relevance end as overall_relevance,
      case when attempt.status = 'completed' then content_review.repetition_flag end as repetition_flag
    from reports as report
    join learning.groups as learner_group
      on learner_group.active
    join visible
      on visible.group_id = learner_group.id
    join learning.enrolments as enrolment
      on enrolment.group_id = learner_group.id
     and enrolment.status = 'active'
    join learning.students as student
      on student.id = enrolment.student_id
     and student.active
    join learning.activity_assignments as assignment
      on assignment.id = learning.current_activity_assignment_id(learner_group.id, report.activity_id)
     and assignment.active
    left join learning.activity_states as sitting
      on sitting.assignment_id = assignment.id
     and sitting.student_id = student.id
     and sitting.activity_version_id = report.activity_version_id
    left join lateral (
      select attempt_row.*
      from learning.attempts as attempt_row
      where attempt_row.assignment_id = assignment.id
        and attempt_row.student_id = student.id
        and attempt_row.activity_version_id = report.activity_version_id
      order by attempt_row.received_at desc
      limit 1
    ) as attempt on true
    left join lateral (
      select response_row.*
      from learning.responses as response_row
      where response_row.attempt_id = attempt.id
      order by response_row.marked_at desc nulls last
      limit 1
    ) as response on true
    left join lateral (
      select count(*)::integer as formative_check_count
      from learning.formative_checks as formative_check
      where formative_check.assignment_id = assignment.id
        and formative_check.student_id = student.id
        and formative_check.activity_version_id = report.activity_version_id
    ) as formative on true
    left join lateral (
      select review.overall_relevance, review.repetition_flag
      from learning.knowledge_report_content_reviews as review
      where review.response_id = response.id
      order by review.analysed_at desc
      limit 1
    ) as content_review on true
    where (p_course_key is null or report.course_key = p_course_key)
      and (p_group_code is null or learner_group.code = p_group_code)
      and (p_student_number is null or student.student_number = p_student_number)
      and (p_activity_key is null or report.activity_key = p_activity_key)
  )
  select
    cohort.student_id,
    cohort.student_number,
    cohort.learner_name,
    cohort.group_id,
    cohort.group_code,
    cohort.group_name,
    cohort.course_key,
    cohort.activity_id,
    cohort.activity_key,
    cohort.activity_version_id,
    cohort.report_title,
    cohort.assignment_id,
    cohort.completion_status,
    cohort.started_at,
    cohort.duration_seconds,
    cohort.word_count,
    cohort.minimum_words,
    cohort.minimum_met,
    cohort.elapsed_seconds,
    cohort.submission_method,
    cohort.requires_review,
    cohort.submitted_at,
    cohort.reviewed_at,
    cohort.response_id,
    cohort.overall_relevance,
    cohort.repetition_flag
  from cohort
  where (p_completion_status is null or cohort.completion_status = p_completion_status)
    and (
      p_minimum_met is null
      or (p_minimum_met = 'met' and cohort.minimum_met is true)
      or (p_minimum_met = 'not_reached' and cohort.minimum_met is false)
    )
    and (
      p_review_status is null
      or (p_review_status = 'needs_review' and cohort.requires_review is true)
      or (p_review_status = 'reviewed' and cohort.completion_status = 'reviewed')
    )
    and (p_relevance is null or cohort.overall_relevance = p_relevance)
  order by cohort.learner_name, cohort.activity_key, cohort.student_number
  limit least(greatest(coalesce(p_limit, 500), 0), 1000)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

comment on function admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, text, integer, integer
) is
  'Assigned knowledge-report cohort for staff-visible hub groups. Returns sitting timing and submitted metadata only. Never returns draft state_payload or report text.';

revoke all on function admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, text, integer, integer
) from public, anon, authenticated;

grant execute on function admin_api.list_knowledge_report_cohort(
  text, text, text, text, text, text, text, text, text, integer, integer
) to authenticated;

