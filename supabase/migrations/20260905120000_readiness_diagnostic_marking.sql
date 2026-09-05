-- Authoritative Readiness Diagnostic marking for the current 25-question
-- contract (diagnostic version 1.1.0). Learner RPCs never accept or return
-- scores. Specs are not granted to anon/authenticated.

create table learning.diagnostic_question_marking (
  diagnostic_key text not null,
  diagnostic_version text not null,
  activity_id text not null,
  question_key text not null,
  unit_key text not null,
  topic_key text,
  spec jsonb not null,
  max_score numeric(8,2) not null,
  scorable boolean not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint diagnostic_question_marking_pkey
    primary key (diagnostic_key, diagnostic_version, activity_id, question_key),
  constraint diagnostic_question_marking_key_valid check (
    diagnostic_key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    and diagnostic_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'
  ),
  constraint diagnostic_question_marking_activity_valid check (
    activity_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
  ),
  constraint diagnostic_question_marking_question_valid check (
    question_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
  ),
  constraint diagnostic_question_marking_unit_valid check (
    unit_key in (
      'general',
      'global-information',
      'fundamentals-of-it',
      'cyber-security',
      'web-design'
    )
  ),
  constraint diagnostic_question_marking_spec_object
    check (jsonb_typeof(spec) = 'object'),
  constraint diagnostic_question_marking_max_score_valid check (
    max_score >= 0
    and (
      (scorable and max_score > 0)
      or (not scorable and max_score = 0)
    )
  )
);

comment on table learning.diagnostic_question_marking is
  'Versioned Readiness Diagnostic marking specs. Never granted to learners. Independent of learning.question_marking because diagnostic items are not catalogue questions.';

alter table learning.diagnostic_question_marking enable row level security;

revoke all on table learning.diagnostic_question_marking
from public, anon, authenticated;

alter table learning.diagnostic_responses
  add column awarded_score numeric(8,2),
  add column max_score numeric(8,2);

alter table learning.diagnostic_responses
  add constraint diagnostic_response_awarded_score_valid check (
    awarded_score is null
    or (
      max_score is not null
      and awarded_score >= 0
      and awarded_score <= max_score
    )
  );

comment on column learning.diagnostic_responses.awarded_score is
  'Server-authoritative awarded marks. Null when no spec exists for the sitting version.';
comment on column learning.diagnostic_responses.max_score is
  'Server-authoritative maximum marks for this question version. Null when unmarked.';
comment on column learning.diagnostic_responses.is_correct is
  'Server-authoritative correctness. Null when unmarked or intentionally unscored.';

create function learning.mark_diagnostic_evidence(
  p_spec jsonb,
  p_evidence jsonb,
  p_max_score numeric
)
returns table (
  awarded_score numeric(8,2),
  is_correct boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_mode text;
  v_option text;
  v_expected text[];
  v_actual text[];
  v_ok boolean;
  v_key text;
  v_expected_cat text;
  v_actual_cat text;
  v_assignments jsonb;
begin
  v_mode := coalesce(p_spec ->> 'mode', '');

  if v_mode = 'unscored' or v_mode = '' then
    awarded_score := null;
    is_correct := null;
    return next;
    return;
  end if;

  if v_mode = 'single-choice' then
    if jsonb_typeof(p_evidence) = 'string' then
      v_option := btrim(p_evidence #>> '{}');
    else
      v_option := coalesce(
        nullif(btrim(coalesce(p_evidence ->> 'optionId', '')), ''),
        nullif(btrim(coalesce(p_evidence ->> 'selectedOptionId', '')), '')
      );
    end if;
    v_ok := coalesce(v_option, '') = coalesce(p_spec ->> 'correctOptionId', '')
      and coalesce(v_option, '') <> ''
      and coalesce(v_option, '') <> 'not-sure';
    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    return next;
    return;
  end if;

  if v_mode = 'multi-select-exact' then
    if jsonb_typeof(p_evidence) = 'array' then
      select coalesce(array_agg(distinct btrim(value) order by btrim(value)), '{}')
      into v_actual
      from jsonb_array_elements_text(p_evidence) as value
      where btrim(value) <> '';
    elsif jsonb_typeof(p_evidence) = 'object' and jsonb_typeof(p_evidence -> 'optionIds') = 'array' then
      select coalesce(array_agg(distinct btrim(value) order by btrim(value)), '{}')
      into v_actual
      from jsonb_array_elements_text(p_evidence -> 'optionIds') as value
      where btrim(value) <> '';
    else
      v_actual := '{}';
    end if;

    select coalesce(array_agg(distinct btrim(value) order by btrim(value)), '{}')
    into v_expected
    from jsonb_array_elements_text(coalesce(p_spec -> 'correctOptions', '[]'::jsonb)) as value
    where btrim(value) <> '';

    v_ok := v_expected = v_actual
      and coalesce(array_length(v_expected, 1), 0) > 0
      and not ('not-sure' = any (v_actual));
    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    return next;
    return;
  end if;

  if v_mode = 'classification-map' then
    v_assignments := coalesce(p_spec -> 'correctAssignments', '{}'::jsonb);
    if jsonb_typeof(p_evidence) is distinct from 'object'
       or jsonb_typeof(v_assignments) is distinct from 'object'
       or v_assignments = '{}'::jsonb then
      awarded_score := 0;
      is_correct := false;
      return next;
      return;
    end if;

    v_ok := true;
    if (
      select count(*) from jsonb_object_keys(p_evidence)
    ) <> (
      select count(*) from jsonb_object_keys(v_assignments)
    ) then
      v_ok := false;
    else
      for v_key in select jsonb_object_keys(v_assignments)
      loop
        v_expected_cat := btrim(coalesce(v_assignments ->> v_key, ''));
        v_actual_cat := btrim(coalesce(p_evidence ->> v_key, ''));
        if v_expected_cat = ''
           or v_actual_cat = ''
           or v_actual_cat <> v_expected_cat
           or v_actual_cat = 'not-sure' then
          v_ok := false;
          exit;
        end if;
      end loop;
    end if;

    awarded_score := case when v_ok then p_max_score else 0 end;
    is_correct := v_ok;
    return next;
    return;
  end if;

  awarded_score := null;
  is_correct := null;
  return next;
end
$fn$;

comment on function learning.mark_diagnostic_evidence(jsonb, jsonb, numeric) is
  'Server-only diagnostic marker. Never granted to anon or authenticated. Does not return answer keys.';

revoke all on function learning.mark_diagnostic_evidence(jsonb, jsonb, numeric)
from public, anon, authenticated;

create function learning.diagnostic_version_max_score(
  p_diagnostic_key text,
  p_diagnostic_version text
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(sum(marking.max_score), 0)
  from learning.diagnostic_question_marking as marking
  where marking.diagnostic_key = p_diagnostic_key
    and marking.diagnostic_version = p_diagnostic_version
    and marking.scorable;
$fn$;

comment on function learning.diagnostic_version_max_score(text, text) is
  'Returns the scorable denominator for a diagnostic version. Does not expose answer keys.';

revoke all on function learning.diagnostic_version_max_score(text, text)
from public, anon;

grant execute on function learning.diagnostic_version_max_score(text, text)
to authenticated;

create or replace function api.submit_diagnostic_response(
  p_session_id uuid,
  p_activity_id text,
  p_unit_key text,
  p_question_key text,
  p_evidence jsonb,
  p_is_not_sure boolean default false,
  p_confidence text default null,
  p_topic_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_session learning.diagnostic_sessions%rowtype;
  v_activity_id text;
  v_question_key text;
  v_unit_key text;
  v_topic_key text;
  v_confidence text;
  v_is_not_sure boolean;
  v_response_id uuid;
  v_spec jsonb;
  v_max numeric(8,2);
  v_awarded numeric(8,2);
  v_correct boolean;
begin
  if p_session_id is null then
    raise exception using errcode = '22023', message = 'INVALID_SESSION_ID';
  end if;

  select session.*
  into v_session
  from learning.diagnostic_sessions as session
  where session.id = p_session_id;

  if not found then
    raise exception using errcode = '22023', message = 'DIAGNOSTIC_SESSION_NOT_FOUND';
  end if;
  if v_session.status = 'completed' then
    raise exception using errcode = '22023', message = 'DIAGNOSTIC_SESSION_COMPLETED';
  end if;

  v_activity_id := btrim(coalesce(p_activity_id, ''));
  v_question_key := btrim(coalesce(p_question_key, ''));
  v_unit_key := btrim(coalesce(p_unit_key, ''));
  v_topic_key := nullif(btrim(coalesce(p_topic_key, '')), '');
  v_confidence := nullif(btrim(coalesce(p_confidence, '')), '');

  if v_activity_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
    raise exception using errcode = '22023', message = 'INVALID_ACTIVITY_ID';
  end if;
  if v_question_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
    raise exception using errcode = '22023', message = 'INVALID_QUESTION_KEY';
  end if;
  if v_unit_key not in (
    'general',
    'global-information',
    'fundamentals-of-it',
    'cyber-security',
    'web-design'
  ) then
    raise exception using errcode = '22023', message = 'INVALID_UNIT_KEY';
  end if;
  if v_topic_key is not null and v_topic_key !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception using errcode = '22023', message = 'INVALID_TOPIC_KEY';
  end if;
  if p_evidence is null
     or jsonb_typeof(p_evidence) not in ('object', 'array', 'string', 'number', 'boolean')
     or octet_length(p_evidence::text) > 4096 then
    raise exception using errcode = '22023', message = 'INVALID_EVIDENCE';
  end if;
  if v_confidence is not null
     and (
       char_length(v_confidence) > 64
       or v_confidence ~ '[[:cntrl:]]'
     ) then
    raise exception using errcode = '22023', message = 'INVALID_CONFIDENCE';
  end if;

  v_is_not_sure := learning.diagnostic_not_sure_from_evidence(p_evidence, p_is_not_sure);

  select marking.spec, marking.max_score
  into v_spec, v_max
  from learning.diagnostic_question_marking as marking
  where marking.diagnostic_key = v_session.diagnostic_key
    and marking.diagnostic_version = v_session.diagnostic_version
    and marking.activity_id = v_activity_id
    and marking.question_key = v_question_key;

  if found then
    select mark.awarded_score, mark.is_correct
    into v_awarded, v_correct
    from learning.mark_diagnostic_evidence(v_spec, p_evidence, v_max) as mark;
  else
    v_awarded := null;
    v_correct := null;
    v_max := null;
  end if;

  insert into learning.diagnostic_responses (
    diagnostic_session_id,
    activity_id,
    unit_key,
    topic_key,
    question_key,
    evidence,
    is_correct,
    awarded_score,
    max_score,
    is_not_sure,
    confidence
  ) values (
    v_session.id,
    v_activity_id,
    v_unit_key,
    v_topic_key,
    v_question_key,
    p_evidence,
    v_correct,
    v_awarded,
    v_max,
    v_is_not_sure,
    v_confidence
  )
  on conflict (diagnostic_session_id, activity_id, question_key)
  do update set
    unit_key = excluded.unit_key,
    topic_key = excluded.topic_key,
    evidence = excluded.evidence,
    is_correct = excluded.is_correct,
    awarded_score = excluded.awarded_score,
    max_score = excluded.max_score,
    is_not_sure = excluded.is_not_sure,
    confidence = excluded.confidence,
    updated_at = clock_timestamp()
  returning id into v_response_id;

  update learning.diagnostic_sessions
  set updated_at = clock_timestamp()
  where id = v_session.id;

  return jsonb_build_object(
    'id', v_response_id,
    'activity_id', v_activity_id,
    'question_key', v_question_key,
    'is_not_sure', v_is_not_sure
  );
end
$fn$;

comment on function api.submit_diagnostic_response(uuid, text, text, text, jsonb, boolean, text, text) is
  'Persist one diagnostic response and apply server marking for the sitting version. Client scores and is_correct are not accepted or returned.';

insert into learning.diagnostic_question_marking (
  diagnostic_key,
  diagnostic_version,
  activity_id,
  question_key,
  unit_key,
  topic_key,
  spec,
  max_score,
  scorable
)
values
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-opening-confidence', 'RDY-GEN-001', 'general', 'confidence', '{"mode":"unscored"}'::jsonb, 0, false),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-gist-storage-media', 'RDY-GIST-001', 'global-information', 'storage-media', '{"mode":"classification-map","correctAssignments":{"handwritten-note":"paper","usb":"portable","dvd":"portable","cloud-drive":"shared"}}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-gist-shared-project', 'RDY-GIST-002', 'global-information', 'shared-storage', '{"mode":"single-choice","correctOptionId":"shared-cloud"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-gist-information-styles', 'RDY-GIST-003', 'global-information', 'information-styles', '{"mode":"classification-map","correctAssignments":{"logo":"graphic","spoken":"audio","total":"numerical","message":"text"}}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-gist-download-time', 'RDY-GIST-005', 'global-information', 'transmission', '{"mode":"multi-select-exact","correctOptions":["file-size","network-busy","connection-speed"]}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-gist-copying', 'RDY-GIST-006', 'global-information', 'copying-files', '{"mode":"single-choice","correctOptionId":"both-copies"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-gist-file-sizes', 'RDY-GIST-007', 'global-information', 'file-size', '{"mode":"single-choice","correctOptionId":"video"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-fit-hardware-software', 'RDY-FIT-001', 'fundamentals-of-it', 'hardware-software', '{"mode":"classification-map","correctAssignments":{"keyboard":"hardware","windows":"software","monitor":"hardware","browser":"software","mouse":"hardware","word-processor":"software"}}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-fit-device-roles', 'RDY-FIT-002', 'fundamentals-of-it', 'input-output-storage', '{"mode":"classification-map","correctAssignments":{"keyboard":"input","microphone":"input","monitor":"output","speakers":"output","ssd":"storage","usb-drive":"storage"}}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-fit-running-applications', 'RDY-FIT-003', 'fundamentals-of-it', 'memory', '{"mode":"single-choice","correctOptionId":"ram"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-fit-operating-system', 'RDY-FIT-004', 'fundamentals-of-it', 'operating-systems', '{"mode":"single-choice","correctOptionId":"manage-hardware"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-fit-suitable-software', 'RDY-FIT-006', 'fundamentals-of-it', 'application-software', '{"mode":"single-choice","correctOptionId":"spreadsheet"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-fit-storage-space', 'RDY-FIT-007', 'fundamentals-of-it', 'storage-capacity', '{"mode":"single-choice","correctOptionId":"more-storage"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-cyber-suspicious-message', 'RDY-CYB-001', 'cyber-security', 'phishing', '{"mode":"single-choice","correctOptionId":"official-check"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-cyber-password-reuse', 'RDY-CYB-002', 'cyber-security', 'credential-reuse', '{"mode":"single-choice","correctOptionId":"tried-elsewhere"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-cyber-account-habits', 'RDY-CYB-003', 'cyber-security', 'account-habits', '{"mode":"classification-map","correctAssignments":{"unique-password":"helps","share-password":"does-not-help","extra-check":"helps","unexpected-link":"does-not-help"}}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-cyber-updates', 'RDY-CYB-004', 'cyber-security', 'updates', '{"mode":"single-choice","correctOptionId":"fix-problems"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-cyber-unknown-usb', 'RDY-CYB-005', 'cyber-security', 'removable-media', '{"mode":"single-choice","correctOptionId":"give-to-staff"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-cyber-software-download', 'RDY-CYB-007', 'cyber-security', 'safe-downloads', '{"mode":"multi-select-exact","correctOptions":["official-site","security-warning","legitimate-publisher"]}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-web-navigation', 'RDY-WEB-001', 'web-design', 'navigation', '{"mode":"classification-map","correctAssignments":{"nav-bar":"helps","related-links":"helps","site-map":"helps","moving-menus":"harder","too-many-choices":"harder","click-here":"harder"}}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-web-mobile', 'RDY-WEB-002', 'web-design', 'responsive-design', '{"mode":"single-choice","correctOptionId":"smaller-screen"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-web-wireframe', 'RDY-WEB-003', 'web-design', 'wireframes', '{"mode":"single-choice","correctOptionId":"layout-plan"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-web-readability', 'RDY-WEB-004', 'web-design', 'readability', '{"mode":"multi-select-exact","correctOptions":["contrast","headings","text-size"]}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-web-prototype-feedback', 'RDY-WEB-006', 'web-design', 'user-testing', '{"mode":"single-choice","correctOptionId":"review-navigation"}'::jsonb, 1, true),
  ('level-3-it-year-1-readiness', '1.1.0', 'readiness-web-audiences', 'RDY-WEB-007', 'web-design', 'audience', '{"mode":"single-choice","correctOptionId":"audience-affects-design"}'::jsonb, 1, true);

update platform.hubs
set features = features || jsonb_build_object('diagnosticVersion', '1.1.0'),
    updated_at = clock_timestamp()
where hub_code = 'level-3-it-year-1-readiness';

drop view if exists admin_api.diagnostic_sessions;
drop view if exists admin_api.diagnostic_responses;

create view admin_api.diagnostic_sessions
with (security_invoker = true)
as
select
  session.id as session_id,
  session.student_name,
  session.student_id,
  hub.hub_code,
  hub.hub_name,
  course.stable_key as course_key,
  course.title as course_title,
  session.status,
  session.started_at,
  session.completed_at,
  (
    select count(*)
    from learning.diagnostic_responses as response
    where response.diagnostic_session_id = session.id
  ) as response_count,
  (
    select count(*)
    from learning.diagnostic_responses as response
    where response.diagnostic_session_id = session.id
      and response.is_not_sure
  ) as not_sure_count,
  session.diagnostic_key,
  session.diagnostic_version,
  (
    select sum(response.awarded_score)
    from learning.diagnostic_responses as response
    where response.diagnostic_session_id = session.id
      and response.awarded_score is not null
  ) as awarded_score,
  nullif(
    learning.diagnostic_version_max_score(
      session.diagnostic_key,
      session.diagnostic_version
    ),
    0
  ) as max_score,
  case
    when session.status <> 'completed' then null
    when coalesce(
      learning.diagnostic_version_max_score(
        session.diagnostic_key,
        session.diagnostic_version
      ),
      0
    ) = 0 then null
    else round(
      100.0 * coalesce((
        select sum(response.awarded_score)
        from learning.diagnostic_responses as response
        where response.diagnostic_session_id = session.id
      ), 0) / learning.diagnostic_version_max_score(
        session.diagnostic_key,
        session.diagnostic_version
      ),
      1
    )
  end as score_percentage
from learning.diagnostic_sessions as session
join platform.hubs as hub on hub.id = session.hub_id
join learning.courses as course on course.id = session.course_id
where (select platform.current_staff_has_role('platform_admin'));

create view admin_api.diagnostic_responses
with (security_invoker = true)
as
select
  response.id as response_id,
  response.diagnostic_session_id as session_id,
  session.student_name,
  session.student_id,
  hub.hub_code,
  course.stable_key as course_key,
  response.activity_id,
  response.unit_key,
  response.topic_key,
  response.question_key,
  response.evidence,
  response.is_not_sure,
  response.confidence,
  response.is_correct,
  response.created_at,
  response.updated_at,
  response.awarded_score,
  response.max_score
from learning.diagnostic_responses as response
join learning.diagnostic_sessions as session
  on session.id = response.diagnostic_session_id
join platform.hubs as hub on hub.id = session.hub_id
join learning.courses as course on course.id = session.course_id
where (select platform.current_staff_has_role('platform_admin'));

comment on view admin_api.diagnostic_sessions is
  'Platform-admin Readiness Diagnostic session list. awarded_score/max_score/score_percentage are server-authoritative and null when the sitting version has no marking spec.';
comment on view admin_api.diagnostic_responses is
  'Platform-admin Readiness Diagnostic response detail. is_correct and awarded_score are server-derived; answer keys are not included.';

revoke all on
  admin_api.diagnostic_sessions,
  admin_api.diagnostic_responses,
  admin_api.diagnostic_summary
from public, anon, authenticated;

grant select on
  admin_api.diagnostic_sessions,
  admin_api.diagnostic_responses,
  admin_api.diagnostic_summary
to authenticated;
